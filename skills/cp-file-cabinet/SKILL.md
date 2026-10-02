---
name: cp-file-cabinet
description: Use when a task needs to read, download, list, create, edit, or delete a NetSuite File Cabinet file in any account where Creative Planning's cp_file_cabinet_rl RESTlet is installed (CP's own accounts or a client's). Covers the cp_file_cabinet_rl RESTlet's JSON contract, called via netsuite-cli restlet call.
---

# File Cabinet files via the cp_file_cabinet_rl RESTlet

`cp_file_cabinet_rl` is a RESTlet Creative Planning installs into NetSuite accounts, CP's own and
clients' (script/deploy ids are the same everywhere): `customscript_cp_file_cabinet_rl` /
`customdeploy_cp_file_cabinet_rl`. It describes, downloads, lists, creates, edits, and deletes
File Cabinet files over JSON — call it with `netsuite-cli restlet call`.

## Before the first call in an account

1. **Pick the account.** Every call takes `--account <alias>`, the `netsuite-cli` alias for the
   target account. Never fall back to the CLI's default account: if the user hasn't said which
   account, ask.
2. **Confirm the RESTlet is installed there** (once per account per session):

   ```bash
   netsuite-cli suiteql --account <alias> "SELECT scriptid FROM script WHERE scriptid = 'customscript_cp_file_cabinet_rl'"
   ```

   - One row: go ahead.
   - No rows: it isn't installed. Tell the user it can be installed from the `ai-tools` repo
     (`netsuite/restlets/`, see its README) and stop. Never deploy it yourself; installing
     scripts into an account is the user's decision.
   - The query itself errors (unknown alias, auth failure): report that error. It says nothing
     about whether the RESTlet is installed.

**Never deploy, install, or edit script or deployment records yourself**, in any account. If the
RESTlet is missing, undeployed, not released, or failing, report what you found and let the user
fix it. Changing scripts in an account, especially a client's, is the user's decision.

NetSuite's REST API has no file-content support, so this RESTlet is the only scriptable path to
File Cabinet content. **File Cabinet vs `suiteql`:** for metadata-only questions (does a file
exist, what's its size/type/folder, list a folder) plain `netsuite-cli suiteql` over the `file` /
`mediaitemfolder` tables (recipes below) is faster to iterate on. Reach for this RESTlet whenever
you need file **contents** (download/create/edit) or a **create/edit/delete** operation — SuiteQL
is read-only and never touches content.

## FileDescription (describe/create/edit response shape)

```json
{
  "id": 1001, "name": "cp_saved_search_rl.js",
  "path": "/SuiteScripts/CreativePlanning/RESTlet/cp_saved_search_rl.js",
  "folder": { "id": 2001, "path": "/SuiteScripts/CreativePlanning/RESTlet" },
  "fileType": "JAVASCRIPT", "size": 9813,
  "url": "/core/media/media.nl?id=1001&c=<accountId>&h=…&mv=…&_xt=.js",
  "description": null, "encoding": "UTF-8", "isOnline": false, "isInactive": false,
  "createdDate": "08/01/2026", "lastModifiedDate": "08/05/2026"
}
```

`folder.id` is `null` only for the File Cabinet root. Download adds `"contents"` and
`"contentsEncoding": "utf8"|"base64"`.

## Describe — GET with `id` XOR `path`

Exactly one of `id` (numeric internal id) or `path` (absolute) is required; both or neither errors.

```bash
netsuite-cli restlet call --account <alias> --script customscript_cp_file_cabinet_rl --deploy customdeploy_cp_file_cabinet_rl \
  --method GET --param "path=/SuiteScripts/CreativePlanning/RESTlet/cp_saved_search_rl.js"
```

## Download — add `contents=T` (or `true`, case-insensitive)

```bash
netsuite-cli restlet call --account <alias> --script customscript_cp_file_cabinet_rl --deploy customdeploy_cp_file_cabinet_rl \
  --method GET --param "id=1002" --param contents=T
```

Text file types (see map below) come back as real UTF-8 text with `contentsEncoding: "utf8"`;
everything else comes back base64 with `contentsEncoding: "base64"`. NetSuite's `getContents()`
caps out at **10MB** (`MAX_CONTENT_BYTES = 10_485_760`) — a larger file 400s with a pointed error
telling you to fetch it via its `url` instead.

## List — GET with `folder=`

`folder` is a numeric internal id or absolute path (`/` for the File Cabinet root); optional
`nameContains` substring-filters file names only (case-insensitive), never folder names:

```bash
netsuite-cli restlet call --account <alias> --script customscript_cp_file_cabinet_rl --deploy customdeploy_cp_file_cabinet_rl \
  --method GET --param "folder=/SuiteScripts/CreativePlanning/examples" --param nameContains=hello
# → {"folder":{"id":2002,"path":"…"},"folders":[{"id":…,"name":…,"path":…}],"files":[{"id":…,"name":…,"size":…,"fileType":…,"url":…,"lastModifiedDate":…}]}
```

`folder=` is exclusive with `id`/`path`/`contents` on the same GET (a call is either a file op or
a list, never both).

Both GET variants and DELETE return a JSON **string** body, not an object — NetSuite serializes a
RESTlet response off the *request's* `Content-Type`, and a bodyless GET/DELETE sends none.
`restlet call` parses it transparently; a raw HTTP caller must `JSON.parse()` it itself.

## Create — POST

Keys: `path`, `folder`, `name`, `contents`, `contentsEncoding`, `fileType`, `description`,
`isOnline`, `encoding`, `overwrite`. Target with **either** `path` **or** `folder`+`name` (both or
neither errors); any other key is rejected with `unknown key(s): …`. Root (`folder: "/"` or a
one-segment `path`'s parent) is rejected — `cannot create files at the File Cabinet root`. Missing
intermediate folders auto-create.

```bash
netsuite-cli restlet call --account <alias> --script customscript_cp_file_cabinet_rl --deploy customdeploy_cp_file_cabinet_rl \
  --method POST --data '{"path": "/SuiteScripts/CreativePlanning/examples/hello.txt", "contents": "héllo\nwörld", "description": "example"}'
```

Re-POSTing the same target without `overwrite` fails closed, naming the existing id:

```json
{"error": "file already exists at /SuiteScripts/CreativePlanning/examples/hello.txt (id 1002) — pass \"overwrite\": true to replace it"}
```

Add `"overwrite": true` to replace in place — QA-verified (2026-08-10) that this keeps the same
internal id and media hash, only bumping the version token.

`fileType` is derived from the name's extension when omitted (compact map — full list in the
module's `EXTENSION_TYPE_MAP`; see Maintaining this skill):

| ext | type | ext | type | ext | type |
|---|---|---|---|---|---|
| js | JAVASCRIPT | json | JSON | css/scss | STYLESHEET/SCSS |
| htm/html | HTMLDOC | xml | XMLDOC | txt/md | PLAINTEXT |
| csv | CSV | pdf | PDF | zip/gz/tar | ZIP/GZIP/TAR |
| png/jpg/gif/bmp/ico/tif | \*IMAGE/ICON | doc(x) | WORD | xls(x) | EXCEL |

Unmapped extension with no explicit `fileType` → `cannot derive a fileType from "…"`.
`contentsEncoding` defaults to `utf8`; pass `"base64"` for binary types (required — a binary type
with `utf8` errors, as does non-base64-shaped `contents` under `base64`).

## Edit — PUT (patch, not full replace)

Target with `id` or `path` (same XOR rule as GET/describe). Editable keys: `contents`, `name`,
`folder`, `description`, `isOnline`, `isInactive` — send only what you're changing, everything
else is left alone. At least one editable key is required (`nothing to edit — pass at least one
of …`). `fileType` is **immutable**: pass it back unchanged and it's a no-op, pass a different
value and you get `fileType cannot be changed — the file's type is <actual>`.

A `contents` replace preserves the file's internal id, `encoding`, `description`, `isOnline`,
and `isInactive` (all 8 supported encodings verified live 2026-08-11, incl. MacRoman). An
unrecognized encoding readback aborts the replace with an `unrecognized encoding …` error
rather than silently re-encoding the file to UTF-8.

```bash
netsuite-cli restlet call --account <alias> --script customscript_cp_file_cabinet_rl --deploy customdeploy_cp_file_cabinet_rl \
  --method PUT --data '{"id": 1002, "contents": "PUT replaced contents — ünïcode line1\nline2\n"}'
```

Content replace has no native NetSuite "set contents" API — the module saves a new file with the
same name into the same folder, which NetSuite documents as the replace mechanism. **QA-verified
2026-08-10**: the internal id and media `h=` hash are retained across
create → overwrite → PUT-replace, with no shadow duplicate left behind — confirmed via a fresh
GET and a folder listing after each step.

`name`+`folder` together rename **and** move in one PUT; missing target subfolders auto-create;
the old path then 404s (`file not found: …`). Moving to root is rejected: `cannot move a file to
the File Cabinet root — target a folder`.

## Delete — DELETE, and it MUST carry `--data '{}'`

```bash
netsuite-cli restlet call --account <alias> --script customscript_cp_file_cabinet_rl --deploy customdeploy_cp_file_cabinet_rl \
  --method DELETE --param "path=/SuiteScripts/CreativePlanning/examples/qa1x1.png" --data '{}'
# → {"deleted":true,"id":1003,"path":"…/qa1x1.png"}
```

**Always pass `--data '{}'` on a DELETE call.** Without a request `Content-Type` header, NetSuite
500s at the platform layer *before the script runs at all* — reproduced on this RESTlet and on
`cp_saved_search_rl`, so it's a platform quirk affecting any RESTlet DELETE, not a bug here.
`--data '{}'` makes `netsuite-cli restlet call` send a JSON `Content-Type`, which is enough even
though the body is ignored. Same `id` XOR `path` targeting rules as GET.

Repeat deletes are not silently idempotent — deleting by **path** a second time gives a clean
`{"error": "file not found: …"}`; deleting by a **stale id** instead surfaces NetSuite's raw
`N/file.load` message, `"You do not have access to the media item you selected."` — prefer path
targeting when the file might already be gone, for the friendlier error.

## Size limits

Platform cap on both `getContents()` (download) and `file.create()`/save (upload) is **10MB**
decoded (`MAX_CONTENT_BYTES`) — and it is the binding limit: NetSuite accepts RESTlet request
bodies of at least 11MB (probed 2026-08-11), so the RESTlet's own cap errors first. For anything
beyond trivial size, pass the body as a file: `--data @payload.json` (or `--data -` for stdin) —
verified round-trip clean at 9.9MB text and 7MB binary (9.3MB base64 body). Inline `--data '...'`
alone is capped by shell ARG_MAX (~1MB), so prefer `@file` habitually for uploads. Downloads
aren't argument-bound; read up to the 10MB cap freely.

## SuiteQL recipes (metadata only, no RESTlet)

Global file search by name:

```bash
netsuite-cli suiteql --account <alias> "SELECT id, name, folder, filesize FROM file WHERE LOWER(name) LIKE LOWER('%hello%')"
```

Folder path walk (repeat one level at a time, or join if you know the depth):

```bash
netsuite-cli suiteql --account <alias> "SELECT id, name, parent FROM mediaitemfolder WHERE parent IS NULL AND LOWER(name) = LOWER('SuiteScripts')"
```

## Limits

No folder rename/move/delete (folders are UI-only for those — Documents → Files → File Cabinet);
no chunked/streaming upload (whole-file `--data` only); no server-side copy (download then
re-upload); unknown body keys on POST/PUT are rejected outright rather than silently ignored.

## Maintaining this skill

The RESTlet source and its tests live in CP's private `sdf-creative-planning` repo:
`src/RESTlet/cp_file_cabinet_rl.ts` and `src/netsuite_modules/file-cabinet/index.ts` (which holds
`EXTENSION_TYPE_MAP`); design spec `docs/superpowers/specs/2026-08-10-file-cabinet-restlet-design.html`.
Changes reach other accounts by running `netsuite/restlets/sync.sh` in `ai-tools`, committing,
and redeploying.
