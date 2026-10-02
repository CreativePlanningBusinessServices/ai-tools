/**
 * @NApiVersion 2.1
 * @NModuleScope SameAccount
 * Author: Jon Lamb
 * Date: 08/01/2026
 * Version: 1.0
 * Description: Shared serialization core for cp_saved_search_rl — maps saved searches to and from
 *   the round-trippable JSON definition in the design spec. All caller-input validation lives
 *   here, before N/search sees anything, because N/search's own errors are cryptic.
 */
define(["require", "exports", "N/search"], function (require, exports, search) {
    "use strict";
    Object.defineProperty(exports, "__esModule", { value: true });
    exports.columnKeys = exports.applyDefinition = exports.buildColumns = exports.searchToJson = exports.combineFilterExpressions = exports.parseRunFilter = exports.ValidationError = void 0;
    exports.definitionFromJson = definitionFromJson;
    // Caller mistakes throw this; the RESTlet turns it into {error} without log.error noise.
    class ValidationError extends Error {
    }
    exports.ValidationError = ValidationError;
    const TOP_LEVEL_KEYS = ['id', 'internalId', 'title', 'type', 'isPublic', 'filterExpression', 'columns'];
    // Keys that only mean something once a search is persisted, and so are rejected on an ad-hoc run.
    const PERSISTED_ONLY_KEYS = ['id', 'internalId', 'isPublic'];
    // An ad-hoc search is never saved, so nothing ever displays this — but N/search.create still
    // wants a title, and a fixed one keeps the audit log readable.
    const ADHOC_TITLE = 'ad-hoc run (not saved)';
    const COLUMN_KEYS = ['name', 'join', 'summary', 'formula', 'sort', 'label'];
    const SUMMARIES = ['GROUP', 'COUNT', 'SUM', 'AVG', 'MIN', 'MAX'];
    const LOGICAL_OPERATORS = ['and', 'or', 'not'];
    const SCRIPT_ID = /^customsearch[a-z0-9_]+$/;
    function definitionFromJson(body, mode) {
        if (!body || typeof body !== 'object' || Array.isArray(body)) {
            throw new ValidationError('request body must be a JSON object');
        }
        const raw = body;
        const unknownKeys = Object.keys(raw).filter((key) => !TOP_LEVEL_KEYS.includes(key));
        if (unknownKeys.length > 0) {
            throw new ValidationError(`unknown key(s): ${unknownKeys.join(', ')} (allowed: ${TOP_LEVEL_KEYS.join(', ')})`);
        }
        if (mode === 'adhoc') {
            const persisted = PERSISTED_ONLY_KEYS.filter((key) => raw[key] !== undefined && raw[key] !== null);
            if (persisted.length > 0) {
                throw new ValidationError(`${persisted.join(', ')} ${persisted.length === 1 ? 'is' : 'are'} not valid on an ad-hoc run — nothing is saved (drop the key, or POST without run to create a saved search)`);
            }
        }
        // Create and update require a title — it is what a human picks the search out by. An ad-hoc run
        // has no such list to appear in, so it defaults rather than making callers invent one.
        const rawTitle = mode === 'adhoc' && raw.title === undefined ? ADHOC_TITLE : raw.title;
        if (typeof rawTitle !== 'string' || rawTitle.trim() === '') {
            throw new ValidationError('title is required and must be a non-empty string');
        }
        const definition = {
            title: rawTitle,
            filterExpression: validateFilterExpression(resolveReplaceArray(raw, 'filterExpression', mode)),
            columns: validateColumns(resolveReplaceArray(raw, 'columns', mode)),
        };
        if (mode !== 'update' && raw.type === undefined) {
            throw new ValidationError('type is required and must be a non-empty string');
        }
        // Optional-key null tolerance (defensive: old-style payloads with an explicit `null` still round-trip):
        // id, internalId and isPublic are optional in both modes; type is optional only on update.
        const typeGiven = raw.type !== undefined && !(mode === 'update' && raw.type === null);
        if (typeGiven) {
            if (typeof raw.type !== 'string' || raw.type.trim() === '') {
                throw new ValidationError('type must be a non-empty string');
            }
            definition.type = raw.type;
        }
        if (raw.id !== undefined && raw.id !== null) {
            if (typeof raw.id !== 'string' || !SCRIPT_ID.test(raw.id)) {
                throw new ValidationError(`id must be a customsearch_* script id (lowercase letters, digits and underscores), got ${JSON.stringify(raw.id)}`);
            }
            definition.id = raw.id;
        }
        const internalIdGiven = raw.internalId !== undefined && raw.internalId !== null;
        if (mode !== 'update' && internalIdGiven) {
            throw new ValidationError('internalId is not valid on create — it has no meaning until the search is saved (use id, or omit both to auto-generate one)');
        }
        if (internalIdGiven) {
            if (typeof raw.internalId !== 'number' || !Number.isInteger(raw.internalId)) {
                throw new ValidationError(`internalId must be an integer, got ${JSON.stringify(raw.internalId)}`);
            }
            definition.internalId = raw.internalId;
        }
        if (raw.isPublic !== undefined && raw.isPublic !== null) {
            if (typeof raw.isPublic !== 'boolean') {
                throw new ValidationError('isPublic must be a boolean');
            }
            definition.isPublic = raw.isPublic;
        }
        return definition;
    }
    // Create keeps the historical default-to-[] behavior — a brand-new search has nothing to wipe.
    // Update requires the key explicitly present: PUT is a full-definition replace, so a caller who
    // omits filterExpression/columns almost certainly meant to keep them, not blank them out.
    const resolveReplaceArray = (raw, key, mode) => {
        if (raw[key] !== undefined)
            return raw[key];
        if (mode === 'update') {
            throw new ValidationError(`${key} is required on update — full-definition replace overwrites it (send the array from describe)`);
        }
        return [];
    };
    const validateFilterExpression = (expression, label = 'filterExpression') => {
        if (!Array.isArray(expression)) {
            throw new ValidationError(`${label} must be an array`);
        }
        // A bare term like ["isinactive","is","F"] is the most likely caller mistake — give it a
        // pointed hint instead of the generic element-by-element error.
        if (expression.length > 0 && typeof expression[0] === 'string' && !isLogicalOperator(expression[0])) {
            throw new ValidationError(`${label} must be an array of term arrays — wrap a single term like [["field","operator","value"]]`);
        }
        validateExpressionElements(expression, label);
        return expression;
    };
    // Run-time additional filter (GET ?filter=...): the query-param value is a JSON-encoded
    // filter-expression array, validated with the same rules as create/update but labeled "filter"
    // in errors. An empty array is rejected — the caller who built [] almost certainly has a bug.
    const parseRunFilter = (raw) => {
        let parsed;
        try {
            parsed = JSON.parse(raw);
        }
        catch {
            throw new ValidationError('filter must be valid JSON — a filter-expression array like [["field","operator","value"]]');
        }
        const expression = validateFilterExpression(parsed, 'filter');
        if (expression.length === 0) {
            throw new ValidationError('filter must not be an empty array — omit the param to run unfiltered');
        }
        return expression;
    };
    exports.parseRunFilter = parseRunFilter;
    // Grouped combining: each side becomes a parenthesized sub-expression, so a stored top-level OR
    // keeps its grouping — (A OR B) AND (extra), never A OR (B AND extra).
    const combineFilterExpressions = (stored, extra) => stored.length === 0 ? extra : [stored, 'AND', extra];
    exports.combineFilterExpressions = combineFilterExpressions;
    const validateExpressionElements = (expression, path) => {
        expression.forEach((element, index) => {
            if (typeof element === 'string') {
                if (!isLogicalOperator(element)) {
                    throw new ValidationError(`${path}[${index}] must be "AND", "OR" or "NOT", got ${JSON.stringify(element)}`);
                }
                return;
            }
            if (!Array.isArray(element)) {
                throw new ValidationError(`${path}[${index}] must be a term array, a sub-expression array, or a logical operator string`);
            }
            // A term is ["fieldId", "operator", ...values]; anything else recurses as a sub-expression.
            // Operator/value semantics are deliberately left to N/search — only the shape is checked.
            if (typeof element[0] === 'string' && !isLogicalOperator(element[0])) {
                if (typeof element[1] !== 'string') {
                    throw new ValidationError(`${path}[${index}] term must be ["fieldId", "operator", ...values]`);
                }
                return;
            }
            validateExpressionElements(element, `${path}[${index}]`);
        });
    };
    const isLogicalOperator = (value) => LOGICAL_OPERATORS.includes(value.toLowerCase());
    const validateColumns = (rawColumns) => {
        if (!Array.isArray(rawColumns)) {
            throw new ValidationError('columns must be an array');
        }
        return rawColumns.map(validateColumn);
    };
    const validateColumn = (rawColumn, index) => {
        if (!rawColumn || typeof rawColumn !== 'object' || Array.isArray(rawColumn)) {
            throw new ValidationError(`columns[${index}] must be an object`);
        }
        const column = rawColumn;
        const unknownKeys = Object.keys(column).filter((key) => !COLUMN_KEYS.includes(key));
        if (unknownKeys.length > 0) {
            throw new ValidationError(`columns[${index}] unknown key(s): ${unknownKeys.join(', ')} (allowed: ${COLUMN_KEYS.join(', ')})`);
        }
        if (typeof column.name !== 'string' || column.name.trim() === '') {
            throw new ValidationError(`columns[${index}].name is required and must be a non-empty string`);
        }
        const definition = { name: column.name };
        for (const key of ['join', 'formula', 'label']) {
            const value = column[key];
            if (value === undefined)
                continue;
            if (typeof value !== 'string' || value === '') {
                throw new ValidationError(`columns[${index}].${key} must be a non-empty string`);
            }
            definition[key] = value;
        }
        if (column.summary !== undefined) {
            if (typeof column.summary !== 'string' || !SUMMARIES.includes(column.summary.toUpperCase())) {
                throw new ValidationError(`columns[${index}].summary must be one of ${SUMMARIES.join(', ')}`);
            }
            definition.summary = column.summary.toUpperCase();
        }
        if (column.sort !== undefined) {
            if (column.sort !== 'ASC' && column.sort !== 'DESC') {
                throw new ValidationError(`columns[${index}].sort must be "ASC" or "DESC"`);
            }
            definition.sort = column.sort;
        }
        return definition;
    };
    const searchToJson = (loaded) => {
        const definition = {
            // internalId is always numeric after a load — kept unconditionally, unlike id below.
            internalId: loaded.searchId ?? null,
            title: loaded.title || null,
            type: loaded.searchType,
            isPublic: loaded.isPublic === true,
            filterExpression: loaded.filterExpression || [],
            columns: (loaded.columns || []).map(columnToJson),
        };
        // A search with no script id (e.g. a private UI-created one) has no value to report — omit
        // rather than emit null, so definitionFromJson's update-mode round-trip doesn't reject it.
        if (loaded.id)
            definition.id = loaded.id;
        return definition;
    };
    exports.searchToJson = searchToJson;
    const buildColumns = (columns) => columns.map((column) => {
        const options = { name: column.name };
        if (column.join !== undefined)
            options.join = column.join;
        if (column.summary !== undefined) {
            // @ts-expect-error: string-literal → enum nominal-enum mismatch; values validated in Task 1
            options.summary = column.summary;
        }
        if (column.formula !== undefined)
            options.formula = column.formula;
        if (column.label !== undefined)
            options.label = column.label;
        if (column.sort !== undefined) {
            // @ts-expect-error: string-literal → enum nominal-enum mismatch; values validated in Task 1
            options.sort = column.sort;
        }
        return search.createColumn(options);
    });
    exports.buildColumns = buildColumns;
    // Update direction: full-definition replace of everything the contract exposes. The script id and
    // search type are immutable — the RESTlet guards type before calling this.
    const applyDefinition = (loaded, definition) => {
        loaded.title = definition.title;
        loaded.filterExpression = definition.filterExpression;
        loaded.columns = (0, exports.buildColumns)(definition.columns);
        if (definition.isPublic !== undefined)
            loaded.isPublic = definition.isPublic;
    };
    exports.applyDefinition = applyDefinition;
    // Join-qualified, de-duplicated keys for run-result rows ("customer.companyname"); a second column
    // with the same key gets a numeric suffix so no cell silently overwrites another.
    const columnKeys = (columns) => {
        const seen = new Map();
        return columns.map((column) => {
            const name = typeof column === 'string' ? column : column.name;
            const join = typeof column === 'string' ? undefined : column.join;
            const base = join ? `${join}.${name}` : name;
            const timesSeen = (seen.get(base) ?? 0) + 1;
            seen.set(base, timesSeen);
            return timesSeen === 1 ? base : `${base}_${timesSeen}`;
        });
    };
    exports.columnKeys = columnKeys;
    const columnToJson = (column) => {
        if (typeof column === 'string')
            return { name: column };
        const definition = { name: column.name };
        if (column.join)
            definition.join = column.join;
        if (column.summary)
            definition.summary = String(column.summary).toUpperCase();
        if (column.formula)
            definition.formula = column.formula;
        const sort = column.sort ? String(column.sort).toUpperCase() : null;
        if (sort === 'ASC' || sort === 'DESC')
            definition.sort = sort;
        if (column.label)
            definition.label = column.label;
        return definition;
    };
});
