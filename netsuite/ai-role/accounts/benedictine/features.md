# Benedictine Sisters of Perpetual Adoration (account 11996600, production)

Role: `customrole_cp_readonly` ("CP Support (Read Only)"), internal id 1447. No sandbox. A client account:
Jon confirmed the client's written approval (role, certificate logins, browser login, SuiteCloud access) on
2026-11-25 and approved the production deploy and the role on the login the same day.

Support cases come in under CP's customer 441319.

## Survey (2026-11-25)

- 2 subsidiaries, so the header keeps `<subsidiaryoption>ALL</subsidiaryoption>`.
- About 74,700 transactions, a third of them eTap donation sales (custom transaction type `CuTrSale`). In
  2026: sales orders, invoices and item fulfilments lead, then customer payments, deposit applications,
  customer deposits, cash sales and deposits.
- 403 custom record types, 109 of them "Use Permission List".
- CP's five RESTlets were installed earlier the same day (`verify.sh benedictine` passed).

## Custom records and transaction types

60 lines on the role at View: 59 custom record types and the custom transaction type
`customsale_legacy_etap_transactio`.

- Left out: Company Bank Details, Bank Details and Bill EFT Payment Information (bank account details), and
  Online Donation Setup and Online Donor Key (donation-gateway setup). Unlike United Capital and SageView,
  this is a client account, so the bank-detail records stay off unless the client asks.
- Not reachable through SDF ("not in the account"), 45 record types: nonprofit grants and segments
  (`npo`, `cseg_npo_*`), Benchmark 360, APM, Item 360, SuiteSuccess and similar SuiteApp records, plus the
  NPO custom transaction types Receivable Write-Off and Release from Restriction (no records).
- The baseline doesn't cover custom transaction types: without the `customsale_` line the role saw 49,897
  of 74,681 transactions (no `CuTrSale`). With it, all of them.

## Deploy (2026-11-25, role internal id 1447)

`view-role.py deploy` took 3 attempts (`dropped.txt`: `REPO_EMAIL`, `TRAN_RECEIVEINBOUND`). A second deploy
added the custom transaction type. It first failed with "Record must be unique": this account has a segment
named `cseg1`, and `view-role.py` only recognised `cseg_` names, so it sent `[scriptid=customrecord_cseg1]`
instead of the `[type=customsegment, scriptid=cseg1]` form the role holds. Fixed in `view-role.py` (any
`customrecord_cseg` prefix). The re-import holds 358 keys. Not at View: `REPO_ANALYTICS` Edit,
`LIST_OTHER_ADDRESS` Full (added by NetSuite as usual; step 11's address write was refused),
`ADMI_LOGIN_OAUTH2`, `ADMI_RESTWEBSERVICES`, `ADMI_APP_DEPLOYMENT` and `ADMI_WORKFLOW` Full.
`coreadminpermission` is on; two-factor is `OFF` on the role.

Role 1447 was added to employee 5319 ("CPES Support 1"), which also holds Administrator, the BSPA roles and
two NetSuite 360 roles. The account requires a department on employees and 5319 had none, so the same save
set it to Monastery (Jon's choice).

## Verification (step 11, 12, 14), as `benedictine-ai`

- Reads work: transactions (all 74,681), scripts (861), workflows (37), ScriptNote, customers.
- Writes refused with `INSUFFICIENT_PERMISSION` ("Lists -> Constituents"): one customer's comments and one
  address line, each rewritten with the value it already had.
- Employees are not visible ("Record 'employee' was not found"), so SSN and salary are not reachable.
- RESTlets: saved search 1079 ran through `cp_saved_search_rl`, the CP RESTlet folder listed through
  `cp_file_cabinet_rl`, and an `isOnline` rewrite with its current value was refused ("Lists -> Documents and
  Files"). `cp_mr_driver_rl` stays Administrator only.
- SDF as `11996600_AI`: workflows listed, `customscript_cp_saved_search_rl` exported.

## Browser (step 13, 2026-11-25)

- Same approach as SageView: Jon copied the login's existing authenticator secret into
  `totp-cli add netsuite-ai-benedictine` and saved vault login `netsuite-ai-benedictine`.
- The first vault save could not be decrypted by the agent ("Decryption failed: aead::Error"). `auth save`
  runs through agent-browser's default daemon, which encrypts with the `AGENT_BROWSER_ENCRYPTION_KEY` it was
  started with. That daemon had been started from a terminal whose `~/.zshrc` exports a different key from
  the one in Claude's settings (the one the agent runs with), so every later save used the wrong key, even
  with the right key exported for that command. `agent-browser close` (default session), then saving again
  under the settings key, fixed it.
- `ensureBrowserSession` returned "logged in from vault with 2FA, switched to role 1447"; the page context
  read back `customrole_cp_readonly`, and the employee list showed "you do not have permission to access
  employee data".
- Pilot config: customer 441319 with alias `benedictine-ai`, `sdfAuthId` `11996600_AI`, browser host
  `11996600.app.netsuite.com`, role 1447.
- Still to confirm: Administrator as the login's default role (My Roles), and whether the account allows
  multiple sessions per user.

## Logins on Jon's Mac

- Admin: `benedictine-login` (browser), `benedictine` (M2M) and SuiteCloud `11996600_M2M`, employee 5319
  with Administrator.
- Agent: `benedictine-ai` (M2M) and SuiteCloud `11996600_AI`, employee 5319 with role 1447.
