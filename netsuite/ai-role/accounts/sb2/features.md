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

Accepted by: ____
