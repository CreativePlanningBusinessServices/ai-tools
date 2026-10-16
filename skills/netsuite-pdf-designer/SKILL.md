---
name: netsuite-pdf-designer
description: Use when a task needs to view, preview, validate, edit, redesign, or create a NetSuite Advanced PDF/HTML template — a template URL (pdftemplate.nl?id=…), id, scriptid (CUSTTMPL_…/STDTMPL…) or name, "what does this invoice PDF look like", "move the PO number", "add a column to the statement", "build a new invoice template", "will this render in NetSuite?" — in any account where Creative Planning's cp_pdf_template_rl RESTlet is installed. Covers the RESTlet's JSON contract (called via netsuite-cli restlet call), previewing the real PDF plus a clickable HTML twin against a real record, NetSuite's FreeMarker and the BFO HTML/CSS subset, a local validator, and saving or creating templates through a scratch SDF project (bash, awk, jq, xmllint, xsltproc; no Python or Node).
---

# Advanced PDF/HTML templates via the cp_pdf_template_rl RESTlet

`cp_pdf_template_rl` is a RESTlet Creative Planning installs into NetSuite accounts, CP's own and
clients' (script/deploy ids are the same everywhere): `customscript_cp_pdf_template_rl` /
`customdeploy_cp_pdf_template_rl`. It describes a template with its source, renders a saved or
draft template to a PDF plus NetSuite's merged markup against a real record, and backs a template
up to the File Cabinet. **It never writes templates**: NetSuite has no API for that, so saves and
new templates deploy through a scratch SuiteCloud (SDF) project with `scripts/sdf-template.sh`.

## Before the first call in an account

1. **Pick the account.** Every call takes `--account <alias>`, the `netsuite-cli` alias for the
   target account. Never fall back to the CLI's default account: if the user hasn't said which
   account, ask.
2. **Confirm the RESTlet is installed there** (once per account per session):

   ```bash
   netsuite-cli suiteql --account <alias> "SELECT scriptid FROM script WHERE scriptid = 'customscript_cp_pdf_template_rl'"
   ```

   - One row: go ahead.
   - No rows: it isn't installed. Don't call the RESTlet; ask the user whether they'd like you
     to install it, following "Installing the RESTlet" below.
   - The query itself errors (unknown alias, auth failure): report that error. It says nothing
     about whether the RESTlet is installed.

**Install, redeploy, save or create only after the user says yes for that account.** If the
RESTlet is missing, ask whether they'd like you to install it. If it's there but a call fails
because the deployment is undeployed or not released, report what you found and ask whether to
redeploy the package. An `{error}` the RESTlet itself returns, or a permission error on the calling
role, isn't an install problem and a redeploy won't fix it. A request to view or edit a template
isn't a yes, neither is a "do whatever it takes" said before the user knew an install or save was
needed, and a yes for one account isn't a yes for another. Deploying the package is the only change
you make to scripts: never edit a script or deployment record by hand (UI or API), in any account.

Define a helper and a work folder once per shell (zsh does not word-split `$VARS`, so the helper
is a function; `$SP` is the session scratchpad folder, `$PD` this skill's real path):

```bash
rl() { netsuite-cli restlet call --account <alias> --script customscript_cp_pdf_template_rl --deploy customdeploy_cp_pdf_template_rl "$@"; }
SP=<session scratchpad directory>/pdf-designer; mkdir -p "$SP"
PD="$(cd "<this skill's base directory>" && pwd -P)"
NS_HOST=$(netsuite-cli account list | jq -r --arg alias <alias> '.accounts[] | select(.alias == $alias) | .accountId | ascii_downcase | gsub("_"; "-")')
```

`NS_HOST` is the account's UI host prefix (`1234567_SB1` → `1234567-sb1`). If it comes back empty,
the alias is wrong; stop and check it rather than linking a guessed host.

## How NetSuite renders PDF templates

- A template (`advancedpdftemplate`: id, scriptid, name, printtype, trantype, preferred, inactive)
  is FreeMarker 2.3.34 over BFO Report Generator XML. FreeMarker merges first, then BFO parses the
  XML and draws the PDF. Syntax and roots: `references/freemarker.md`. Supported HTML/CSS, page
  setup, macros, tables, fonts and what BFO ignores: `references/bfo.md`. Read the relevant one
  before editing; don't guess syntax.
- Roots: `record` (the transaction) plus `companyInformation`, `user`, `preferences` and `nsfont`,
  which NetSuite fills itself. `subsidiary` is **not** filled by NetSuite's render API; the RESTlet
  adds it from the transaction's subsidiary. Statement templates loop
  `<#list statements as statement>` inside `<pdfset>`.
- A missing field (`${record.nosuchfield}`) renders as an empty string, silently. A broken
  FreeMarker construct (unclosed `<#if>`, unknown `?built-in`) fails with `UNEXPECTED_ERROR` and no
  detail, which the RESTlet translates into a hint to run the validator. Malformed XML comes back
  with a clear "Error Parsing XML" message.
- Unsupported tags and CSS that parse (`display:flex`, `grid`, `border-radius`, `rem`) are ignored
  silently. `scripts/pdf-validate.sh` catches these, plus FreeMarker structure and XML errors.
- A draft render of a template's own source gives the same PDF as the saved render, so draft
  previews are faithful.
- Standard templates (scriptid `STDTMPL…`, `isStandard: true`) can be read and rendered but not
  edited: "editing" one creates a custom copy.

## RESTlet contract

Bodyless GET returns a JSON **string** (NetSuite quirk; `restlet call` parses it). Caller mistakes
come back as `{"error": "…"}` (unknown keys are rejected, naming the allowed ones); NetSuite
failures pass through with their message, except `UNEXPECTED_ERROR` during a render (see above).

### GET `?id=<n>` or `?scriptid=<CUSTTMPL_…|STDTMPL…>` — describe + source

```bash
rl --method GET --param id=123 > "$SP/get-123.json" \
  && { jq -e 'has("error") | not' "$SP/get-123.json" >/dev/null || { jq -r .error "$SP/get-123.json"; false; }; } \
  && jq -j .source "$SP/get-123.json" > "$SP/pdf-base-123.xml"     # -j: no added newline
```

```json
{ "id": 123, "scriptid": "CUSTTMPL_EXAMPLE_INVOICE", "name": "Example Invoice", "printType": "TRANSACTION",
  "tranType": "CustInvc", "isPreferred": false, "isInactive": false, "isStandard": false, "source": "<?xml…" }
```

Exactly one of `id` / `scriptid`. Pass only the numeric id, never the `pdftemplate.nl` URL.

### POST — render

```bash
rl --method POST --data '{"templateId": 123, "record": {"type": "invoice", "id": 456}}'    # saved (or "scriptId")
rl --method POST --data @"$SP/draft.json"   # draft: {"source": "<?xml…", "templateId": 123, "record": {…}}
rl --method POST --data '{"printType": "STATEMENT", "entityId": 789, "formId": 210}'       # saved statement
```

- **Transaction** (default when `printType` is absent): `record {type, id}` is required; `type` is
  the SuiteScript record type (`CustInvc` → `invoice`, `CustCred` → `creditmemo`, `SalesOrd` →
  `salesorder`, `PurchOrd` → `purchaseorder`, `CashSale` → `cashsale`, `Estimate` → `estimate`,
  `VendBill` → `vendorbill`, `Check` → `check`). `source` makes it a draft; `templateId` alongside
  it is accepted and ignored.
- **Statement** (saved only): `entityId` (customer) and `formId`, the id of an existing statement
  form that prints with the template, are required; `statementDate`, `startDate`
  (`MM/DD/YYYY` strings) and `openTransactionsOnly` (boolean) are optional. The form decides the
  template. SuiteQL has no table that lists transaction forms, so ask the user for the form id
  (Customization → Forms → Transaction Forms, type Statement; the id is in the form's URL).

```json
{ "mode": "saved" | "draft", "printType": "TRANSACTION" | "STATEMENT",
  "record": { "type": "invoice", "id": 456 } | { "entityId": 789, "formId": 210 },
  "pdf": "<base64>", "pdfBytes": 41318, "xml": "<merged BFO markup>" }
```

A statement's `xml` is a `<pdfset>` holding one `<html>` child per statement; both local scripts
accept it. Empty source, or the literal `null`/`undefined`, is refused (a shell pipeline lost its
input).

### PUT `{id}` or `{scriptid}` — backup

```bash
rl --method PUT --data '{"id": 123}' > "$SP/backup-123.json"
```

The RESTlet reads the current source itself and writes it to
`/SuiteScripts/CreativePlanning/pdf-template-backups/<id>-<scriptid>-<yyyyMMdd-HHmmss>.xml`:
`{"id": 123, "scriptid": "…", "backup": {"id": 2468, "path": "/SuiteScripts/…"}}`. Restore = save
the backup file's contents (download it with the netsuite-file-cabinet skill) through step 6.

## Workflow

1. **Resolve the template.** From a URL take the `id=`; from a name fragment list matches:
   ```bash
   netsuite-cli suiteql --account <alias> "SELECT id, scriptid, name, printtype, trantype, preferred FROM advancedpdftemplate WHERE inactive = 'F' AND LOWER(name) LIKE '%invoice%'"
   ```
   `GET` it, keep the source as `$SP/pdf-base-<id>.xml` (with `jq -j`), and tell the user the name,
   print and transaction type, whether it's the preferred template, and the source size. For a
   standard template, say that saving will create a custom copy.
2. **Pick a sample record** of the template's `tranType`. If the user named one, use it. Otherwise
   list five recent candidates that have lines and ask the user to choose:
   ```bash
   netsuite-cli suiteql --account <alias> "SELECT txn.id, txn.tranid, txn.trandate, BUILTIN.DF(txn.entity) AS entity, COUNT(line.id) AS linecount FROM transaction txn JOIN transactionline line ON line.transaction = txn.id WHERE txn.type = 'CustInvc' AND line.mainline = 'F' AND line.taxline = 'F' GROUP BY txn.id, txn.tranid, txn.trandate, BUILTIN.DF(txn.entity) ORDER BY txn.id DESC FETCH FIRST 5 ROWS ONLY"
   ```
   Prefer a sample where the fields the template uses are filled in (read its `${record.…}` paths).
   For a statement, a customer with open invoices:
   `SELECT customer.id, customer.entityid, COUNT(txn.id) AS openinvoices FROM transaction txn JOIN customer ON customer.id = txn.entity WHERE txn.type = 'CustInvc' AND txn.status = 'A' GROUP BY customer.id, customer.entityid ORDER BY openinvoices DESC FETCH FIRST 5 ROWS ONLY`
   (`ORDER BY COUNT(*)` fails with `UNEXPECTED_ERROR`; order by the alias),
   plus the statement form id from the user.
3. **Check what can be previewed.** Transactions: saved and draft. Statements: saved only; **draft
   statement previews are not available yet**, so validate drafts and preview after saving. Other
   print types (packing slip, picking ticket, labels, price list, GL impact): no preview in this
   version; read, validate and save still work. **Check templates that loop over `records`** (the
   Print Checks batch list) can't be previewed either: before rendering, run
   `grep -Eq '<#list[[:space:]]+records[[:space:]]' "$SP/pdf-base-<id>.xml"` and, on a match, say
   so instead of calling the RESTlet. Validate and save still work for them.
4. **Preview.** `POST` (saved mode first), then write the PDF and the HTML twin:
   ```bash
   rl --method POST --data '{"templateId": 123, "record": {"type": "invoice", "id": 456}}' > "$SP/render-123.json" \
     && { jq -e 'has("error") | not' "$SP/render-123.json" >/dev/null || { jq -r .error "$SP/render-123.json"; false; }; } \
     && jq -j .pdf "$SP/render-123.json" | base64 -D > "$SP/pdf-preview-123.pdf" \
     && jq -j .xml "$SP/render-123.json" > "$SP/merged-123.xml"
   bash "$PD/scripts/bfo-to-html.sh" "$SP/merged-123.xml" "$SP/pdf-preview-123.html"
   bash "$PD/scripts/preview-banner.sh" "$SP/pdf-preview-123.html" "<template name>" "<alias>" "<sample, e.g. invoice INV123>" saved
   ```
   Stop on an `{error}`: report it and send nothing. If `bfo-to-html.sh` fails, still send the PDF
   and report the error.
   Send **both** files together with SendUserFile (render display) as the **last** action of the
   turn, after the explanatory text, so the cards sit at the bottom of the chat. The PDF is the
   real output; the HTML twin is for clicking and annotating (every element carries a `data-bfo`
   path into the merged XML). Page flow, repeated headers and fonts are exact only in the PDF.
   Nothing opens the Browser pane automatically: writing the file, `show_pane` and a preview server
   all fail to, so don't try them. Where SendUserFile is unavailable, give the paths. Previews hold
   real customer data: they live only in the scratchpad and are never committed, attached, or
   published.
5. **Edit loop.** The working copy is `$SP/pdf-draft-<id>.xml` (start as a copy of the base). After
   each edit:
   ```bash
   bash "$PD/scripts/pdf-validate.sh" "$SP/pdf-draft-123.xml"              # fix every ERROR before rendering
   jq -n --rawfile source "$SP/pdf-draft-123.xml" '{source: $source, templateId: 123, record: {type: "invoice", id: 456}}' > "$SP/draft.json"
   rl --method POST --data @"$SP/draft.json" > "$SP/render-123.json" \
     && { jq -e 'has("error") | not' "$SP/render-123.json" >/dev/null || { jq -r .error "$SP/render-123.json"; false; }; } \
     && jq -j .xml "$SP/render-123.json" > "$SP/merged-123.xml"
   bash "$PD/scripts/pdf-validate.sh" --merged "$SP/merged-123.xml"        # markup FreeMarker produced
   ```
   then PDF, twin and banner (mode `draft`) as in step 4, and re-send both. Say in one line what
   changed. Keep the FreeMarker out of the conversation; name changes in plain words. Point out
   blanks that come from the sample record (no ship-to, no PO number) rather than the template, so
   they aren't "fixed" in the wrong place. When the user annotates the twin, the `data-bfo` path
   locates the element in the merged XML; find the matching source element by structure and text
   (FreeMarker loops and `<#if>`s mean the paths don't map one to one).

   **Triage the validator in plain words**, as the email designer does with its compatibility
   check: for each finding, say what will look different or fail and where, and propose a fix.
   `ERROR` (envelope, FreeMarker structure, XML, unsupported element) means NetSuite will refuse
   or fail the render, and `sdf-template.sh` refuses to save it. `WARN` means BFO ignores or only
   partly supports something (`bfo.css`, `bfo.css-value`, `bfo.unit`), text in a `<div>` won't
   draw (`netsuite.div-text`), an absolute position may break the render (`bfo.position`), or an
   image may not load (`netsuite.image-http`, `netsuite.image-host`). Apply fixes only once the
   user agrees.
6. **Save** an existing custom template, only after an explicit yes that names the account
   ("save to <alias>"). Production is written only when the user names production for this save.
   - **SuiteCloud auth id** for that account: `suitecloud account:manageauth --list`, then
     `suitecloud account:manageauth --info <authid>` on each listed id; its Account ID must equal
     the alias's `accountId` (`netsuite-cli account list`). Browser-login ids are listed only with
     `SUITECLOUD_CI` unset, certificate (M2M) ids only with it set. None match: follow the
     suitecloud-cli skill's "Authenticate an account netsuite-cli already knows" recipe first.
   - Then, with `PROJ="$SP/sdf-<alias>"` and the template's scriptid:
   ```bash
   bash "$PD/scripts/sdf-template.sh" init <authid> "$PROJ"          # once per account; reuses an existing one
   rl --method PUT --data '{"id": 123}' > "$SP/backup-123.json"     # backup first, always
   bash "$PD/scripts/sdf-template.sh" stage "$PROJ" CUSTTMPL_EXAMPLE_INVOICE "$SP/pdf-draft-123.xml" --base "$SP/pdf-base-123.xml"
   bash "$PD/scripts/sdf-template.sh" deploy "$PROJ" CUSTTMPL_EXAMPLE_INVOICE --expect Update --authid <authid>
   rl --method GET --param id=123 > "$SP/get-123.json" && jq -j .source "$SP/get-123.json" | cmp - "$SP/pdf-draft-123.xml"
   ```
   `--authid` is the auth id of the account the user named; `deploy` refuses when `project.json`
   targets any other, when the dry run shows anything but `Update` of that one scriptid, or when
   the draft has a validator ERROR. `stage` refuses when the template changed in NetSuite since the
   base was read: re-read it, merge, and try again (`--force` only if the user says to overwrite).
   Import and deploy can each take a minute or more; give the Bash calls a long timeout. After a matching `cmp`, copy the draft over the base
   (`cp "$SP/pdf-draft-<id>.xml" "$SP/pdf-base-<id>.xml"`; the draft is now the base), render once
   in saved mode as the confirmation preview, then report the backup path and the record link
   (step 9). A failed deploy leaves the template unchanged; report the error and the backup.
7. **Which template gets the result.** When the user hands you an existing custom template (URL,
   id, scriptid or name) and asks to change, redo or rebuild it, the result goes back onto **that
   template** (same scriptid), even when rewritten from scratch: forms and scripts reference it.
   Create a new template only when the user asks for one, or when the source is a standard
   template (a custom copy, step 8).
8. **Create.** Start from `references/starter-transaction.xml` (invoice-style layout: logo and
   company header, page x of y footer, Letter, an item table with a `<thead>` of `@label`s,
   totals) or `references/starter-statement.xml` (the same frame over `statement.lines` with the
   aging row), or from a copy of an existing template. Work in `$SP/pdf-draft-new.xml`, preview
   transaction drafts against a sample (step 5), then, after an explicit yes naming the account:
   Find the auth id and `init` the project as in step 6 (production only when the user names it for
   this create).
   ```bash
   bash "$PD/scripts/sdf-template.sh" create "$PROJ" custtmpl_cp_example_invoice "$SP/pdf-draft-new.xml" --title "Example Invoice" --printtype TRANSACTION --trantype CUSTINVC
   bash "$PD/scripts/sdf-template.sh" deploy "$PROJ" custtmpl_cp_example_invoice --expect Create --authid <authid>
   netsuite-cli suiteql --account <alias> "SELECT id FROM advancedpdftemplate WHERE UPPER(scriptid) = 'CUSTTMPL_CP_EXAMPLE_INVOICE'"
   ```
   The scriptid is `custtmpl_` plus lowercase letters, digits and underscores; agree on it and the
   title with the user. `--trantype` is the upper-cased `tranType` (`CUSTINVC`); leave it out for
   print types without one. For a custom copy of a standard template, add
   `--standard <its STDTMPL… scriptid>` (it varies by account; SuiteTax accounts end in `ST`).
   `create` always writes `preferred F`: **never make a template preferred** unless the user asks,
   because that changes what prints by default, and assigning templates to forms is a UI task.
   Then GET it, render once in saved mode, and link it (step 9).
9. **Link the record.** Every successful save or create ends with a clickable link to the
   template in the account it was written to:
   ```bash
   jq -r --arg host "$NS_HOST" '"https://\($host).app.netsuite.com/app/common/custom/advancedprint/pdftemplate.nl?id=\(.id)&nl=\(if .isStandard then "T" else "F" end)&tt=\(.tranType // "CustInvc")&pt=\(.printType)&e=T"' "$SP/get-123.json"
   ```
   The URL needs `id`, `nl`, `tt` and `pt` (`id` alone gives "An unexpected error has occurred");
   templates with no transaction type still use `tt=CustInvc`. Name the link after the template
   and the account, e.g. `[Example Invoice (sb1)](https://1234567-sb1.app.netsuite.com/…)`. A
   refused or failed save gets no link; report the error instead.

## Gotchas

- **`position:absolute` needs a `position:relative` ancestor.** Without one the render fails with
  the opaque `UNEXPECTED_ERROR`. For a fixed spot on the page, use a background macro
  (`references/bfo.md`).
- **Text directly inside a `<div>` is not drawn.** Wrap it in `<p>`, `<span>` or a table cell.
- `subsidiary` comes from the RESTlet adding the transaction's subsidiary; whether NetSuite's own
  print fills it the same way is untested. If a printed PDF shows a blank where the preview didn't,
  suspect this root.
- Images need absolute, publicly reachable URLs with `&` written `&amp;`; File Cabinet images that
  aren't "available without login" go through `<@filecabinet nstype="image" src="…"/>`.
  The merged XML embeds such images as data URIs, so it can be much larger than the source.
- `UNEXPECTED_ERROR` with no detail: run `pdf-validate.sh` on the draft. If it's clean, bisect the
  draft (comment out halves with `<#-- -->`) and re-render.
- Merged statement markup is `<pdfset>` with `<html>` children, not `<pdf>`; `bfo-to-html.sh`
  and `pdf-validate.sh --merged` both accept it.
- **Never `echo "$json"` in zsh**: it expands `\r\n` escapes inside JSON strings. Write responses
  to files and read them with jq. Build request bodies with `jq --rawfile source <file>`, never
  `--arg source "$(cat …)"`: a failed `$(…)` yields an empty string or `null`. Extract source with
  `jq -j .source`, never `jq -r` (which adds a newline and breaks the byte-for-byte check).
- A RESTlet call or a deploy occasionally takes over two minutes. Give Bash calls a longer timeout
  rather than killing them; macOS has no `timeout` command.
- SDF cannot delete templates; deleting one is a UI task (Customization → Forms → Advanced
  PDF/HTML Templates). `deploy.xml` in the scratch project is rewritten for every stage or create,
  so a deploy never carries another template along.

## Installing the RESTlet — only after the user says yes

The RESTlet ships in an SDF package in the `ai-tools` repo, `netsuite/restlets/`, together with
the other CP RESTlets. This skill is a symlink into that clone, so the package is two levels up
from the skill's real path:

```bash
cd "$(cd "<this skill's base directory>" && pwd -P)/../../netsuite/restlets" && pwd -P && ls INSTALL.md
```

Read `INSTALL.md` there before you ask the user about installing, then follow it step by step. It
gives the question to ask, then the SuiteCloud CLI steps that install, upgrade or repair the package
and verify the result. No `INSTALL.md` there: ask the user where their `ai-tools` clone is.

## Maintainers

Source: the private `sdf-creative-planning` repo, `src/RESTlet/cp_pdf_template_rl.ts` and
`src/netsuite_modules/pdf-template/index.ts`, with tests under `__tests__/pdf_template/`. Shipped
here via `netsuite/restlets/sync.sh`. Spec:
`docs/superpowers/specs/2026-10-16-netsuite-pdf-designer-design.html` in that repo. Local scripts
are tested by `tests/pdf-validate.test.sh`, `tests/bfo-to-html.test.sh` and
`tests/sdf-template.test.sh` (`tests/run.sh` runs all); the allowlist is `data/bfo-support.json`.
