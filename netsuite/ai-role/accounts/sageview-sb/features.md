# SageView sandbox (SageView Advisory Group, LLC, account 875176_SB1)

Role: `customrole_cp_readonly` ("CP Support (Read Only)"), internal id 2360. Sandbox, done before
production (875176). Approval: Jon. SageView is a Creative Planning subsidiary and CP has full access to
the account; Jon approved the role, the RESTlet package and the role on his employee on 2026-11-20.

Support cases come in under CP's customer 439432 ("IC - SageView Retirement").

## Survey (2026-11-20)

- 14 subsidiaries (OneWorld), so the header keeps `<subsidiaryoption>ALL</subsidiaryoption>`.
- About 267,000 transactions. Since 2025: invoices, customer payments and card charges lead, then revenue
  arrangements, vendor bills and payments, journals, deposits.
- `SELECT type, COUNT(*) FROM transaction GROUP BY type` over every year fails with an unexpected-error 500;
  with a date filter it runs.
- 255 custom record types, 165 of them "Use Permission List".
- CP scripts already there (FAM, bulk deletion, invoice PDFs), but none of CP's RESTlets. The RESTlet package
  (`netsuite/restlets`) was installed on 2026-11-20 and `verify.sh sageview-sb` passed.

## Custom records

99 of the 165 "Use Permission List" types are on the role at View.

- Included, as for United Capital, although they hold bank or payment data: Company Bank Details, Bank
  Details, Bill EFT Payment Information and the other Electronic Payments (`customrecord_2663_*`) records.
- Left out: Versapay SuitePayment (`customrecord_netsuitepay`), which may hold processor or card data.
- Not reachable through SDF ("not in the account"), 65 types: NetClose (`customrecord_nact_*`), APM setup
  (`customrecord_nsapm_*`), SFTP (`customrecord_ns_sftp_*`, `customrecord_ps_sftp_*`) and email-capture
  (`customrecord_scs_email_*`) records. Add them in the UI if the agent needs them. A saved search on a
  NetClose record is refused to the role ("You need a higher permission for custom record type NetClose
  Accounting Procedure Step").

## Deploy (2026-11-20, role internal id 2360)

`view-role.py deploy` took 10 attempts; the refused keys are in `dropped.txt`. Built with 560 permissions,
deployed with 551; the re-import holds 392. NetSuite added `LIST_OTHER_ADDRESS` at Full as usual, and
step 11's address write was refused. `coreadminpermission` is on (baseline since 2026-11-03).

## Verification (step 11, 12, 14), as `sageview-sb-ai`

- Reads work: transactions, scripts, workflows (41), ScriptNote, customers.
- Writes refused with `INSUFFICIENT_PERMISSION` ("Lists -> Clients"): one customer's comments and one
  address line, each rewritten with the value it already had.
- Employees are not visible ("Record 'employee' was not found"), so SSN and salary are not reachable.
- RESTlets: a transaction saved search ran through `cp_saved_search_rl`, `/SuiteScripts` listed through
  `cp_file_cabinet_rl`, and an `isOnline` rewrite with its current value was refused ("Lists -> Documents
  and Files").
- `sdf-read` listed workflows and exported `customscript_cp_saved_search_rl` as `875176_SB1_AI`.

## Browser (step 13, 2026-11-20)

- The login is employee 130897 ("CPES Support-1"), which also holds
  Administrator and NetSuite 360. Administrator is its default role (My Roles, set by Jon on 2026-11-20).
- The account allows multiple sessions per user, so the agent's browser does not sign Jon out.
- Two-factor on role 2360 could not be set: the role's "Two-Factor Authentication Required" field is greyed
  out at "Not required" (possibly because of Core Administration Permissions; not confirmed). It doesn't
  block the agent: the login lands in Administrator, which asks for the authenticator code, and the agent
  then switches to role 2360.
- The login was already enrolled on Jon's phone, so NetSuite would not show the setup key again. Jon copied
  the secret from his authenticator app into `totp-cli add netsuite-ai-sageview-sb`; phone and agent share it.
- Vault login `netsuite-ai-sageview-sb` (saved by Jon). `ensureBrowserSession` returned "logged in from vault
  with 2FA, switched to role 2360", the page context read back `customrole_cp_readonly`, and the employee
  list showed "you do not have permission to access employee data".

## Logins on Jon's Mac

- Admin: `sageview-sb-login` (browser), `sageview-sb` (M2M) and SuiteCloud `875176_SB1_M2M`, all employee
  130897 (Jon) with Administrator.
- Agent: `sageview-sb-ai` (M2M) and SuiteCloud `875176_SB1_AI`, employee 130897 with role 2360.

## Still to do

- Production done on 2026-11-20 (`accounts/sageview/`).
