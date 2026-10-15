# ai-tools

Claude Code skills and NetSuite scripts maintained by Creative Planning.

## What's here

| Path | What it is |
|---|---|
| `skills/netsuite-saved-search` | Run, create, edit, describe and delete saved searches; decode a SuiteCloud export to read a search's Available Filters, Audience and email settings |
| `skills/netsuite-file-cabinet` | Read, download, list, create, edit and delete File Cabinet files |
| `skills/netsuite-mr-driver` | Trigger Map/Reduce scripts and poll their progress |
| `skills/netsuite-email-designer` | Preview, edit, save and create email templates, with an email-client compatibility check |
| `netsuite/restlets` | The four RESTlets those skills call, ready to deploy into an account |
| `skills/edi-template-builder` | Build and revise EDI benefits-feed templates (X12 834 and others) |
| `skills/suitecloud-cli` | When and how to use the SuiteCloud CLI for NetSuite object definitions (forms, records, fields, scripts…), and how to set up its machine-to-machine auth from an existing netsuite-cli account |

The `netsuite-*` skills only work in an account where the RESTlets are installed.
`edi-template-builder` has its own setup notes, including how to upgrade from the old zip
install, in [`skills/edi-template-builder/INSTALL.md`](skills/edi-template-builder/INSTALL.md).

## Prerequisites

- Claude Code
- For the `netsuite-*` skills: [`netsuite-cli`](https://github.com/CreativePlanningBusinessServices/netsuite-cli),
  with an account alias for each NetSuite account you work in. For `netsuite-mr-driver`, that
  alias must be an Administrator-role integration.
- `jq`
- To install the RESTlets: the SuiteCloud CLI (`npm install -g @oracle/suitecloud-cli`)

## Install the skills

```bash
git clone https://github.com/CreativePlanningBusinessServices/ai-tools.git
ai-tools/scripts/install-skills.sh
```

This symlinks each skill into `~/.claude/skills/`. It never overwrites: if a skill with the same
name already exists there, it's skipped and named so you can move it aside. Run `git pull` in the
clone to update; the links pick up changes automatically. When a pull adds, renames or removes a
skill, re-run the script: it links the new names and deletes links to skills that are gone.
Restart Claude Code to load new skills.

## Install the RESTlets in an account

This installs CP-maintained scripts, named "CP | …", into the account. In a client's account,
follow whatever change process applies for that client before deploying.

The skills offer to do this for you: when one finds its RESTlet missing from an account, it asks
whether you'd like it installed and, on a yes, runs the steps below itself, following
[`netsuite/restlets/INSTALL.md`](netsuite/restlets/INSTALL.md). Adding a SuiteCloud auth ID for a
new account: the `suitecloud-cli` skill walks through it, reusing the netsuite-cli alias.

1. Make sure SuiteScript (server-side scripting) is enabled in the account.
2. **Point the project at this account, every time you deploy.** The SuiteCloud CLI deploys to
   whichever account was set up last for this folder, and there's no flag to choose one at
   deploy time. So before each deploy, select the auth ID for the account you're installing into
   (the `suitecloud-cli` skill's auth recipe adds one for a new account without a browser):

   ```bash
   cd ai-tools/netsuite/restlets
   suitecloud account:manageauth --list
   suitecloud account:setup:ci --select <authid>
   cat project.json        # defaultAuthId must be the account you mean to change
   ```

   If `defaultAuthId` names any other account, stop and select again. (A browser login,
   `suitecloud account:setup`, only works with the `SUITECLOUD_CI*` variables unset.)
3. Validate, preview, then deploy:

   ```bash
   suitecloud project:validate          # 4.x always validates on the server; --server is a no-op
   suitecloud project:deploy --dryrun
   suitecloud project:deploy
   ```

4. Check the install (read-only):

   ```bash
   ./verify.sh <netsuite-cli alias>
   ```

   Every line should read `PASS`.

**Upgrade:** `git pull`, then deploy again. SDF updates the scripts in place.

**Remove:** SDF can't delete objects. In NetSuite, delete the four script deployments, then the
four scripts ("CP | Saved Search RESTlet", "CP | File Cabinet RESTlet", "CP | MR Driver
RESTlet", "CP | Email Template RESTlet"), then the files under `/SuiteScripts/CreativePlanning/`.
The email template RESTlet keeps backups of edited templates under
`/SuiteScripts/CreativePlanning/email-template-backups/`; review those before deleting the folder.

## Maintainers

- The RESTlet source and tests live in the private `sdf-creative-planning` repo. After a RESTlet
  changes there, rebuild the package with `netsuite/restlets/sync.sh` (it builds `origin/main`
  in a temporary worktree and never commits), review the diff, and commit. `netsuite/restlets/SOURCE`
  records which commit the package was built from.
- Run `tests/run.sh` before committing script changes.
- Run `scripts/scrub-check.sh` before every commit. Its pattern list lives outside the repo, at
  `~/.config/ai-tools/scrub-patterns.txt`; ask a maintainer for a copy. Patterns prefixed
  `code-ok:` aren't applied to the compiled code under `netsuite/restlets/FileCabinet/`, which
  ships exactly as built so `verify.sh` can compare it with what an account runs.
- After the first commit, changes go through pull requests.
