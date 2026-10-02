# ai-tools

Claude Code skills and NetSuite scripts maintained by Creative Planning Business Services.
This repo is private: don't copy it anywhere public.

## What's here

| Path | What it is |
|---|---|
| `skills/cp-saved-search` | Run, create, edit, describe and delete saved searches |
| `skills/cp-file-cabinet` | Read, download, list, create, edit and delete File Cabinet files |
| `skills/cp-mr-driver` | Trigger Map/Reduce scripts and poll their progress |
| `netsuite/restlets` | The three RESTlets those skills call, ready to deploy into an account |

The skills only work in an account where the RESTlets are installed.

## Prerequisites

- Claude Code
- [`netsuite-cli`](https://github.com/CreativePlanningBusinessServices/netsuite-cli), with an
  account alias for each NetSuite account you work in. For `cp-mr-driver`, that alias must be an
  Administrator-role integration.
- `jq`
- To install the RESTlets: the SuiteCloud CLI (`npm install -g @oracle/suitecloud-cli`)

## Install the skills

```bash
git clone https://github.com/CreativePlanningBusinessServices/ai-tools.git
ai-tools/scripts/install-skills.sh
```

This symlinks each skill into `~/.claude/skills/`. It never overwrites: if a skill with the same
name already exists there, it's skipped and named so you can move it aside. Run `git pull` in the
clone to update; the links pick up changes automatically. Restart Claude Code to load new skills.

## Install the RESTlets in an account

This installs CP-maintained scripts, named "CP | …", into the account. In a client's account,
follow whatever change process applies for that client before deploying.

1. Make sure SuiteScript (server-side scripting) is enabled in the account.
2. **Point the project at this account, every time you deploy.** The SuiteCloud CLI deploys to
   whichever account was set up last for this folder, and there's no flag to choose one at
   deploy time. So before each deploy, run setup and pick (or add) the auth ID for the account
   you're installing into:

   ```bash
   cd ai-tools/netsuite/restlets
   suitecloud account:setup
   cat project.json        # defaultAuthId must be the account you mean to change
   ```

   If `defaultAuthId` names any other account, stop and run setup again.
3. Validate, preview, then deploy:

   ```bash
   suitecloud project:validate --server
   suitecloud project:deploy --dryrun
   suitecloud project:deploy
   ```

4. Check the install (read-only):

   ```bash
   ./verify.sh <netsuite-cli alias>
   ```

   Every line should read `PASS`.

**Upgrade:** `git pull`, then deploy again. SDF updates the scripts in place.

**Remove:** SDF can't delete objects. In NetSuite, delete the three script deployments, then the
three scripts ("CP | Saved Search RESTlet", "CP | File Cabinet RESTlet", "CP | MR Driver
RESTlet"), then the files under `/SuiteScripts/CreativePlanning/`.

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
