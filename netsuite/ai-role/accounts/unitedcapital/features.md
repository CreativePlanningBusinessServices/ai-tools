# United Capital (United Capital Financial Advisors, LLC, account 4244448, production)

Role: `customrole_cp_readonly` ("CP Support (Read Only)"). Production. Approval: Jon (admin in 4244448)
confirmed approval on 2026-10-31.

History: first deployed 2026-10-31 as `customrole_cp_ai_readonly` ("CP AI Support (Read Only)", internal
id 1534) from the baseline. Jon found it too narrow next to the account's own "UCW - CFO/Executive" role
(170 permissions), and renamed it the same day so people can hold it too. Delete role 1534 in the UI.

## How this role was built: Administrator, flipped to View

Administrator's standard permissions are implicit (SuiteQL `rolepermissions` lists only its custom record
permissions), so the role was built from SDF's full permission list (`sdf_metadata/list/generic_permission.xml`
in the SuiteCloud CLI jar, 702 keys) instead:

1. Every key at `VIEW`, minus the exclusions below.
2. `project:validate --server` against 4244448, then dropped what NetSuite rejected:
   - 149 keys that have no View level (Full-only setup permissions such as `ADMI_ACCOUNTING`,
     `ADMI_COMPANY`, `ADMI_AUDITLOGIN`, `REPO_ANALYTICS`).
   - 9 keys a custom role may not hold: `ADMI_BILLPAYSETUP`, `TRAN_APPROVEDD`, `TRAN_APPROVEEFT`,
     `TRAN_APPROVEVP`, `TRAN_BILLPAY_APPROVE`, `TRAN_BILLPAY_STATUS`, `TRAN_STATUSDD`, `TRAN_STATUSEFT`,
     `TRAN_STATUSVP`.
   - All single sign-on keys (`ADMI_SAMLSSO`, `ADMI_OPENIDSSO`, `ADMI_OIDC`, and their setup keys): they
     can't be combined with each other or with SuiteAnalytics Connect, and the role doesn't sign in by SSO.
3. Added three keys missing from SDF's list that the CFO role holds: `LIST_BULK_PROCESSING`,
   `LIST_CONTACTSUBSIDIARYRELATION`, `ADMI_RECORDS_CATALOG` (View).
4. Kept the baseline's non-View levels: `ADMI_RESTWEBSERVICES`, `ADMI_ANALYTICS` (see "SuiteQL fix"), `ADMI_LOGIN_OAUTH2` (all
   Full, API access), plus `ADMI_APP_DEPLOYMENT` and `ADMI_WORKFLOW` (Full only) for SDF exports.

Result: 480 permissions (64 setup, 186 lists, 20 registers, 56 reports, 151 transactions), validated with
0 errors.

## Deploy (2026-10-31, role internal id 1535)

`project:validate --server` does not catch everything. The deploy refused 16 more keys, one per attempt
("Invalid permkey reference key …"), and each was dropped before the next attempt: `LIST_ADDRESS`,
`LIST_EMPLOYEE_PUBLIC`, `LIST_EMPLOYEE_SELF`, `LIST_MYROLES`, `LIST_TEGATAACCOUNT`, `REPO_EMAIL`,
`REPO_GSTSUMMARY`, `REPO_PSTSUMMARY`, `ADMI_CUSTPAGE`, `TRAN_GST_REFUND`, `TRAN_PRINT`,
`TRAN_PRINTCHECKSFORMS`, `TRAN_RECEIVEINBOUND`, `TRAN_TAXLIAB`, `TRAN_TEGPYBL`, `TRAN_TEGRCVBL`.
The 17th attempt created the role with 464 permissions.

The re-import holds 276: NetSuite silently dropped 189 keys for features this account doesn't have
(manufacturing, work orders, inventory, projects, revenue recognition, subscriptions, time, HCM,
commissions, payroll tax reports) and added `LIST_OTHER_ADDRESS` at Full. `customrole_cp_readonly.xml`
in this folder is the re-import, i.e. the role as it exists in the account.

## Excluded on purpose (sensitive data or security administration)

- Payroll and compensation: `ADMI_PAYROLL`, `LIST_PAYCHECK`, `LIST_PAYROLLITEM`, `REGT_PAYROLL`,
  `REPO_PAYCHECKDETAIL`, all `REPO_PAYROLL*`, `TRAN_COMMITPAYROLL`, `TRAN_MANAGEPAYROLL`, `TRAN_PAYCHECK`,
  `TRAN_PAYROLLRUN`, `TRAN_COMMISSN`, `TRAN_APPROVECOMMISSN`.
- HR and confidential employee data: `LIST_EMPLOYEESSN`, `LIST_EMPLOYEE_CONFIDENTIAL`,
  `LIST_EMPLOYEE_ADMINISTRATION`, `LIST_EMPLOYEE_RECORD`, `LIST_EMPLOYEE_ACCESS`, `LIST_EMPLOYEECHANGE*`,
  `LIST_EMPLOYEEEFFECTIVEDATING`, `LIST_EMPLOYEESEPARATION`, `LIST_TALENT_ADMINISTRATION`,
  `LIST_JOBREQUISITION`, `LIST_TIMEOFFADMIN`.
- Credentials, keys and payment data: `ADMI_KEYS`, `LIST_KEYS`, `ADMI_SECRETS`, `ADMI_CERTIFICATES`,
  `LIST_CERTIFICATES`, `ADMI_EMAILPWD`, `LIST_GENERAL_TOKEN`, `LIST_PAYMENT_CARD`, `LIST_PAYMENT_CARD_TOKEN`,
  `LIST_PAYMENT_INSTRUMENTS`, `ADMI_VIEWACHACCOUNT`, `ADMI_VIEWCREDITCARDS` (unmasked card numbers),
  `TRAN_EDITBANKINGINFO`, `LIST_ACH`, `ADMI_ACH`.
- Users, roles, OAuth and SSO administration: `ADMI_MANAGEUSERS`, `ADMI_MANAGEROLES`, `ADMI_MANAGE_OAUTH2`,
  `ADMI_MANAGE_OAUTH_TOKENS`, `ADMI_MANAGE_OWN_OAUTH_TOKENS`, `ADMI_LOGIN_OAUTH`, `ADMI_OPENIDSSOSETUP`,
  `ADMI_SAMLSSOSETUP`, `ADMI_VICARIOUS_EMAILS`.
- Bulk data export and personal-data removal: `ADMI_BACKUPEXPORT`, `LIST_EXPORT`, `ADMI_PI_REMOVAL_CREATE`,
  `ADMI_PI_REMOVAL_RUN`.
- Found only after the deploy, and dropped by NetSuite here only because the features are off. Exclude
  them explicitly for the next account: government-issued IDs (`LIST_ALLGOVERNMENTISSUEDIDS`,
  `LIST_BASICGOVERNMENTISSUEDIDS`, `LIST_GOVERNMENTISSUEDIDTYPE`), bonuses (`LIST_BONUS`,
  `LIST_BONUSTYPE`), employee tax forms (`REPO_W4`, `TRAN_AMENDW4`, `REPO_940`, `REPO_941`), commission
  rules and reports (`LIST_COMMISSIONRULES`, `REPO_COMMISSION`), HCM (`LIST_HCMJOB`, `LIST_HCMPOSITION`,
  `REPO_WORKFORCEANALYTICS`).
- `LIST_FILECABINET`: was an opt-in at first; added at View on 2026-10-31 at Jon's request (see "Verification").

Included, unlike the baseline: bank and card transactions and registers at View (`TRAN_CARDCHRG`,
`TRAN_CARDRFND`, `TRAN_CHECK`, `TRAN_DEPOSIT`, `TRAN_TRANSFER`, `REGT_BANK`, `REGT_CREDCARD`). The CFO
role has them too.

## Custom records (added 2026-10-31)

The account has 302 custom record types (`SELECT usepermissions, nopermissionrequired FROM customrecordtype`):
75 need no permission, 168 "Require Custom Record Entries Permission" (covered by `LIST_CUSTRECORDENTRY`
at View), and 59 "Use Permission List", which a role sees only when it lists them.

47 of the 59 are on the role at View, deployed as an update to role 1535 (323 permissions in all). The
SDF entries are `[scriptid=customrecord_…]`, and each needs an `<object>` dependency in `manifest.xml`;
the deploy used a scratch copy of this project so the shared manifest stays account-neutral. The three
segment records re-import as `[type=customsegment,scriptid=cseg_…]`.

- Included at Jon's request (2026-10-31), although they hold bank account data: Bank Details
  (`customrecord_2663_entity_bank_details`), Company Bank Details (`customrecord_2663_bank_details`),
  Entity Bank Details (FI) (`customrecord_fispan_vendor_bank_details`), Bill EFT Payment Information
  (`customrecord_2663_bill_eft_payment`).
- Left out: Solupay Merchants (`customrecord_solupay_merchants`) and Versapay SuitePayment
  (`customrecord_solupaysuitepayment`), which may hold processor credentials or card data.
- Not reachable through SDF ("not in the account"): the APM SuiteApp setup records (`customrecord_nsapm_*`,
  7) and Item 360 setup records (`customrecord_item360_*`, 3). Add them in the UI if needed.

## Write access that remains

- `ADMI_APP_DEPLOYMENT` lets SuiteCloud update existing objects even with View-only customization
  permissions (see `accounts/sb2/features.md`). For the agent, the `sdf-read` guard is the barrier.
- `ADMI_WORKFLOW` at Full lets a person holding this role create and edit workflows in the UI, and does
  not make workflows export (see step 14 above). Keep it until a search with the `workflow` join has
  been run as this role (see "Workflow states" in `accounts/sb2/features.md`).
- NetSuite added `LIST_OTHER_ADDRESS` at Full on deploy (as on role 1534 and in SB2). ONBOARDING step
  11's address write must fail.
- `ADMI_ANALYTICS` (Analytics Administrator) at Full, from the first baseline. It is the wrong
  permission for SuiteQL and is now in `exclusions.txt`; remove it from role 1535 in the UI.

## SuiteQL fix (2026-10-31)

The first verification as `unitedcapital-ai` failed: every SuiteQL query returned "Your current role does
not have permission", while REST record reads worked. SuiteQL needs `REPO_ANALYTICS` (SuiteAnalytics
Workbook), which the UCW roles hold at Edit, not `ADMI_ANALYTICS`. The baseline now sets
`REPO_ANALYTICS` at Edit.

Deployed 2026-10-31 with Jon's yes, as the re-import plus that one line (324 permissions; the re-import
in this folder matches it line for line). A first attempt from `view-role.py` failed with "Record must be
unique": the script wrote the three segment records as `[scriptid=customrecord_cseg_…]`, which the role
already holds as `[type=customsegment, …]`. The script now writes the segment form. Its build matches
this role except for keys NetSuite drops here and the two it holds on its own (`ADMI_ANALYTICS`,
`LIST_OTHER_ADDRESS`), and dry-runs as an update; a real redeploy hasn't been run since the fix.

## Verification as `unitedcapital-ai` (ONBOARDING step 11, 2026-10-31)

- SuiteQL reads work (counts only): transaction 78,057; customer 141,502; script 883; workflow 32;
  ScriptNote 4,559; Bank Details custom record 208.
- Writes refused with `INSUFFICIENT_PERMISSION` ("Lists -> Customers"): one customer's comments and one
  of its address lines, each rewritten with the value it already had.
- Employees are not visible at all ("Record 'employee' was not found"), so SSN and salary are not
  reachable. Advanced Employee Permissions is on here and `LIST_EMPLOYEE_RECORD` is excluded. The agent
  can't look up employees by name in this account.
- RESTlets (step 12): `cp_saved_search_rl` and `cp_file_cabinet_rl` are deployed to all roles here, so
  the role needed no audience change. A transaction saved search ran through `cp_saved_search_rl`. The
  File Cabinet RESTlet at first refused the role ("Lists -> Documents and Files"). `cp_mr_driver_rl` is
  Administrator only.
- Documents and Files (2026-10-31, Jon's request): `LIST_FILECABINET` deployed at View as the re-import
  plus that one line (325 permissions; the re-import in this folder is the result). As the agent, the File
  Cabinet RESTlet lists the root, describes and downloads a file, and SuiteQL counts 17,046 files.
  Rewriting one file's `isOnline` with its current value through the RESTlet's PUT was refused ("You need
  a higher level of the 'Lists -> Documents and Files' permission"). The agent's guard also allows only
  GET on RESTlets. The File Cabinet can hold statements and HR files, and the role can now read them.
- `sdf-read` (step 14, 2026-10-31, as `4244448_AI` with the passkey from the keychain): listing workflows
  works, and CP's `customscript_cp_saved_search_rl` exported. SuiteApp scripts (STE, Versapay) are locked
  for everyone. **Every workflow export fails** ("You need a higher level of the 'Workflow' permission")
  although NetSuite lists `ADMI_WORKFLOW` at Full on the role; the admin login exports the same workflow.
  Tested in SB2 the same day: a workflow export needs Full on the workflow's record type (Edit is not
  enough), so this role won't export workflows. The agent reads them through SuiteQL.

## Entity

The agent signs in as Jon's own employee in this account (employee 5, the entity of the `unitedcapital`
admin alias), with this role, through netsuite-cli's built-in integration and SuiteCloud's. No dedicated
employee or integration record. Browser use (2026-11-02, the client's yes): the same employee's login, saved as
vault profile and `totp-cli` account `netsuite-ai-unitedcapital`, with `"role": 1535` in the pilot config so each
pass switches the browser to this role (case-triage-agent PR #4); tested end to end the same day. Role 1535 was added to employee 5 through
`netsuite-cli record update employee` on 2026-10-31, with Jon's yes; Jon deleted role 1534 in the UI.

Agent logins (2026-10-31, certificates valid to 2028-10-30): netsuite-cli alias `unitedcapital-ai`,
SuiteCloud auth id `4244448_AI` ("CP Support (Read Only)"). Admin logins: `unitedcapital-login`
(browser), `unitedcapital` and `4244448_M2M` (certificates).

## Two-factor (2026-11-02)

SDF cannot require two-factor on this role. The SDK lists only `OFF` and `SMS` for `tfarequired`, and
the server refuses `SMS` ("The object field tfarequired must not be SMS") at validation, so nothing was
deployed. Jon required it in the UI the same day; the re-import then reads `<tfarequired>TOTP</tfarequired>`, a
value the SDK's list doesn't have. The committed file holds that re-import, so a redeploy of it keeps two-factor
on (a redeploy with `OFF` would turn it off).

## System notes in SuiteQL (2026-11-02)

Without the System Notes for Analytics and REST permission (`LIST_SYSTEMNOTES`), SuiteQL's `systemnote` table
returns only the changes the querying user made: role 1535 saw 1.9 million of the account's 9.4 million notes, all
made by employee 5 (the user it runs as), and none of the 3,016 CSV notes on invoices 399452–399499. Notes Tab
(`LIST_HISTORY`) and the transaction permissions don't change that. An ad-hoc search with the
`systemnotes.context` join does return other users' notes to the role.

Jon added `LIST_SYSTEMNOTES` (View) in the UI to test it. The role then saw all 9,409,626 notes, the same as admin,
including notes on employee records it cannot otherwise read: gender (293), termination reason and details (3 each)
and release dates, with their values. The permission is not limited by record access. A system-note search
(N/search) still is: it returns only the role's own changes, and an employee search with the system-notes join is
refused.

Kept on the role (2026-11-02): United Capital is fine with the agent reading employee change history, per Jon.
The role file holds the re-import with `LIST_SYSTEMNOTES`. Employee values stay out of the triage reports: the agent
is told never to report them, and the runner removes any value it read from an employee-record note
(case-triage-agent PR #10). The baseline now includes it for every client, with removal on request (ONBOARDING
step 1). SDF accepts the key although its permission list lacks it: validation and a dry run of this role file
passed on 2026-11-02.

Accepted by: ____
