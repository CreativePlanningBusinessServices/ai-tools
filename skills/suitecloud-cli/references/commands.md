# SuiteCloud CLI command reference (4.x)

`suitecloud <command> [--option value ...]`. `-h` on any command prints its options. `-i` runs a
command's interactive wizard and **cannot be combined with other options**. Every `project:`, `object:`, `file:`
and `config:` command, and `account:setup*`, must run inside a SuiteCloud project folder
(`account:manageauth` works anywhere). Account targeting is never a flag:
it is the `defaultAuthId` in the project's `project.json`.

Option legend: `*` required when the command does its main job; `(multi)` takes several values
separated by spaces; `(flag)` takes no value.

## account

| Command | Purpose | Options | Notes |
|---|---|---|---|
| `account:setup` | Browser-based OAuth login; creates or picks an auth id and writes it to `project.json`. | `--dev` (flag: prompt for a custom NetSuite domain) | Interactive only. Refused while `SUITECLOUD_CI` / `SUITECLOUD_CI_PASSKEY` are set ("Browser-based authentication is not allowed for the current execution context"). Not supported under WSL. |
| `account:setup:ci` | Certificate (machine-to-machine) auth: creates an auth id without a browser and writes it to `project.json`; or just selects an existing one. | `--account <id>*`, `--authid <alias>*`, `--certificateid <id>*`, `--privatekeypath <path>*`, `--domain <host>` (only for non-standard domains), `--select <authid>` (alone) | Requires `SUITECLOUD_CI=1` and `SUITECLOUD_CI_PASSKEY` in the environment. Key must be an RSA PEM. |
| `account:manageauth` | Manage the auth ids stored on this machine. | `--list`, `--info <authid>`, `--rename <authid> --renameto <new>`, `--remove <authid>` | Local only; `--remove` revokes nothing in NetSuite. Shows only the auth ids of the current execution context. |

## project

| Command | Purpose | Options | Notes |
|---|---|---|---|
| `project:create` | Scaffold an account customization project (ACP) or SuiteApp. | `--type ACCOUNTCUSTOMIZATION\|SUITEAPP*`, `--projectname <name>*`, `--projectid`, `--publisherid`, `--projectversion` (the last three required for SuiteApps), `--overwrite` (flag), `--includeunittesting` (flag) | Creates `<name>/src/{Objects,FileCabinet,AccountConfiguration,Translations}`, `manifest.xml`, `deploy.xml`, `suitecloud.config.js`. Then `cd` into it and select an auth id. |
| `project:adddependencies` | Add every missing feature/object/file dependency to `manifest.xml`. | none | Read the manifest diff afterwards: it can mark a feature `required="true"` that the target account lacks; set it to `required="false"` unless the object truly needs it. Unreliable for workflows (SKILL.md → "Workflow objects"): edit the manifest by hand there. |
| `project:validate` | Validate the project on the server. | `--accountspecificvalues WARNING\|ERROR` (ACP; default ERROR), `--applyinstallprefs` (SuiteApp), `--log <dir-or-file>`, `--json` (flag) | `--server` still parses but is a no-op since 4.0 (validation is always server-side). |
| `project:deploy` | Zip what `deploy.xml` references and deploy it; validates first. | `--dryrun` (flag: preview only), `--accountspecificvalues WARNING\|ERROR`, `--applyinstallprefs`, `--log <dir-or-file>`, `--json` (flag) | `--validate` is a no-op since 4.0. `--dryrun` is non-interactive only. Deploys to the account in `project.json`. |
| `project:package` | Build the deployment ZIP without deploying. | none | |

## object

| Command | Purpose | Options | Notes |
|---|---|---|---|
| `object:list` | List custom objects in the account. | `--type <t1 t2 ...>` (multi; omit = all), `--scriptid <substring>`, `--appid <publisher.app>` | Prints one `type:scriptid` line per object after "The following objects were found in your account:", e.g. `transactionForm:custform_12_1234567_345`; names live inside the XML. |
| `object:import` | Pull objects into the project as XML; in an ACP, referenced SuiteScript files come too. | `--type <type\|ALL>*`, `--scriptid <id1 id2 ...\|ALL>*` (multi), `--destinationfolder /Objects[/sub]*`, `--appid`, `--excludefiles` (flag) | Overwrites project files silently. The destination folder is relative to the project folder, must start with `/Objects`, and **must already exist**. |
| `object:update` | Overwrite objects already in the project with the account's current version. | `--scriptid <id1 id2 ...>*` (multi), `--includeinstances` (flag; custom record types only) | |

`object:create` exists in the package but is unfinished; do not use it.

## file

| Command | Purpose | Options | Notes |
|---|---|---|---|
| `file:list` | List File Cabinet files under a folder, recursively. | `--folder "/SuiteScripts/..."*` | |
| `file:import` | Pull File Cabinet files into `FileCabinet/` (ACP only). | `--paths "/SuiteScripts/a.js" ...*` (multi), `--excludeproperties` (flag: skip `.attributes/`) | No wildcards; quote every path. |
| `file:upload` | Push files from `FileCabinet/` to the account. | `--paths "/SuiteScripts/a.js" ...*` (multi) | SuiteApp paths look like `/SuiteApps/<appid>/a.js`. |
| `file:create` | Scaffold a SuiteScript 2.1 file. | `--type <ScriptType>`, `--path "FileCabinet/SuiteScripts/x.js"*`, `--module N/record ...` (multi) | |

## config and proxy

| Command | Purpose | Options | Notes |
|---|---|---|---|
| `config:import` | Import the account's feature configuration into `AccountConfiguration/` (ACP only, 4.1+). | none | |
| `proxy:generatekey`, `proxy:start --authid <id> --port <n>` | Local proxy for Oracle's SuiteCloud Developer Assistant. | | Out of scope for this skill. |

## 4.x output

`project:validate` and `project:deploy` print a summary block then one line per step:

```
Validation Results: 0 error(s), 0 warning(s)
SDF Errors: none
Account: <name>   Account ID: <id>   Role: <role>
✔ Step 1: PROJECT_VALIDATION
✔ Step 5: CUSTOM_OBJECT_VALIDATION --- custform_xyz (entryform)
...
Begin deployment
Create object -- custform_xyz (entryform)
Installation COMPLETE (0 minutes 9 seconds)
```

A `--dryrun` ends with `DEPLOYMENT PREVIEW` and the `Create object` / `Update object` lines without
deploying.

4.1.1 prints the same information differently, for a preview and for a real deploy: a summary
block first (`PREVIEW SUMMARY` on a `--dryrun`, then `Status: SUCCESS|FAILED` and
`Steps: <done>/<total> successful`), and one step per object and sub-object instead of the
`Create object` / `Update object` lines:

```
✔ Step 24: BEGIN_DEPLOYMENT --- <project>
✔ Step 25: CUSTOM_OBJECT_CREATION --- custbody_xyz (transactionbodycustomfield)
✔ Step 26: CUSTOM_OBJECT_UPDATE --- customworkflow_xyz (workflow)
✔ Step 27: CUSTOM_OBJECT_UPDATE --- customworkflow_xyz.workflowstate1 (workflowstate)
...
✔ Step 53: FILE_UPLOAD --- ~/Objects/customworkflow_xyz.xml
```

Read `CUSTOM_OBJECT_CREATION` as "Create object" and `CUSTOM_OBJECT_UPDATE` as "Update object". A
failed step is marked `✖`; `Status:` and `Steps:` are the lines to check first.

With `--json` the same run returns one object:

```json
{"summary": {"action": "preview", "status": "SUCCESS"},
 "steps": [{"name": "PROJECT_VALIDATION", "status": "SUCCESSFUL"}, ...]}
```

Parse `--json`, not the text, in anything automated. 3.x printed a different layout and ran a local
validation pass that reported false "object referenced in id is missing" errors; upgrade rather
than work around it.

## Environment variables

| Variable | Effect |
|---|---|
| `SUITECLOUD_CI=1` + `SUITECLOUD_CI_PASSKEY=<32–100 letters/digits>` | Machine-to-machine context: certificate auth ids are usable, browser login is refused. Set both persistently for unattended use. |
| neither set | Developer context: browser auth ids only; a certificate auth id is "not available". |
| `SUITECLOUD_CI_PASSKEY` alone | Only `account:setup:ci` runs. |
| `SUITECLOUD_FALLBACK_PASSKEY` | Browser-based credentials without OS secure storage (headless Linux). Must not coexist with the CI passkey. |
| `SUITECLOUD_PROXY` | `http(s)://host:port` for all NetSuite traffic, including the SDK jar download. |
| `SUITECLOUD_CLI_ACCEPT_LICENSE=true` | Skip the license prompt during `npm install -g`. |

Credentials live in `~/.suitecloud-sdk/` (`%USERPROFILE%\.suitecloud-sdk` on Windows):
`credentials_ci.p12` (certificate auth ids, encrypted with the CI passkey) and
`credentials_browser_based.p12` (browser auth ids, key in the OS keychain). The SDK jar is
`~/.suitecloud-sdk/cli/cli-<version>.jar`; Java 17 or 21 must be on `PATH` (`JAVA_HOME` is ignored).
