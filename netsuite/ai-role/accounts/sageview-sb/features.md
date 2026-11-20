## Browser (step 13, 2026-11-20)

- The login is employee 130897 ("CPES Support-1", `cpes+sageview@creativeplanning.com`), which also holds
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
