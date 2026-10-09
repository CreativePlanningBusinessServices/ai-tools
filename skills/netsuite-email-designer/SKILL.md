---
name: netsuite-email-designer
description: Use when a task needs to view, preview, edit, redesign, or create a NetSuite email template — a template URL (emailtemplate.nl?id=…), id or name, "what does this email look like", "change the wording of the invoice email", "build a new email for X", "will this email work in Outlook?" — in any account where Creative Planning's cp_email_template_rl RESTlet is installed. Covers the RESTlet's JSON contract (called via netsuite-cli restlet call), how NetSuite renders FreeMarker templates, previewing in the Code tab against a real record, building new templates as hand-written email HTML, and an email-client compatibility check against caniemail data (bash + jq, no Python or Node).
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
NS_HOST=$(netsuite-cli account list | jq -r --arg alias <alias> '.accounts[] | select(.alias == $alias) | .accountId | ascii_downcase | gsub("_"; "-")')
```

`NS_HOST` is the account's UI host prefix (`6967599_SB2` → `6967599-sb2`), used to link records
in the NetSuite UI: `https://$NS_HOST.app.netsuite.com/…`. If it comes back empty, the alias is
wrong; stop and check it rather than linking a guessed host.

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
  write the file directly. The parenthesised form also works in conditions, which gives a cleaner
  greeting than a blank name: `<#if (recipient.firstName)?has_content>Hello ${recipient.firstName},<#else>Hello,</#if>`.
- A template with an empty subject merges with its **name** as the subject (NetSuite's fallback);
  say so in the preview banner rather than showing an empty subject.

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

   "Most recent" means highest internal id; ids are unique, dates tie. Prefer a sample whose fields
   have values: a record with zero hours or no contact renders a convincing but empty email. A join
   onto the referenced child record finds a better one, e.g.
   `SELECT agreement.id, agreement.name, cycle.custrecord_used_hours AS used FROM customrecord_erp_agreement agreement JOIN customrecord_cp_erp_billing_cycle cycle ON cycle.id = agreement.custrecord_active_billing_cycle WHERE cycle.custrecord_used_hours > 0 ORDER BY agreement.id DESC FETCH FIRST 5 ROWS ONLY`
   (record and field names vary by account; read them off the template's `${…}` paths). `recipient` is the person the
   email goes to: for a transaction, a contact of its customer (`SELECT id, firstname, lastname FROM
   contact WHERE company = <entityId>`) when the template uses `${recipient.…}`; a company customer
   has no first name and renders it blank. Omit `recipient` when the template never references it. Fields the sample leaves blank render empty — say so in the
   preview message rather than "fixing" the template.
3. **Preview.** `POST` in saved mode and write the body to `$SP/email-preview-<templateId>.html`, with a banner inserted after the opening `<body…>` tag (or
   prepended when there is none):
   ```bash
   bash ~/.claude/skills/netsuite-email-designer/scripts/preview-banner.sh "$SP/email-preview-123.html" "<subject>" "<alias>" "<sample>" "saved"
   ```
   Show it with SendUserFile (render display), and make that the **last** action of the turn, after
   the explanatory text, so the card sits at the bottom of the chat where the user sees it without
   scrolling. Clicking the card opens the Browser pane, where the user can select and annotate
   elements to ask for changes. Nothing opens that pane automatically: writing the file with the
   Write tool, the file pane (`show_pane`), and a preview server all fail to, so don't try them.
   Where SendUserFile is unavailable, give the path. Previews hold
   real customer data: they live only in the scratchpad and are never committed, attached, or
   published.
4. **Edit loop.** Keep the working copy at `$SP/email-draft-<templateId>.html`. After each edit:
   ```bash
   jq -n --rawfile body "$SP/email-draft-123.html" '{templateId: 123, body: $body, transactionId: 456}' > "$SP/draft.json"
   rl --method POST --data @"$SP/draft.json" > "$SP/draft-out.json"
   jq -r .body "$SP/draft-out.json" > "$SP/email-preview-123.html"   # then banner + show
   ```
   Say in one line what changed. Never turn a `${…}` field into literal text, or literal text into
   a field, without saying so.
5. **Check client compatibility** before every save or create, and whenever the user asks whether
   an email will work in Outlook or Gmail. `scripts/email-compat.sh` (next to this file; needs
   only bash, awk, jq and curl, so no Python or Node) looks up every HTML element, attribute, CSS
   property, unit, at-rule and image format the email uses in caniemail.com's public support
   data, and reports each one that the latest tested version of a mainstream client doesn't
   support (or only partly supports), with caniemail's footnotes:
   ```bash
   bash ~/.claude/skills/netsuite-email-designer/scripts/email-compat.sh "$SP/email-draft-123.html"
   ```
   It downloads `https://www.caniemail.com/api/data.json` with curl once a day into the temp dir.
   Where curl can't reach it, fetch that URL however you can and pass `--data <file>`.
   `--clients all` widens the default list (Outlook on every platform, Gmail, Apple Mail, Yahoo,
   Samsung) to every client caniemail tracks. Run it on the draft or exported HTML, not on a
   preview: the preview banner adds markup of its own.

   The report is raw data, and you do the triage. Every table-based email hits the same baseline
   entries, which only matter if the template relies on the part that's missing: `<body>`
   replaced by a `<div>`, the HTML5 doctype ignored, `padding`/`margin`/`width`/`max-width` only
   partly supported in Outlook for Windows, and `role` ignored. For each entry, check how the
   template uses the feature and whether it already has a fallback (a `width` attribute next to
   `max-width`, `bgcolor` next to `background-color`, a solid colour behind a background image).
   Then tell the user in plain words what will look different and where, for example "Outlook
   desktop shows square corners on the card". Real problems are features the layout or the
   legibility depends on with no fallback: flex or grid layout, `rem` font sizes, background
   images that carry text, SVG or WebP images, `height` on a `<div>`, layout that only exists
   inside `@media`. Propose a fix for each one and apply it only once the user agrees. The check
   reads code, it doesn't render anything. For a broad client send, also suggest a test send to
   Outlook desktop and Gmail, or a Litmus / Email on Acid run.
6. **Save.** Only after an explicit yes that names the account ("save to <alias>"). Build the PUT
   body from the draft file the same way, `PUT`, then report `backup.id` and `backup.path` and how
   to restore, plus the record link (step 9). Finish with one saved-mode `POST` as the
   confirmation preview.
7. **Which template gets the result.** When the user hands you an existing Email Template record
   (a URL, an id or a name) and asks to change, redo or rebuild its email, the finished HTML goes
   back onto **that record** with `PUT {id, body, subject}`, even when it was rewritten from
   scratch. Its storage stays as it was: an inline template keeps its body on the record,
   a file-backed one gets its media file overwritten, and the automatic backup covers both. Do
   not create a new template or drop a file into the File Cabinet instead; the record is what
   workflows, saved searches and scripts reference. Create a new template only when the user
   asks for a new one, or when no record exists yet.
8. **New templates.** Write the HTML by hand in `$SP/email-draft-new.html`, following the email
   conventions the compatibility check expects: a table layout (an outer full-width table
   centring a fixed-width inner table of about 600–640px, every table with `role="presentation"`,
   `cellpadding="0"`, `cellspacing="0"` and `border="0"`), styles inline on each element, a `width`
   attribute on every image and table alongside any CSS width, web-safe font stacks, and real text
   rather than text baked into images. A `<style>` block is only for optional extras such as
   mobile or dark-mode tweaks, because several clients drop it. Type FreeMarker fields straight
   into the HTML (`${transaction.tranid}`), with `recipient` and `sender` written null-safe. Then
   preview in draft mode with a sample record, run the compatibility check, and `PUT` without `id`
   (`storage: "file"` for CP) to create, then give the user the new record's link (step 9). From
   then on the template record is the source: later edits start from a `GET` of its body, and
   every `PUT` backs up the previous version.
9. **Link the record.** Every successful `PUT`, whether it creates a template or updates one
   (body, subject or name), ends with a clickable link to that Email Template record in the
   account it was written to, built from the `id` in the `PUT` response:
   ```bash
   jq -r --arg host "$NS_HOST" '"https://\($host).app.netsuite.com/app/crm/common/merge/emailtemplate.nl?id=\(.id)"' "$SP/save-out.json"
   ```
   Put it in the reply as a markdown link named after the template and the account, e.g.
   `[CP ES Contract Notification (sb2)](https://6967599-sb2.app.netsuite.com/app/crm/common/merge/emailtemplate.nl?id=320)`.
   A refused or failed `PUT` gets no link; report the error instead.

## Gotchas

- `${recipient.…}` / `${sender.…}` in a draft or a new template must be written null-safe,
  `${(recipient.firstName)!""}`, or the temporary/new template record cannot be saved (see "How
  NetSuite renders"). The error names the missing root.
- A RESTlet call occasionally takes over two minutes (NetSuite side). Give Bash calls a longer
  timeout rather than killing them; macOS has no `timeout` command.

- **Never `echo "$json"` in zsh** — it expands `\r\n` escapes inside JSON strings and jq then
  fails with "control characters must be escaped". Write responses to files and read them with jq;
  use `printf '%s'` if a variable is unavoidable.
- Build request bodies with `jq --rawfile body <file>`, never `--arg body "$(cat …)"`: a failed
  `$(…)` yields an empty string (or `null` from `jq -r` on a non-object) and the capture is bounded
  by ARG_MAX. Check the draft file has content and `${` fields before any PUT; the RESTlet refuses
  `"null"` and field-stripping bodies, but a wrong-but-plausible body it cannot catch.
- Images referenced by hashed `media.nl` URLs render in the preview only when public; a broken
  image is a template issue, not a preview artifact.
- Email HTML: an empty `<td>` still claims width, so a table-based progress bar whose fill cell is
  `width="0%"` renders half full. Give every cell an explicit width and wrap the zero-width cell in
  `<#if percent gt 0>…</#if>`.
- When the user is describing changes against the preview, keep the FreeMarker out of the
  conversation: name what changed in plain words and show the re-rendered preview. Point out
  anything in the preview that comes from the sample record (blank name, zero hours) rather than
  from the template, so it isn't "fixed" in the wrong place.
- `preferences.message_signature` renders the calling integration user's signature, not the
  eventual sender's.
- Template files must live in `/Templates/Marketing Templates`; NetSuite rejects `mediaitem` for
  files in `/Templates/E-mail Templates`.

## Maintainers

Source: the private `sdf-creative-planning` repo, `src/RESTlet/cp_email_template_rl.ts` and
`src/netsuite_modules/email-template/index.ts`, with tests under `__tests__/email_template/`.
Shipped here via `netsuite/restlets/sync.sh`. Spec:
`docs/superpowers/specs/2026-10-05-netsuite-email-designer-design.html` in that repo.
