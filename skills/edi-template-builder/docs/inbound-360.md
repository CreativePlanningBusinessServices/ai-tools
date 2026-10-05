# Inbound 360 feeds (carrier change file → UKG Ready)

A **360 / inbound** feed is the reverse of everything else in this skill. The carrier *sends us* a CSV "change file" (deferral %/$ changes, Roth, loans, hardship, eligibility, ACA, address — keyed by Plan ID + SSN). We parse it and land the changes in UKG Ready. There is **no Handlebars, no X12 segments, no envelope**. Use `editester deserialize`, not `serialize`.

## Template shape (`inboundtemplate.json`)

Two sections — `parser` then `assembler`:

```json
{
  "$schema": ".../schema-files/inboundtemplate.json",
  "parser": {
    "kind": "csv", "skipLines": 0, "delimiter": ",", "trim": true,
    "fields": [ { "name": "ssn", "index": 1 }, { "name": "401kpercent", "index": 4 } ]
  },
  "assembler": {
    "groupBy": "ssn",
    "rules": [
      { "take": { "sequence": "last" }, "mergeInto": { "path": "ssn", "operation": "set", "output": "ssn" } },
      { "when": { "and": [ { "field": "401kpercent", "notequals": "0.0000" }, { "field": "401kpercent", "notequals": "" } ] },
        "mergeInto": { "path": "deferrals", "operation": "push",
          "output": { "kind": { "_value": "401k" }, "earningsList": { "_value": "Retirement Eligible Earnings" }, "percent": "401kpercent" } } }
    ]
  }
}
```

- **`parser.fields`** map CSV columns **by 0-based index**. Spec "field N" = index **N−1**. Only list the columns you use.
- **`assembler.groupBy`** collapses multiple CSV rows for the same key (usually `ssn`) into one member.
- **Rules** apply in order to build the member:
  - `take.sequence: first|last` → pull a value from the first/last grouped row.
  - `when` (`and`/`or` of `equals`/`notequals`) → conditional gate. **String comparison, not numeric** (see gotcha below).
  - `mergeInto.operation: set` → set a scalar/nested path (`demographic.addr1`).
  - `mergeInto.operation: push` → append to an array path (`deferrals`).
  - `output` is a field name (`"401kpercent"`) to copy a parsed value, or an object; `{ "_value": "401k" }` hardcodes a literal.
  - `transform`: `dateFormat` ({inFormat,outFormat}) or `percentFormat` ({inFormat: percent|decimal}).

## `kind` = the target client's UKG deduction code

`mergeInto.output.kind` is **not** a fixed enum and **not** the deduction's display name — the converter maps `kind` → the deferral `code` field that UKG Ready matches against, so it must equal the **target client's** deduction *code* from `ukgready_get_deduction_codes` (e.g. code `Roth401k`, whose *name* is `Roth 401k` with a space). A wrong value lands nothing — the deferral silently fails to apply, exactly like a mistyped outbound `Deductions` key.

**Re-map every `kind` when seeding from a sibling.** A seed carries the *seed client's* codes; copying them verbatim is a silent, common bug. Confirmed: two deployed 360 templates each use their own client's codes (`401K`/`ROTH`/`401K LOAN` and `401k`/`Roth401k`), while a third was seeded from the first, kept its codes, and is broken for its own client. Always pull the new client's codes and re-map pre-tax / Roth / loan to that client's 401k / Roth / 401k-loan code.

## The fixed-record-model gotcha (most important)

The assembler/converter is **hardcoded** — it is NOT a generic key-value writer. The member is pre-initialized as exactly:

```
{ ssn, effectiveDate, demographic: {}, deferrals: [] }
```

and the converter emits **only two record types**: deferral records (from `deferrals[]` → `{ssn, effectiveDate, code, percent|amount}`) and demographic records (from `demographic.*` → `{ssn, addr1..zip}`, emitted only when `demographic.city` is set).

Consequences:
- **`push` to any other array** (`loans`, `deductions`, …) → hard error `can not push to non array member property '<name>'`.
- **`set` to an unknown scalar path** (`eligibilityDate`, …) is accepted by the assembler but **silently dropped by the converter** — no output record.
- A member that assembles to ssn+effectiveDate only (no deferral/demographic) is dropped entirely.

So **loans (change-file fields ~11–17), eligibility date, hardship suspension, ACA** cannot be added at the template level. They require a code change to editester itself (`assembler.ts` `createMember()` + `converter.ts` + the `UploadRecord` union in `types.ts`, in the `azr-ca-edi-translation` repo) **and** a downstream UKG import path that accepts those record types. Flag this to Kelly rather than authoring rules that error or vanish.

## String-comparison guard gotcha (zero-filler leak)

`when … notequals` compares **literal strings**, so a guard value must byte-match the carrier's exact decimal format. In EPIC change files each row carries one real value and zero-fills the other column; percents are formatted `0.0000` (4dp) and dollar amounts `0.00` (2dp). A percent guard of `notequals "0.00"` therefore **fails to filter** `"0.0000"` (`"0.0000" != "0.00"` is true), leaking a junk `percent: 0` deferral that would zero the employee's deferral. Guard percent rules with `notequals "0.0000"`; guard amount rules with `notequals "0.00"`.

## Validate with `editester deserialize`

`scripts/editester.sh` (same binary, `EDITESTER_ALLOW_NETWORK=1`). `--input` takes the raw change-file CSV path directly — no `wrap-data.sh`, no `--data`. Inspect each stage:

```bash
EDITESTER_ALLOW_NETWORK=1 $CLAUDE_PLUGIN_ROOT/scripts/editester.sh deserialize \
  --template <tpl>.json --input <changefile>.csv --only-parse      # parsed rows
# --only-assemble  → grouped members (before converter)
# (no flag)        → final UploadRecord[] (what lands in UKG)
```

Validate every branch: confirm real %/$ changes survive, zero-filler is dropped, addresses come through, and **no spurious `percent: 0` records** remain. If the live data doesn't exercise a branch, clone a row with `jq` to synthesize it.

**No job data when the schedule has never run.** Inbound `mcp__claude_ai_EDI_Cosmos_DB__edi_list_jobs` is often empty (status `testing`, `lastRun: ""`), so there's no `mcp__claude_ai_EDI_Blob_Storage__edi_get_job_data`. Validate against the **sample change-file CSV** the carrier/Kelly provided instead. Note the sample may carry another client's Plan ID — the assembler usually ignores `planid`, so it still validates the logic.

## Deploy & run

All three tools below are on the `mcp__claude_ai_EDI_Cosmos_DB__` server and take `organizationId`.

- `mcp__claude_ai_EDI_Cosmos_DB__edi_upload_schedule_template` uploads to `<shortname>/<name>.json` **and repoints the schedule's `translationTemplateURL`**. Uploading to an existing path overwrites — check you're not clobbering a different deployed template.
- **`mcp__claude_ai_EDI_Cosmos_DB__edi_start_job`** runs **translation-only** (always `doNotSendToProvider`) and never uploads to UKG — safe for testing.
- **`mcp__claude_ai_EDI_Cosmos_DB__edi_rerun_job` stage `upload` ACTUALLY UPLOADS to UKG Ready** (inbound's "send" stage). Use `stage: translation` to re-test safely; never `upload` unless you intend to write to UKG.
- Inbound jobs fetch `<filenameTemplate>` from the SFTP and **fail at file-retrieval** (`... does not exist`) if the carrier hasn't dropped that exact file yet. That's a missing-file issue, not a template bug — the filename filter is date-stamped (e.g. `ABC{{dateFormat 'MMddyyyy'}}change.csv`), so the sample's name/date usually won't match a live run.
