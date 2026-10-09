---
name: cp-mr-driver
description: Use when a task needs to trigger (run/execute/kick off) a NetSuite Map/Reduce script programmatically in any account where Creative Planning's cp_mr_driver_rl RESTlet is installed (CP's own accounts or a client's), or poll a submitted MR task's progress — including ad-hoc reruns of scheduled MRs, per-run script-parameter overrides, and waiting for an MR to complete before verifying its output. Covers the cp_mr_driver_rl RESTlet's JSON contract, called via netsuite-cli restlet call.
---

# Triggering Map/Reduce scripts via the cp_mr_driver_rl RESTlet

`cp_mr_driver_rl` is a RESTlet Creative Planning installs into NetSuite accounts, CP's own and
clients' (script/deploy ids are the same everywhere): `customscript_cp_mr_driver_rl` /
`customdeploy_cp_mr_driver_rl`. NetSuite's REST API has no endpoint that executes scripts, so
`N/task` behind this RESTlet is the only programmatic way to start a Map/Reduce — call it with
`netsuite-cli restlet call`.

The deployment audience is **Administrator only** (it can start any MR in the account), so the
`netsuite-cli` alias you call it with must be an Administrator-role integration. Any other role
gets a permission error by design.

## Before the first call in an account

1. **Pick the account.** Every call takes `--account <alias>`, the `netsuite-cli` alias for the
   target account. Never fall back to the CLI's default account: if the user hasn't said which
   account, ask.
2. **Confirm the RESTlet is installed there** (once per account per session):

   ```bash
   netsuite-cli suiteql --account <alias> "SELECT scriptid FROM script WHERE scriptid = 'customscript_cp_mr_driver_rl'"
   ```

   - One row: go ahead.
   - No rows: it isn't installed. Don't call the RESTlet; ask the user whether they'd like you
     to install it, following "Installing the RESTlet" below.
   - The query itself errors (unknown alias, auth failure): report that error. It says nothing
     about whether the RESTlet is installed.

**Install or redeploy only after the user says yes for that account.** If the RESTlet is missing,
ask whether they'd like you to install it. If it's there but a call fails because the deployment is
undeployed or not released, report what you found and ask whether to redeploy the package. Either
way, the question to ask and the steps are in "Installing the RESTlet" below. An `{error}` the
RESTlet itself returns, or a permission error on the calling role, isn't an install problem and a
redeploy won't fix it. A request to trigger a Map/Reduce isn't a yes, neither is a "do whatever it
takes" said before the user knew an install was needed, and a yes for one account isn't a yes for
another. Deploying the package is the only change you make to scripts: never edit a script or
deployment record by hand (UI or API), in any account.

## Trigger — POST `{ script, deployment?, params? }`

```bash
netsuite-cli restlet call --account <alias> \
  --script customscript_cp_mr_driver_rl --deploy customdeploy_cp_mr_driver_rl \
  --method POST --data '{
    "script": "customscript_example_mr",
    "deployment": "customdeploy_example_mr_adhoc",
    "params": {"custscript_example_rate": "83"}
  }'
# → {"taskId":"MAPREDUCETASK_0268…","script":"customscript_example_mr",
#    "deployment":"customdeploy_example_mr_adhoc","status":"PENDING","stage":null}
```

- `script` — required; `customscript_*` id or numeric internal id (both work).
- `deployment` — optional; omit and NetSuite picks a free deployment of that script. Prefer an
  explicit ad-hoc deployment (`status NOTSCHEDULED`) when one exists, so you don't consume the
  scheduled one's slot.
- `params` — optional per-run script-parameter overrides, `{"custscript_x": value}`. **Unknown
  param keys are silently ignored by the platform** (verified in a sandbox) — a typo'd key means the
  script quietly runs with its stored defaults, so double-check param ids.
- Unknown top-level body keys are rejected with a pointed `{error}` (only `script`, `deployment`,
  `params` are valid).
- Submitting while the same script+deployment is already running returns
  `{"error":"Map/Reduce Script N with Deployment M is already running…"}` — NetSuite's
  MAP_REDUCE_ALREADY_RUNNING guard, surfaced as-is.

## Poll — GET `?taskid=`

```bash
netsuite-cli restlet call --account <alias> \
  --script customscript_cp_mr_driver_rl --deploy customdeploy_cp_mr_driver_rl \
  --method GET --param "taskid=MAPREDUCETASK_0268…"
# → {"taskId":"…","scriptId":1234,"deploymentId":2,"status":"COMPLETE","stage":null,
#    "percentComplete":100,"counts":{"currentTotalSize":0,"pendingMap":0,"totalMap":19,
#    "pendingReduce":0,"totalReduce":0,"pendingOutput":0,"totalOutput":0}}
```

- `status`: PENDING → PROCESSING → COMPLETE / FAILED. `stage` (GET_INPUT/MAP/SHUFFLE/REDUCE/
  SUMMARIZE) is only non-null mid-run.
- `scriptId`/`deploymentId` come back as **numeric internal ids**, not customscript_/customdeploy_
  strings.
- A typo'd/unknown taskid returns `{"error":"no task found for taskid …"}` (checkStatus itself
  doesn't throw for those — the RESTlet adds the guard).
- Small MRs finish in well under a minute; poll every ~10s. A COMPLETE status only means the MR
  ran — check the script's own log for what it did:
  `netsuite-cli suiteql --account <alias> "SELECT type, title, detail, date FROM scriptnote WHERE
  scripttype = <script internal id> ORDER BY internalid DESC FETCH FIRST 10 ROWS ONLY"`.

## Finding a script's deployments first

```bash
netsuite-cli suiteql --account <alias> "SELECT script.id, script.scriptid, dep.scriptid AS depid,
  dep.status, dep.isdeployed FROM script JOIN scriptdeployment dep ON dep.script = script.id
  WHERE script.scripttype = 'MAPREDUCE' AND script.scriptid LIKE '%example%'"
```

## Gotchas

- GET responses are JSON **strings** at the platform level (bodyless-GET serialization rule shared
  with the sibling cp_* RESTlets); netsuite-cli parses them transparently.
- The RESTlet audits every submission (`map/reduce submitted`, AUDIT level, with taskId/script/
  deployment/params) in its own script log — useful when reconstructing who started what.
- Scheduled deployments also fire on their own schedule; when verifying "my run happened", match
  the taskId or the deployment id (`_adhoc`) rather than assuming the latest run is yours.

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

## Maintaining this skill

The RESTlet source and its tests live in CP's private `sdf-creative-planning` repo:
`src/RESTlet/cp_mr_driver_rl.ts`. Changes reach other accounts by running
`netsuite/restlets/sync.sh` in `ai-tools`, committing, and redeploying.
