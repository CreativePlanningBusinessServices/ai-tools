# Carrier conventions

## Contents

- Surency
  - Status Effective Date for terminated employees = termination date + 1 day
  - Gender accepts only `M`, `F`, or blank
  - HSA plan code is the literal `HSA`
  - Contribution (CT) file — CDEX format rules
- Transamerica Retirement Solutions
  - Each client needs two templates: a Base file and a 180 / Payroll file
  - Format: CSV, two rules
  - Columns are per-client — pull from that client's spec workbook
  - Account Number
  - Field mappings confirmed against the spec
  - 180 / Payroll: contribution field conventions
  - Inbound 360 (carrier change file → UKG Ready)

Carrier-specific rules the team has confirmed apply to **every** template for a
given carrier, regardless of which client the feed is for. Apply the matching
carrier's section during both the **build flow** (while authoring) and the
**revision flow** (while applying feedback) — honor these even when the current
vendor feedback doesn't explicitly mention them.

Only carrier-wide rules belong here. Client-specific quirks — one employer's
plan start date, payroll frequency, division name, employer code — do **not**;
those stay with the individual template or its `[TODO]` placeholders.

When a rule is already baked into a carrier's seed template in `templates/`,
this doc still records it so reviewers know it is intentional and so the rule
survives if a future template is built without that seed.

---

## Surency

Carrier admin code: `SUR`. Seed template: [`templates/surency-pt.json`](../templates/surency-pt.json).

### Status Effective Date for terminated employees = termination date + 1 day

When an employee terminates, Surency expects the `Terminated` status to take
effect the **day after** the termination date, not on the termination date
itself. In the participant (PT) template, the `Status Effective Date` element:

```handlebars
{{#if _PARENT.[Member Termination Date]}}{{dateFormat 'MMddyyyy' (getDate 'start' 'next' 'day' _PARENT.[Member Termination Date]) 'MM/dd/yyyy'}}{{else}}{{#if _PARENT.[Member Rehire Date]}}{{dateFormat 'MMddyyyy' _PARENT.[Member Rehire Date]}}{{else}}{{dateFormat 'MMddyyyy' _PARENT.[Member Hire Date]}}{{/if}}{{/if}}
```

`getDate 'start' 'next' 'day'` returns the start of the next calendar day (term
date + 1) as `MM/dd/yyyy`; the surrounding `dateFormat` re-parses that into the
carrier's `MMddyyyy`. The active-employee branch is unchanged — rehire date if
present, otherwise hire date.

### Gender accepts only `M`, `F`, or blank

Surency rejects any other gender code (e.g. `U`, `X`). Map anything that isn't
`M` or `F` to blank — never pass a value through unmapped.

### HSA plan code is the literal `HSA`

In the enrollment (EN) template, the HSA plan code element sends `HSA`, not the
benefit-plan name (e.g. not `Health Savings Accounts`). The same codes apply on
CT records: valid Plan Name values are exactly `FSA`, `FSA-DEP`, `HSA`.

### Contribution (CT) file — CDEX format rules

Validated against the "CDEx - Surency Flex" spec (file version 3.5, CT record
version 2.0). These contradict patterns seen in generated CT bases — check all
of them when reviewing a Surency CT template:

- **Amounts must include an explicit decimal point** — spec: "Decimals are not
  assumed and must be populated" (`99999999.99`). Use `numberFormat 'dot' 2`,
  **never** `'nodot'`. No thousands separators (`'dot'` does not emit them).
  `numberFormat` renders zero as an empty string, so wrap with
  `{{#if amt}}{{numberFormat 'dot' 2 amt}}{{else}}0.00{{/if}}` when explicit
  zeros are wanted.
- **Two CT records per deduction code** — one `Payroll Deduction` line using
  `[Employee Amount]` and one `Employer Contribution` line using
  `[Employer Amount]`. Watch for copy-paste bases that pull `Employee Amount`
  on both lines.
- **FF Record Count excludes the FH and FF records themselves** — it counts
  only the records between header and footer. `{{_segment_count}}` includes
  both; use `{{sub _segment_count 2}}`.
- **HSA restrictions** — Amount Type can only be `Actual` (never `YTD`), and
  negative amounts are rejected for HSA plans (allowed for other plans, e.g.
  `-38.00` on FSA).
- **Unused optional trailing fields** (Tax Year, Notes, plan-year dates,
  names, Contribution Label) omit their delimiters entirely — end the record
  after Amount Type.
- **Spec caveat:** no Employer Contribution records should be sent for plans
  Surency configures to fund on the Plan Year Start Date — confirm plan
  funding configuration with the carrier before including ER lines.

---

## Transamerica Retirement Solutions

Carrier admin code: `TRS`. These are **401k retirement feeds, not X12 834**. Seed
templates: [`templates/transamerica-base.json`](../templates/transamerica-base.json)
and [`templates/transamerica-180.json`](../templates/transamerica-180.json).

### Each client needs two templates: a Base file and a 180 / Payroll file

401k feeds split into two files that share the same demographic/identity columns
and differ only in their contribution/date columns:

- **Base file** — one-time, sent at plan inception. Establishes every participant
  and their *historical* data on Transamerica's platform: YTD contributions,
  prior-year figures, eligibility dates, years of service. ~79 columns.
- **180 / Payroll Remittance file** — recurring, sent every payroll run. Carries
  *current-pay-period* data: contribution amounts, hours, current compensation,
  and pay-period start/end/check dates. ~50 columns.

### Format: CSV, two rules

`elementSeparator: ","`, `segmentSeparator: "\n"`, `componentSeparator: "::::::"`,
`repetitionSeparator: "!!!!!!"`. Each template has a `Columns` rule
(`container:false`, no repetition — emits the header row) followed by an
`EmployeeRecord` rule (`container:false`, `repetition: {property:"members",
filter:"1"}` — one row per member).

Do **not** seed from a fixed-width `01/02/99` record-type template. An older
Transamerica template deployed under another client exists in that layout — it is the
**wrong** format for Transamerica. Always seed from the CSV-format Base/180 templates above.

### Columns are per-client — pull from that client's spec workbook

Transamerica issues a "TRS Standard File Layouts" workbook per client (a
`Base Data` sheet and a `Remittance - Payroll Data` sheet). Column lists and
names vary by client and plan (contribution-source names, year references, etc.).
Never copy another client's column list — read the new client's workbook and
match its `Data Element` names literally. Use a prior client's template only as a
structural seed.

### Account Number

The full `QK########` string from the spec's Account Number row, used verbatim
as the `Account Number` element value (e.g. `QK0000000000`).

### Field mappings confirmed against the spec

- **Gender** — CPBC emits `M` / `F` / `U`; Transamerica codes Unknown as `N`.
  Map `U` to `N` (`M→M`, `F→F`, `U→N`) — do not pass `U` through.
- **Marital Status** — CPBC emits `Married` / `Single` / blank; Transamerica wants
  a 1-char code. Emit `{{[Members Marital Status]}}` with `attributes.length`
  `{min:0, max:1}` so it truncates to `M` / `S`.
- **Payroll Frequency** — `Bi-Weekly→26`, `Monthly→12`, `Semi-Monthly→24`,
  `Weekly→52`.

### 180 / Payroll: contribution field conventions

These apply to the `EmployeeRecord` rule in every Transamerica 180/Payroll template.

**Employee Roth contribution amount** — CPBC splits Roth deferrals into two buckets:
`[Roth 401k]` (regular) and `[Roth 401k Catch Up]` (age-50+ catch-up). Both must be
summed. The key name is `Roth 401k`, not `401k Roth`. Use:

```handlebars
{{add [Deductions].[Roth 401k Catch Up].[Employee Amount] [Deductions].[Roth 401k].[Employee Amount]}}
```

**Employer Match contribution amount** — Transamerica expects the combined employer match
from both traditional and Roth 401k sources in a single field. Never leave this blank if
the plan carries an employer match. Use:

```handlebars
{{add [Deductions].[Roth 401k].[Employer Amount] [Deductions].[401k].[Employer Amount]}}
```

**Employee Loan Repayment** — CPBC may carry up to three loan deduction buckets
(`401k Loan`, `401k Loan2`, `401k Loan3`). Key names have **no space** before the digit
(`401k Loan2`, not `401k Loan 2`). When summing three values, nest `add` calls:

```handlebars
{{add (add [Deductions].[401k Loan].[Employee Amount] [Deductions].[401k Loan2].[Employee Amount]) [Deductions].[401k Loan3].[Employee Amount]}}
```

If a client only has one or two loan buckets, the missing buckets render empty and `add`
treats them as 0 — the nested form is still safe to use.

### Inbound 360 (carrier change file → UKG Ready)

A Transamerica **360** is the inbound counterpart to the 180: Transamerica *sends us* a
change-file CSV that we **deserialize** into UKG Ready (deferral %/$, Roth, loan changes).
It is a different feed and a different template schema from the outbound Base/180 above — see
[inbound-360.md](inbound-360.md) for the parser/assembler mechanics.

- **Seed only from a 360 Transamerica template that is deployed on an active schedule.** At
  least one deployed sibling 360 template carries another client's `kind` codes and would never
  match a real file — confirm a seed's `kind` codes against its own client's deduction codes
  before trusting it. (Same trap as the outbound fixed-width warning above: a buggy sibling
  exists.)
- **Parser (0-based CSV indices):** `ssn`=3, `effectiveDate`=4, `contributionCode`=6,
  `deferralPercent`=7, `deferralAmt`=8, `loanPaymentAmount`=11. `skipLines: 1`, comma-delimited,
  `groupBy: ssn`.
- **Carrier `contributionCode` literals** (index 6, what Transamerica writes — gate each deferral
  rule on these): `401K` = pre-tax, `4ROTH` = Roth, `401L` = loan.
- **Map each to the client's own UKG deduction code for `kind`** (pre-tax → 401k code, Roth → Roth
  code, loan → 401k-loan code). These are per-client: one client's are `401K`/`ROTH`/`401K LOAN`;
  another client's may be `401k`/`Roth401k`/`401KLoan`. See [inbound-360.md](inbound-360.md).
