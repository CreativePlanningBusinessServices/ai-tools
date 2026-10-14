# SuiteCloud CLI errors: message → cause → fix

Messages are quoted as the 4.x CLI prints them (placeholders in `<…>`).

| Message | Cause | Fix |
|---|---|---|
| `Java is not installed on this machine. Install any of the following Oracle JDK versions: 17, 21, to run CLI for Node.js.` | No `java` on `PATH` (`JAVA_HOME` is ignored). | Install JDK 17 or 21 and put its `bin` on `PATH`; open a new shell. |
| `Your Java version <x> is not compatible with CLI for Node.js. Install any of the following Oracle JDK versions: 17, 21.` | The first `java` on `PATH` is another major version. The verdict is cached. | Fix `PATH`, then delete `~/.suitecloud-sdk/suitecloud-sdk-settings.json` so the check reruns. |
| `There is no JAR file in your CLI for Node.js. Run "npm install" from "<path>" to install the JAR file.` | The postinstall download of the SDK jar failed (proxy, license prompt in CI, `--ignore-scripts`). | Re-run `npm install` in that folder with `SUITECLOUD_CLI_ACCEPT_LICENSE=true` and, behind a proxy, `SUITECLOUD_PROXY`. |
| `No suitecloud.config.js file was found in <dir>. Run "<command>" in a valid project folder.` | Not inside a SuiteCloud project. | `cd` into the project, or create a scratch one with `project:create` and `cd` into it. |
| `Invalid SuiteCloud project context for command "<command>".` / `- Missing deploy.xml in <dir>.` | 4.x requires `deploy.xml` for every project command, even `object:list`; repos often gitignore it. | Create the minimal `deploy.xml` from SKILL.md Preflight in the project folder and scope it before deploying. |
| `The '-i' option cannot be used in combination with other options.` | `-i` was mixed with flags. | Drop `-i`, or drop the other options. |
| `Browser-based authentication is not allowed for the current execution context.` | `SUITECLOUD_CI` and/or `SUITECLOUD_CI_PASSKEY` are set in this shell. | For a browser login run `env -u SUITECLOUD_CI -u SUITECLOUD_CI_PASSKEY suitecloud account:setup` (PowerShell: clear `$env:SUITECLOUD_CI` and `$env:SUITECLOUD_CI_PASSKEY` for that window). |
| `In the current execution context, you can perform only machine-to-machine authentication or operations that do not require authentication.` | `SUITECLOUD_CI_PASSKEY` is set but `SUITECLOUD_CI` is not. | Set `SUITECLOUD_CI=1` too (persistently) for M2M use. |
| `Machine-to-machine authentication is not allowed for the current execution context.` | `account:setup:ci` without the passkey. | Export `SUITECLOUD_CI_PASSKEY` (32–100 letters/digits) and `SUITECLOUD_CI=1`. |
| `The "<authid>" authentication ID is not available. Check your authentication credentials and try again.` | `project.json` names an auth id that does not exist in the **current execution context** (certificate ids live only with the CI variables set, browser ids only without), or the credentials file was deleted. | Check `suitecloud account:manageauth --list` in the context you are in; switch context or re-run `account:setup:ci`. |
| `The following environment variables are currently set: <vars>. The operation you are trying to perform is not allowed with the current environment variable configuration.` | Conflicting variables, e.g. both `SUITECLOUD_CI_PASSKEY` and `SUITECLOUD_FALLBACK_PASSKEY`. | Unset one. |
| `The credentials passkey set in the environment variable … must be between 32 and 100 alphanumeric characters.` | Passkey format. | Letters and digits only, 32–100 characters. |
| `The current passkey cannot decrypt the credentials file <file>.` | The passkey changed after `credentials_ci.p12` was written. | Restore the original passkey, or delete the file and run `account:setup:ci` again for every auth id. |
| `Secure storage is inaccessible. Ensure that the secure storage in your system is properly configured and accessible.` | No OS keychain (headless Linux, containers). | Use the CI variables, or `SUITECLOUD_FALLBACK_PASSKEY` for browser auth. |
| `There was an error with the private key used to authenticate. Verify the contents of the private key.` | The key is not an RSA PEM (EC keys such as netsuite-cli's produce this), or it is not the key for that certificate. | Generate an RSA 4096 key pair and map its certificate; pass the matching key path. |
| `There was an error with the certificate ID used to authenticate. Verify that certificate ID <id> is valid and not expired or revoked in account <account>.` | The certificate is revoked or expired, is mapped to another integration (it must be **SuiteCloud Development Integration**), the mapping was wiped by a sandbox refresh, or `--account` is wrong. | Check the mapping on the OAuth 2.0 Client Credentials Setup page (or `netsuite-cli account cert list --client-id <SuiteCloud client id>`); re-map and re-run `account:setup:ci`. |
| `The <domain> domain does not exist. Check the NetSuite domain and try again.` | Bad `--domain` / `--dev` value. | Omit `--domain` unless the account uses a custom domain. |
| `<project>/Objects/<folder> does not exist.` (listed under "The following objects failed") | `--destinationfolder` points at a folder that is not there. | `mkdir` it first. |
| `Form name must be between 1 and 60 characters long.` | `<name>` too long in a form XML. | Shorten it. |
| `To install this SuiteCloud project, the <FEATURE> feature must be enabled in the account.` | `manifest.xml` marks a feature `required="true"` (often added by `project:adddependencies`) that the target lacks. | Set it to `required="false"` if the object does not truly need it, otherwise enable the feature. |
| `The manifest contains a dependency on <object> object, but it is not in the account.` | A referenced object exists in the source account only. | Import and deploy that object too, or remove the reference. |
| `The "<field>" field depends on the "<FEATURE>" feature. The manifest must define the "<FEATURE>" feature as required or optional.` | Missing feature dependency. | `project:adddependencies`, then review the manifest. |
| `[ACCOUNT_SPECIFIC_VALUE]` validation errors | Imported XML holds an internal id that did not travel (employee, folder, item…). | Replace the value, or `--accountspecificvalues WARNING` for optional fields (ACP only). |
| `Installation preferences cannot be applied in an Account Customization Project` | `--applyinstallprefs` on an ACP. | Drop the flag; it is for SuiteApps. |
| `The "--validate" option has no effect…` / `The "--server" option has no effect…` | Flags from 3.x. | Remove them; 4.x always validates on the server. |
| `ERROR: SDK exited with code <n>` followed by text | The Java SDK failed; the real message follows. | Read the lines after it; usually a Java version or server validation error. |
| 3.x only: `The object referenced in "id" is missing in the project and is not included in the dependencies list.` on `project:validate` | Local validation false positive. | Upgrade to 4.x (`npm install -g @oracle/suitecloud-cli`). |

## Copied transaction forms

A new form is created from the standard form plus the XML, so `project:validate` rejects settings
that exist on the source form but that SDF cannot apply. These appear only once any manifest
feature error is cleared. Each fix changes the copy, so after deploying re-import the new form,
`diff` it against the source, and tell the user what differs.

| Message | Cause | Fix |
|---|---|---|
| `The mandatory value of the [scriptid=<field>] field object cannot be modified.` | The field is mandatory on its own definition; a form that hides it exports `<mandatory>F</mandatory>`. | Set `<mandatory>T</mandatory>` on that field in the copy. Confirm the cause with `SELECT scriptid, ismandatory FROM customfield WHERE scriptid = '<FIELD ID IN UPPERCASE>'`. The rendered form is unchanged. |
| `The columnBreak value of the <field> field object cannot be modified.` | A layout setting on a standard field that SDF cannot set. | Set `<columnBreak>F</columnBreak>` on that field. Cosmetic difference: the field no longer starts a new column. |
| `The sublist id value, <sublist>, is either invalid or does not exist in the account.` | The export lists a standard sublist the account does not have (seen with `PROMOTIONS`). | Delete that `<subList>` block; if it was the only one, delete its empty `<subItems>` wrapper too. No visible difference: the account never rendered that sublist. |
| `You cannot move the <sublist> sublist/subtab from the <tab A> tab to the <tab B> tab in a transaction form. Moving sublists and subtabs is not supported.` | The export shows the sublist directly under tab B; the standard form keeps it inside subtab A (seen with `MESSAGES`, `TRANSACTIONOUTPUTOPTIONS`, `TRANSACTIONCOMMUNICATION`). | Delete that `<subList>` block from tab B; the deploy restores it inside subtab A. Visible difference: one subtab where the source showed two, with the list still present. |
| `ERROR: An error occurred during custom object creation.` at `CUSTOM_OBJECT_CREATION`, no detail | The server failed part-way and can leave the object half-built: it is listed and opens in the UI under the right name, but most of the XML's settings are missing (a form re-imported at this point differed from its XML on several hundred lines). | `suitecloud object:list --type <type> --scriptid <new id>` first, then rerun the same deploy either way. If it was listed, the rerun's step reads `CUSTOM_OBJECT_UPDATE` and completes the object; do not report it as created before that rerun succeeds. Then re-import and diff as above. |

Sublists that the source export omits can come back from the re-import as extra `<subList>`
blocks (custom child-record sublists). Check they render the same by opening one record under each
form (`<record url>&cf=<form internal id>`) and comparing the tabs.
