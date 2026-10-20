---
name: edi-template-builder
description: Build and revise EDI benefits-feed templates (X12 834 enrollment, etc.) for insurance carriers. Use when the user mentions an EDI template, a benefits feed, provider spec ingestion, an 834 transaction set, a carrier-specific template, or vendor feedback on an existing template. Handles the full loop — gather spec, scan unique values, author or revise the template JSON, translate it, validate against the spec, iterate.
---

# EDI Benefits Template Builder

You build and revise EDI benefits-feed templates that drive the EDI translation engine (the serializer the pipeline runs). A template is a JSON file (schema in [docs/template-structure.md](docs/template-structure.md)) that uses Handlebars expressions to map benefit-feed JSON records into X12 EDI segments.

## Hard rules

1. **For large feeds, inspect with `jq`/`grep` via Bash, not `Read`.** The `Read` tool has a ~256KB cap; production benefit feeds are commonly 500KB–1MB. Use `Read` only on small templates and short text files. For benefit-feed records use:
   ```bash
   jq '.data[] | .["Benefit Plans"][] | select(.["Benefit Plan ID"] == 123456789)' <working-dir>/<job_id>.json
   ```
   Job data saved from `edi_get_job_data` wraps the records in `data`; for a user-supplied file that is a bare array, start with `.[]` instead.
   The `cpbc-unique` script (Step 4 of the build flow) gives you the broad orientation; targeted `jq` queries cover the rest.
2. **All scripts live inside this skill folder** (and the `editester` binary, which is only used for inbound 360 templates). Resolve them by absolute path from the **skill base directory** printed when the skill loads (e.g. `~/.claude/skills/edi-template-builder`). `$CLAUDE_PLUGIN_ROOT` points there too *when it is set*, but it is empty for skills installed under `~/.claude/skills/` rather than as a packaged plugin — so wherever this doc writes `$CLAUDE_PLUGIN_ROOT/...`, substitute the skill base directory if the variable is empty. Do not assume anything is on `PATH` except `jq` and `curl`.
3. **Outbound templates are translated with `mcp__claude_ai_EDI_Cosmos_DB__edi_translate`, never the local `editester serialize`.** The tool runs the deployed translation function — the engine the pipeline uses — so its output is what the pipeline will produce. The bundled CLI is out of date: it rejects the production XML (`xml_0.0.1`) template schema. How to call it is in Build flow [Step 7](#7-translate) and [docs/edi-translate.md](docs/edi-translate.md).
4. **Output goes alongside the input file by default**, not into the skill folder. The skill is read-mostly — write template JSONs and `output.edi` files into the user's working directory (or whatever path they specify).

## House style for templates

Three conventions to apply when authoring or revising a template — all three reflect corrections the team has made to generated templates:

1. **No fallback defaults on enumerated mappings.** When mapping a coded value (relationship code → X12 code, plan ID → insurance line code), do not add a catch-all `{{else}}SOMECODE{{/if}}`. Omit the final branch so an unmapped value renders empty and fails loudly during spec validation, instead of silently emitting a wrong code.
2. **No empty `{{else}}{{/if}}`.** If the else branch renders nothing, drop it: write `{{#if x}}val{{/if}}`, not `{{#if x}}val{{else}}{{/if}}`.
3. **Match the carrier spec's field names literally in element `name` keys.** Preserve underscores, capitalization, and word-boundary punctuation exactly as the spec writes them. The `name` field is purely a human cross-reference — the carrier parses pipe positions, not names — but mismatched names (template says `CDD_Employment Status`, spec says `CDD_EmploymentStatus`) cost real time during feedback review by forcing fuzzy matching between Kelly's bullet list and the template.

For field-access conventions — numeric literals vs `numberFormat`, `_PARENT` vs direct scope access, bracketing field names with spaces — see [docs/cpbc-data-shape.md](docs/cpbc-data-shape.md). Read it before writing any Handlebars expressions.

## Mode detection

The first thing you do is decide which flow this is:

**First, is this an inbound (360) feed?** Everything else in this skill is for **outbound** templates (Handlebars → X12/CSV/XML, translated with `mcp__claude_ai_EDI_Cosmos_DB__edi_translate`). A **360 / inbound** feed is the reverse — the carrier *sends us* a "change file" CSV that we parse into UKG Ready via `editester deserialize`. It uses a completely different template schema (`parser` + `assembler`, no Handlebars, no segments).

**The schedule's `direction` field is authoritative — check it before committing to a flow.** If the client has a CPBC account, pull the schedule first (Build flow Step 2) and read its `direction`/`feedType`. Treat it as inbound when the schedule has `direction: "inbound"`, the template `$schema` ends in `inboundtemplate.json`, or (no schedule yet) the spec describes a file the carrier sends *to us* (e.g. a deferral/loan "Daily Change File"). **A task labeled "Retirement (360)" is NOT automatically inbound** — retirement feeds are commonly *outbound* contribution CSVs with `direction: "outbound"`, `feedType: "financial"` (e.g. CPTPA), where comments like "report Plan ID X" / "two Match contributions" describe an outbound file we send. So when the task says "360" but a schedule exists, confirm against the schedule's `direction` rather than the task's Plan Type label. If it really is inbound, **stop and read [docs/inbound-360.md](docs/inbound-360.md)** — the build/revision steps below do not apply.

Otherwise (outbound), decide which flow this is:

- **Revision flow** — the user supplied (a) an existing template JSON path and (b) vendor feedback (pasted in chat, or referenced by ClickUp task ID). Go to **Revision flow** below.
- **Build flow** — anything else. Go to **Build flow** below.

If you can't tell, ask once with a short question.

## Build flow

### 1. Create the working folder

Before downloading anything, create a dedicated folder in the user's working directory:

```
<Client Name> - <Provider> - <Feed Type>/
```

For example: `Example Dental Group - EPIC - Benefit` or `Example Design Co - EPIC - Financial`. Use the client's full display name (not the shortname), the provider name, and the feed type (`Benefit`, `Financial`, `Cobra`, etc.). All files for this feed — spec docs, reference template, new template, job data, and output — go in this folder.

### 2. Gather inputs and download spec files

Required: a provider name, a provider spec (PDF / pasted text / a ClickUp link), and a sample data file (`.json`).

If the user gave a ClickUp task ID (e.g. "task 86abc123"), read it with `clickup-cli` (see the `clickup-cli` skill). Save the task JSON once and `jq` out only what you need, to keep your context small:
- `clickup-cli task get <id> --markdown > /tmp/task-<id>.json`, then `jq -r '.markdown_description // .description' /tmp/task-<id>.json` for the description.
- `clickup-cli comment list --task <id> --all | jq '.items[] | {id, user: .user.username, comment_text, reply_count}'` for the comment thread (newest first; with `--all` the comments are under `.items`, without it under `.comments`).
- `clickup-cli comment replies <comment-id>` for any comment with `reply_count > 0`.
- **For task-level file attachments (specs, schedules, etc.) — pull them yourself, don't ask the user to download:**
  1. `jq '.attachments | map({title, extension, url})' /tmp/task-<id>.json` to list every attachment. (Use this rather than `clickup-cli task attachments`, which returned 404 on EDI workspace tasks.)
  2. `curl -sfL -o /tmp/<basename> <url>` to download each one you need.
  4. For `.docx` specs, convert to text with `$CLAUDE_PLUGIN_ROOT/scripts/docx-to-text.sh /tmp/<spec>.docx > /tmp/<spec>.txt`, then read that. For `.xlsx` spec workbooks (e.g. carrier file-layout workbooks), dump them with `$CLAUDE_PLUGIN_ROOT/scripts/xlsx-to-text.sh /tmp/<spec>.xlsx > /tmp/<spec>.txt`, then read that — it walks every sheet and needs no third-party packages. `.pdf` specs can be passed directly to `Read`.

**If the client has a CPBC account (UKG company shortname available)**, use the EDI Cosmos DB MCP to locate the organization, schedule, and job data — don't ask the user to find these manually:

1. **Organization** — `mcp__claude_ai_EDI_Cosmos_DB__edi_list_organizations` with the `shortname` filter (e.g. `KPAY12345678`). Note the organization `id` — every later Cosmos call takes it as `organizationId`.
2. **Schedule** — `mcp__claude_ai_EDI_Cosmos_DB__edi_list_schedules` with `organizationId`. Note the schedule `id` and current `translationTemplateURL`.
3. **Latest job** — `mcp__claude_ai_EDI_Cosmos_DB__edi_list_jobs` with `organizationId`, `scheduleId`, and `limit: 1` (results are sorted newest first). Note the job `id`.
4. **Job data** — `mcp__claude_ai_EDI_Blob_Storage__edi_get_job_data` with `job_id`. The response is the job's records (anonymized), pre-wrapped as `{ "data": [...], "today": "<ISO>" }`. Save it directly to `<working-dir>/<job_id>.json`. You inspect it and build translation samples from it; keep the job `id`, which the full-feed check in Step 7 uses.

If anything required is missing, ask before continuing.

### 3. Read the sample data

Use the job data saved in Step 2, or the local `.json` file the user supplied. Real feeds are usually too large for `Read` — inspect them with `jq` (hard rule 1).

### 4. Scan unique values

```bash
$CLAUDE_PLUGIN_ROOT/scripts/cpbc-unique.sh -b <data-path>
```

Read the output. It lists benefit plans, coverage names, relationship codes, genders, marital statuses — every value Claude needs to write `{{#compare}}` / `{{match}}` / `find` expressions correctly.

**For financial/payroll feeds**, `cpbc-unique` produces minimal output (no benefit plans, no relationship codes). Scan the job data directly instead:
```bash
jq '[.data[] | {payrollType: .[\"Payroll Type\"], deductions: (.Deductions // {} | keys)}] | unique' <working-dir>/<job_id>.json
```
The key things to confirm are: which deduction codes are present (e.g. `401k`, `Roth 401k`), what payroll types appear, and what pay frequencies are used.

### 5. Look for a seed template

Look for a seed in this order, and **always save whatever seed you use into the working folder** as `<working-dir>/<name> (reference).json` — per Step 1 the reference template lives alongside the new one, so the user can diff and review it without re-fetching:

1. **The schedule's existing `translationTemplateURL`** (noted in Step 2) is your primary seed — **even when it points at a *different* client's file**. Kelly often pre-creates a new feed's schedule pointing at a sibling client's deployed template as a starting point (e.g. a new CPTPA feed's schedule pointing at `KPAY.../<Sibling Client>-CPTPA.json`). Fetch it with `mcp__claude_ai_EDI_Blob_Storage__edi_get_template_data` (pass the URL directly as `blob_path`) and save the copy. Do this even though you'll repoint the schedule to the new client's path on upload.
2. **A ClickUp comment that names a reference template** (e.g. "Reference <client> EPIC template" / "use THE CPTPA template") — look it up in Cosmos: find the named client's organization via `mcp__claude_ai_EDI_Cosmos_DB__edi_list_organizations`, then `mcp__claude_ai_EDI_Cosmos_DB__edi_list_translation_templates` with its `organizationId`, then `mcp__claude_ai_EDI_Blob_Storage__edi_get_template_data`. Also save any template **attachment** on the task (Step 2) into the working folder.
3. **A local skill template** — glob `$CLAUDE_PLUGIN_ROOT/templates/*.json` and case-insensitively substring-match the provider name against filenames.
4. **No seed anywhere** — scaffold from the structure in [docs/template-structure.md](docs/template-structure.md) (ISA → GS → ST → payload → SE → GE → IEA).

**When a comment names a reference (source 2) and the schedule pointer (source 1) aim at *different* clients, reconcile before seeding — they often disagree, and the comment wins.** Kelly's pre-pointed schedule frequently aims at a different (sometimes buggy or abandoned) sibling than the template she later names in a comment. Resolve the comment-named client by name (`edi_list_organizations` → `edi_list_translation_templates`), confirm it really is that client (the client a comment named once turned out to be a *different* client than the one whose file the schedule pointed at), and seed from the named one. Either way, never trust a sibling seed's enumerated values verbatim — re-validate its code mappings against the carrier spec and the target client's UKG config (deduction codes, plan IDs).

### 6. Author the template

Write the template JSON to `<working-dir>/<provider>-template.json` in the user's working directory.

While writing, refer to:
- [docs/template-structure.md](docs/template-structure.md) for the JSON schema
- [docs/cpbc-data-shape.md](docs/cpbc-data-shape.md) for the benefit-feed schema — member-scope vs Benefit Plan-scope fields, the `_PARENT` scope rule, and field-access conventions
- [docs/handlebars-helpers.md](docs/handlebars-helpers.md) for every available Handlebars helper (dateFormat, compare, dateCompare, match, find, sum, replace, replaceAll, ssnFormat, phoneFormat, numberFormat, getDate, getDayOfMonth, add/sub/mul/div, and/or/not, toUpper/toLower, length)
- [docs/edi-translate.md](docs/edi-translate.md) for the translate tool's inputs, defaults and errors
- [docs/carrier-conventions.md](docs/carrier-conventions.md) — if the provider has a section there, apply its carrier-wide rules even when the spec is silent on them
- The **House style** rules above

Common patterns:
- INS member loop with filter: `{"property": "data", "filter": "{{#compare \"Relationship Code\" '==' 'Self'}}true{{/compare}}"}`
- HD benefit loop nested under member with `_PARENT` access to member fields
- SE close rule using `{{_segment_count}}`
- Length attributes for fixed-width fields: `"attributes": {"length": {"min": 9, "max": 9, "padding": "0", "align": "right"}}`
- **Conditionally emitting a single segment** (e.g. salary `ICM` only on subscribers) → use `ignore`, which is a **render-IF-truthy gate despite the name** — the segment renders only when the expression is non-empty, *not* skipped when truthy. Write the condition for when you want the segment to appear: `"ignore": "{{#compare [Subscriber Type] '==' 'Subscriber'}}{{#if [Member Pay Annual]}}true{{/if}}{{/compare}}"`. To suppress on a condition, invert it. Two traps that waste serialize iterations: (1) the natural reading ("ignore when X") is backwards — see the `ignore` row in [docs/template-structure.md](docs/template-structure.md); (2) `filter` does **not** gate emission — it filters an array property in place and still renders the segment once, so it can't stand in for `ignore`.

### 7. Translate

Translate with `mcp__claude_ai_EDI_Cosmos_DB__edi_translate`. Pass the template as `templateContent`: the **full, unchanged text** of `<working-dir>/<provider>-template.json` (`cat` it). On every run also pass `today` set to the job data's `today`, so dates don't move between iterations. Inputs, defaults and error messages are in [docs/edi-translate.md](docs/edi-translate.md).

**Iterate on a small sample.** Build `<working-dir>/sample.json`: a JSON array of 5–10 records that between them hit the template's branches (a subscriber with dependents, each coverage type, a waived coverage, …). Pick them with `jq`, e.g.
```bash
jq '[.data[0:3][], (.data[3:] | map(select(.["Relationship Code"] != "Self")))[0:2][]]' <working-dir>/<job_id>.json > <working-dir>/sample.json
```
Call `edi_translate` with `data` = the array in `sample.json` and `templateContent`. The result has two content blocks: a header (`Translated output: 4,210 characters (complete). today=…`) and the output verbatim. Write the second block to `<working-dir>/output.edi` (`output.xml` for an XML template) and inspect it with `grep` / `awk` — split X12 into one segment per line first with `tr '~' '\n'`. Synthetic records for branch checks (Step 8) go through the same call: add them to the sample.

**Then translate the full feed once, before delivering.** Call `edi_translate` with `organizationId`, `jobId` (the job from Step 2) and `templateContent`. The server reads that job's complete data itself, so nothing large passes through the conversation on the way in. The output is **real, unanonymized data**, and every page of it lands in the conversation, so don't save it to a file by default — writing a file means typing the whole output out again. Page through it: when the header says `TRUNCATED`, call again with the `offset` it gives and the same inputs until it says `(end of output)`. An error-free run means every record rendered; read the SE, GE and IEA counts from the last page. Content checks belong on the sample.

A `Template error at rules[0].children[2]: …` error names the rule whose expression failed — fix that rule and translate again.

### 8. Validate against the spec

Read the spec. Spot-check each requirement against `output.edi` using `grep` / `awk` to pull specific segments. Look for: required segments present, field positions correct, length/padding/alignment matches the spec, dates formatted as the spec requires, codes mapped per the spec (e.g. relationship → numeric code), envelope counts (SE, GE, IEA) accurate.

**Spot-checking the live output only proves the branches the live data happens to exercise — that is necessary but not sufficient.** Before delivering, enumerate every conditional/computed branch in the template (each `{{#if}}`, each multi-key `add`/`sum`, each enumerated `match`/`find`, each optional field) and confirm each one is actually exercised by a non-trivial value. Watch especially for **summed deduction columns where one addend has zero activity in the sample** (e.g. `add [Deductions].[401K Loan]… [Deductions].[Company Loan]…` when only `Company Loan` has amounts) — the live feed proves `add(0, X) = X` but never the dormant key's path or the real sum, and a misspelled/wrong key renders silently blank. For any branch the live feed doesn't exercise (zero-activity deduction keys, absent term dates, a one-of-N code value no record uses), build synthetic records to verify it: clone a real record with `jq`, inject the triggering value, add it to the sample, translate, and confirm the branch renders the expected output. Note in the delivery summary which branches were checked synthetically rather than against the live feed.

**Then check for the opposite blind spot: spec segments the template omits entirely.** Branch enumeration only validates segments the template already has — it can never surface one that was never authored. Situational/Optional segments are the trap: a Required-driven first pass skips them, the output serializes cleanly without them, and nothing fails until the carrier reviews the file (this is exactly how Principal's `ICM` salary segment shipped missing). So walk the spec's segment list and, for every segment marked **Situational/Optional**, ask: *does the live feed carry data that should populate it?* List the source field(s) per segment (e.g. `ICM` ← `Member Pay Annual`; member phone/email ← contact fields) and confirm each omission is deliberate, not overlooked. Watch for segments that *look* covered because a sibling was implemented — e.g. implementing the salary-effective-date `DTP*303` does **not** mean the salary-amount `ICM` is handled; they are different segments. Flag any genuinely ambiguous "should we send this?" call to Kelly rather than silently omitting.

### 9. Iterate

If validation finds gaps, `Edit` the template JSON, translate the sample again, re-validate. Loop until clean. After three failed iterations, stop and surface what's blocking — don't churn silently.

If the template has been uploaded and a job has run with it, also check the file the pipeline actually wrote — see [Checking a real run's generated file](#checking-a-real-runs-generated-file).

### 10. Deliver

Print:
- Final template JSON path
- A ~50-line excerpt of `output.edi`
- A short summary: provider, transaction set, key segments produced, filters applied (e.g. "skips Waived coverages, excludes terminated employees by date"), any open `[TODO]` values that need real sender/receiver IDs.
- A plain-English decode of every Benefit Plan ID list in the template — follow the **ID list reference** section below. Always include this for a freshly generated template.

## Revision flow

### 1. Collect feedback

If the user gave a ClickUp task ID, pull task description + comments + threaded replies (same MCP tools as the build flow). Otherwise use whatever the user pasted into chat. Concatenate into a single working feedback log.

### 2. Read the existing template

`Read` the user-supplied template path.

### 3. Get sample data

If the user supplied a sample data file, inspect it (with `jq` if it is large — hard rule 1). If you know or can look up the organization and schedule, fetch the latest job's data as in Build flow Step 2 (items 1–4) and keep the job `id` for the full-feed check. If you have neither, proceed without data but warn that you won't be able to re-validate end-to-end after edits.

### 4. Parse feedback into a change list

Produce a numbered list. For each item:
- Segment + element identifier (e.g. "REF*0F element 2")
- Current behavior (cite the line / expression)
- Requested behavior
- Concrete change (which `attributes.length`, which Handlebars helper, which value string)

Show the list to the user. Ask them to confirm before editing. Do not skip this — vendor feedback is often ambiguous and one wrong reading propagates.

### 5. Apply edits

Use `Edit` (not full rewrites). One edit per change item keeps the diff readable. If a change requires modifying multiple segments, make multiple targeted edits. Any new or changed Handlebars must follow the **House style** rules above and the field-access conventions in [docs/cpbc-data-shape.md](docs/cpbc-data-shape.md). If the carrier has a section in [docs/carrier-conventions.md](docs/carrier-conventions.md), make sure the template still honors those rules — and if a feedback item conflicts with a documented carrier-wide rule, flag it to the user rather than silently overriding.

### 6. Translate

Same as Build flow [Step 7](#7-translate): iterate on a small sample, then translate the full feed once by `jobId`. Skip if there is no sample data.

### 7. Validate

Spot-check each feedback item against the new EDI output (e.g. if the feedback was "pad SSN to 9", grep `REF\*0F` and confirm 9 characters).

If a feedback item targets a condition that no record in the sample data exercises (e.g. terminated employees when no test record has a termination date), construct a synthetic record to validate it: clone a real record with `jq`, set the triggering field, add it to the sample, translate, and confirm the changed branch renders correctly. Note in the delivery summary that this branch was checked synthetically rather than against the live feed.

If the revised template has been uploaded and a job has run with it, also check the file the pipeline actually wrote — see [Checking a real run's generated file](#checking-a-real-runs-generated-file).

### 8. Deliver

Print:
- Updated template path
- Diff-style summary: one line per change item, with the segment, what changed, and which helper / attribute now drives it
- A short excerpt of the affected segments from the new `output.edi`
- If the revision added or changed any Benefit Plan ID list, a plain-English decode of the affected list(s) — follow the **ID list reference** section below. If no ID lists were touched, skip this.

## Checking a real run's generated file

Translating your local template proves what that template produces. Once a job has run through translation, read the file the pipeline actually wrote instead of assuming it matches. A safe test run is `mcp__claude_ai_EDI_Cosmos_DB__edi_start_job` (translation-only, always `doNotSendToProvider`) after the template is uploaded with `mcp__claude_ai_EDI_Cosmos_DB__edi_upload_schedule_template`.

1. **Find the job** — `mcp__claude_ai_EDI_Cosmos_DB__edi_list_jobs` (`organizationId`, `scheduleId`, `limit: 1`). It has a generated file only when `generatedFileURL` is non-empty (status stage `translation` or later, name `complete`/`completed`). A job that failed at extraction or translation has none — read its `status.errorMessage` instead.
2. **Fetch the file** — `mcp__claude_ai_EDI_Blob_Storage__edi_get_generated_file` with `job_id_or_url` set to the job's `generatedFileURL` (the job `id` also works for outbound jobs). The result has two content blocks: a header line (`Generated file <name>: 13,577 characters (complete).`) and the file itself, verbatim. Save the second block to `<working-dir>/<job_id>.generated.txt`. It is real, unanonymized data, same as job data.
3. **Page large files** — one call returns at most `max_chars` characters (default 50,000, max 500,000). When the header says `TRUNCATED`, call again with the `offset` it gives and append each part in order until the header says `(end of file)`. Inspect the saved file with `grep` / `awk`, as with `output.edi` — don't pull a large file into context to read it.
4. **Compare like with like** — call `mcp__claude_ai_EDI_Cosmos_DB__edi_translate` with `organizationId` and that job's `jobId` and **no** `templateContent`. It replays the job: the job's data, its `translationTemplateURL`, its `dateCreated` as `today` and its `documentNumber`. Save it (paging as in step 3) to `<working-dir>/<job_id>.replay.txt` and compare one segment per line: `diff <(tr '~' '\n' < <job_id>.generated.txt) <(tr '~' '\n' < <job_id>.replay.txt)`. Expect differences only in wall-clock stamps: every element that uses `{{dateFormat '…'}}` with no date argument renders the time of translation. That is usually ISA/GS/BGN dates and times (an XML `DateTime`), but grep the template for no-argument `dateFormat` — some templates stamp member segments too (e.g. a `DTP*303`). Any other difference is real — most often the template blob was overwritten after the job ran (the replay reads the current blob), so compare the job's template with `edi_get_template_data`. Report it rather than explaining it away.

A `No generated file found` error means the blob does not exist under that name; a `Could not decrypt` error means the tool cannot read that file, which is expected for generated files from early 2025 and older — the error text gives the cause. For inbound (360) jobs the blob names are different — see [docs/inbound-360.md](docs/inbound-360.md).

## ID list reference (include at delivery)

CPBC templates routinely filter, map, or guard segments using bare lists of Benefit Plan IDs (and occasionally other code lists). Those numbers are opaque on their own and make the template hard to validate. Whenever the delivered template contains one or more ID/code lists, hand the user a plain-English decode of them.

1. **Build a decoder table** — every Benefit Plan ID used anywhere in the template, paired with its plan name from the `cpbc-unique` output.
2. **Find every distinct ID list** in the template — in `match` expressions, `repetition`/`filter` expressions, and `ignore` expressions. The same list often appears in more than one place, and near-identical lists (overlapping by one or two IDs) usually mean *different* things — do not assume they are the same concept.
3. **For each distinct list, explain in plain English:**
   - which plans it contains, by name rather than number;
   - the business concept it encodes (e.g. "plans that cover dependents", "life-type plans that carry a face-value amount", "plans bundled with an AD&D rider");
   - what the expression does with it (include/skip a segment, map to an EDI code, etc.);
   - where it matters, why a given plan is in or out of the list.
4. **Group repeats** — if the same list is used in multiple places, say so and explain it once.

Keep it concise: a decoder table plus one short labelled paragraph per distinct list. The goal is that a reviewer can check the template against the provider spec without mentally expanding magic numbers.

## Posting back to ClickUp

Only triggered when the user explicitly asks you to post a comment or attach a file to a task. The default is still "do not send messages on the user's behalf" — see [What you do NOT do](#what-you-do-not-do).

When directed:

1. Confirm the exact comment text with the user first if you drafted it. Post their version verbatim — do not add "Thanks, <name>" or other sign-offs they didn't write.
2. `clickup-cli comment create --task <task-id> --text "<comment>"` (plain text).
3. For each attachment, `clickup-cli task attach <task-id> <path>`. The CLI uploads the file from disk, so file size doesn't cost context.

Attachments via `task attach` attach to the **task**, not inline in a specific comment — they will appear in the task's Files section and be visible to everyone watching the task.

If the comment needs formatting (headings, bullets, bold) or the file must appear **inline in the comment**, use `python3 ~/.claude/scripts/clickup-rich-comment.py <task-id> --body comment.md --attach <file>` instead of steps 2–3: `--text` is rendered by ClickUp as raw markdown (`##`, `**`), and only its rich-text `comment` ops (which the script builds, via clickup-cli) format or embed a file. Verified 2026-09-04.

## What you do NOT do

- Do not edit files in `$CLAUDE_PLUGIN_ROOT` itself (the skill is install-time read-only — except for `bin/` which `ensure-editester.sh` populates).
- Do not translate outbound templates with the local `editester serialize`; use `mcp__claude_ai_EDI_Cosmos_DB__edi_translate`.
- Do not commit anything or push branches on behalf of the user.
- **Do not send messages or post comments on the user's behalf unless they explicitly direct you to post a specific comment in the current turn.** When directed, follow the [Posting back to ClickUp](#posting-back-to-clickup) recipe and post the agreed-upon text verbatim.
- Do not download or install software other than what `ensure-editester.sh` handles (the editester binary, needed only for inbound 360 templates).
