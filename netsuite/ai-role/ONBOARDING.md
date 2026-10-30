# Onboarding an account to the AI support agent

This is Jon's checklist for giving the triage agent read-only access to one NetSuite account (a
client's, or another CP account). The agent signs in as an integration user with the role
`customrole_cp_ai_readonly` ("CP AI Support (Read Only)"). The role is the same everywhere by script
id and name, but its permission list is tailored per account, because accounts have different
features switched on and a role can't hold a permission for a feature the account lacks.

Remember: the triage wrapper never saves support cases in CP's account (a different account from the
one you are onboarding). Onboarding doesn't change that, and nothing here gives the agent write access.

## Layout

```
baseline/customrole_cp_ai_readonly.xml     permissions every account has (View, plus the API ones)
accounts/<alias>/customrole_cp_ai_readonly.xml   that account's final role, as deployed
accounts/<alias>/features.md               what was added and why
deploy.xml                                 ships Objects/Roles/customrole_cp_ai_readonly.xml only
```

`project.json` is git-ignored, like the RESTlets package. `Objects/` is a scratch folder you create
for each deploy and don't commit.

## The checklist

1. **Client-admin approval.** Get the account owner's written yes for: an integration user with this
   read-only role, an OAuth 2.0 client-credentials mapping, and (for browser use) a login for that
   user. Also ask whether the client's change process covers deploying an SDF role.
2. **Multiple sessions per login.** NetSuite allows one session per user by default, so the agent's
   browser login and a person's login would knock each other out. Check the account's setting
   (Setup > Company > General Preferences > Security: "Allow multiple sessions per login", or ask the
   admin) and write down what you found. Use a dedicated "CP AI Support" user so nobody else shares it.
3. **Find what the account uses.**
   - Features: Setup > Company > Enable Features, or ask the admin (work orders, manufacturing,
     purchase orders, projects, revenue arrangements, subsidiaries).
   - `netsuite-cli suiteql --account <alias> "SELECT type, COUNT(*) AS txn_count FROM transaction GROUP BY type"`
     (without `ORDER BY`; sort afterwards).
4. **Tailor the role.**
   ```bash
   cd <ai-tools>/netsuite/ai-role
   mkdir -p accounts/<alias> Objects/Roles
   cp baseline/customrole_cp_ai_readonly.xml accounts/<alias>/
   ```
   Edit the copy: add `VIEW` permissions for the modules in use (work orders `TRAN_WORKORD`, assembly
   builds `TRAN_BUILD`, manufacturing routings, projects `LIST_JOB`, revenue arrangements, credit
   memos `TRAN_CUSTCRED`, and so on). Never add: bank or payment instruments (deposits, checks,
   transfers, card charges), payroll, employee compensation or HR, or any Create, Edit or Full on a
   record. If the account has no OneWorld subsidiaries, remove `LIST_SUBSIDIARY` and set
   `<subsidiaryoption>OWN</subsidiaryoption>`.
5. **Point SuiteCloud at the account** (the `suitecloud-cli` skill covers adding an auth id). Every
   time, before any account-facing command:
   ```bash
   suitecloud account:manageauth --info <authid>     # Account ID must be the account you mean
   suitecloud account:setup:ci --select <authid>
   cat project.json                                  # defaultAuthId must be that auth id
   ```
6. **Validate and drop what is rejected.**
   ```bash
   cp accounts/<alias>/customrole_cp_ai_readonly.xml Objects/Roles/
   suitecloud project:validate --server
   ```
   Remove any permission it rejects from `accounts/<alias>/` and validate again. If the rejected one
   is in the baseline, also move it out of the baseline and into the accounts that do have it.
7. **Deploy, then re-import and diff.**
   ```bash
   suitecloud project:deploy --dryrun && suitecloud project:deploy
   mkdir -p Objects/Reimport
   suitecloud object:import --type role --scriptid customrole_cp_ai_readonly --destinationfolder /Objects/Reimport
   ```
   Compare the permission lists of `accounts/<alias>/…xml` and `Objects/Reimport/…xml` (ignore order).
   Differences mean NetSuite added or dropped something; make the committed file match the account
   and say so in `features.md`.
8. **Write `accounts/<alias>/features.md`:** what you added beyond the baseline and why, what you
   left out on purpose, and anything NetSuite changed.
9. **Entity and integration record.** Create or reuse an employee "CP AI Support" with this role, and
   an integration record with OAuth 2.0 client credentials enabled. These need a person logged in to
   the account.
10. **OAuth 2.0 client-credentials mapping** with an uploaded public certificate (Setup > Integration >
    OAuth 2.0 Client Credentials (M2M) Setup), for that entity and role.
11. **Register the alias:** `netsuite-cli account add <alias> --flow m2m …` (see the `netsuite-cli`
    skill), then add the alias to `config/pilot.json` in the case-triage-agent repo.
12. **Verify the role does what it should (reads work, writes fail).** Run these, in order, and stop
    if any result differs:
    ```bash
    netsuite-cli suiteql --account <alias> "SELECT id FROM transaction FETCH FIRST 1 ROWS ONLY"       # succeeds
    netsuite-cli suiteql --account <alias> "SELECT id, scriptid FROM script FETCH FIRST 1 ROWS ONLY"  # succeeds
    netsuite-cli suiteql --account <alias> "SELECT scriptid, name FROM workflow FETCH FIRST 1 ROWS ONLY"  # succeeds
    netsuite-cli suiteql --account <alias> "SELECT internalid FROM ScriptNote FETCH FIRST 1 ROWS ONLY"    # succeeds
    netsuite-cli record update customer <id> --account <alias> --data '{"comments":"x"}'              # must FAIL with a permission error
    ```
    Where the account has the RESTlets, also check one `cp_saved_search_rl` GET and one
    `cp_file_cabinet_rl` GET. If the write succeeds, stop: the role is too broad, and the account is
    not onboarded. Use any customer id; the write should never succeed. This step has not yet been run for SB2, because creating an integration and mapping
    needs a human login: run it at the first real onboarding.
13. **RESTlet audiences.** In each account, keep the role off `cp_file_cabinet_rl` write use and off
    `cp_mr_driver_rl` (that one is released to Administrator only; don't add this role).
14. **Browser use (only if the agent will use the UI).** Store a vault login for the CP AI Support user,
    enrol its TOTP secret in `totp-cli`, and record the result of the multiple-sessions check from step 2.

## What validation taught us (SB2, 2026-10-30)

- `ADMI_ANALYTICS` (SuiteAnalytics Workbook) accepts only `FULL`, not `EDIT`. Full there means building
  your own workbooks and datasets; it grants no record write.
- `ADMI_WORKFLOW` accepts only `FULL`, so it is not in the role. Workflows are read through SuiteQL
  (step 12 checks the `workflow` table). If an account needs more, decide it with Jon first.
- `TRAN_PURCHORD` is dropped without an error when purchase orders are not enabled. It is a per-account
  add, not baseline.
- NetSuite adds `LIST_OTHER_ADDRESS` (Full) on its own when the entity lists are on the role, so the
  baseline lists it. It is a Full on address records, which this task otherwise forbids, so step 12's write test matters: it proves the integration still cannot change records. If a later NetSuite release lets you drop it, do.
- Center type for "Classic" is `ACCOUNTCENTER` in SDF XML; `CLASSIC` is rejected.
- **A redeploy only adds permissions; it never removes one.** To narrow an already-deployed role, remove
  the permission in the UI (Setup > Users/Roles > Manage Roles) or deploy under a new script id.
