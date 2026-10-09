# Installing the CP RESTlets: runbook for an agent

The four CP skills (`cp-saved-search`, `cp-file-cabinet`, `cp-mr-driver`,
`netsuite-email-designer`) send you here when their RESTlet is missing from an account, or when
its deployment is undeployed or not released. This folder is the SDF package that holds all four
RESTlets; it installs with the SuiteCloud CLI, and the same steps upgrade or repair an existing
install. The steps for a person doing this by hand are in the repo README.

Nothing below step 1 that touches the account runs until the user has said yes for that account.

**1. Ask first.** One question, and it says:

- the account: the `netsuite-cli` alias, its account id (`netsuite-cli account list`), and whether
  that's production or a sandbox (a sandbox id ends in `_SB<n>`; a bare number is production);
- what gets installed: the package is all-or-nothing, so it's all four CP RESTlets (saved search,
  File Cabinet, Map/Reduce driver, email template), not only the one the task needs. They arrive
  as scripts named "CP | …" with their files under `/SuiteScripts/CreativePlanning/`. The
  Map/Reduce driver is released to Administrator only; the other three to all internal roles;
- which of the four are already there (read-only, so run it before asking):

  ```bash
  netsuite-cli suiteql --account <alias> "SELECT scriptid FROM script WHERE scriptid IN ('customscript_cp_saved_search_rl', 'customscript_cp_file_cabinet_rl', 'customscript_cp_mr_driver_rl', 'customscript_cp_email_template_rl')"
  ```

  For each one that is, the deploy sets its deployment back to deployed and Released and replaces
  its files with this package's versions;
- for a client's account: that the client's change process has to allow it;
- whether SuiteCloud already has an auth ID for that account (step 3's `--list` and `--info` are
  local and read-only, so run them before asking). If it doesn't, say that after their yes
  they'll need to do a browser login before you can deploy. If `suitecloud` isn't on PATH at
  all, the question also covers installing it (`npm install -g @oracle/suitecloud-cli`).

On anything but a yes, leave the account alone.

**2. Work from this folder.** Run every command in steps 3 to 5 from this folder's absolute
path: `suitecloud` acts on whatever SDF project the current directory holds, so a shell that has
drifted elsewhere deploys something else.

**3. Point the project at the account, every time.** The SuiteCloud CLI deploys to whichever
account was last selected for this folder; there's no flag to choose one at deploy time.

```bash
suitecloud account:manageauth --list
suitecloud account:manageauth --info <authid>     # Account ID must equal the alias's accountId
suitecloud account:setup:ci --select <authid>
cat project.json                                  # defaultAuthId must be that auth ID
```

- Auth IDs are SuiteCloud's own names, unrelated to `netsuite-cli` aliases. Run `--info` on each
  one listed and match on the account id it prints, never on a similar-looking name. Several
  match: ask which.
- None match: the user has to add one. `suitecloud account:setup` is an interactive browser login
  you can't drive, so ask them to run it in their own terminal from this folder, with a role that
  can deploy SDF projects (Administrator works), then continue from here.

**4. Validate, preview, deploy.**

```bash
suitecloud project:validate --server
suitecloud project:deploy --dryrun
suitecloud project:deploy
```

Run the real deploy only if validation finished without errors (its warning about `<allroles>`
is expected) and every object line in the preview names one of the four scripts or its
deployment, like these two for each of `saved_search`, `file_cabinet`, `mr_driver` and
`email_template`:

```
Update object -- customscript_cp_saved_search_rl (restlet)
Update object -- customscript_cp_saved_search_rl.customdeploy_cp_saved_search_rl (scriptdeployment)
```

The verb can differ on a first install; the object names are what you check. Any other object,
or an error at any step from 3 on (including a permission error from the auth ID's role): stop
and show the user the output. A validation error naming `SERVERSIDESCRIPTING`
means SuiteScript is off in the account; turning features on is the user's call.

**5. Verify, then pick the task back up.**

```bash
./verify.sh <alias>
```

It's read-only and every line should read `PASS`. Report the result and mention that this folder
now points at that account (`project.json`). If a line failed, show the user the output; carry on
with what they originally asked for only if the lines for the RESTlet that task needs passed.
