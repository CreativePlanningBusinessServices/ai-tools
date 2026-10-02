/**
 * @NApiVersion 2.1
 * @NScriptType Restlet
 * @NModuleScope SameAccount
 * Author: Jon Lamb
 * Date: 08/01/2026
 * Version: 1.0
 * Description: Create, edit, describe and run saved searches over JSON — NetSuite has no REST API
 *   for saved-search definitions and its SOAP runner is being sunset. Primarily called by
 *   netsuite-cli via `restlet call`. Contract: GET ?id= describes; GET ?id=&run=T&pageIndex=&pageSize=
 *   runs one page; POST creates; POST {"run":true,...} runs a definition without saving it;
 *   PUT updates (full-definition replace); DELETE ?id= removes a saved search. See the design spec
 *   in docs/superpowers/specs/2026-07-31-saved-search-restlet-design.html.
 */
define(["require", "exports", "N/log", "N/query", "N/search", "../netsuite_modules/saved-search-serializer/index.js"], function (require, exports, log, query, search, index_js_1) {
    "use strict";
    const DEFAULT_PAGE_SIZE = 1000;
    const MIN_PAGE_SIZE = 5; // runPaged's documented minimum
    const MAX_PAGE_SIZE = 1000; // runPaged's documented maximum
    // Paging controls travel alongside the definition in an ad-hoc POST body; they are not part of the
    // definition itself, so they are stripped before it reaches definitionFromJson's strict key check.
    const PAGING_KEYS = ['pageSize', 'pageIndex'];
    const RUN_CONTROL_KEYS = ['run', ...PAGING_KEYS];
    // NetSuite picks a RESTlet response's serialization from the REQUEST's Content-Type header.
    // A bodyless GET (this is how netsuite-cli and most callers issue it) carries no Content-Type,
    // so returning an object here fails at platform serialization after our code has already run
    // correctly. Returning a JSON string sidesteps that: it's valid under any content type, and
    // JSON-parsing callers see the identical object.
    const get = (params) => JSON.stringify(handle(() => {
        const runRequested = isRunRequested(params.run);
        const extraFilter = additionalFilter(params.filter, runRequested);
        const loaded = loadSearch(params.id);
        if (!runRequested)
            return serializeWithTitle(loaded);
        return runPage(loaded, resolvePaging(params.pageSize, params.pageIndex), extraFilter);
    }));
    // DELETE, like GET, receives query params rather than a body — and like GET it must return a JSON
    // string, since a bodyless request gives NetSuite no Content-Type to serialize an object from.
    // The search is loaded first so a bad id fails as a ValidationError before anything is destroyed,
    // and so the response and audit log can name what went.
    const remove = (params) => JSON.stringify(handle(() => {
        const loaded = loadSearch(params.id);
        const internalId = typeof loaded.searchId === 'number' ? loaded.searchId : null;
        const title = serializeWithTitle(loaded).title ?? null;
        search.delete({ id: internalId ?? params.id.trim() });
        log.audit('saved search deleted', { internalId, id: loaded.id, title });
        return { deleted: true, internalId, ...(loaded.id ? { id: loaded.id } : {}), title };
    }));
    // The run-time additional filter (Basecamp 519344750): ANDed onto the stored criteria for this
    // run only. Empty string counts as absent, like every other query param. Sending it on a
    // describe call is rejected rather than silently ignored — it would mask a forgotten run=T.
    const additionalFilter = (filter, runRequested) => {
        if (filter === undefined || filter === '')
            return null;
        if (!runRequested) {
            throw new index_js_1.ValidationError('filter is only valid on a run call — add run=T or remove filter');
        }
        return (0, index_js_1.parseRunFilter)(filter);
    };
    // Empty/absent means describe; "T" or "true" (either case) means run; anything else is a caller
    // mistake — silently falling back to describe would mask a typo like run=1 or run=yes.
    const isRunRequested = (run) => {
        if (run === undefined || run === '')
            return false;
        const normalized = run.toLowerCase();
        if (normalized === 't' || normalized === 'true')
            return true;
        throw new index_js_1.ValidationError(`run must be "T" or "true" (case-insensitive), got ${JSON.stringify(run)}`);
    };
    // A RESTlet's post handler is passed only the request body — NetSuite hands query params to get
    // and delete alone — so the ad-hoc switch rides in the body rather than as ?run=T like GET's runner.
    const post = (body) => handle(() => {
        const { adHoc, pageSize, pageIndex, definitionBody } = splitRunControls(body);
        return adHoc ? runAdHoc(definitionBody, resolvePaging(pageSize, pageIndex)) : createSearch(definitionBody);
    });
    // Runs a definition that is never persisted: search.create() already returns a runnable Search, and
    // save() is the only thing that would write it to the account — this path simply never calls it.
    // That makes throwaway queries (what is attached to record X?) stateless, instead of leaving behind
    // probe searches that only the UI can delete.
    const runAdHoc = (body, paging) => {
        const definition = (0, index_js_1.definitionFromJson)(body, 'adhoc');
        const created = search.create({
            type: definition.type,
            title: definition.title,
            filters: definition.filterExpression,
            columns: (0, index_js_1.buildColumns)(definition.columns),
        });
        return runPage(created, paging, null);
    };
    const splitRunControls = (body) => {
        // A non-object body is definitionFromJson's error to report, with its own wording.
        if (!body || typeof body !== 'object' || Array.isArray(body)) {
            return { adHoc: false, pageSize: undefined, pageIndex: undefined, definitionBody: body };
        }
        const raw = body;
        const adHoc = isAdHocRequested(raw.run);
        // Paging keys are meaningless on a create, and stripping them regardless would silently save a
        // search that definitionFromJson's unknown-key check would otherwise have rejected — the exact
        // accidental-persist this feature exists to prevent. Rejected rather than ignored, matching the
        // "filter is only valid on a run call" rule on GET.
        const strays = PAGING_KEYS.filter((key) => raw[key] !== undefined);
        if (!adHoc && strays.length > 0) {
            throw new index_js_1.ValidationError(`${strays.join(', ')} ${strays.length === 1 ? 'is' : 'are'} only valid on an ad-hoc run — add "run": true or remove ${strays.length === 1 ? 'it' : 'them'}`);
        }
        const definitionBody = {};
        Object.keys(raw).forEach((key) => {
            if (!RUN_CONTROL_KEYS.includes(key))
                definitionBody[key] = raw[key];
        });
        return { adHoc, pageSize: raw.pageSize, pageIndex: raw.pageIndex, definitionBody };
    };
    // JSON bodies naturally carry a boolean, but "T"/"true" are accepted too so the flag reads the same
    // as GET's run param. Anything else is a caller mistake — falling through to create would silently
    // persist a search the caller expected to be throwaway, which is the one outcome worth guarding.
    const isAdHocRequested = (run) => {
        if (run === undefined || run === null || run === '')
            return false;
        if (typeof run === 'boolean')
            return run;
        if (typeof run === 'string') {
            const normalized = run.toLowerCase();
            if (normalized === 't' || normalized === 'true')
                return true;
            if (normalized === 'f' || normalized === 'false')
                return false;
        }
        throw new index_js_1.ValidationError(`run must be true/false or "T"/"true", got ${JSON.stringify(run)}`);
    };
    const createSearch = (body) => {
        const definition = (0, index_js_1.definitionFromJson)(body, 'create');
        const created = search.create({
            type: definition.type,
            title: definition.title,
            filters: definition.filterExpression,
            columns: (0, index_js_1.buildColumns)(definition.columns),
            ...(definition.id !== undefined ? { id: definition.id } : {}),
            ...(definition.isPublic !== undefined ? { isPublic: definition.isPublic } : {}),
        });
        const internalId = created.save();
        log.audit('saved search created', { internalId, id: definition.id, title: definition.title });
        return serializeWithTitle(search.load({ id: internalId }), definition.title);
    };
    const put = (body) => handle(() => {
        const definition = (0, index_js_1.definitionFromJson)(body, 'update');
        const loaded = loadSearch(definition.id ?? (definition.internalId !== undefined ? String(definition.internalId) : undefined));
        if (definition.type !== undefined && definition.type !== loaded.searchType) {
            throw new index_js_1.ValidationError(`type cannot be changed — the search's type is ${loaded.searchType}`);
        }
        (0, index_js_1.applyDefinition)(loaded, definition);
        const internalId = loaded.save();
        log.audit('saved search updated', { internalId, title: definition.title });
        return serializeWithTitle(search.load({ id: internalId }), definition.title);
    });
    // N/search.load() never returns a search's title — confirmed in sb2 against both just-saved
    // reloads and describes of long-existing, unrelated searches untouched this session, so it isn't
    // same-execution staleness — it's a permanent platform gap. savedsearch.name in SuiteQL reliably
    // holds the real title, so this is the one title-resolution mechanism used everywhere a search is
    // serialized for a response — describe, POST, and PUT alike — rather than a caller-title overlay
    // that fixes writes but leaves describe (which has no caller title to fall back on) still broken.
    const serializeWithTitle = (loaded, fallbackTitle) => {
        const serialized = (0, index_js_1.searchToJson)(loaded);
        if (serialized.title)
            return serialized;
        const internalId = typeof serialized.internalId === 'number' ? serialized.internalId : null;
        return { ...serialized, title: resolveTitle(internalId, fallbackTitle) };
    };
    // A lookup failure or empty result doesn't fail the request: POST/PUT fall back to the
    // caller-supplied title (already SuiteQL-verified correct at the moment it was persisted);
    // describe has no such fallback, so its title stays null in that case — the documented round-trip
    // caveat is that a caller PUTing a raw describe output back after a genuine lookup failure must
    // supply its own title, same as any other required field.
    const resolveTitle = (internalId, fallbackTitle) => {
        if (internalId !== null) {
            try {
                const rows = query
                    .runSuiteQL({
                    query: /* sql */ `SELECT name FROM savedsearch WHERE id = ?`,
                    params: [internalId],
                })
                    .asMappedResults();
                if (rows.length && rows[0].name)
                    return rows[0].name;
            }
            catch (err) {
                log.error('cp_saved_search_rl title lookup failed', err);
            }
        }
        return fallbackTitle ?? null;
    };
    // Shared by GET's saved-search runner and POST's ad-hoc runner, so both enforce the same bounds.
    const resolvePaging = (rawPageSize, rawPageIndex) => {
        const pageSize = intParam(rawPageSize, 'pageSize') ?? DEFAULT_PAGE_SIZE;
        if (pageSize < MIN_PAGE_SIZE || pageSize > MAX_PAGE_SIZE) {
            throw new index_js_1.ValidationError(`pageSize must be between ${MIN_PAGE_SIZE} and ${MAX_PAGE_SIZE}, got ${pageSize}`);
        }
        return { pageSize, pageIndex: intParam(rawPageIndex, 'pageIndex') ?? 0 };
    };
    const runPage = (loaded, { pageSize, pageIndex }, extraFilter) => {
        if (extraFilter !== null) {
            // In-memory only — the run path never calls save(), so the stored definition is untouched.
            loaded.filterExpression = (0, index_js_1.combineFilterExpressions)(loaded.filterExpression || [], extraFilter);
        }
        const paged = loaded.runPaged({ pageSize });
        const totalPages = paged.pageRanges.length;
        if (totalPages === 0 || pageIndex >= totalPages) {
            return { items: [], count: 0, totalRecords: paged.count, totalPages, pageIndex, hasMore: false };
        }
        const columns = loaded.columns || [];
        const keys = (0, index_js_1.columnKeys)(columns);
        const page = paged.fetch({ index: pageIndex });
        const items = page.data.map((result) => serializeResult(result, columns, keys));
        return {
            items,
            count: items.length,
            totalRecords: paged.count,
            totalPages,
            pageIndex,
            hasMore: pageIndex < totalPages - 1,
        };
    };
    const serializeResult = (result, columns, keys) => {
        const row = {};
        columns.forEach((column, index) => {
            const value = result.getValue(column);
            const text = result.getText(column);
            row[keys[index]] = text !== null && text !== undefined && text !== value ? { value, text } : { value };
        });
        return row;
    };
    const loadSearch = (id) => {
        const trimmedId = id?.trim() ?? '';
        if (trimmedId === '') {
            throw new index_js_1.ValidationError('id is required — a customsearch_* script id or numeric internal id');
        }
        try {
            return search.load({ id: /^\d+$/.test(trimmedId) ? Number(trimmedId) : trimmedId });
        }
        catch (err) {
            // An id N/search can't find is a caller mistake (typo, wrong environment, deleted search) —
            // not a platform failure — so this must not log.error, same contract as any other ValidationError.
            throw new index_js_1.ValidationError(err.message || String(err));
        }
    };
    // Query params arrive as strings, ad-hoc body controls as JSON numbers; both are accepted.
    const intParam = (value, name) => {
        if (value === undefined || value === null || value === '')
            return null;
        if (typeof value === 'number' ? Number.isInteger(value) && value >= 0 : /^\d+$/.test(String(value))) {
            return Number(value);
        }
        throw new index_js_1.ValidationError(`${name} must be a non-negative integer, got ${JSON.stringify(value)}`);
    };
    const handle = (operation) => {
        try {
            return operation();
        }
        catch (err) {
            if (err instanceof index_js_1.ValidationError)
                return { error: err.message };
            log.error('cp_saved_search_rl error', err);
            return { error: err.message || String(err) };
        }
    };
    return { get, post, put, delete: remove };
});
