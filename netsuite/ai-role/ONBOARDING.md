# Onboarding an account to the AI support agent

This is Jon's checklist for giving the triage agent read-only access to one NetSuite account (a
client's, or another CP account). The agent signs in with the role `customrole_cp_readonly`
("CP Support (Read Only)"), which people can be given too. The role is Administrator with every
permission flipped to View, minus sensitive data and security administration. It has the same script
id and name everywhere, but each account ends up with its own permission list, because NetSuite drops
permissions for features an account doesn't have.

Remember: the triage wrapper never saves support cases in CP's account (a different account from the
one you are onboarding). Onboarding doesn't change that. The role is read-only except for the SDF and
workflow access it needs for exports (see "Write access that remains"): NetSuite has no read-only form
of SuiteCloud access, so the agent's command guard (`sdf-read`, exports only) is what keeps it from
changing anything.

Do the sandbox before production, for every client that has both. First done end to end for United
Capital (4244448) on 2026-10-31; `accounts/unitedcapital/` is the worked example.

## Layout

```
baseline/customrole_cp_readonly.xml          the role's header, every permission not at View, and keys the SDK list lacks
exclusions.txt                               keys never added (sensitive data, security admin, refused keys)
no-view-level.txt                            keys that have no View level (SDF refuses them at View)
scripts/view-role.py                         builds the role into a scratch SDF project, and deploys it
accounts/<alias>/customrole_cp_readonly.xml  that account's role, re-imported after deploy (as it exists)
accounts/<alias>/dropped.txt                 keys that account refused on deploy, or the client asked to leave off
accounts/<alias>/custom-records.txt          custom record types listed on the role there
accounts/<alias>/features.md                 decisions for that account, with an "Accepted by" line
deploy.xml                                   ships Objects/Roles/customrole_cp_readonly.xml only
```

`project.json` and `Objects/` are git-ignored. `view-role.py` writes each deploy into a scratch folder
of its own (with its own `project.json` and `manifest.xml`), so this folder's manifest stays the same
for every account.

## The checklist

Placeholders: `<ID>` is the account id (`4244448`, `1234567_SB1`), `<alias>` the short name
(`unitedcapital`). The admin aliases are `<alias>-login` and `<alias>`; the agent's are `<alias>-ai`
and `<ID>_AI`.

1. **Client-admin approval.** Get the account owner's written yes for: this read-only role on an
   employee, OAuth 2.0 client-credentials certificates for it, (for browser use) a login for that
   user, and SuiteCloud access with the Workflow permission. Say plainly that SuiteCloud access can't
   be made read-only in NetSuite and that CP's agent only runs exports. Also ask whether the client's
   change process covers deploying an SDF role.

   Tell them the role includes System Notes for Analytics and REST (`LIST_SYSTEMNOTES`) by default. It lets
   SuiteQL read every system note in the account, including changes on employee records (gender, termination
   reason and details), whatever else the role can read. The agent uses these to see who changed what; the
   triage runner keeps employee values out of the reports, which every CP NetSuite user can read. If the client
   says no, add `LIST_SYSTEMNOTES  # client asked to leave it off` to `accounts/<alias>/dropped.txt` before step 6,
   and record it in `features.md`.
2. **Multiple sessions per login.** NetSuite allows one session per user by default, so a browser
   login for the agent and a person's login would knock each other out. Check the account's setting
   (Setup > Company > General Preferences > Security, or ask the admin) and write down what you found.
   This matters only for browser use (step 13).
3. **Admin access for setup (your own Administrator login).** Everything up to step 9 runs as you.
   No integration record is created: both logins reuse integrations that are already in every account.
   ```bash
   # a. Browser login. Pick the Administrator role; answer N to the SOAP/saved-search question.
   netsuite-cli account login <alias>-login --account-id <ID>

   # b. Certificate login (no browser) for the same user and role. The upload response's
   #    entity_role_id gives your employee id (ent) and role id (rol); keep them.
   mkdir -p ~/.config/netsuite-cli && chmod 700 ~/.config/netsuite-cli && cd ~/.config/netsuite-cli
   netsuite-cli account cert generate --key-out <alias>-key.pem --cert-out <alias>-cert.pem --common-name <alias>-admin
   chmod 600 <alias>-key.pem
   netsuite-cli account cert upload --account <alias>-login --cert <alias>-cert.pem
   netsuite-cli account add <alias> --account-id <ID> --flow m2m --cert-id=<certificate id> --key ~/.config/netsuite-cli/<alias>-key.pem
   netsuite-cli account test --account <alias>

   # c. SuiteCloud for the same user and role (RSA, mapped to SuiteCloud's public client id).
   mkdir -p ~/.suitecloud-sdk/keys/<ID> && chmod 700 ~/.suitecloud-sdk/keys/<ID> && cd ~/.suitecloud-sdk/keys/<ID>
   openssl req -x509 -newkey rsa:4096 -sha256 -days 730 -nodes -subj "/CN=suitecloud-<alias>-admin" -keyout suitecloud-key.pem -out suitecloud-cert.pem
   chmod 600 suitecloud-key.pem
   netsuite-cli account cert upload --account <alias> --cert suitecloud-cert.pem --client-id 6da57bf05a6247fc876c6d228184ff487760a382a43ac7e93eaff743803d22ac --entity <ent> --role <rol>
   cd <ai-tools>/netsuite/ai-role
   suitecloud account:setup:ci --account <ID> --authid <ID>_M2M --certificateid <certificate id> --privatekeypath ~/.suitecloud-sdk/keys/<ID>/suitecloud-key.pem
   ```
   Certificate ids can start with `-`, so pass them as `--cert-id=<id>`. The `setup:ci` line must name
   the account and `[Administrator]`.
4. **Survey the account** with the admin alias, and write what you find at the top of
   `accounts/<alias>/features.md`:
   ```bash
   netsuite-cli suiteql --account <alias> --all "SELECT type, COUNT(*) AS txn_count FROM transaction GROUP BY type"
   netsuite-cli suiteql --account <alias> "SELECT COUNT(*) AS n FROM subsidiary"
   netsuite-cli suiteql --account <alias> "SELECT scriptid, name FROM script WHERE LOWER(scriptid) LIKE 'customscript_cp_%'"
   ```
   With one subsidiary (no OneWorld), set `<subsidiaryoption>OWN</subsidiaryoption>` in the baseline
   header for that account's build, and expect `LIST_SUBSIDIARY` in `dropped.txt`. The last query shows
   whether CP's RESTlets (saved search, file cabinet) are installed; step 12 needs them.
5. **Choose the custom record types.** Only types set to "Use Permission List" need a line on a role;
   "Require Custom Record Entries Permission" types are covered by `LIST_CUSTRECORDENTRY` (View, from
   the SDK list), and the rest need no permission.
   ```bash
   mkdir -p accounts/<alias>
   netsuite-cli suiteql --account <alias> --all "SELECT internalid, scriptid, name FROM customrecordtype WHERE usepermissions = 'T'" \
     | jq -r '.items[] | "\(.scriptid | ascii_downcase)\t# \(.name)"' > accounts/<alias>/custom-records.txt
   ```
   Review the list with the client and delete lines (or turn them into `#` comments) for types holding
   bank details, payment credentials or card data; record each decision in `features.md`. United
   Capital kept its bank-detail records at Jon's request and left out the Versapay/Solupay ones.
6. **Build and validate.**
   ```bash
   python3 scripts/view-role.py build --alias <alias> --authid <ID>_M2M --out /tmp/cp-role-<alias>
   (cd /tmp/cp-role-<alias> && suitecloud project:validate --server)
   ```
   Fix what validation reports:
   - "Invalid permlevel reference key VIEW for permkey X": add X to `no-view-level.txt` (true in every
     account).
   - "The permkey field … must not be X": add X to `exclusions.txt` under "may not hold".
   - "The manifest contains a dependency on customrecord_x object, but it is not in the account": a
     SuiteApp's record that SDF can't reach (United Capital: `customrecord_nsapm_*`, `customrecord_item360_*`).
     Remove it from `custom-records.txt` and note it in `features.md`; add it in the UI if it's needed.
7. **Deploy, then re-import and diff.** Validation doesn't catch everything: the deploy refuses keys for
   missing features one at a time ("Invalid permkey reference key X"). `deploy` appends each refused
   key to `accounts/<alias>/dropped.txt` and retries until the deploy goes through:
   ```bash
   python3 scripts/view-role.py deploy --alias <alias> --authid <ID>_M2M --out /tmp/cp-role-<alias>
   (cd /tmp/cp-role-<alias> && mkdir -p Objects/Reimport \
     && suitecloud object:import --type role --scriptid customrole_cp_readonly --destinationfolder /Objects/Reimport)
   cp /tmp/cp-role-<alias>/Objects/Reimport/customrole_cp_readonly.xml accounts/<alias>/
   netsuite-cli suiteql --account <alias> "SELECT id FROM role WHERE scriptid = 'customrole_cp_readonly'"
   ```
   Deploy to production only when the account owner said production for this change. The re-import is
   much shorter than what you deployed: NetSuite silently drops keys for features the account lacks
   (United Capital: 464 deployed, 276 kept). Diff it against the build anyway and record in
   `features.md` anything NetSuite added. It adds `LIST_OTHER_ADDRESS` at Full every time, which needs
   Jon's acceptance (the `Accepted by` line) and step 11's address write must fail. Segment records
   re-import as `[type=customsegment, scriptid=cseg_…]`; `view-role.py` writes them in that form,
   because the `[scriptid=customrecord_cseg_…]` form fails a redeploy with "Record must be unique".

   To add one permission to a deployed role (as for the SuiteQL fix), the smallest change is the
   re-import plus that one line, deployed from the scratch folder: the role then differs from the live
   one by exactly that line. An SDF redeploy never removes a permission: to take one off a deployed role
   (`LIST_SYSTEMNOTES` when a client asks later), remove it in the UI, list it in `dropped.txt` and re-import.
8. **Put the role on the employee.** The agent signs in as one employee with this role. Either:
   - your own employee in that account (`ent` from step 3b). No extra user license, and audit trails
     show you with this role. United Capital uses employee 5 this way, for the browser too (step 13): the
     agent's browser switches to this role on every pass, and each browser login signs you out of that
     account, because NetSuite allows one session per user.
   - a dedicated employee "CP AI Support" with login access and only this role, when the client prefers
     the agent not to sign in as you. It takes a user license, and creating it needs the UI.

   Adding the role is a permissions change, so do it only with the account owner's yes. The REST API
   merges a new Roles line into the employee's existing roles:
   ```bash
   netsuite-cli record update employee <employee id> --account <alias> --data '{"roles":{"items":[{"selectedRole":{"id":"<role id>"}}]}}'
   netsuite-cli record get employee <employee id> --account <alias> --expand-sub-resources \
     | jq -r '.roles.items[] | "\(.selectedRole.id) \(.selectedRole.refName)"'
   ```
   Saving the employee runs that account's employee scripts and workflows, as a UI save would. SDF
   can't do this step (role assignments are record data), and neither SDF nor REST can delete a role:
   an old role is deleted in the UI (Setup > Users/Roles > Manage Roles).
9. **The agent's two certificates**, mapped to that employee and role through the same two integrations
   as step 3. Keys stay on this machine and out of every repo.
   ```bash
   cd ~/.config/netsuite-cli
   netsuite-cli account cert generate --key-out <alias>-ai-key.pem --cert-out <alias>-ai-cert.pem --common-name <alias>-ai
   chmod 600 <alias>-ai-key.pem
   netsuite-cli account cert upload --account <alias> --cert <alias>-ai-cert.pem --entity <employee id> --role <role id>
   netsuite-cli account add <alias>-ai --account-id <ID> --flow m2m --cert-id=<certificate id> --key ~/.config/netsuite-cli/<alias>-ai-key.pem

   mkdir -p ~/.suitecloud-sdk/keys/<ID>_AI && chmod 700 ~/.suitecloud-sdk/keys/<ID>_AI && cd ~/.suitecloud-sdk/keys/<ID>_AI
   openssl req -x509 -newkey rsa:4096 -sha256 -days 730 -nodes -subj "/CN=suitecloud-ai" -keyout suitecloud-key.pem -out suitecloud-cert.pem
   chmod 600 suitecloud-key.pem
   netsuite-cli account cert upload --account <alias> --cert suitecloud-cert.pem --client-id 6da57bf05a6247fc876c6d228184ff487760a382a43ac7e93eaff743803d22ac --entity <employee id> --role <role id>
   (cd /tmp/cp-role-<alias> && suitecloud account:setup:ci --account <ID> --authid <ID>_AI --certificateid <certificate id> \
     --privatekeypath ~/.suitecloud-sdk/keys/<ID>_AI/suitecloud-key.pem)
   ```
   Run `setup:ci` in the scratch folder, not here: it makes `<ID>_AI` the default of the folder it runs
   in, and this folder's `project.json` should stay on the admin auth id. The line must report the role
   "CP Support (Read Only)".
10. **Pilot config** (case-triage-agent `config/pilot.json`): set the customer's `alias` to
    `<alias>-ai` and `sdfAuthId` to `<ID>_AI`. `browserHost` stays null unless step 13 is done.
11. **Verify the role: reads work, writes fail.** Run these as `<alias>-ai` and stop if any result
    differs. Reads, all of which must succeed:
    ```bash
    netsuite-cli suiteql --account <alias>-ai "SELECT COUNT(*) AS n FROM transaction"
    netsuite-cli suiteql --account <alias>-ai "SELECT COUNT(*) AS n FROM script"
    netsuite-cli suiteql --account <alias>-ai "SELECT COUNT(*) AS n FROM workflow"
    netsuite-cli suiteql --account <alias>-ai "SELECT COUNT(*) AS n FROM ScriptNote"
    ```
    Counts keep client data out of the terminal. Also one `cp_saved_search_rl` GET, after step 12.

    Writes, all of which must fail with a permission error. Write each field back with the value it
    already has, so a write that wrongly succeeds changes nothing: read the customer with the admin
    alias first, then
    ```bash
    netsuite-cli record update customer <id> --account <alias>-ai --data '{"comments":<its current comments, as JSON>}'
    netsuite-cli record update customer <id> --account <alias>-ai --data '{"addressBook":{"items":[{"id":<an address line id>,"addressBookAddress":{"addr1":<its current addr1>}}]}}'
    ```
    If either write succeeds, stop: the role is too broad and the account is not onboarded. The
    address write matters because NetSuite grants `LIST_OTHER_ADDRESS` at Full on its own.

    Sensitive fields must not be readable:
    ```bash
    netsuite-cli suiteql --account <alias>-ai "SELECT COUNT(socialsecuritynumber) AS ssn, COUNT(salary) AS salary FROM employee"
    ```
    This must return an error or zero counts. If not, stop and find the permission that exposes them.
    With Advanced Employee Permissions on (United Capital), the role can't see employees at all
    ("Record 'employee' was not found"): that needs `LIST_EMPLOYEE_RECORD`, which is excluded as HR data.
12. **RESTlet audiences.** Check who each CP RESTlet deployment is open to:
    ```bash
    netsuite-cli suiteql --account <alias> "SELECT scriptid, allroles, audslctrole FROM scriptdeployment WHERE scriptid LIKE 'customdeploy_cp_%_rl'"
    ```
    The package deploys `cp_saved_search_rl` and `cp_file_cabinet_rl` to all roles (`allroles = T`), so
    there is nothing to add. `cp_mr_driver_rl` is Administrator only; leave it so. Only an account where
    someone narrowed a deployment needs the role added to it.

    A RESTlet runs with the caller's role, so the role's own permissions still apply inside it. The role
    holds `LIST_FILECABINET` ("Documents and Files") at View: the File Cabinet RESTlet lists, describes
    and downloads files for it, and refuses every write ("You need a higher level of the 'Lists ->
    Documents and Files' permission"). The agent's command guard is the second layer: `restlet call`
    allows `--method GET` with no `--data`, plus one POST: an ad-hoc `cp_saved_search_rl` run whose
    inline body holds `"run": true` and only the ad-hoc keys, which saves nothing (case-triage-agent
    `src/guard.ts`).

    As `<alias>-ai`, run one saved search through `cp_saved_search_rl` and count the rows, list a
    folder through `cp_file_cabinet_rl`, and rewrite one file's `isOnline` with the value it already has
    (`--method PUT --data '{"id":<file id>,"isOnline":<current value>}'`), which must fail.
13. **Browser use (only if the agent will use the UI).** The read-only role cannot open workflow
    definitions (that needs Full on the record type, see below), but it shows records as a user sees them,
    a record's workflow history, script and deployment pages and saved search results.
    1. The login is the step 8 employee: your own (it also holds other roles, such as Administrator) or a
       dedicated "CP AI Support" with only this role.
    2. Require two-factor authentication on this role in the UI (Setup > Users/Roles > Manage Roles), unless
       the account already requires it for every role. Without it a login from a new device asks security
       questions, which nothing automated can answer; with it the agent answers with `totp-cli`. SDF can't set
       it: the SDK offers `OFF` and `SMS` and the server refuses `SMS`. Re-import the role afterwards: it then
       reads `<tfarequired>TOTP</tfarequired>`, and a redeploy of a file still saying `OFF` would turn it off.
    3. Sign in once in a visible window and enrol the authenticator: NetSuite's two-factor is per account, so
       the authenticator for your CP login doesn't work here. NetSuite shows a setup key, which goes into
       `totp-cli` (it prompts without echo), and on your own login also into your phone, so both give the same
       codes. Tick "Trust this device" on the code page.
       ```bash
       agent-browser --session netsuite-ai-<alias> --session-name netsuite-ai-<alias> --headed open https://<account host>/app/center/card.nl
       totp-cli add netsuite-ai-<alias>
       ```
    4. Save the login to the agent-browser vault (it prompts for the password):
       ```bash
       agent-browser --session netsuite-ai-<alias> --session-name netsuite-ai-<alias> auth save netsuite-ai-<alias> \
         --url https://<account host>/app/center/card.nl --username <login email> --password-stdin
       ```
    5. In case-triage-agent `config/pilot.json`, give the customer `"browserHost": "<account host>"` and
       `"browserLogin": { "vaultProfile": "netsuite-ai-<alias>", "totpAccount": "netsuite-ai-<alias>", "role": <role id> }`,
       then run `node scripts/setup-agent.ts` (it adds the deny rules for the session). No code change. `role`
       is required for a login that holds other roles: each pass switches the browser to it through the
       account's change-role link and reads it back, or runs without the browser. Leave it out only for a
       login whose only role is this one.
    6. Run one pass on a case for this customer and check the log says `browser <account host> ready (…,
       in role <role id>)` or `switched to role <role id>`.
    Record the result of the multiple-sessions check from step 2.
14. **SDF through the agent's wrapper**, not raw `suitecloud`. Write a pass policy into a scratch run folder
    (`{"allowedAliases":["prod","<alias>-ai"],"browserHost":null,"forbiddenCaseId":null,"forbiddenCaseNumber":null,
    "forbiddenMessageIds":[],"allowedRestletScripts":[],"sdfAuthIds":{"<alias>-ai":"<ID>_AI"},"suitecloudPath":"<path>"}`),
    then from case-triage-agent:
    ```bash
    env -u SUITECLOUD_CI -u SUITECLOUD_CI_PASSKEY TRIAGE_POLICY_FILE=<run folder>/policy.json \
      bin/sdf-read list --account <alias>-ai --type workflow --scriptid customworkflow
    env -u SUITECLOUD_CI -u SUITECLOUD_CI_PASSKEY TRIAGE_POLICY_FILE=<run folder>/policy.json \
      bin/sdf-read export --account <alias>-ai --type restlet --scriptid customscript_cp_saved_search_rl
    ```
    Unsetting the two variables makes `sdf-read` read the passkey from the keychain, as it does under
    claude. Export a script the account owns: SuiteApp scripts (Versapay, STE and the like) are locked
    for everyone. Workflow exports fail for this role, by design (they need Full on the record type; see
    below); the agent reads workflows through SuiteQL instead. Delete `agent/.sdf-exports/<run folder name>/` afterwards so no pass reads it.

## Write access that remains

- `ADMI_APP_DEPLOYMENT` (SuiteApp Deployment, i.e. SDF) at Full: with it, SuiteCloud can update
  existing objects even when every customization permission is View (tested in SB2, see
  `accounts/sb2/features.md`). For the agent, `sdf-read` is the barrier.
- `ADMI_WORKFLOW` at Full: a person holding the role can create and edit workflows in the UI. It was
  added so workflows would export, but exports also need Full on each workflow's record type (see
  below). Keep it until a search with the `workflow` join has been run as this role: the join may
  need it (see "Workflow states" in `accounts/sb2/features.md`).
- `REPO_ANALYTICS` (SuiteAnalytics Workbook) at Edit: SuiteQL needs it. It lets the holder build their
  own workbooks and datasets, not change records.
- `LIST_OTHER_ADDRESS` at Full, added by NetSuite on every deploy.

Give the role to people knowing they get the first two.

## What building the role taught us (United Capital, 2026-10-31)

- Administrator is a standard role: SDF can't list or import it (`object:list --type role` returns
  custom roles only), and SuiteQL `rolepermissions` shows only its custom-record permissions. The full
  key list comes from the SuiteCloud CLI jar (`sdf_metadata/list/generic_permission.xml`).
- `project:validate --server` passes keys that the deploy then refuses. Expect a dozen or more deploy
  rounds on a first account; `view-role.py deploy` handles them.
- **SuiteQL needs `REPO_ANALYTICS` (SuiteAnalytics Workbook), not `ADMI_ANALYTICS` (Analytics
  Administrator).** The first baseline had `ADMI_ANALYTICS` at Full, and every SuiteQL query failed with
  "Your current role does not have permission" while REST record reads worked. `ADMI_ANALYTICS` is now
  in `exclusions.txt`. It is still on SB2's role and on United Capital's 1535, and a redeploy can't
  remove it: take it off in the UI.
- A redeploy only adds permissions; it never removes one. To narrow a deployed role, remove the
  permission in the UI (Setup > Users/Roles > Manage Roles) or deploy under a new script id.
- Center type for "Classic" is `ACCOUNTCENTER` in SDF XML; `CLASSIC` is rejected.
- A custom record permission is `[scriptid=customrecord_x]` in the role and needs `customrecord_x` as a
  manifest dependency. A custom segment's record is the exception: `[type=customsegment, scriptid=cseg_x]`
  with `cseg_x` in the manifest.

## What the SDF test taught us (SB2, 2026-10-31)

- The SDF permission is `ADMI_APP_DEPLOYMENT` ("SuiteApp Deployment"), Full only.
- With it and View-only customization permissions, **creating** an object was refused but **updating**
  an existing one succeeded. No role makes SuiteCloud read-only; the agent's `sdf-read` guard is the
  barrier. Details in `accounts/sb2/features.md`.
- **Exporting a workflow needs `ADMI_WORKFLOW` at Full and Full on every record type it runs on**, plus
  SDF access. Tested in SB2 on 2026-10-31 with two throwaway roles (`accounts/sb2/features.md`): Edit on
  the record type always failed ("You need a higher level of the 'Workflow' permission"), a workflow on
  three transaction types failed until all three were Full, and without `ADMI_WORKFLOW` the message is
  "You need the 'Workflow' permission". A custom record type that needs no permission counts as Full.
  The customization permissions are not needed. Full on a record type means creating, editing and deleting those records, so this role will
  not export workflows; the agent reads them through SuiteQL (`workflow` table). `ADMI_MANAGEROLES` is
  in `exclusions.txt`, so role definitions don't export either. Some forms refuse to export (likely their role
  preferences).
- SB2's role predates this process: it is the narrow baseline version under the old script id
  `customrole_cp_ai_readonly`. Rebuild it with `view-role.py` before SB2 is used again.
