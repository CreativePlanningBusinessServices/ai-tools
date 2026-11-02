# SB2 (Creative Planning sandbox 2, account 6967599_SB2)

First tailored account. Role: `customrole_cp_ai_readonly`, deployed 2026-10-30.

Renamed 2026-10-31 to `customrole_cp_readonly` ("CP Support (Read Only)") so people can use it too. SB2
still holds the role under the old script id and name; deploy this file to SB2 (it creates the new role)
and delete the old one in the UI before SB2 is used again.

Transaction types in use (`SELECT type, COUNT(*) FROM transaction GROUP BY type`): CustInvc, CustPymt,
VendPymt, Journal, VendBill, Deposit, CashSale, ExpRept, Check, VendCred, CustCred, Transfer, CashRfnd,
Opprtnty, CustRfnd, DepAppl, CustDep, SalesOrd, RtnAuth, CardChrg.

Added on top of the baseline (all View):

| Permission | Why |
|---|---|
| `TRAN_CUSTCRED`, `TRAN_VENDCRED` | Credit memos and vendor credits are in use (348 and 410) |
| `TRAN_CASHSALE`, `TRAN_CASHRFND`, `TRAN_CUSTRFND` | Cash sales (31k), cash refunds and customer refunds are in use |
| `TRAN_OPPRTNTY` | Opportunities are in use (15); the ERP flow links them to contracts and projects |
| `TRAN_EXPREPT` | Expense reports are in use (16k). They carry employee reimbursement data; a client account needs the client's confirmation for this one |
| `LIST_JOB`, `LIST_PROJECTTASK` | Projects and project tasks back the ERP support cases |

Deliberately not added although used: `Deposit`, `Check`, `Transfer`, `CardChrg` (bank and payment
instruments).

Left out of the committed file:
- `TRAN_PURCHORD`: SB2 has no purchase orders and NetSuite drops it silently.
- `ADMI_WORKFLOW`: accepts only Full.
- `LIST_FILECABINET`: optional per-account opt-in (broad File Cabinet read); SB2 doesn't need it. The
  deployed SB2 role still holds it from the first deploy, because SDF redeploys never remove
  permissions; remove it in the UI if wanted.

NetSuite-imposed permission (not in the role definition): `LIST_OTHER_ADDRESS` at Full is added by
NetSuite on deploy and shows in a re-import. It is a Full on address records and needs Jon's explicit
acceptance. ONBOARDING.md step 12 includes an address write that must fail.

Added 2026-10-31 for the SDF read test (all View): `ADMI_CUSTFORM`, `ADMI_CUSTENTRYFORM`, `ADMI_CUSTBODYFIELD`,
`ADMI_CUSTCOLUMNFIELD`, `ADMI_CUSTENTITYFIELD`, `ADMI_CUSTEVENTFIELD`, `ADMI_CUSTITEMFIELD`, `ADMI_CUSTFIELDTAB`,
`LIST_EMAILTEMPLATE`.

## SDF read test (2026-10-31)

Question: can SuiteCloud CLI run under this role so it can export definitions but not deploy?

- The SDF permission is `ADMI_APP_DEPLOYMENT` ("SuiteApp Deployment"); it accepts only Full.
- With it, plus View on the customization permissions, exports worked for scripts and deployments,
  custom record types, custom lists, CRM fields, saved searches, Advanced PDF and email templates,
  subtabs and some entry/transaction forms.
- Exports refused: workflows (need `ADMI_WORKFLOW`, Full only), roles (need `ADMI_MANAGEROLES`, Full
  only), and forms that the Administrator can export but this role cannot (likely their role preferences).
- Deploys: creating a new custom list was refused ("higher level of the Custom Lists permission"), but
  **updating an existing custom list succeeded** (its description changed). View-level customization
  permissions do not stop SDF updates, so a role with `ADMI_APP_DEPLOYMENT` is not read-only.
- Cleanup: `ADMI_APP_DEPLOYMENT` removed in the UI, the SuiteCloud certificate revoked, the list restored.
  Jon's SB2 employee still holds this role (added for the test).

Conclusion: SDF access means trusting the agent's command guard (`sdf-read`, exports only). Jon decided on
2026-10-31 to give client roles SDF access anyway (ONBOARDING step 15).

Accepted by: ____

## Workflow export test (2026-10-31)

Question: which permission does a workflow export need beyond `ADMI_WORKFLOW` at Full? (United Capital's
role refused every workflow export with it.)

Throwaway role `customrole_cp_wftest` ("CP Workflow Export Test", internal id 1677): login and SDF
permissions, `ADMI_WORKFLOW` Full, every customization permission at View, Customers (`LIST_CUSTJOB`) and
Projects (`LIST_JOB`) at View. Put on Jon's employee 242090 with his yes, with a SuiteCloud certificate
mapped to it. Exports of `customworkflow_cpes_client_defaults` (customer) and
`customworkflow_project_defaults` (project):

| Customers | Customer workflow | Project workflow |
|---|---|---|
| View | refused | refused |
| Edit | refused | refused |
| Full | **exported** | refused |

Narrowed the same day with a second throwaway role, `customrole_cp_wftest2` ("CP Workflow Export Test 2",
internal id 1678), and more grants on 1677:

| Role | Grants | Workflow | Result |
|---|---|---|---|
| 1677 | Invoices Edit | `customworkflow_cp_es_invoice_defaults` (invoice) | refused |
| 1677 | Invoices Full | same | **exported** |
| 1677 | Vendor bills and vendor credits Full, checks none | `customworkflow10` (check, vendor bill, vendor credit) | refused |
| 1677 | plus checks Full | same | **exported** |
| 1677 | nothing for the record | `customworkflow_erp_support_contract_defa` (custom record, no permission required) | **exported** |
| 1678 | SDF, login, Customers Full; no Workflow, no customization permissions | customer workflow | refused: "You need the 'Workflow' permission" |
| 1678 | plus `ADMI_WORKFLOW` Full | customer workflow | **exported** |

The rule: a workflow exports through SDF with `ADMI_APP_DEPLOYMENT` Full (plus the login permissions),
`ADMI_WORKFLOW` Full, and Full on every record type the workflow runs on. A custom record type that needs
no permission counts as Full for everyone. Edit is never enough, and the customization permissions
(custom fields, lists, records, SuiteScript) are not needed even when the workflow sets custom fields.
Not tested: a custom record type whose access comes from a line on the role or from Custom Record
Entries; presumably that line at Full.

Both test certificates were revoked and the test logins removed from Jon's Mac. Roles 1677 and 1678 are
still on employee 242090: take them off the employee and delete both roles in the UI.

## Workflow states (2026-11-01)

**The UI workflow list hides workflows from a limited role.** Logged in as role 1677 (Workflow Full,
Customers, Invoices, Bills, Bill Credits and Checks Full, Projects View), Customization > Workflow >
Workflows showed 18 of the account's 61 active workflows. Hidden: every workflow on a record type the
role lacks, Project Defaults (Projects at View), and also CP ES | Invoice Approval and CP ES | Invoice
Defaults although Invoices is Full. Those two test the Subsidiary field; the visible invoice workflows do
not. The role has all subsidiaries, so why the list hides those two is not settled.

**Opening a workflow needs Full on its record type, as exporting does.** Opened by URL
(`/app/common/workflow/setup/nextgen/workflowdesktop.nl?id=<id>`) as role 1677: CPES | Client Defaults
(Customers Full) and CP ES | Invoice Approval (Invoices Full, hidden from the list) both opened; Project
Defaults (Projects View) and ERP Case | Initial Case Assignment (no Case permission) showed "You do not
have privileges to view this page". Edit on the record type was not tested. A browser login with the
read-only role therefore cannot show workflow definitions; only an administrator login can.

**A search reads each record's workflow state.** The `workflow` join on a record search returns the
workflows running on each record and their current state, and the `workflowhistory` join returns the
workflows a record has been through:

```json
{"run": true, "type": "invoice", "pageSize": 5,
 "filterExpression": [["mainline", "is", "T"], "AND", ["workflow.workflow", "anyof", "248"]],
 "columns": [{"name": "tranid"}, {"name": "workflow", "join": "workflow"},
             {"name": "currentstate", "join": "workflow"}]}
```

Run as admin through `cp_saved_search_rl` (POST, ad-hoc run). Columns that work: `workflow`,
`currentstate` and `status` (not groupable) on the `workflow` join; `workflow`, `state` and
`dateenteredstate` on the `workflowhistory` join.

**The joins only see a workflow that is still running on the record or that keeps its history.**
ERP Case | Initial Case Assignment (247) runs on create, finishes, and keeps history "Only When Testing";
released, it leaves nothing, so neither join returns a single case for it although SB2 has 456 cases.
Of the eight case workflows, only Case Buttons (144) shows up: 6 cases still in its Start state, with
history through Not Assigned and Start.

The read-only role can run both joins: in United Capital, role 1535 (`unitedcapital-ai`) returned 319
customers on "Set Churn Date on Customer Record" through the `workflow` join, and the `workflowhistory`
join ran without error. The triage agent's guard allows this ad-hoc run (POST with `"run": true`) from
2026-11-01 on the case-triage-agent `feature/sdf-read` branch.
