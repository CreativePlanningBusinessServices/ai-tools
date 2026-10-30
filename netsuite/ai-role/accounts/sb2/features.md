# SB2 (Creative Planning sandbox 2, account 6967599_SB2)

First tailored account. Role: `customrole_cp_ai_readonly`, deployed 2026-10-30.

Transaction types in use (`SELECT type, COUNT(*) FROM transaction GROUP BY type`): CustInvc, CustPymt,
VendPymt, Journal, VendBill, Deposit, CashSale, ExpRept, Check, VendCred, CustCred, Transfer, CashRfnd,
Opprtnty, CustRfnd, DepAppl, CustDep, SalesOrd, RtnAuth, CardChrg.

Added on top of the baseline (all View):

| Permission | Why |
|---|---|
| `TRAN_CUSTCRED`, `TRAN_VENDCRED` | Credit memos and vendor credits are in use (348 and 410) |
| `TRAN_CASHSALE`, `TRAN_CASHRFND`, `TRAN_CUSTRFND` | Cash sales (31k), cash refunds and customer refunds are in use |
| `TRAN_OPPRTNTY` | Opportunities are in use (15); the ERP flow links them to contracts and projects |
| `TRAN_EXPREPT` | Expense reports are in use (16k) |
| `LIST_JOB`, `LIST_PROJECTTASK` | Projects and project tasks back the ERP support cases |

Deliberately not added although used: `Deposit`, `Check`, `Transfer`, `CardChrg` (bank and payment
instruments).

Baseline entries moved out or changed (see `../../ONBOARDING.md`, "What validation taught us"):
`TRAN_PURCHORD` is absent because SB2 has no purchase orders and NetSuite drops it silently;
`ADMI_WORKFLOW` is absent because it accepts only Full; `LIST_OTHER_ADDRESS` (Full) is listed because
NetSuite adds it on its own, and a re-import shows it.
