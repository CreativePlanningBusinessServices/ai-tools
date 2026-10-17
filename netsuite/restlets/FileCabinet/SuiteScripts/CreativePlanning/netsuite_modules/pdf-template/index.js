define(["require", "exports", "N/log", "N/query", "N/record", "N/render", "../file-cabinet/index.js", "./statement-data.js"], function (require, exports, log, query, record, render, index_js_1, statement_data_js_1) {
    "use strict";
    Object.defineProperty(exports, "__esModule", { value: true });
    exports.formatStamp = exports.parseJsonObject = exports.parseTemplateRef = exports.renderTemplate = exports.backupTemplate = exports.describeTemplate = exports.FREEMARKER_HINT = exports.BACKUP_FOLDER = exports.ValidationError = void 0;
    Object.defineProperty(exports, "ValidationError", { enumerable: true, get: function () { return index_js_1.ValidationError; } });
    exports.BACKUP_FOLDER = '/SuiteScripts/CreativePlanning/pdf-template-backups';
    exports.FREEMARKER_HINT = 'NetSuite hit a FreeMarker or layout error but gives no detail — run pdf-validate.sh on the draft. Common causes: an unclosed <#if>/<#list>, an unknown ?built-in, a ${…} left open, position:absolute on an element with no position:relative ancestor.';
    const BACKUP_KEYS = ['id', 'scriptid'];
    const TRANSACTION_RENDER_KEYS = ['templateId', 'scriptId', 'source', 'record', 'printType'];
    const STATEMENT_RENDER_KEYS = ['printType', 'entityId', 'formId', 'statementDate', 'startDate', 'openTransactionsOnly'];
    const DRAFT_STATEMENT_RENDER_KEYS = ['printType', 'source', 'entityId', 'statementDate', 'startDate', 'openTransactionsOnly'];
    // ============ Describe ============
    const describeTemplate = (ref) => {
        const row = loadMetadata(ref);
        return {
            id: row.id,
            scriptid: row.scriptid,
            name: row.name,
            printType: row.printtype,
            tranType: row.trantype ?? null,
            isPreferred: row.preferred === 'T',
            isInactive: row.inactive === 'T',
            isStandard: row.scriptid.toUpperCase().startsWith('STDTMPL'),
            source: readSource(ref, row),
        };
    };
    exports.describeTemplate = describeTemplate;
    const loadMetadata = (ref) => {
        const rows = query
            .runSuiteQL({
            query: /* sql */ `
        SELECT id, scriptid, name, printtype, trantype, preferred, inactive
        FROM advancedpdftemplate
        WHERE ${'id' in ref ? 'id' : 'UPPER(scriptid)'} = ?`,
            params: ['id' in ref ? ref.id : ref.scriptid],
        })
            .asMappedResults();
        if (rows.length === 0) {
            throw new index_js_1.ValidationError('id' in ref
                ? `no advanced PDF/HTML template with id ${ref.id}`
                : `no advanced PDF/HTML template with scriptid ${ref.scriptid}`);
        }
        return rows[0];
    };
    const readSource = (ref, row) => {
        const renderer = render.create();
        if ('id' in ref)
            renderer.setTemplateById({ id: ref.id });
        else
            renderer.setTemplateByScriptId({ scriptId: row.scriptid.toUpperCase() });
        return renderer.templateContent;
    };
    // ============ Backup ============
    const backupTemplate = (body) => {
        const request = asObject(body, BACKUP_KEYS);
        const description = (0, exports.describeTemplate)((0, exports.parseTemplateRef)(request));
        if (description.source.trim() === '') {
            throw new index_js_1.ValidationError(`the source of template ${description.id} came back empty — refusing to write an empty backup`);
        }
        const created = (0, index_js_1.createFile)({
            path: `${exports.BACKUP_FOLDER}/${description.id}-${description.scriptid.toLowerCase()}-${(0, exports.formatStamp)(new Date())}.xml`,
            contents: description.source,
            description: `PDF Designer backup of advanced PDF/HTML template ${description.id} (${description.name})`,
        });
        return { id: description.id, scriptid: description.scriptid, backup: { id: created.id, path: created.path } };
    };
    exports.backupTemplate = backupTemplate;
    // ============ Render ============
    const renderTemplate = (body) => {
        const request = (0, exports.parseJsonObject)(body);
        const printType = request.printType ?? 'TRANSACTION';
        if (printType !== 'TRANSACTION' && printType !== 'STATEMENT') {
            throw new index_js_1.ValidationError(`draft preview supports TRANSACTION and STATEMENT, got ${JSON.stringify(printType)}`);
        }
        if (printType === 'TRANSACTION')
            return translateRenderErrors(() => renderTransaction(request));
        return translateRenderErrors(() => ('source' in request ? renderDraftStatement(request) : renderStatement(request)));
    };
    exports.renderTemplate = renderTemplate;
    const translateRenderErrors = (operation) => {
        try {
            return operation();
        }
        catch (err) {
            if (err?.name === 'UNEXPECTED_ERROR') {
                log.error('opaque render error', err);
                throw new index_js_1.ValidationError(exports.FREEMARKER_HINT);
            }
            throw err;
        }
    };
    const renderTransaction = (body) => {
        const request = asObject(body, TRANSACTION_RENDER_KEYS);
        const isDraft = 'source' in request;
        const source = isDraft ? requireSource(request.source) : '';
        const templateRef = isDraft ? null : parseSavedTemplateRef(request);
        const target = requireRecordRef(request.record);
        const renderer = render.create();
        if (templateRef === null)
            renderer.templateContent = source;
        else if ('id' in templateRef)
            renderer.setTemplateById({ id: templateRef.id });
        else
            renderer.setTemplateByScriptId({ scriptId: templateRef.scriptid });
        const transaction = record.load({ type: target.type, id: target.id });
        renderer.addRecord({ templateName: 'record', record: transaction });
        const subsidiaryId = transaction.getValue({ fieldId: 'subsidiary' });
        if (subsidiaryId !== '' && subsidiaryId !== null && subsidiaryId !== undefined) {
            renderer.addRecord({
                templateName: 'subsidiary',
                record: record.load({ type: record.Type.SUBSIDIARY, id: Number(subsidiaryId) }),
            });
        }
        const pdfFile = renderer.renderAsPdf();
        return {
            mode: isDraft ? 'draft' : 'saved',
            printType: 'TRANSACTION',
            record: target,
            pdf: pdfFile.getContents(),
            pdfBytes: pdfFile.size,
            xml: renderer.renderAsString(),
        };
    };
    const renderStatement = (body) => {
        const request = asObject(body, STATEMENT_RENDER_KEYS);
        if (request.entityId === undefined)
            throw new index_js_1.ValidationError('entityId is required for a STATEMENT render');
        if (request.formId === undefined)
            throw new index_js_1.ValidationError('formId is required for a STATEMENT render — pass the id of the statement form that prints with the template');
        const entityId = requireId(request.entityId);
        const formId = requireId(request.formId);
        const options = {
            entityId,
            formId,
            ...(request.statementDate !== undefined && { statementDate: String(request.statementDate) }),
            ...(request.startDate !== undefined && { startDate: String(request.startDate) }),
            ...(request.openTransactionsOnly !== undefined && { openTransactionsOnly: request.openTransactionsOnly === true }),
        };
        const pdfFile = render.statement({ ...options, printMode: render.PrintMode.PDF });
        // HTML mode returns the merged markup (a <pdfset> of <html> children), which the preview needs.
        const htmlFile = render.statement({ ...options, printMode: render.PrintMode.HTML });
        return {
            mode: 'saved',
            printType: 'STATEMENT',
            record: { entityId, formId },
            pdf: pdfFile.getContents(),
            pdfBytes: pdfFile.size,
            xml: htmlFile.getContents(),
        };
    };
    const renderDraftStatement = (body) => {
        if ('formId' in body)
            throw new index_js_1.ValidationError('formId is only for saved statements — a draft (source) renders against rebuilt statement data, not a form');
        const request = asObject(body, DRAFT_STATEMENT_RENDER_KEYS);
        const source = requireSource(request.source);
        if (request.entityId === undefined)
            throw new index_js_1.ValidationError('entityId is required for a STATEMENT render');
        const entityId = requireId(request.entityId);
        const draft = (0, statement_data_js_1.buildDraftStatement)({
            entityId,
            statementDate: request.statementDate,
            startDate: request.startDate,
            openTransactionsOnly: request.openTransactionsOnly === true,
            source,
        });
        const renderer = render.create();
        renderer.templateContent = draft.templateSource;
        const customer = record.load({ type: record.Type.CUSTOMER, id: entityId });
        renderer.addRecord({ templateName: 'record', record: customer });
        renderer.addRecord({ templateName: 'customer', record: customer });
        if (draft.subsidiaryId !== null) {
            renderer.addRecord({ templateName: 'subsidiary', record: record.load({ type: record.Type.SUBSIDIARY, id: draft.subsidiaryId }) });
        }
        renderer.addCustomDataSource({ format: render.DataSource.OBJECT, ...draft.dataSource });
        const pdfFile = renderer.renderAsPdf();
        return {
            mode: 'draft',
            printType: 'STATEMENT',
            record: { entityId },
            pdf: pdfFile.getContents(),
            pdfBytes: pdfFile.size,
            xml: renderer.renderAsString(),
            approximate: true,
        };
    };
    const requireSource = (source) => {
        const isBlank = typeof source !== 'string' || ['', 'null', 'undefined'].includes(source.trim());
        if (isBlank)
            throw new index_js_1.ValidationError('source must be the template markup — got an empty, "null" or "undefined" value, so the draft file was probably not read');
        return source;
    };
    const parseSavedTemplateRef = (request) => {
        const hasTemplateId = request.templateId !== undefined && request.templateId !== '';
        const hasScriptId = request.scriptId !== undefined && request.scriptId !== '';
        if (hasTemplateId === hasScriptId)
            throw new index_js_1.ValidationError('pass exactly one of templateId or scriptId (or source for a draft)');
        return hasTemplateId ? { id: requireId(request.templateId) } : (0, exports.parseTemplateRef)({ scriptid: request.scriptId });
    };
    const requireRecordRef = (value) => {
        const reference = typeof value === 'object' && value !== null ? value : {};
        if (typeof reference.type !== 'string' || reference.type.trim() === '' || reference.id === undefined) {
            throw new index_js_1.ValidationError('record {type, id} is required, e.g. {"type": "invoice", "id": 456}');
        }
        return { type: reference.type.trim(), id: requireId(reference.id) };
    };
    // ============ Request parsing helpers ============
    const parseTemplateRef = (params) => {
        const hasId = params.id !== undefined && params.id !== '';
        const hasScriptId = params.scriptid !== undefined && params.scriptid !== '';
        if (hasId && hasScriptId)
            throw new index_js_1.ValidationError('pass exactly one of id or scriptid, not both');
        if (!hasId && !hasScriptId)
            throw new index_js_1.ValidationError('id or scriptid is required — GET ?id=<template internal id> or ?scriptid=<CUSTTMPL_…>');
        if (hasId)
            return { id: requireId(params.id) };
        if (typeof params.scriptid !== 'string' || params.scriptid.trim() === '') {
            throw new index_js_1.ValidationError('scriptid must be a non-empty string');
        }
        return { scriptid: params.scriptid.trim().toUpperCase() };
    };
    exports.parseTemplateRef = parseTemplateRef;
    const requireId = (value) => {
        if (typeof value === 'number' && Number.isInteger(value) && value > 0)
            return value;
        if (typeof value === 'string' && /^\d+$/.test(value))
            return Number(value);
        throw new index_js_1.ValidationError(`id must be a numeric internal id, got ${JSON.stringify(value)} — paste only the id, not the template URL`);
    };
    const parseJsonObject = (body) => {
        let parsed = body;
        if (typeof body === 'string') {
            try {
                parsed = JSON.parse(body);
            }
            catch {
                throw new index_js_1.ValidationError('request body must be a JSON object');
            }
        }
        if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
            throw new index_js_1.ValidationError('request body must be a JSON object');
        }
        return parsed;
    };
    exports.parseJsonObject = parseJsonObject;
    const asObject = (body, allowedKeys) => {
        const request = (0, exports.parseJsonObject)(body);
        const unknownKeys = Object.keys(request).filter((key) => !allowedKeys.includes(key));
        if (unknownKeys.length > 0) {
            throw new index_js_1.ValidationError(`unknown key(s): ${unknownKeys.join(', ')} — allowed: ${allowedKeys.join(', ')}`);
        }
        return request;
    };
    const formatStamp = (date) => {
        const pad = (part) => String(part).padStart(2, '0');
        return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}-${pad(date.getHours())}${pad(date.getMinutes())}${pad(date.getSeconds())}`;
    };
    exports.formatStamp = formatStamp;
});
