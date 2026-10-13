---
name: suitecloud-cli
description: Use when a task needs to view, export, duplicate, edit, deploy or migrate NetSuite custom objects (custom forms, record types, fields, lists, scripts, workflows, roles, PDF templates; whole saved searches or email templates when migrating), pull or upload SuiteScript files, or set up SuiteCloud CLI (SDF, `suitecloud`) authentication for an account netsuite-cli already knows — including when netsuite-cli has no endpoint for an object definition or the only alternative seems to be the NetSuite UI.
---

# SuiteCloud CLI (SDF) for object definitions

`suitecloud` is Oracle's SuiteCloud Development Framework command line. It round-trips NetSuite
**object definitions** as XML (forms, records, fields, scripts, workflows, roles, templates…) and
uploads SuiteScript files. It is the tool for the gap netsuite-cli cannot cover: the REST API has
no endpoint for object definitions. **netsuite-cli stays first for data; SuiteCloud CLI comes
before any browser automation for objects.**

## When this skill applies

| Need | Use |
|---|---|
| Record data: read, query, create, update, transform, schemas, RESTlets, File Cabinet contents; saved searches (run, create, edit, delete → `cp-saved-search`); email templates (preview, edit, create → `netsuite-email-designer`) | `netsuite-cli` and its sibling skills — always first |
| An object's definition: see it, copy it, change a label/field/tab, add a script deployment, move it (including a whole saved search or template) to another account, upload a SuiteScript file | **this skill** |
| Delete an object, touch a standard form, legacy (non-advanced) PDF/HTML form layouts, Setup pages | browser (agent-browser) or a person — only after both CLIs are ruled out |

Symptoms that mean "object, not data": the user says *form, field, custom record type, list,
script deployment, workflow, role, template, dashboard, segment, subtab*, or wants something
"copied / duplicated / migrated to prod / exported as XML". For an object change, the UI is the
fallback for what SDF cannot do, never a peer "alternative": do not offer "or just do it in the UI".

## Preflight (once per session)

```
suitecloud --version          # want 4.x; 3.x prints extra local-validation noise
java -version                 # JDK 17 or 21 must be on PATH (JAVA_HOME is ignored)
suitecloud account:manageauth --list
echo $SUITECLOUD_CI           # PowerShell: $env:SUITECLOUD_CI
```

- Not installed: `npm install -g @oracle/suitecloud-cli`. Java missing: install OpenJDK 17, add its `bin` to PATH.
- **Every `project:`, `object:`, `file:` and `config:` command, and `account:setup*` (they write `project.json`), runs inside a SuiteCloud project** (a folder with
  `suitecloud.config.js` and `manifest.xml`; objects go under the folder named by
  `defaultProjectFolder`, often `src/` or `.`). Not in one? Create a scratch project:
  `suitecloud project:create --type ACCOUNTCUSTOMIZATION --projectname scratch` then `cd scratch`.
- **4.x refuses every project command, even `object:list`, until `deploy.xml` exists** ("Invalid
  SuiteCloud project context"). Repos often gitignore it: create a minimal one in the project folder
  (`<deploy><objects><path>~/Objects/*</path></objects></deploy>`) and scope it before deploying.
  Do not build a separate rehearsal project to get around it.
- **Certificate (M2M) auth ids are only visible while `SUITECLOUD_CI=1` and `SUITECLOUD_CI_PASSKEY`
  are set; browser auth ids only while they are unset.** "authentication ID is not available" usually
  means the wrong context. A browser login with the variables set fails ("Browser-based authentication
  is not allowed for the current execution context"): run it as
  `env -u SUITECLOUD_CI -u SUITECLOUD_CI_PASSKEY suitecloud account:setup` (PowerShell: clear both `$env:` vars first).
- **The project's account is whatever `project.json` says** (`defaultAuthId`); there is no
  per-command account flag. Read it before every list/import/deploy (`cat project.json`;
  PowerShell `Get-Content project.json`). Wrong account? `suitecloud account:setup:ci --select <authid>`.
  No auth id for it yet? See "Authenticate an account netsuite-cli already knows" below.

## Workflows

Object types are case-sensitive; the three form types are camelCase (`entryForm`,
`transactionForm`, `addressForm`). Full list with script-id prefixes: `references/object-types.md`.

### Find the object's script id
```
suitecloud object:list --type transactionForm              # prints type:scriptid lines, e.g. transactionForm:custform_12_1234567_345
suitecloud object:list --type customrecordtype --scriptid erp   # substring filter
```
Form ids carry no name and there is no SuiteQL table for forms. Narrow first: for a standard
record type, `netsuite-cli record select-options <type> --fields customForm` lists form names with
internal ids, and the form's page in the UI (`custform.nl?id=<internal id>`) shows the script id;
for custom record forms, `object:list --type entryForm --scriptid <account id or prefix>` then import
the few candidates and read `<name>`. Never `--scriptid ALL` on forms: hundreds of forms time out.
Scripts and record types do have tables: `SELECT scriptid, name FROM script` / `FROM customrecordtype`.

### View / export an object
```
mkdir Objects/Forms                       # the destination folder must already exist
suitecloud object:import --type transactionForm --scriptid custform_12_1234567_345 --destinationfolder /Objects/Forms --excludefiles
```
`--destinationfolder` is relative to the project folder and must start with `/Objects`.
Omit `--excludefiles` when you also want the SuiteScript files a script object references.
A project's `suitecloud.config.js` may hook `object:import` and move the file (for example into
`Objects/Forms/EntryForm/`); check where it landed before editing. Read the XML; it is the
complete definition (fields, tabs, labels, display types, scripts).

### Duplicate an object (e.g. copy a form)
1. Import the source object (above).
2. Copy the XML to `Objects/Forms/custform_<new_id>.xml`; the file name must equal the new
   script id, which must keep the type's prefix (`custform_`, `customrecord_`, `customscript_`…),
   lowercase, no spaces.
3. In the copy change the root `scriptid="…"` and `<name>` (forms: ≤ 60 characters, and a
   name that already exists creates a confusing twin). Set `<preferred>F</preferred>` unless
   the user wants the copy to become the default form.
4. Scope `deploy.xml` to exactly the files you mean to ship:
   ```xml
   <deploy>
     <objects>
       <path>~/Objects/Forms/custform_<new_id>.xml</path>
     </objects>
   </deploy>
   ```
   (`~` is the project folder. The default `~/Objects/*` ships everything you ever imported.)
5. `suitecloud project:adddependencies`, then **read the manifest diff**: it lists every object
   the form references and sometimes adds a feature as `required="true"` that the account does
   not have (the deploy then fails with "the X feature must be enabled"). Flip such a feature to
   `required="false"` unless the object genuinely needs it.
6. `suitecloud project:validate` → `suitecloud project:deploy --dryrun` (expect
   `Create object -- custform_<new_id> (entryform)`) → `suitecloud project:deploy`.
7. Confirm: `suitecloud object:list --type entryForm --scriptid custform_<new_id>`.

### Edit an existing object
Import it fresh (`object:import`, or `object:update --scriptid <id>` if it is already in the
project) so you edit the account's current version, change the XML, scope `deploy.xml` to that
file, then adddependencies → validate → `--dryrun` (expect `Update object -- …`) → deploy.
Never edit `<definition>` blobs (saved searches, workbooks, datasets); they are opaque.

### Migrate between accounts (sandbox → production)
1. In the project pointed at the **source** account, import the objects.
2. Switch: `suitecloud account:setup:ci --select <target authid>` and re-read `project.json`.
3. `suitecloud project:validate --accountspecificvalues WARNING` — imported XML can contain
   `[ACCOUNT_SPECIFIC_VALUE]` where an internal id (employee, folder, item…) did not travel;
   replace those by hand or accept the WARNING for optional fields.
4. `project:deploy --dryrun`, read the preview, then deploy **only when the user named the
   target account**. A clean sandbox run is not proof for production.

### SuiteScript files
```
suitecloud file:list --folder "/SuiteScripts/MyFolder"
suitecloud file:import --paths "/SuiteScripts/MyFolder/my_script.js"      # pull into FileCabinet/
suitecloud file:upload --paths "/SuiteScripts/MyFolder/my_script.js"      # push from FileCabinet/
```
Paths are File Cabinet paths and must be quoted; no wildcards. For reading or writing file
*contents* without a project, the cp-file-cabinet skill is simpler; `file:upload` is the right
tool when the file belongs to a script deployment you are also deploying.

## Authenticate an account netsuite-cli already knows

Summary (full recipe with Windows and macOS/Linux variants, edge cases and cleanup:
`references/auth-setup.md`):

1. `netsuite-cli account list` → account id (sandboxes end in `_SB1`, `_SB2`…).
   `suitecloud account:manageauth --list` → if an auth id for that account exists, just
   `account:setup:ci --select <authid>` and stop.
2. `netsuite-cli account cert list --account <alias>` → the **entity** and **role** ids of the
   existing machine-to-machine mapping (the same user and role will own the SuiteCloud mapping).
3. Generate a **new RSA 4096** key pair with openssl (SuiteCloud rejects the EC keys netsuite-cli
   uses, and one certificate can map to only one integration, so netsuite-cli's cert cannot be reused).
4. Map the certificate to the **SuiteCloud Development Integration** application for that entity
   and role, without a browser: `netsuite-cli account cert upload --account <alias> --cert <cert.pem>
   --client-id 6da57bf05a6247fc876c6d228184ff487760a382a43ac7e93eaff743803d22ac --entity <id> --role <id>`
   (that client id is SuiteCloud's public one, the same in every account). The response's
   `certificateId` is the **certificate id**.
5. Generate a passkey into the environment without printing it (the reference has the one-line
   bash and PowerShell forms that write `SUITECLOUD_CI_PASSKEY` and `SUITECLOUD_CI=1` persistently),
   open a new shell, then `suitecloud account:setup:ci --account <ACCOUNT_ID> --authid <ACCOUNT_ID>_M2M --certificateid <id> --privatekeypath <absolute path to key.pem>`
6. Verify: `suitecloud object:list --type customlist`, and
   `netsuite-cli suiteql --account <alias> "SELECT oauthappname, status FROM LoginAudit WHERE date >= SYSDATE - 0.01 ORDER BY date DESC"`
   shows a `SuiteCloud Development Integration` success.

## Safety rules

- `--dryrun` before every deploy and read the preview lines (`Create object`, `Update object`).
- `deploy.xml` lists only the files for this task.
- Deploy to production only when the user named production for this change.
- SuiteCloud cannot delete objects: say so and offer the UI path instead of retrying.
- Never run `project:deploy` without reading `project.json` in the same session, and never run any
  account-facing command (even `object:list`) while it names a different account than the task.

## Gotchas

- `--destinationfolder` must exist → "…/Objects/Forms does not exist".
- `project:adddependencies` can add a feature the account lacks as `required="true"` (deploy then
  fails with "the X feature must be enabled"), and it re-flips it on every run: review the manifest
  diff after each run and set it back to `required="false"`.
- `-i` cannot be combined with other options.
- Renaming a form and deploying creates a new form instead of updating the old one.
- Form names max 60 characters; every field label needs a value (use a single space).
- Standard forms are not objects; a custom form points at its base via `standard="STANDARD…"`.
- 3.x prints local "object referenced in id is missing" errors that the server does not; upgrade.
- Windows: paths use forward slashes everywhere, `~/.suitecloud-sdk` is `%USERPROFILE%\.suitecloud-sdk`,
  openssl ships with Git for Windows at `C:/Program Files/Git/usr/bin/openssl.exe`.
- Errors and their fixes: `references/errors.md`. All commands and flags: `references/commands.md`.
