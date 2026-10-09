---
name: cp-saved-search
description: Use when a task needs to run, create, edit, describe or delete a NetSuite saved search in any account where Creative Planning's cp_saved_search_rl RESTlet is installed (CP's own accounts or a client's) — including one-off queries that should NOT be saved (listing a record's attachments, ad-hoc joins), running a search with an extra filter, or building a hyperlink/drill URL that opens a saved search's UI results pre-filtered via searchresults.nl query params (record, class, date-range filters). Covers the cp_saved_search_rl RESTlet's JSON contract, called via netsuite-cli restlet call; the URL-filter rules are generic NetSuite.
---

# Saved searches via the cp_saved_search_rl RESTlet

`cp_saved_search_rl` is a RESTlet Creative Planning installs into NetSuite accounts, CP's own and
clients' (script/deploy ids are the same everywhere): `customscript_cp_saved_search_rl` /
`customdeploy_cp_saved_search_rl`. It creates, edits, describes, runs and deletes saved searches
over a round-trippable JSON definition, and runs one-off searches that are never saved — call it
with `netsuite-cli restlet call`.

## Before the first call in an account

1. **Pick the account.** Every call takes `--account <alias>`, the `netsuite-cli` alias for the
   target account. Never fall back to the CLI's default account: if the user hasn't said which
   account, ask.
2. **Confirm the RESTlet is installed there** (once per account per session):

   ```bash
   netsuite-cli suiteql --account <alias> "SELECT scriptid FROM script WHERE scriptid = 'customscript_cp_saved_search_rl'"
   ```

   - One row: go ahead.
   - No rows: it isn't installed. Don't call the RESTlet; ask the user whether they'd like you
     to install it, following "Installing the RESTlet" below.
   - The query itself errors (unknown alias, auth failure): report that error. It says nothing
     about whether the RESTlet is installed.

**Install or redeploy only after the user says yes for that account.** If the RESTlet is missing,
ask whether they'd like you to install it. If it's there but a call fails because the deployment is
undeployed or not released, report what you found and ask whether to redeploy the package. Either
way, the question to ask and the steps are in "Installing the RESTlet" below. An `{error}` the
RESTlet itself returns, or a permission error on the calling role, isn't an install problem and a
redeploy won't fix it. A request to run or build a search isn't a yes, neither is a "do whatever it
takes" said before the user knew an install was needed, and a yes for one account isn't a yes for
another. Deploying the package is the only change you make to scripts: never edit a script or
deployment record by hand (UI or API), in any account.

This is the go-forward saved-search path here: NetSuite has no native REST API for saved-search
definitions, and the CLI's `saved-search run` command rides SuiteTalk SOAP, which NetSuite is
sunsetting (no new TBA/SOAP integrations after 2027.1; endpoints removed in 2028.2). Prefer this
RESTlet; treat `saved-search run` as a legacy fallback — and once the account is on 2028.2 or
later, as unavailable: use only this RESTlet, and don't suggest new SOAP/TBA setup after 2027.1.

**Saved search vs `suiteql`:** reach for the RESTlet when you want the saved search's own
filters/formulas/columns exactly as the search owner built them, when the data is only exposed
via a saved search, or when you need to create/edit a definition. Otherwise prefer
`netsuite-cli suiteql` — it's easier to iterate on.

## Definition JSON (describe's response shape; also the POST/PUT body shape)

```json
{
  "id": "customsearch_cp_example_invoices",
  "internalId": 1234,
  "title": "Example Invoices",
  "type": "transaction",
  "isPublic": true,
  "filterExpression": [["field", "operator", "value"], "AND", [...]],
  "columns": [{"name": "entity", "join": "...", "summary": "SUM", "formula": "...", "sort": "ASC", "label": "..."}]
}
```

`id` is optional on create (omit to let NetSuite generate one) and, along with `type`, immutable
afterward — describe **omits `id` entirely** (not `null`) for a search with no script id (e.g. a
private UI-created one); target those with `internalId` instead. `title` is always required. Only
`name` is required per column. `filterExpression` is always an array of term-arrays and
`"AND"`/`"OR"`/`"NOT"` strings — **a bare single term must be wrapped**: `[["isinactive","is","F"]]`,
not `["isinactive","is","F"]` (the RESTlet returns a pointed `{error}` if you forget).

## Describe — GET with `id` (script id or numeric internal id), no `run`

```bash
netsuite-cli restlet call --account <alias> --script customscript_cp_saved_search_rl --deploy customdeploy_cp_saved_search_rl \
  --method GET --param id=1234
# → the definition JSON shape above
```

## Run — GET with `run=T` or `run=true` (case-insensitive; any other non-empty value errors)

`pageSize` 5–1000 (default 1000), `pageIndex` 0-based (default 0):

```bash
netsuite-cli restlet call --account <alias> --script customscript_cp_saved_search_rl --deploy customdeploy_cp_saved_search_rl \
  --method GET --param id=1234 --param run=T --param pageSize=5 --param pageIndex=0
# → {"items":[{"<columnKey>":{"value":...,"text":...}, ...}, ...],
#     "count":5,"totalRecords":N,"totalPages":N,"pageIndex":0,"hasMore":true}
```

Both GET variants return a JSON **string** body — NetSuite serializes a RESTlet response off the
*request's* Content-Type, and a bodyless GET sends none. `restlet call` parses it transparently;
a raw HTTP caller must `JSON.parse()` it itself.

### Run-time additional filter (`filter` param)

A run call may add `filter=<JSON filter-expression>` — same format as `filterExpression`,
including a bare term needing the wrap: `[["field","operator","value"]]`. It is ANDed onto the
search's stored criteria **for that run only**; the stored definition is never modified. Both
sides are grouped, so a stored top-level `A OR B` correctly becomes `(A OR B) AND (extra)`:

```bash
netsuite-cli restlet call --account <alias> --script customscript_cp_saved_search_rl --deploy customdeploy_cp_saved_search_rl \
  --method GET --param id=1234 --param run=T \
  --param 'filter=[["trandate","within","thismonth"]]'
```

Rejected with `{error}` (no run happens): `filter` on a describe call (no `run=T`), malformed
JSON, an explicitly empty `[]` (omit the param to run unfiltered), and a bare unwrapped term.

## Ad-hoc run — POST a definition with `"run": true`, nothing is saved

**Default to this for one-off questions.** It returns the same paged result shape as a saved run
but never writes to the account — no `customsearchNNNN` litter, and nothing to clean up
afterwards (deletes are possible now, but not creating the search is better still).

The flag lives in the **body, not the query string**: a RESTlet's `post` handler is passed only
the request body — NetSuite gives query params to `get` and `delete` alone. `pageSize` /
`pageIndex` go in the body too, as JSON numbers or strings.

```bash
netsuite-cli restlet call --account <alias> --script customscript_cp_saved_search_rl --deploy customdeploy_cp_saved_search_rl \
  --method POST --data '{
    "run": true, "type": "job",
    "filterExpression": [["internalid","anyof","5678"]],
    "columns": [{"name":"name","join":"file"},{"name":"filetype","join":"file"},{"name":"url","join":"file"}]
  }'
# → {"items":[...],"count":N,"totalRecords":N,"totalPages":N,"pageIndex":0,"hasMore":false}
```

That example is the **canonical way to list a record's attachments** — there is no REST or
SuiteQL route to them (`/job/{id}/attachments` returns `NONEXISTENT_FIELD`; `entityfile`,
`jobfile` and friends are not valid SuiteQL search types), so a `file` join is the only option.
Oracle's `/rest/v1/projects/{id}/attachments` belongs to **SuiteProjects Pro**, a different
product; it does not exist in NetSuite ERP accounts.

- `run` accepts `true` or `"T"`/`"true"`; `false`/`"F"`/omitted creates and saves as normal.
  Any other value is rejected rather than silently persisting a search you meant to throw away.
- `pageSize`/`pageIndex` are **run-only** — sending either without `run: true` is an error
  (`pageSize is only valid on an ad-hoc run — add "run": true or remove it`), not a silent
  create. Same rule as `filter` on a GET describe.
- `type` is still required. `title` is optional and defaults to `ad-hoc run (not saved)`.
- **`id`, `internalId` and `isPublic` are rejected** — they only mean something once saved. A
  describe output therefore needs those keys stripped before it can be re-run ad-hoc.

## Create — POST the definition

`type` required. **ALWAYS pass an explicit `id`**: `customsearch_cp_<slug>` in CP's own accounts;
in a client's account, the client's naming convention (ask if you don't know it). Omitting it
mints an anonymous `customsearchNNNN`, and the id is unfixable
afterward — it's API-immutable, and the UI's scriptid field on `search.nl?cu=T` *looks*
editable but silently discards the change on save (verified: form redisplays the typed value
while `N/search.load` still resolves only the old id). The only remedy is retitle-old →
recreate-with-proper-id → migrate flags/references → delete the old one (Delete section below),
so get it right at create time. `internalId` is rejected on create — it has no meaning until
the search is saved. Afterwards, give the user the search link (section below):

```bash
netsuite-cli restlet call --account <alias> --script customscript_cp_saved_search_rl --deploy customdeploy_cp_saved_search_rl \
  --method POST --data '{
    "title": "CP Example", "type": "customer", "isPublic": true,
    "filterExpression": [["isinactive", "is", "F"]],
    "columns": [{"name": "entityid", "sort": "ASC"}, {"name": "email"}]
  }'
```

## Update — PUT the full definition (full-definition replace, not a patch)

Target with `id` or `internalId`. `title`, `filterExpression` and `columns` are all **required
keys** on PUT — omitting either array wipes it (send back the array describe gave you, even
unchanged); `isPublic` is the only field that's still optional and preserved when omitted.
Afterwards, give the user the search link (section below):

```bash
netsuite-cli restlet call --account <alias> --script customscript_cp_saved_search_rl --deploy customdeploy_cp_saved_search_rl \
  --method PUT --data '{
    "id": "customsearch_cp_example", "title": "CP Example (renamed)", "type": "customer",
    "filterExpression": [["isinactive", "is", "F"], "AND", ["email", "isnotempty", ""]],
    "columns": [{"name": "entityid", "sort": "DESC"}, {"name": "email", "label": "Mail"}]
  }'
```

Describe output is round-trippable straight into PUT with zero edits — every field describe
returns is one PUT accepts — unless a rare title-lookup failure left describe's `title` null (see
below), in which case supply your own.

## After every create or update — give the user the search link

A POST that saved a search (no `"run": true`) and every PUT return the search's `internalId`.
The message that reports the change to the user includes the search's results link, one per
search created or updated:

```
https://<account-host>.app.netsuite.com/app/common/search/searchresults.nl?searchid=<internalId>
```

`<account-host>` is the alias's `accountId` from `netsuite-cli account list`, lowercased with `_`
replaced by `-`: `1234567` stays `1234567`, `1234567_SB1` becomes `1234567-sb1`. Use the numeric
`internalId`, not the script id. Ad-hoc runs and deletes leave no search to link to.

## Delete — DELETE with `id`, and it MUST carry `--data '{}'`

```bash
netsuite-cli restlet call --account <alias> --script customscript_cp_saved_search_rl --deploy customdeploy_cp_saved_search_rl \
  --method DELETE --param id=customsearch_cp_example --data '{}'
# → {"deleted":true,"internalId":4321,"id":"customsearch_cp_example","title":"CP Example"}
```

**Always pass `--data '{}'`.** Without a request `Content-Type` header NetSuite 500s at the
platform layer *before the script runs at all* — an HTML error page, no `{error}` JSON, and
**nothing in the Script Execution Log**, which is the tell that your code never executed. The
body itself is ignored; it exists only to make the CLI send a JSON content type. Same platform
quirk as `cp_file_cabinet_rl`'s delete — it affects any RESTlet DELETE, not this one.

Like GET, DELETE takes **query params** and returns a JSON **string**. The search is loaded
before it is removed, so an unknown id fails as a plain `{error}` with nothing destroyed, and the
response names what went. **There is no undo and no confirmation prompt** — the RESTlet deletes
whatever the id resolves to, so check with a describe first if the id came from anywhere but your
own hand.

Note NetSuite exposes no other programmatic route: `savedsearch` is not a REST record type
(`record delete savedsearch <id>` → `Record type 'savedSearch' does not exist`), so before this
verb existed the only way to remove one was the UI.

## Title resolution

`N/search.load().title` is null account-wide — a permanent NetSuite platform gap, not staleness.
Describe, POST, and PUT responses all resolve the real title via a
`SELECT name FROM savedsearch WHERE id = ?` SuiteQL lookup layered on top; POST/PUT additionally
fall back to the caller-supplied title if that lookup ever fails, so their `title` is reliable.
Describe has no such fallback — on the rare lookup failure it returns `title: null`, and a caller
PUTing that back must supply its own title like any other required field.

## Limits

`id` and `type` are immutable once created (PUT with a different `type` returns
`{"error": "type cannot be changed — the search's type is <actual>"}`); the only editable fields
are `title`, `filterExpression`, `columns`, and `isPublic` — no scheduling, email alerts, or
audience settings. Verbs are describe / run / ad-hoc run / create / update / delete.

## UI-only flags: Available for Reminders / Dashboard View / Show in Menu (verified 2026-08-07)

The RESTlet cannot set these because `N/search` itself doesn't expose them (its scriptable surface
is title/filters/columns/isPublic; the `savedsearch` record isn't scriptable via `N/record`
either). To flag a search for the dashboard Reminders portlet, use a browser session logged in
to the account (e.g. the `agent-browser` skill):

1. Open `search.nl?id=<internalId>&e=T&cu=T` — the flag checkboxes (`isreminder`, dashboard/menu
   flags, `ispublic`) render **only in customize mode (`cu=T`)**; plain `e=T` shows a reduced form
   without them.
2. Click the skinned widget (`#isreminder_fs img.checkboximage` or the input) —
   `nlapiSetFieldValue('isreminder','T')` updates the client model but does not submit.
3. Click the **`save` button. `#submitter` on search.nl is the PREVIEW button** — it runs the
   search and silently discards definition changes (bit twice before noticing).
4. Reload with `cu=T` and confirm the checkbox persisted before telling anyone it's done.

## Search-type drift and duplicate type filters (verified 2026-08-07)

- POST with `"type": "transaction"` plus a `["type","anyof","CustInvc"]` filter can be **stored as
  a single-record-type search** (e.g. `invoice`), and a later UI save can flip it back to
  `transaction`. PUT must pass the search's *current* type — on
  `{"error":"type cannot be changed — the search's type is <X>"}`, resend with `<X>`; re-describe
  after any UI edit rather than trusting the type you created with.
- A UI save also **materializes the implicit record-type criterion as an explicit filter row**, so
  a stored explicit `type` term shows up duplicated in the UI ("Type is Client Invoice" twice).
  Logically harmless, visually confusing — clean it with a PUT containing exactly one `type` term
  (a `transaction`-type search needs the explicit term; a single-record-type search doesn't).

## Audience

Deployed with `allroles=T` (all internal roles) — SDF rejects scoping this deployment's
`audslctrole` to a custom role (tried both the uppercase enum-style and lowercase scriptid forms
of a real custom role; both errored `must not be <value>`, an apparent SDF platform limitation on
custom-role audience references). Access is gated by OAuth 2.0 client-credential auth plus the
calling role's own RESTlet execute permission, not audience scoping.

## Linking to UI results with URL filters (searchresults.nl) — verified 2026-08-12

`/app/common/search/searchresults.nl?searchid=<internalId>&...` applies extra query params as
**ad-hoc criteria** on top of the stored definition. This needs NO "Available Filters" setup —
that theory is wrong (an empty Available Filters tab does NOT mean params are ignored; only a
wrong param spelling does). Verified live on a transaction search and a timebill search:

| Filter | Param form | Example |
|---|---|---|
| Custom body/column field | **BARE uppercase field id** (a `Transaction_` prefix is silently ignored) | `CUSTBODY_EXAMPLE_FIELD=<internal id>` |
| Standard field | `<Type>_<FIELD>` prefixed (bare is ignored) | `Transaction_NAME=<customer internal id>`, `Transaction_CLASS=<class internal id>`, `Time_CUSTOMER=...` |
| Empty / none | `%40NONE%40` as the value, either form | `Transaction_NAME=%40NONE%40` |
| **Date range** | base param **`=CUSTOM`** plus `from`/`to` — from/to alone are SILENTLY IGNORED in every spelling | `Transaction_TRANDATE=CUSTOM&Transaction_TRANDATEfrom=3%2F1%2F2026&Transaction_TRANDATEto=3%2F31%2F2026` |

- Use the **search field id, not the SuiteQL column**: timebill's date is `Time_DATE`
  (`Time_TRANDATE` is ignored); timebill's type prefix is `Time_`.
- **Free-text fields do NOT filter via URL params** (verified live 2026-08-21):
  `Transaction_MEMO=<text>`, bare `MEMO=<text>`, and a `=CUSTOM`+`text` triplet were all silently
  ignored. Only select/reference and date fields respond; a text-valued condition needs the
  RESTlet's run-time `filter` param or a cloned search, not a link.
- `searchtype`, `...modi=WITHIN`, `...range=CUSTOM`, `...fromreltype=DAGO` (seen in older code)
  are all unnecessary.
- Ignored params are harmless — the page renders unfiltered instead of erroring. So test
  discriminatively: filter to a certainly-empty range and confirm zero data before trusting it,
  and beware summarized searches where "TOTAL: 1" is one summary row either way.

## Installing the RESTlet — only after the user says yes

The RESTlet ships in an SDF package in the `ai-tools` repo, `netsuite/restlets/`, together with
the other CP RESTlets. This skill is a symlink into that clone, so the package is two levels up
from the skill's real path:

```bash
cd "$(cd "<this skill's base directory>" && pwd -P)/../../netsuite/restlets" && pwd -P && ls INSTALL.md
```

Read `INSTALL.md` there before you ask the user about installing, then follow it step by step. It
gives the question to ask, then the SuiteCloud CLI steps that install, upgrade or repair the package
and verify the result. No `INSTALL.md` there: ask the user where their `ai-tools` clone is.

## Maintaining this skill

The RESTlet source and its tests live in CP's private `sdf-creative-planning` repo:
`src/RESTlet/cp_saved_search_rl.ts` and `src/netsuite_modules/saved-search-serializer/`; design
spec `docs/superpowers/specs/2026-07-31-saved-search-restlet-design.html`. A working drill-link
builder is `drillSearchUrl` in `src/netsuite_modules/erp_forecast/drill_links.ts`. Changes reach
other accounts by running `netsuite/restlets/sync.sh` in `ai-tools`, committing, and
redeploying.
