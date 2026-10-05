# CPBC benefit-feed data shape

## Contents

- Top level
- Member-scope fields
- Benefit Plan-scope fields
- Scope rule — `_PARENT` vs direct access
- Financial/payroll feeds (`feedType: financial`)
- Handlebars pathing reminders for this data

The benefit-feed JSON that CPBC produces has a fixed structure. It does not vary by carrier — only the values change. Use this reference instead of inferring the schema from a sample file each run.

After `wrap-data.sh`, editester receives `{ "data": [ ...member objects... ], "today": "<ISO>" }`. The serializer exposes the `data` array to the root template context under the name **`members`** — that is why the outermost `repetition` in a template is `"property": "members"`.

---

## Top level

An array of **member objects**. One object per person (employees and their dependents/beneficiaries are all members; `Subscriber Type` and the `Employee` / `Dependent` / `Beneficiary` flags distinguish them).

---

## Member-scope fields

Every field below lives directly on a member object. Inside a top-level `repetition` over `members`, access them directly: `{{[First Name of Member]}}`.

| Group | Fields | Notes |
|---|---|---|
| Identity | `Reference ID` (number), `Parent Reference ID`, `Employee ID` (string), `First Name of Member`, `Middle Initial of Member`, `Last Name of Member`, `Suffix of Member`, `SSN of Member`, `SSN of Individual` | `SSN of Member` = the subscriber's SSN; `SSN of Individual` = this member's own SSN. |
| Role / relationship | `Relationship Code` (string), `Relationship Code Mapped`, `Subscriber Type` (`"Subscriber"` / `"Non-Subscriber"`), `Employee` (bool), `Primary` (bool), `Emergency` (bool), `Beneficiary` (bool), `Dependent` (bool), `Qualifying Event` | `Relationship Code` values: `Self`, `Spouse`, `Child`, `Parent`, `Sibling`, `Partner`, `Significant Other`, `Other`. |
| Contact | `Insured Party Telephone Number`, `Member Phone Cell`, `Member Phone Work`, `Member Phone Home`, `Member Phone Primary`, `Member Email Address` | Any phone field may be empty string. |
| Address | `Subscribers Address Line 1`, `Subscribers Address Line 2`, `Subscribers City`, `Subscribers State`, `Subscribers Zip Code`, `Subscribers Country Code` | |
| Demographics | `Members Date of Birth`, `Members Gender` (`M` / `F` / `U` / empty), `Members Marital Status` (`Married` / `Single` / empty), `Member Handicapped`, `Member Smoker` (bool), `Member Deceased` (bool), `Student Status` | |
| Employment | `Member Hire Date`, `Member Start Date`, `Member Termination Date`, `Member Rehire Date`, `Member Base Compensation Date`, `Member Employment Status`, `Employee Type`, `Member Paid Hourly` (bool), `Member Pay Frequency`, `Member Pay Annual` (number), `Member Pay Hourly` (number), `Average Hours Worked Weekly` (number), `Hours Past 12 Months` (number) | All dates are strings. Empty string when not applicable (e.g. `Member Termination Date` on an active employee). |
| Nested | `Benefit Plans` (array — see below), `Cost Centers` (object), `YTD` (object), `Employee Fields` (object, present only on some records) | |

### Nested object shapes

```
Cost Centers : { "Location":   { "name", "key", "externalId", "level1", "level2" },
                 "Department": { ...same... },
                 "Class":      { ...same... } }

YTD          : { "YTD Hours Worked": number, "YTD Hours Off": number }

Employee Fields : a denormalized copy of the subscriber's identity / contact /
                  demographic fields (Employee ID, names, DOB, gender, marital
                  status, phones, email, address, smoker, deceased, handicapped).
                  Present on dependent/beneficiary records that point back to an
                  employee. Not present on every member.
```

---

## Benefit Plan-scope fields

Each element of a member's `Benefit Plans` array. Inside a `repetition` or `filter` over `Benefit Plans`, the Handlebars context **is** a Benefit Plan element — access these directly: `{{[Benefit Plan Name]}}`.

| Fields | Notes |
|---|---|
| `Benefit Plan ID` (**number**) | Client-specific. Compare with unquoted numeric literals: `(match [Benefit Plan ID] 123456789)`. |
| `Benefit Plan Name`, `Benefit Plan Provider Name`, `Benefit Plan Policy Number`, `Benefit Type`, `Vendor`, `EOI Provider Name`, `Contact Type` | Strings. |
| `Coverage Name`, `Coverage Amount` (number), `Coverage Units`, `Employee Deduction Amount` (number), `Employer Deduction Amount` (number) | `Coverage Name` includes the literal value `"Waived"` for declined coverage — filter it out. |
| `Member Benefit Begin Date`, `Member Benefit End Date`, `Benefit Plan Effective From`, `Benefit Plan Effective To` | Date strings. |
| `Relationship Code` (string) | **Duplicated from the member.** See the scope rule below. |

---

## Scope rule — `_PARENT` vs direct access

The serializer makes the current iterated object the Handlebars context. Inside a `Benefit Plans` loop, the context is a Benefit Plan element, and `_PARENT` points back to the member.

**Prefer direct access. Only reach for `_PARENT` when the field genuinely does not exist on the current scope.**

- `Relationship Code` **is duplicated onto every Benefit Plan element.** Inside a `Benefit Plans` loop, write `{{[Relationship Code]}}` / `(match [Relationship Code] 'Self')` — **not** `_PARENT.[Relationship Code]`. This is the main trap: it looks like it needs `_PARENT`, but it doesn't.
- `Member Termination Date` (and the other `Member *` employment/identity fields, names, address, demographics) are **member-scope only** — they are NOT copied onto Benefit Plans. To read them inside a `Benefit Plans` loop you **must** use `_PARENT`: `{{dateFormat 'yyyyMMdd' _PARENT.[Member Termination Date]}}`.

Quick test before writing `_PARENT.X`: is `X` in the Benefit Plan-scope table above? If yes, drop the `_PARENT.`. If no, keep it.

---

## Financial/payroll feeds (`feedType: financial`)

Financial feeds (contribution/CT files, 401k remittance, etc.) share the member
identity/employment fields above but differ in shape:

- **No `Benefit Plans` array.** Per-payroll fields instead: `Pay Date`,
  `Payroll Start Date`, `Payroll End Date`, `Payroll Type` (e.g. `Regular`),
  plus `Deductions`, `Employer FEIN`, pay/compensation fields.
- **`Deductions` is an object keyed by UKG deduction *name*, verbatim and
  case-sensitive** (e.g. `125HSA Individual`, `Flexible Spending`, `Roth 401k`).
  Verify keys with `ukgready_get_deduction_codes` — it's the deduction **name**,
  not the shorter `code`. A wrong key renders silently blank.
- Each deduction value is `{ "Employee Amount": number, "Employer Amount":
  number, "Rate": number }`. Entries can exist with all-zero amounts — gate on
  presence (`{{#if [Deductions].[X]}}`) vs amount (`{{#if [Deductions].[X].[Employee Amount]}}`)
  deliberately.
- **Scope trap:** record rules usually sit directly in the `members` loop, so
  member fields (`SSN of Individual`, `Pay Date`, …) are accessed **directly**.
  `_PARENT` points at the root wrapper there and renders empty — templates
  adapted from benefit-feed (PT/EN) templates often carry `_PARENT.[SSN …]`
  over incorrectly.
- A member can appear in multiple records (one per payroll), and the same
  person can carry two related deduction codes on one check (e.g. HSA
  Individual + HSA Family after a mid-year tier change).

---

## Handlebars pathing reminders for this data

- **Field names contain spaces** — always bracket them: `{{[First Name of Member]}}`, `{{[Benefit Plan ID]}}`. A bare `{{First Name of Member}}` is parsed as a helper call with arguments and will not resolve.
- **Numeric fields are numbers**, not strings (`Benefit Plan ID`, `Coverage Amount`, `Reference ID`, the pay/hours fields). Compare them with unquoted numeric literals and do not wrap them in `numberFormat` to stringify them.
- `__TODAY` and the `today`/`yesterday`/`lastweek` keywords in `dateCompare` are the supported "now" references — see [handlebars-helpers.md](handlebars-helpers.md).
