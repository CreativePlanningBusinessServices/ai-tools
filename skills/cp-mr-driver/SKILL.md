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
   - No rows: it isn't installed. Tell the user it can be installed from the `ai-tools` repo
     (`netsuite/restlets/`, see its README) and stop. Never deploy it yourself; installing
     scripts into an account is the user's decision.
   - The query itself errors (unknown alias, auth failure): report that error. It says nothing
     about whether the RESTlet is installed.

**Never deploy, install, or edit script or deployment records yourself**, in any account. If the
RESTlet is missing, undeployed, not released, or failing, report what you found and let the user
fix it. Changing scripts in an account, especially a client's, is the user's decision.

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

## Maintaining this skill

The RESTlet source and its tests live in CP's private `sdf-creative-planning` repo:
`src/RESTlet/cp_mr_driver_rl.ts`. Changes reach other accounts by running
`netsuite/restlets/sync.sh` in `ai-tools`, committing, and redeploying.
