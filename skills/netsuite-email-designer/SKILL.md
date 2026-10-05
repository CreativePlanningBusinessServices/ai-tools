---
name: netsuite-email-designer
description: Use when a task needs to view, preview, edit, redesign, or create a NetSuite email template — a template URL (emailtemplate.nl?id=…), id or name, "what does this email look like", "change the wording of the invoice email", "build a new email for X" — in any account where Creative Planning's cp_email_template_rl RESTlet is installed. Covers the RESTlet's JSON contract (called via netsuite-cli restlet call), how NetSuite renders FreeMarker templates, previewing in the Code tab against a real record, and a react.email starter for templates built from scratch.
---

# Email templates via the cp_email_template_rl RESTlet

`cp_email_template_rl` is a RESTlet Creative Planning installs into NetSuite accounts, CP's own and
clients' (script/deploy ids are the same everywhere): `customscript_cp_email_template_rl` /
`customdeploy_cp_email_template_rl`. It describes a scriptable email template with its body, renders
it against real records with NetSuite's own engine, saves edits with a backup, and creates new
templates — call it with `netsuite-cli restlet call`.

## Before the first call in an account

1. **Pick the account.** Every call takes `--account <alias>`, the `netsuite-cli` alias for the
   target account. Never fall back to the CLI's default account: if the user hasn't said which
   account, ask.
2. **Confirm the RESTlet is installed there** (once per account per session):

   ```bash
   netsuite-cli suiteql --account <alias> "SELECT scriptid FROM script WHERE scriptid = 'customscript_cp_email_template_rl'"
   ```

   - One row: go ahead.
   - No rows: it isn't installed. Tell the user it can be installed from the `ai-tools` repo
     (`netsuite/restlets/`, see its README) and stop. Never deploy it yourself; installing
     scripts into an account is the user's decision.
   - The query itself errors (unknown alias, auth failure): report that error. It says nothing
     about whether the RESTlet is installed.

**Never deploy, install, or edit script or deployment records yourself**, in any account. If the
RESTlet is missing, undeployed, not released, or failing, report what you found and let the user
fix it.

Define a helper and a work folder once per shell (zsh does not word-split `$VARS`, so the helper
is a function, not a variable; `$SP` below is the session scratchpad folder for this template):

```bash
rl() { netsuite-cli restlet call --account <alias> --script customscript_cp_email_template_rl --deploy customdeploy_cp_email_template_rl "$@"; }
SP=<session scratchpad directory>/email-designer; mkdir -p "$SP"
```

## How NetSuite renders email templates

- A template record (`emailtemplate`) stores its body either as a File Cabinet HTML file
  (`storage: "file"`) or inline in its content field (`storage: "inline"`). The subject is a
  FreeMarker string too.
- Body and subject run through FreeMarker. Root hashes: `transaction`, `entity`, `customrecord`
  (also `customRecord`), `case`, `recipient`, `sender`/`user`, `companyInformation`
  (`logoUrl`, `companyName`), `preferences` (`message_signature`). Field ids are SuiteScript ids
  (`${transaction.tranid}`, `${customrecord.custrecord_client}`); camel or lower case both work;
  joins are dot paths (`${customrecord.custrecord_contact.firstname}`). Sublists are not exposed.
- The template's Record Type (Entity / Transaction / Custom Record / Case / Event) only drives the
  UI field picker. At merge time NetSuite uses whichever records are passed.
- The RESTlet renders with `render.mergeEmail`, the same call NetSuite scripts use to send, so a
  preview is byte-for-byte what a send would produce for that record.
- **NetSuite validates a template's FreeMarker when the template record is saved**, against a model
  that has the record-type hashes, `companyInformation` and `preferences` but **no `recipient` or
  `sender`**. A body with `${recipient.firstName}` cannot be saved as a record (draft previews and
  PUT create both save one) until the reference is null-safe: `${(recipient.firstName)!""}` — the
  parentheses matter, `${recipient.firstName!""}` still fails. The RESTlet returns this explanation
  when it hits the error. Existing file-backed templates are unaffected by body-only saves, which
  write the file directly.

## RESTlet contract

Bodyless GET returns a JSON **string** (NetSuite serialization quirk; `restlet call` parses it).
Caller mistakes come back as `{"error": "…"}`; NetSuite failures pass through with their message.

### GET `?id=<templateId>` — describe + body

```bash
rl --method GET --param id=123
```

```json
{ "id": 123, "name": "Invoice Email", "scriptid": "custemailtmpl_invoice", "recordType": "TRANSACTION",
  "subject": "Invoice ${transaction.tranid}", "isInactive": false, "isPrivate": false,
  "storage": "file", "mediaItem": { "id": 456, "name": "invoice.html", "path": "/Templates/Marketing Templates/invoice.html" },
  "body": "<!DOCTYPE html>…", "lastModifiedDate": "10/05/2026" }
```

`mediaItem` is `null` for inline templates. Pass only the numeric id, never the
`emailtemplate.nl?id=` URL (the error says so).

### POST — render a preview

```bash
rl --method POST --data '{"templateId": 123, "transactionId": 456, "recipient": {"type": "customer", "id": 789}}'
rl --method POST --data @draft.json      # {"templateId": 123, "body": "<draft html>", "customRecord": {"type": "customrecord_x", "id": 42}}
```

Keys: `templateId`, `body`, `subject`, `recordType`, `transactionId`, `entity`, `recipient`,
`customRecord`, `supportCaseId`. Refs are `{type, id}`; string ids are coerced. **At least one
record ref is required.**

- No `body`/`subject` → **saved mode**: merges the saved template.
- `body` and/or `subject` → **draft mode**: creates a temporary private, inactive template holding
  the draft, merges it, deletes it. `subject`/`recordType` default to the saved template's when
  `templateId` is given; without `templateId`, `body` is required and `recordType` defaults to
  `TRANSACTION`.

```json
{ "mode": "saved" | "draft", "subject": "Invoice INV123", "body": "<!DOCTYPE html>…",
  "merged": { "transactionId": 456, "recipient": { "type": "customer", "id": 789 } },
  "warning": "temporary template 5001 could not be deleted — remove it by hand: …" }
```

A FreeMarker error in a draft (bad field, unclosed `<#if>`) comes back as `error` with NetSuite's
message; point the user at the offending expression. A `warning` about an undeleted temporary
template means a record named "Email Designer preview …" needs removing.

### PUT `{id, …}` — save

```bash
rl --method PUT --data @save.json        # {"id": 123, "body": "<html>", "subject": "…", "name": "…"}  (any subset)
```

Response: the GET shape plus `backup: {id, path} | null` and an optional `warning`.

- When `body` changes, the previous body is first written to
  `/SuiteScripts/CreativePlanning/email-template-backups/<id>-<scriptid|slug>-<yyyyMMdd-HHmmss>.html`.
  File-backed templates are overwritten in place (same media id, same URL); inline ones update the
  record's content.
- Body identical to the saved body → nothing written, `backup: null`, warning says so.
- Refused with `error`: an empty body; the literal strings `null`/`undefined` (a shell pipeline lost
  its input); a body that removes every `${…}` field from a template that had them, unless the
  request carries `"allowNoFields": true`.
- Restore = PUT the backup file's contents back (download it with the cp-file-cabinet skill).

### PUT without `id` — create

```bash
rl --method PUT --data '{"name": "Welcome", "recordType": "TRANSACTION", "subject": "…", "body": "<html>", "storage": "file"}'
```

`recordType`: `ENTITY | TRANSACTION | CUSTOM | CASE | EVENT`. `storage` defaults to `inline`;
`file` creates the HTML file first (default folder `/Templates/Marketing Templates`, the only
folder NetSuite accepts for template files; `folder` overrides) and deletes it if the record save
fails. Returns the GET shape.

## Workflow

1. **Resolve the template.** From a URL take the `id=`; from a name fragment list matches:
   ```bash
   netsuite-cli suiteql --account <alias> "SELECT id, name, recordtype, mediaitem FROM emailtemplate WHERE isinactive = 'F' AND LOWER(name) LIKE '%invoice%'"
   ```
   Then `GET` it and tell the user the name, record type, storage, subject and body size.
2. **Pick a sample record.** If the user named one, use it. Otherwise read the body and subject for
   `${transaction.…}` / `${customrecord.…}` / `${entity.…}` / `${case.…}`, list five recent
   candidates, and ask the user to choose:
   - transaction: `SELECT id, tranid, entity, trandate FROM transaction WHERE type = 'CustInvc' ORDER BY id DESC FETCH FIRST 5 ROWS ONLY` (ask which transaction type once if the template doesn't make it obvious)
   - custom record: find the type that owns a `custrecord_` field the body uses, then list its rows:
     ```bash
     netsuite-cli suiteql --account <alias> "SELECT recordtype FROM customfield WHERE LOWER(scriptid) = 'custrecord_client'"
     netsuite-cli suiteql --account <alias> "SELECT id, name FROM <customrecord_type> ORDER BY id DESC FETCH FIRST 5 ROWS ONLY"
     ```
     (if `customfield` doesn't resolve it, `SELECT scriptid, name FROM customrecordtype WHERE LOWER(name) LIKE '%<word from the template name>%'`)
   - entity: `SELECT id, entityid, companyname FROM customer ORDER BY id DESC FETCH FIRST 5 ROWS ONLY`
   - case: `SELECT id, casenumber, title FROM supportcase ORDER BY id DESC FETCH FIRST 5 ROWS ONLY`

   "Most recent" means highest internal id; ids are unique, dates tie. `recipient` is the person the
   email goes to: for a transaction, a contact of its customer (`SELECT id, firstname, lastname FROM
   contact WHERE company = <entityId>`) when the template uses `${recipient.…}`; a company customer
   has no first name and renders it blank. Omit `recipient` when the template never references it. Fields the sample leaves blank render empty — say so in the
   preview message rather than "fixing" the template.
3. **Preview.** `POST` in saved mode and write the body to `$SP/email-preview-<templateId>.html`, with a banner inserted after the opening `<body…>` tag (or
   prepended when there is none):
   ```bash
   python3 - "$SP/email-preview-123.html" "<subject>" "<alias>" "<sample>" "saved" <<'EOF'
   import re, sys
   path, subject, account, sample, mode = sys.argv[1:6]
   banner = (f'<div style="font:13px/1.4 -apple-system,sans-serif;background:#fff7e6;border-bottom:1px solid #e6c576;padding:8px 12px">'
             f'<b>Subject:</b> {subject} &nbsp;·&nbsp; <b>Account:</b> {account} &nbsp;·&nbsp; <b>Sample:</b> {sample} &nbsp;·&nbsp; '
             f'<b>Mode:</b> {mode} &nbsp;·&nbsp; Preview only — contains live record data, do not share</div>')
   html = open(path).read()
   m = re.search(r'<body[^>]*>', html, re.I)
   html = html[:m.end()] + banner + html[m.end():] if m else banner + html
   open(path, 'w').write(html)
   EOF
   ```
   Show the file in the Code tab's side panel (SendUserFile with render display) when that tool is
   available; otherwise give the user the path. Previews hold
   real customer data: they live only in the scratchpad and are never committed, attached, or
   published.
4. **Edit loop.** Keep the working copy at `$SP/email-draft-<templateId>.html`. After each edit:
   ```bash
   jq -n --arg body "$(cat "$SP/email-draft-123.html")" '{templateId: 123, body: $body, transactionId: 456}' > "$SP/draft.json"
   rl --method POST --data @"$SP/draft.json" > "$SP/draft-out.json"
   jq -r .body "$SP/draft-out.json" > "$SP/email-preview-123.html"   # then banner + show
   ```
   Say in one line what changed. Never turn a `${…}` field into literal text, or literal text into
   a field, without saying so.
5. **Save.** Only after an explicit yes that names the account ("save to <alias>"). Build the PUT
   body from the draft file the same way, `PUT`, then report `backup.id` and `backup.path` and how
   to restore. Finish with one saved-mode `POST` as the confirmation preview.
6. **New templates with react.email.** Copy `react-email-starter/` (next to this file) to the
   destination the user names (for Creative Planning: `sdf-creative-planning/email-templates/<slug>/`),
   `npm install`, author `emails/<slug>.tsx` with `<NS expr>`, `ns('…')` and `<FreeMarker>` (its
   README has the one rule), `npm run export`, preview `out/<slug>.html` in draft mode with a sample
   record, iterate in the TSX only, then `PUT` without `id` (`storage: "file"` for CP) to create.
   When a TSX source exists, later tweaks go there, not in the exported HTML.
7. **Compliance.** Email templates are client-facing communications: remind the user that their
   firm's review process applies before use (for Creative Planning, Compliance review).

## Gotchas

- `${recipient.…}` / `${sender.…}` in a draft or a new template must be written null-safe,
  `${(recipient.firstName)!""}`, or the temporary/new template record cannot be saved (see "How
  NetSuite renders"). The error names the missing root.
- A RESTlet call occasionally takes over two minutes (NetSuite side). Give Bash calls a longer
  timeout rather than killing them; macOS has no `timeout` command.

- **Never `echo "$json"` in zsh** — it expands `\r\n` escapes inside JSON strings and jq then
  fails with "control characters must be escaped". Write responses to files and read them with jq;
  use `printf '%s'` if a variable is unavoidable.
- A `$(…)` that fails yields an empty string, and `jq -r .contents` on a non-object yields `null`.
  Check the draft file has content and `${` fields before any PUT; the RESTlet refuses `"null"`
  and field-stripping bodies, but a wrong-but-plausible body it cannot catch.
- Images referenced by hashed `media.nl` URLs render in the preview only when public; a broken
  image is a template issue, not a preview artifact.
- `preferences.message_signature` renders the calling integration user's signature, not the
  eventual sender's.
- Template files must live in `/Templates/Marketing Templates`; NetSuite rejects `mediaitem` for
  files in `/Templates/E-mail Templates`.

## Maintainers

Source: the private `sdf-creative-planning` repo, `src/RESTlet/cp_email_template_rl.ts` and
`src/netsuite_modules/email-template/index.ts`, with tests under `__tests__/email_template/`.
Shipped here via `netsuite/restlets/sync.sh`. Spec:
`docs/superpowers/specs/2026-10-05-netsuite-email-designer-design.html` in that repo.
