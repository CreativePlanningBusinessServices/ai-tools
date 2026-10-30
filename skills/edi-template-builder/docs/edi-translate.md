# `edi_translate` — translating outbound templates

`mcp__claude_ai_EDI_Cosmos_DB__edi_translate` (EDI Cosmos DB connector) sends a template and member data to the deployed translation function (`func-edi-editester`) and returns the generated file. It is the same serializer the pipeline runs, so it handles X12 (`0.0.1`) and XML (`xml_0.0.1`) templates. Outbound only — inbound 360 templates still use `editester deserialize` ([inbound-360.md](inbound-360.md)).

## Inputs

Pass exactly one of `jobId`, `data` or `dataGzip`, and at most one of `templateContent` or `templateContentGzip`.

| input | when | notes |
|---|---|---|
| `dataGzip` | iterating on a sample (preferred) | the members array gzipped and base64-encoded — see [Gzipped inputs](#gzipped-inputs) |
| `data` | a few tiny synthetic records | JSON array of member records (bare records, not the `{ "data": [...] }` wrapper) |
| `organizationId` + `jobId` | full feed, or replaying a run | the server reads that job's complete extracted data — **raw, not anonymized** |
| `templateContentGzip` | always with `data`/`dataGzip`; with `jobId` to test your local edits (preferred) | the template file gzipped and base64-encoded; omit it with `jobId` to use the job's own `translationTemplateURL` |
| `templateContent` | instead of `templateContentGzip` | the template file's full text as a string; about 9 times more characters than the gzipped form |
| `today` | optional | ISO date-time for `__TODAY` and date helpers that take it. Default: the job's `dateCreated`, else the start of the current UTC day |
| `referenceIdentifier` | optional | the document number (ISA13 / ST02 control numbers). Default: the job's `documentNumber`, else `"1"` |
| `offset`, `max_chars` | paging | leave `max_chars` at its 50,000 default: bigger pages can exceed Claude's tool-output limit |

## Gzipped inputs

`templateContentGzip` and `dataGzip` carry the same JSON as `templateContent` and `data`, gzipped and then base64-encoded:

```bash
gzip -c <working-dir>/<provider>-template.json | base64   # templateContentGzip
gzip -c <working-dir>/sample.json | base64                # dataGzip; the file must hold a bare array
```

Paste the output into the call unchanged. Line breaks in it are fine, since GNU `base64` wraps at 76 characters and macOS `base64` doesn't wrap. The server checks the base64 and the gzip checksum before translating, so a value damaged in copying fails with an error rather than translating something else. If you hit one of those errors, re-run the command and paste again.

`mcp__claude_ai_EDI_Cosmos_DB__edi_upload_schedule_template` takes `templateContentGzip` too.

If the tool definition you see doesn't list these inputs, the connector is showing a cached schema. Pass them anyway: the server accepts them.

## Dates

`{{dateFormat 'yyMMdd'}}` with **no** date argument renders the wall clock at translation time, not `today`. Two runs of the same input differ in those fields (typically ISA/GS/BGN dates and times, or an XML `DateTime`) and nowhere else.

## Output

Two content blocks:
1. A header: `Translated output: 56,542 characters (complete). today=…, referenceIdentifier=2, template=<url or inline>`.
2. The output text, verbatim.

When the output is longer than `max_chars`, the header reads `characters 0–50,000 of 213,577 (TRUNCATED — call again with offset=50000 and the same inputs)`. Call again with that `offset` and append each part in order until a header says `(end of output)`. Each page translates the whole input again, so keep every input the same between pages.

## Errors

| message | meaning |
|---|---|
| `Template error at rules[0].children[1]: Element 'BirthDate' failed to render: …` | an expression in that rule failed — fix the rule |
| `Translation function returned 422: Template does not match its schema: …` | the template JSON breaks its `$schema` |
| `Invalid JSON in translation template…` | `templateContent` (or the decompressed `templateContentGzip`) isn't valid JSON |
| `templateContentGzip is not valid base64…` / `dataGzip is not valid base64…` | the value isn't the `base64` output — re-encode and paste it again |
| `… is not valid gzip data (unexpected end of file)…` / `(incorrect data check)` | the value was cut short or changed in copying — re-encode and paste it again |
| `dataGzip does not contain valid JSON.` / `dataGzip must contain a JSON array of member objects.` | the encoded file isn't a bare array of records (unwrap `{ "data": [...] }` with `jq '.data'`) |
| `Pass exactly one of jobId, data or dataGzip.` / `Pass templateContent or templateContentGzip, not both.` | conflicting inputs |
| `Job … is inbound…` | use `editester deserialize` for 360 templates |
| `Job data not found: …` | the job has no extracted data (it failed before extraction finished) |
| `Translation ran out of time…` / `no response within …` | the translation took longer than the 110 s limit; translate a smaller sample, or retry |
| `Translation is not configured: …` | a server setting is missing — tell Jon |
