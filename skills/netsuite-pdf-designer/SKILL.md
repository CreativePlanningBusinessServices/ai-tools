---
name: netsuite-pdf-designer
description: Use when a task needs to view, preview, validate, edit, redesign, or create a NetSuite Advanced PDF/HTML template — a template URL (pdftemplate.nl?id=…), id, scriptid (CUSTTMPL_…/STDTMPL…) or name, "what does this invoice PDF look like", "move the PO number", "add a column to the statement", "build a new invoice template", "a PDF of this saved search", "a printout for this custom record", "will this render in NetSuite?" — in any account where Creative Planning's cp_pdf_template_rl RESTlet is installed. Covers the RESTlet's JSON contract (called via netsuite-cli restlet call), previewing the real PDF against a real record or saved search results, NetSuite's FreeMarker and the BFO HTML/CSS subset, a local validator, and saving or creating templates through a scratch SDF project (bash, awk, jq, xmllint; no Python or Node).
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
  `<#list statements as statement>` inside `<pdfset>`; a draft statement render gets the customer
  as `record` and `customer`, its subsidiary as `subsidiary`, and rebuilt `statements` data.
  Saved-search (`SEARCH`) templates list `results`, one row per search result
  (`references/freemarker.md` → Saved-search results). Each other print type reads its own data
  (`references/freemarker.md` → Roots); a template saved under the wrong type prints blank.
- A missing field (`${record.nosuchfield}`) renders as an empty string, silently. A broken
  FreeMarker construct (unclosed `<#if>`, unknown `?built-in`) fails with `UNEXPECTED_ERROR` and no
  detail, which the RESTlet translates into a hint to run the validator. So do a `<tr>` or `<td>`
  outside its `<table>` or `<tr>`, `position:absolute` directly inside `<body>`, and
  `position:fixed`. Malformed XML usually comes back with a clear "Error Parsing XML" message.
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
rl --method POST --data @"$SP/draft.json"   # draft statement: {"printType": "STATEMENT", "source": "<?xml…", "entityId": 789}
rl --method POST --data '{"printType": "SEARCH", "templateId": 453, "searchId": "customsearch_cp_balances", "limit": 50}'   # saved search
rl --method POST --data '{"printType": "TRANSACTION", "native": true, "record": {"type": "invoice", "id": 456}, "formId": 159}'   # what the form prints
rl --method POST --data '{"printType": "PICKINGTICKET", "templateId": 8, "record": {"type": "salesorder", "id": 789}}'           # picking ticket
rl --method POST --data '{"printType": "PACKINGSLIP", "templateId": 41, "record": {"type": "itemfulfillment", "id": 987}}'      # packing slip
rl --method POST --data @"$SP/raw.json"   # raw BFO XML, no data: {"xml": "<?xml…"}
```

- **Transaction** (default when `printType` is absent): `record {type, id}` is required; `type` is
  the SuiteScript record type (`CustInvc` → `invoice`, `CustCred` → `creditmemo`, `SalesOrd` →
  `salesorder`, `PurchOrd` → `purchaseorder`, `CashSale` → `cashsale`, `Estimate` → `estimate`,
  `VendBill` → `vendorbill`, `Check` → `check`). `source` makes it a draft; `templateId` alongside
  it is accepted and ignored.
  - **Custom records** use the same body: `type` is any record type `record.load` accepts, custom
    record script ids included (`{"type": "customrecord_cp_example", "id": 10}`). `${record@title}`
    prints the record type's name. NetSuite's own errors pass through: "The record type [X] is
    invalid." or "That record does not exist."
- **Search**: `searchId` (required: a saved search's internal id or script id), `limit` (default
  50, at most 1000) and `resultsAlias` (default `results`, the name the template lists over:
  `<#list results as result>`), with `templateId` / `scriptId` (saved) or `source` (draft). The
  RESTlet loads the saved search, takes its first `limit` rows and renders the template against
  them. This is the same render path a script printing the search uses, so the preview is exact.
  `record` in the response is `{"searchId": …, "searchType": "customer", "resultCount": 50,
  "truncated": true}`; `truncated` means the search had more rows than were shown. `record` is not
  accepted.
- **Native** (`"native": true`, JSON `true` only): NetSuite's own print through a form, with no
  template in the body (`templateId`, `scriptId` and `source` are refused); `mode` is `native`.
  - Transactions: `record` plus an optional `formId` (without it, the record's own form decides,
    as the Email button's "attach PDF" does). Returns the PDF and the merged `xml`.
  - Picking tickets (`formId`, `shipgroup`, `location` optional) and packing slips (`formId`
    optional): PDF only, `xml` is `null`.
  - A form that isn't set to an advanced template prints NetSuite's basic layout, so a native
    render shows what the form prints, not necessarily the template being edited.
- **Picking ticket** (`PICKINGTICKET`): `record` is the sales order (`salesorder` only). Saved and
  draft render the template with the sales order as `record`.
- **Packing slip** (`PACKINGSLIP`): `record` is an `itemfulfillment` (loaded as `record`, its
  created-from sales order as `salesorder`) or a `salesorder` alone, which stands in for the
  fulfillment and makes the result `"approximate": true`. A fulfillment with no created-from sales
  order is refused. `returnForm` is never supplied, so the template's return-form section stays
  hidden; when the source reads it, `notes` says so.
- In picking tickets and packing slips, `${record@title}` would print the loaded record's type
  ("Sales Order"), so the RESTlet swaps in "Picking Ticket" / "Packing Slip" on its copy of the
  source and lists that in `adaptations` (the saved template is never changed).
- **Raw XML** (`{"xml": "<?xml…"}`, nothing else): renders BFO markup as is, with no record and no
  FreeMarker, through `render.xmlToPdf`; `mode` and `printType` are `raw` / `RAW`, `record` is
  `null`. The input must be an `<?xml …?>` document with a `<pdf>`, `<pdfset>` or `<html>` root
  and no `<#`/`${` (use `source` for a template). Merged markup from a native transaction render
  or a saved statement names its documents `<html>`, which `xmlToPdf` refuses, so the RESTlet
  renames them to `<pdf>` and lists `root: html → pdf` in `adaptations`; `pdf-validate.sh --merged`
  accepts either form.
- Other print types answer `<printType> has no preview yet — supported: TRANSACTION, STATEMENT, SEARCH, PICKINGTICKET, PACKINGSLIP`.
- **Statement**: `entityId` (customer) is required; `statementDate` (default today), `startDate`
  (default none: the whole history) and `openTransactionsOnly` (boolean, default false) are
  optional, dates in the user's NetSuite format (`MM/DD/YYYY` in CP's accounts). Saved and draft
  renders both refuse a date that doesn't parse, a `startDate` after the statement date, and an
  `openTransactionsOnly` that isn't a JSON boolean.
  - **Saved**: `formId`, the id of an existing statement form that prints with the template, is
    required, and the form decides the template. SuiteQL has no table that lists transaction
    forms, so ask the user for the form id (Customization → Forms → Transaction Forms, type
    Statement; the id is in the form's URL).
  - **Draft**: `source` and **no** `formId` (a `formId` next to `source` is refused). NetSuite can't
    run a draft through its statement engine, so the RESTlet rebuilds the statement with SuiteQL
    and the response adds `"approximate": true`. What is rebuilt and what isn't: see "Draft
    statements" under Gotchas.

```json
{ "mode": "saved" | "draft" | "native" | "raw",
  "printType": "TRANSACTION" | "STATEMENT" | "SEARCH" | "PICKINGTICKET" | "PACKINGSLIP" | "RAW",
  "record": { "type": "invoice", "id": 456, "formId": 159 } | { "entityId": 789, "formId": 210 } | { "entityId": 789 }
          | { "searchId": "customsearch_…", "searchType": "customer", "resultCount": 50, "truncated": false } | null,
  "pdf": "<base64>", "pdfBytes": 41318, "xml": "<merged BFO markup>" | null,
  "approximate": true,                     // draft statements; a packing slip from a sales order
  "notes": ["returnForm isn't supplied…"], // when something the template reads isn't previewed
  "adaptations": ["title: Packing Slip"] } // what the RESTlet changed on its copy of the source
```

A saved statement's `xml` is a `<pdfset>` holding one `<html>` child per statement; a draft
statement's keeps the source's `<pdf>` children. `pdf-validate.sh --merged` accepts either. Empty
source, or the literal `null`/`undefined`, is refused (a shell pipeline lost its input).

### PUT `{id}` or `{scriptid}` — backup

```bash
rl --method PUT --data '{"id": 123}' > "$SP/backup-123.json"
```

The RESTlet reads the current source itself and writes it to
`/SuiteScripts/CreativePlanning/pdf-template-backups/<id>-<scriptid>-<yyyyMMdd-HHmmss>.xml`:
`{"id": 123, "scriptid": "…", "backup": {"id": 2468, "path": "/SuiteScripts/…"}}`. The timestamp
is in the account's (server's) time zone, not the user's local time.

Restore = step 6 with the backup's contents as the draft:
- the backup's file id is `backup.id` in the PUT response;
- download it with the netsuite-file-cabinet skill (`--param id=<backup.id> --param contents=T`) and
  write it with `jq -j .contents` (not `jq -r`) as the draft;
- draft-render it (step 5) like any other draft, and back up the current state before staging, as
  step 6 always does, so the restore itself can be undone;
- pass `stage --base` the source NetSuite holds **now** (a fresh GET, `jq -j .source`), not the old
  base, or `stage` refuses it as stale.

## Workflow

1. **Resolve the template.** From a URL take the `id=`; from a name fragment list matches:
   ```bash
   netsuite-cli suiteql --account <alias> "SELECT id, scriptid, name, printtype, trantype, preferred FROM advancedpdftemplate WHERE inactive = 'F' AND LOWER(name) LIKE '%invoice%'"
   ```
   `GET` it, keep the source as `$SP/pdf-base-<id>.xml` (with `jq -j`), and tell the user the name,
   print and transaction type, whether it's the preferred template, and the source size. For a
   standard template, say that saving will create a custom copy.

   **Choosing the print type for a new template.** An existing template's `printType` comes from
   its GET. A new one needs a type before anything else: `create --printtype` fixes it, it decides
   where NetSuite offers the template (a form's picking-ticket slot lists only `PICKINGTICKET`
   templates), and it decides which data a preview supplies. Map the request:

   | The user asks for | `--printtype` | `--trantype` |
   |---|---|---|
   | an invoice, credit memo, estimate, sales order, purchase order, cash sale, bill, check… | `TRANSACTION` | the upper-cased `tranType` (`CUSTINVC`, `CUSTCRED`, `SALESORD`…) |
   | a statement | `STATEMENT` | — |
   | a PDF of saved search results | `SEARCH` | — |
   | a picking ticket / a packing slip | `PICKINGTICKET` / `PACKINGSLIP` | — |
   | a shipping / mailing / item label | `SHIPPINGLABEL` / `MAILINGLABEL` / `ITEMLABEL` | — |
   | a GL impact page / a bill of materials / a price list | `GLIMPACT` / `BOM` / `PRICELIST` | — |
   | a custom record's printout | `TRANSACTION` (unconfirmed) | none; ask which record type it's for |

   When the request doesn't say ("a label", "a printout"), ask. A copy of an existing template
   takes that template's type. The custom-record row is unconfirmed: no account has been checked
   for how its custom-record templates are stored. Before creating one, GET a template the account
   already uses for that record (or ask how it's printed today, usually by a script), and take its
   print type. `TRANSACTION` (custom records included), `STATEMENT`, `SEARCH`, `PICKINGTICKET`
   and `PACKINGSLIP` can be previewed in this version (step 3).
2. **Pick a sample record** of the template's `tranType`. If the user named one, use it. Otherwise
   list five recent candidates that have lines and ask the user to choose:
   ```bash
   netsuite-cli suiteql --account <alias> "SELECT txn.id, txn.tranid, txn.trandate, BUILTIN.DF(txn.entity) AS entity, COUNT(line.id) AS linecount FROM transaction txn JOIN transactionline line ON line.transaction = txn.id WHERE txn.type = 'CustInvc' AND line.mainline = 'F' AND line.taxline = 'F' GROUP BY txn.id, txn.tranid, txn.trandate, BUILTIN.DF(txn.entity) ORDER BY txn.id DESC FETCH FIRST 5 ROWS ONLY"
   ```
   Prefer a sample where the fields the template uses are filled in (read its `${record.…}` paths).
   For a statement, a customer with open invoices:
   `SELECT customer.id, customer.entityid, COUNT(txn.id) AS openinvoices FROM transaction txn JOIN customer ON customer.id = txn.entity WHERE txn.type = 'CustInvc' AND txn.status = 'A' GROUP BY customer.id, customer.entityid ORDER BY openinvoices DESC FETCH FIRST 5 ROWS ONLY`
   (`ORDER BY COUNT(*)` fails with `UNEXPECTED_ERROR`; order by the alias). A saved statement
   render also needs the statement form id from the user; a draft doesn't.
   For a `SEARCH` template, the sample is a saved search: ask which one, and use the
   netsuite-saved-search skill to find candidates. Prefer a search whose columns have custom
   labels, because `${result.x@label}` prints only a custom label (blank otherwise).
   For a custom record, list recent ones with
   `SELECT id, name FROM <customrecord_scriptid> ORDER BY id DESC FETCH FIRST 5 ROWS ONLY`, and
   read its `custrecord_…` field ids from `netsuite-cli`'s record schema.
   For a picking ticket, a sales order waiting to be fulfilled:
   `SELECT txn.id, txn.tranid, txn.trandate FROM transaction txn WHERE txn.type = 'SalesOrd' AND txn.status IN ('B', 'D', 'E') ORDER BY txn.id DESC FETCH FIRST 5 ROWS ONLY`.
   For a packing slip, a recent fulfillment and its sales order:
   `SELECT txn.id, txn.tranid, txn.trandate, mainLine.createdfrom, BUILTIN.DF(mainLine.createdfrom) AS salesorder FROM transaction txn JOIN transactionline mainLine ON mainLine.transaction = txn.id AND mainLine.mainline = 'T' WHERE txn.type = 'ItemShip' ORDER BY txn.id DESC FETCH FIRST 5 ROWS ONLY`
   (`createdfrom` lives on the main line; `transaction.createdfrom` is not a SuiteQL column).
   Only a fulfillment created from a sales order can be previewed. If the account has none, use
   a sales order and say the preview is approximate.
3. **Check what can be previewed.** Transactions and custom records: saved and draft. Saved
   searches: saved and draft, against the search's first rows (exact). Picking tickets and packing
   slips: saved and draft (a packing slip from a sales order alone is approximate), plus native.
   **Native** (`native: true`) answers "what will NetSuite actually print or attach": run it when
   the user asks that, or to compare with the template. A form without an advanced template prints
   NetSuite's basic layout, which is not the template being edited; say so when the native PDF
   doesn't look like the template. **Raw XML** is for sketching a layout before there's data and
   for re-rendering merged XML you edited by hand. A change found that way still goes into the
   FreeMarker source. Statements: saved (through a
   form) and draft (rebuilt data, **approximate**). For a statement draft, build the body with
   `jq -n --rawfile source "$SP/pdf-draft-<id>.xml" '{printType: "STATEMENT", source: $source, entityId: 789}'`
   (add `statementDate` / `startDate` / `openTransactionsOnly` when the user asks), label the
   preview `draft (approximate: statement data rebuilt with SuiteQL, not NetSuite's statement engine)`
   in its caption, and tell the user the numbers are rebuilt. When a form for the template exists, a saved render
   through it is the reference to compare against. For a saved search, the body is
   `{printType: "SEARCH", templateId: 453, searchId: "customsearch_…"}` (or `source` for a draft).
   Mention `truncated: true` when the search had more rows than the preview shows. Other print types
   (labels, price list, GL impact, bill of materials): no preview in this version; read, validate
   and save still work. **Check templates that loop over `records`** (the
   Print Checks batch list) can't be previewed either: before rendering, run
   `grep -Eq '<#list[[:space:]]+records[[:space:]]' "$SP/pdf-base-<id>.xml"` and, on a match, say
   so instead of calling the RESTlet (which refuses them too, naming Print Checks). Validate and
   save still work for them.
4. **Preview.** `POST` (saved mode first), then write the PDF, keeping the merged markup for the
   validator:
   ```bash
   rl --method POST --data '{"templateId": 123, "record": {"type": "invoice", "id": 456}}' > "$SP/render-123.json" \
     && { jq -e 'has("error") | not' "$SP/render-123.json" >/dev/null || { jq -r .error "$SP/render-123.json"; false; }; } \
     && jq -j .pdf "$SP/render-123.json" | base64 -D > "$SP/pdf-preview-123.pdf" \
     && jq -j .xml "$SP/render-123.json" > "$SP/merged-123.xml"
   ```
   Stop on an `{error}`: report it and send nothing. Look at the PDF yourself (Read tool) before
   sending it, so what you tell the user matches what it shows.
   Send it with SendUserFile (render display) as the **last** action of the turn, after the
   explanatory text, so the card sits at the bottom of the chat. The caption names the template,
   the account, the sample record and the mode: `saved`, `draft`, step 3's approximate statement
   label, `native (what the form prints)`, `saved (approximate: sales order stands in for the
   fulfillment)` / `draft (approximate: …)` for any packing slip rendered from a sales order (the
   response says `approximate: true`), or `raw (BFO markup, no data)`. Report any `notes` and `adaptations` in one line
   each. A result with `xml: null` (native picking tickets and packing slips) has no merged markup,
   so skip `pdf-validate.sh --merged` for it.
   When one turn produces several previews, send them all in that one call and name each in the
   caption. The user can mark up the PDF in Claude and send it back to point at what to change.
   Where SendUserFile is unavailable, give the path. Previews hold real customer data: they live
   only in the scratchpad and are never committed, attached, or published.
5. **Edit loop.** The working copy is `$SP/pdf-draft-<id>.xml` (start as a copy of the base).
   **Most NetSuite-saved sources are CRLF** (the starters are LF), and some mix CRLF and LF lines:
   match the endings of the lines you edit. The Edit tool and whole-file substitutions
   (`perl -0777`, explicit `\r\n`) keep them; line-anchored `sed` silently matches nothing on a CRLF
   line, and `awk` writes LF lines and adds a final newline the source didn't have. Confirm with
   `diff` that the edit changed something before rendering. The body below is for
   transactions; for a new template, leave `templateId` out. Statement drafts use step 3's body.
   After each edit:
   ```bash
   bash "$PD/scripts/pdf-validate.sh" --printtype TRANSACTION "$SP/pdf-draft-123.xml"   # the template's printType; fix every ERROR before rendering
   jq -n --rawfile source "$SP/pdf-draft-123.xml" '{source: $source, templateId: 123, record: {type: "invoice", id: 456}}' > "$SP/draft.json"
   rl --method POST --data @"$SP/draft.json" > "$SP/render-123.json" \
     && { jq -e 'has("error") | not' "$SP/render-123.json" >/dev/null || { jq -r .error "$SP/render-123.json"; false; }; } \
     && jq -j .xml "$SP/render-123.json" > "$SP/merged-123.xml"
   bash "$PD/scripts/pdf-validate.sh" --merged "$SP/merged-123.xml"        # markup FreeMarker produced
   ```
   then write the PDF as in step 4 (mode `draft`) and re-send it. Say in one line what changed.
   Keep the FreeMarker out of the conversation; name changes in plain words. Point out blanks that
   come from the sample record (no ship-to, no PO number) rather than the template, so they aren't
   "fixed" in the wrong place. When the user marks up the PDF, find the marked element in the
   source by its printed text and its place in the layout (a header or footer macro, a table row,
   a totals cell); text inside a FreeMarker loop or `<#if>` comes from one source element however
   often it prints.

   **Triage the validator in plain words**, as the email designer does with its compatibility
   check: for each finding, say what will look different or fail and where, and propose a fix.
   `ERROR` means NetSuite will refuse or fail the render, and `sdf-template.sh` refuses to save it:
   the envelope, FreeMarker structure, an unknown `?built-in` (`freemarker.builtin`), XML (`xml.*`;
   `xml.tag-text` is text such as a `{TOKEN}` inside a tag, and XML structure errors come one at a
   time, so run the validator again after fixing one), a table element outside its parent
   (`bfo.table`), `position:absolute` directly inside `<body>` (`bfo.position`), and CSS that
   breaks the render (`bfo.css-value … (breaks)`, e.g. `position:fixed`). `WARN` means BFO ignores
   or only partly supports something (`bfo.css`, `bfo.css-value`, `bfo.unit`, `bfo.attribute`),
   may drop an element it doesn't know (`bfo.element`: check the PDF), text in a `<div>` won't draw
   (`netsuite.div-text`), an absolute position in a `<style>` rule couldn't be checked
   (`bfo.position`), non-Latin text needs the nsfont link (`netsuite.nsfont`), or an image may not
   load (`netsuite.image-http`, `netsuite.image-host`). `netsuite.roots` (only with `--printtype`)
   means the source reads data this print type never gets, such as `salesorder` (packing-slip
   data) in an invoice template, so it would print blank: confirm the print type with the user
   before rendering or saving. A clean or WARN-only result is not proof:
   the draft render is the test. Apply fixes only once the user agrees.
6. **Save** an existing custom template, only after an explicit yes that names the account
   ("save to <alias>"). Production is written only when the user names production for this save.
   For previewable print types (transactions, statements), save only a draft whose most recent
   draft render succeeded. Never save after an `{error}` render without telling the user and
   getting their yes.
   - **SuiteCloud auth id** for that account: `suitecloud account:manageauth --list`, then
     `suitecloud account:manageauth --info <authid>` on each listed id; its Account ID must equal
     the alias's `accountId` (`netsuite-cli account list`). Some CLI versions list browser-login ids
     only with `SUITECLOUD_CI` unset and certificate (M2M) ids only with it set: if the id you need
     is missing, list again with the other setting. None match: follow the suitecloud-cli skill's
     "Authenticate an account netsuite-cli already knows" recipe first.
   - Then, with `PROJ="$SP/sdf-<alias>"` and the template's scriptid:
   ```bash
   bash "$PD/scripts/sdf-template.sh" init <authid> "$PROJ"          # once per account; reuses an existing one
   rl --method PUT --data '{"id": 123}' > "$SP/backup-123.json"     # backup first, always
   bash "$PD/scripts/sdf-template.sh" stage "$PROJ" CUSTTMPL_EXAMPLE_INVOICE "$SP/pdf-draft-123.xml" --base "$SP/pdf-base-123.xml"
   bash "$PD/scripts/sdf-template.sh" deploy "$PROJ" CUSTTMPL_EXAMPLE_INVOICE --expect Update --authid <authid>
   rl --method GET --param id=123 > "$SP/get-123.json" && jq -j .source "$SP/get-123.json" | cmp - "$SP/pdf-draft-123.xml"
   ```
   `--authid` is the auth id of the account the user named; `deploy` refuses when `project.json`
   targets any other, when nothing is staged for that scriptid (a refused `stage` or `create`
   leaves nothing), when the staged source has a validator ERROR (it validates again, so an edit
   after `stage` is caught), or when the dry run shows anything but `Update` of that one scriptid.
   `stage` refuses a draft with a validator ERROR, and refuses when the template changed in
   NetSuite since the base was read: re-read it, merge, and try again (`--force` only if the user
   says to overwrite). Neither can see a WARN-level fault that fails the render, which is why the
   save waits for a successful draft render.
   Import and deploy can each take a minute or more; give the Bash calls a long timeout. After a matching `cmp`, copy the draft over the base
   (`cp "$SP/pdf-draft-<id>.xml" "$SP/pdf-base-<id>.xml"`; the draft is now the base), render once
   in saved mode as the confirmation preview, then report the backup path and the record link
   (step 9). A failed deploy leaves the template unchanged; report the error and the backup.
7. **Which template gets the result.** When the user hands you an existing custom template (URL,
   id, scriptid or name) and asks to change, redo or rebuild it, the result goes back onto **that
   template** (same scriptid), even when rewritten from scratch: forms and scripts reference it.
   Create a new template only when the user asks for one, or when the source is a standard
   template (a custom copy, step 8). "Copy X and change it" is one create: apply the changes to
   the copy's draft, preview it, and `create` it with them (step 8); step 6 is for later edits.
8. **Create.** Start from `references/starter-transaction.xml` (invoice-style layout: logo and
   company header, page x of y footer, Letter, an item table with a `<thead>` of `@label`s,
   totals) or `references/starter-statement.xml` (the same frame over `statement.lines` with the
   aging row), or from a copy of an existing template. Pick the print type first (step 1). Work in
   `$SP/pdf-draft-new.xml`, run `pdf-validate.sh --printtype <that type>` on it, and preview
   transaction and custom-record drafts against a sample (step 5, no `templateId`), statement drafts
   with step 3's body, and saved-search drafts with `source` and a `searchId`. Then, after an
   explicit yes naming the account:
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

- **`position:absolute` can't sit directly inside `<body>`**: there the render fails with the
  opaque `UNEXPECTED_ERROR`. Inside a table cell or a block it renders, placed against its parent.
  `position:fixed` always fails. For a fixed spot on the page, use a background macro
  (`references/bfo.md`).
- **Table elements nest strictly**: `<tr>` directly inside `<table>`, `<thead>`, `<tbody>` or
  `<tfoot>`, cells directly inside `<tr>`. A stray one fails the render with `UNEXPECTED_ERROR`.
- **Text directly inside a `<div>` is not drawn.** Wrap it in `<p>`, `<span>` or a table cell.
- `subsidiary` comes from the RESTlet adding the transaction's subsidiary; whether NetSuite's own
  print fills it the same way is untested. If a printed PDF shows a blank where the preview didn't,
  suspect this root.
- Images need absolute, publicly reachable URLs with `&` written `&amp;`; File Cabinet images that
  aren't "available without login" go through `<@filecabinet nstype="image" src="…"/>`.
  The merged XML embeds such images as data URIs, so it can be much larger than the source.
- `UNEXPECTED_ERROR` with no detail: run `pdf-validate.sh` on the draft; it catches the causes
  listed under "How NetSuite renders PDF templates". If it's clean, bisect the draft (comment out
  halves with `<#-- -->`) and re-render.
- Merged statement markup is `<pdfset>` with `<html>` children, not `<pdf>`;
  `pdf-validate.sh --merged` accepts it.
- **Draft statements** are rebuilt, not NetSuite's: AR lines in the customer's currency up to the
  statement date (type name + `#` + number, charge or payment by sign, due date), a running
  balance, a `Balance Forward` line from `startDate`, open-only mode, aging by days past due, the
  default billing address, and any `line.custbody_*` field the template reads. In a sandbox test a
  custom statement template's draft matched its saved render line for line. Known gaps: one statement in
  the customer's currency (no consolidated or multi-currency statements); aging uses today's open
  amounts even for a past `statementDate`; same-day transactions may print in a different order,
  so balances within that day can differ (end-of-day balances agree); labels are NetSuite's English
  ones; `remittanceSlip` prints nothing; on Multi-Book accounts only the primary accounting book is
  read; and subcustomers' transactions are left out (only the customer's own). A legacy
  single-statement layout (reads `record.lines`, never `statements`, as NetSuite's
  `STDTMPLSTATEMENT` does) is refused with an `{error}`, as is a template that passes `statements`
  through a macro call (`<@…>`) or a square-bracket tag (`[#…]`): preview those with a saved render
  through a statement form (`formId`). To make the custom data work, the RESTlet adapts the draft
  before rendering: `statements` (in FreeMarker code, not in string literals) points into its data, known
  `${statement.…@label}` / `${line.…@label}` become their label text, `${record@title}` becomes
  "Statement", and every `statement.…` / `line.…` path the template reads is filled (NetSuite
  silently drops a directive that reads a missing key in custom data). The saved template's source
  is never changed by this.
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
`src/netsuite_modules/pdf-template/index.ts` (draft statement data in `statement-data.ts`), with
tests under `__tests__/pdf_template/`. Shipped
here via `netsuite/restlets/sync.sh`. Spec:
`docs/superpowers/specs/2026-10-16-netsuite-pdf-designer-design.html` in that repo. Local scripts
are tested by `tests/pdf-validate.test.sh` and `tests/sdf-template.test.sh` (`tests/run.sh` runs all); the allowlist is `data/bfo-support.json`.
