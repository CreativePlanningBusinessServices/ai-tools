# SageView production (account 875176)

Role: `customrole_cp_readonly` ("CP Support (Read Only)"), internal id 2461. SuiteCloud names the account
"Creative Planning Institutional Advisors, LLC"; the sandbox (`accounts/sageview-sb/`, done first) still
shows SageView Advisory Group, LLC. Approval: Jon. SageView is a Creative Planning subsidiary and CP has full
access to the account; Jon approved production, the role on his login and the RESTlet package on 2026-11-20.

Support cases come in under CP's customer 439432 ("IC - SageView Retirement").

## Survey (2026-11-20)

- 14 subsidiaries (OneWorld), so the header keeps `<subsidiaryoption>ALL</subsidiaryoption>`.
- About 280,500 transactions. In 2026: invoices, customer payments and card charges lead, then revenue
  arrangements, vendor payments and bills, deposits, journals.
- Grouping transactions by type fails with an unexpected-error 500 even from 2025 on; 2026 alone runs.
- 255 custom record types, 165 "Use Permission List": the same 165 as the sandbox.
- CP's saved search, File Cabinet, MR driver and email template RESTlets were already installed. The package
  (`netsuite/restlets`) was deployed on 2026-11-20: it added the PDF template RESTlet and updated the other
  four; `verify.sh sageview` passed.

## Custom records

Same decisions as the sandbox (`custom-records.txt` is a copy): 99 types at View, Versapay
(`customrecord_netsuitepay`) left out, and the 65 NetClose, APM, SFTP and email-capture types SDF can't reach
left out.

## Deploy (2026-11-20, role internal id 2461)

`view-role.py deploy` took 10 attempts, refusing the same nine keys as the sandbox (`dropped.txt`). Built with
560 permissions, deployed with 551; the re-import holds 392, the same keys as the sandbox. Not at View:
`REPO_ANALYTICS` Edit, `LIST_OTHER_ADDRESS` Full (added by NetSuite as usual; step 11's address write was
refused), `ADMI_LOGIN_OAUTH2`, `ADMI_RESTWEBSERVICES`, `ADMI_APP_DEPLOYMENT` and `ADMI_WORKFLOW` Full.
`coreadminpermission` is on. Two-factor is `OFF` on the role (see Browser).

Role 2461 was added to employee 130897 ("CPES Support-1", `cpes+sageview@creativeplanning.com`), which also
holds Administrator and NetSuite 360.

## Verification (step 11, 12, 14), as `sageview-ai`

- Reads work: transactions (278,440 against the admin's ~280,500), scripts (911), workflows (42),
  ScriptNote, customers.
- Writes refused with `INSUFFICIENT_PERMISSION` ("Lists -> Clients"): one customer's comments and one
  address line, each rewritten with the value it already had.
- Employees are not visible ("Record 'employee' was not found"), so SSN and salary are not reachable.
- RESTlets: saved search 461 ran through `cp_saved_search_rl`, `/SuiteScripts` listed through
  `cp_file_cabinet_rl`, and an `isOnline` rewrite with its current value was refused ("Lists -> Documents and
  Files"). A file in a folder the role can't see is refused earlier ("You do not have access to the media
  item you selected").
- SDF as `875176_AI`: workflows listed, `customscript_cp_saved_search_rl` exported.

## Browser (step 13, 2026-11-20)

- Same approach as the sandbox: the login was already on Jon's phone, so Jon copied the production secret
  into `totp-cli add netsuite-ai-sageview` and saved vault login `netsuite-ai-sageview`.
- `ensureBrowserSession` returned "logged in from vault with 2FA, switched to role 2461"; the page context
  read back `customrole_cp_readonly`, and the employee list showed "you do not have permission to access
  employee data".
- Pilot config: customer 439432 with alias `sageview-ai`, `sdfAuthId` `875176_AI`, browser host
  `875176.app.netsuite.com`, role 2461; `setup-agent.ts` added the session's deny rules.

## Logins on Jon's Mac

- Admin: `sageview-login` (browser), `sageview` (M2M) and SuiteCloud `875176_M2M`, employee 130897 with
  Administrator.
- Agent: `sageview-ai` (M2M) and SuiteCloud `875176_AI`, employee 130897 with role 2461.
