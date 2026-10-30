# Onboarding an account to the AI support agent

This is Jon's checklist for giving the triage agent read-only access to one NetSuite account (a
client's, or another CP account). The agent signs in as an integration user with the role
`customrole_cp_ai_readonly` ("CP AI Support (Read Only)"). The role has the same script id and name
everywhere, but its permission list is tailored per account, because accounts have different features
switched on and a role can't hold a permission for a feature the account lacks.

Remember: the triage wrapper never saves support cases in CP's account (a different account from the
one you are onboarding). Onboarding doesn't change that, and nothing here gives the agent write access.

Do the sandbox before production, for every client that has both.

## Layout

```
baseline/customrole_cp_ai_readonly.xml           permissions every account has (View, plus the API ones)
accounts/<alias>/customrole_cp_ai_readonly.xml   that account's final role, as deployed
accounts/<alias>/features.md                     what was added and why, with an "Accepted by" line
deploy.xml                                       ships Objects/Roles/customrole_cp_ai_readonly.xml only
```

`project.json` and `Objects/` are git-ignored. `Objects/` is a scratch folder you create for each deploy.

## The checklist

1. **Client-admin approval.** Get the account owner's written yes for: an integration user with this
   read-only role, an OAuth 2.0 client-credentials mapping, and (for browser use) a login for that
   user. Also ask whether the client's change process covers deploying an SDF role.
2. **Multiple sessions per login.** NetSuite allows one session per user by default, so the agent's
   browser login and a person's login would knock each other out. Check the account's setting
   (Setup > Company > General Preferences > Security, or ask the admin) and write down what you found.
   Use a dedicated "CP AI Support" user so nobody else shares it.
3. **Find what the account uses.** The AI alias doesn't exist yet (it comes in step 11), so use an
   existing admin `netsuite-cli` alias for the account, or the NetSuite UI.
   - Features: Setup > Company > Enable Features, or ask the admin (work orders, manufacturing,
     purchase orders, projects, revenue arrangements, subsidiaries).
   - `netsuite-cli suiteql --account <admin alias> "SELECT type, COUNT(*) AS txn_count FROM transaction GROUP BY type"`
     (without `ORDER BY`; sort afterwards).
4. **Tailor the role.**
   ```bash
   cd <ai-tools>/netsuite/ai-role
   mkdir -p accounts/<alias> Objects/Roles
   cp baseline/customrole_cp_ai_readonly.xml accounts/<alias>/
   ```
   Edit the copy: add `VIEW` permissions for the modules in use (work orders `TRAN_WORKORD`, assembly
   builds `TRAN_BUILD`, manufacturing routings, projects `LIST_JOB`, purchase orders `TRAN_PURCHORD`,
   credit memos `TRAN_CUSTCRED`, and so on). Never add: bank or payment instruments (deposits, checks,
   transfers, card charges), payroll, employee compensation or HR, or any Create, Edit or Full on a
   record. If the account has no OneWorld subsidiaries, remove `LIST_SUBSIDIARY` and set
   `<subsidiaryoption>OWN</subsidiaryoption>`.
   Optional, off by default: `LIST_FILECABINET` (View). It is needed only if the agent should read
   files through `cp_file_cabinet_rl`, for example SuiteScript source. It is broad: the File Cabinet
   can hold bank statements, payroll or HR files. Confirm with the client before adding it.
   Expense reports (`TRAN_EXPREPT`) carry employee reimbursement data, so confirm those with the
   client too.
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
   A difference means NetSuite added or dropped something. Record it in `features.md`. If it added a
   permission with a level above View (as it does with `LIST_OTHER_ADDRESS`), Jon has to accept it.
8. **Write `accounts/<alias>/features.md`:** what you added beyond the baseline and why, what you
   left out on purpose, anything NetSuite changed, and a blank `Accepted by: ____` line for Jon.
9. **Entity and integration record.** Create or reuse an employee "CP AI Support". On its Access tab,
   give it login access and assign the role "CP AI Support (Read Only)". Create an integration record
   with OAuth 2.0 enabled: only the Client Credentials (Machine to Machine) Grant checked, scope
   REST Web Services and RESTlets, no authorization code grant, no TBA. Note its Client ID.
   These steps need a person logged in to the account.
10. **Certificate and mapping.** Generate the key pair on your machine; the private key never leaves it:
    ```bash
    netsuite-cli account cert generate --key-out ~/.config/netsuite-cli/<alias>-key.pem --cert-out <alias>-cert.pem
    ```
    Upload the certificate: `netsuite-cli account cert upload --account <admin alias> --cert <alias>-cert.pem --client-id <integration client id> --entity <CP AI Support id> --role <role id>`
    (or in the UI: Setup > Integration > OAuth 2.0 Client Credentials (M2M) Setup). Keep the returned
    certificate id. Keep the key out of the repo.
11. **Register the alias** and add it to the pilot config:
    ```bash
    netsuite-cli account add <alias> --account-id <id> --flow m2m --client-id <client id> --cert-id <certificate id> --key ~/.config/netsuite-cli/<alias>-key.pem
    ```
    Then add the alias to `config/pilot.json` in the case-triage-agent repo.
12. **Verify the role: reads work, writes fail.** Run these in order and stop if any result differs.
    Reads, all of which must succeed:
    ```bash
    netsuite-cli suiteql --account <alias> "SELECT id FROM transaction FETCH FIRST 1 ROWS ONLY"
    netsuite-cli suiteql --account <alias> "SELECT id, scriptid FROM script FETCH FIRST 1 ROWS ONLY"
    netsuite-cli suiteql --account <alias> "SELECT scriptid, name FROM workflow FETCH FIRST 1 ROWS ONLY"
    netsuite-cli suiteql --account <alias> "SELECT internalid FROM ScriptNote FETCH FIRST 1 ROWS ONLY"
    ```
    Also one `cp_saved_search_rl` GET. Run one `cp_file_cabinet_rl` GET only if the File Cabinet
    opt-in is on.

    Writes, all of which must fail with a permission error (use any customer id; never expect success):
    ```bash
    netsuite-cli record update customer <id> --account <alias> --data '{"comments":"x"}'
    netsuite-cli record update customer <id> --account <alias> --data '{"addressBook":{"items":[{"addressBookAddress":{"addr1":"x"}}]}}'
    ```
    If either write succeeds, stop: the role is too broad and the account is not onboarded. The
    address write matters because NetSuite grants `LIST_OTHER_ADDRESS` at Full on its own.

    Sensitive fields must not be readable. `LIST_EMPLOYEE` is View, and compensation, HR and SSN-type
    data sit behind separate permissions this role doesn't have. Prove it rather than assume:
    ```bash
    netsuite-cli suiteql --account <alias> "SELECT id, socialsecuritynumber, salary FROM employee FETCH FIRST 1 ROWS ONLY"
    ```
    This must return an error or empty/null values for those columns. If it returns real values, stop
    and remove `LIST_EMPLOYEE` from that account's role.

    This step has not yet been run for SB2, because creating an integration and mapping needs a human
    login. Run it at the first real onboarding.
13. **RESTlet audiences.** Add the role to the audience of the `cp_saved_search_rl` deployment, and
    of `cp_file_cabinet_rl` only if the File Cabinet opt-in is on. Do not add it to `cp_mr_driver_rl`
    (Administrator only). Writes through those RESTlets fail because the role is view-only; step 12's
    must-fail checks prove the role can't write.
14. **Browser use (only if the agent will use the UI).** Save a vault login and enrol the TOTP secret:
    ```bash
    agent-browser --session netsuite-ai --session-name netsuite-ai auth save netsuite-ai-<alias> \
      --url https://<account host>/app/center/card.nl --username <CP AI Support login> --password-stdin
    totp-cli add netsuite-ai-<alias>        # prompts for the secret without echo
    ```
    Record the result of the multiple-sessions check from step 2.

## What validation taught us (SB2, 2026-10-30)

- `ADMI_ANALYTICS` (SuiteAnalytics Workbook) accepts only `FULL`, not `EDIT`. Full there means building
  your own workbooks and datasets; it grants no record write.
- `ADMI_WORKFLOW` accepts only `FULL`, so it is not in the role. Workflows are read through SuiteQL
  (step 12 checks the `workflow` table). If an account needs more, decide it with Jon first.
- `TRAN_PURCHORD` is dropped without an error when purchase orders are not enabled. It is a per-account
  add, not baseline.
- **`LIST_OTHER_ADDRESS` (Full) is imposed by NetSuite, not requested.** The role definition does not
  list it, but NetSuite adds it on deploy when the entity lists are on the role, and a re-import shows
  it. It is a Full on address records, which this design otherwise forbids, so Jon must explicitly
  accept it for each account (the `Accepted by` line in `features.md`), and step 12's address write
  must fail.
- Center type for "Classic" is `ACCOUNTCENTER` in SDF XML; `CLASSIC` is rejected.
- **A redeploy only adds permissions; it never removes one.** To narrow an already-deployed role, remove
  the permission in the UI (Setup > Users/Roles > Manage Roles) or deploy under a new script id.
  (SB2's deployed role still holds `LIST_FILECABINET`, which the committed file no longer lists.)
