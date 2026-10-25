define(["require", "exports", "N/log", "N/query", "N/record", "N/render", "N/search", "../file-cabinet/index.js", "./statement-data.js"], function (require, exports, log, query, record, render, search, index_js_1, statement_data_js_1) {
    "use strict";
    Object.defineProperty(exports, "__esModule", { value: true });
    exports.formatStamp = exports.parseJsonObject = exports.parseTemplateRef = exports.adaptTitle = exports.renderTemplate = exports.backupTemplate = exports.describeTemplate = exports.SEARCH_MAX_LIMIT = exports.SEARCH_DEFAULT_LIMIT = exports.RETURN_FORM_NOTE = exports.RAW_FREEMARKER_REFUSAL = exports.RAW_REFUSAL = exports.NATIVE_TEMPLATE_REFUSAL = exports.NATIVE_REFUSAL = exports.PRINT_CHECKS_REFUSAL = exports.FREEMARKER_HINT = exports.BACKUP_FOLDER = exports.ValidationError = void 0;
    Object.defineProperty(exports, "ValidationError", { enumerable: true, get: function () { return index_js_1.ValidationError; } });
    exports.BACKUP_FOLDER = '/SuiteScripts/CreativePlanning/pdf-template-backups';
    exports.FREEMARKER_HINT = 'NetSuite hit a FreeMarker or layout error but gives no detail — run pdf-validate.sh on the draft. Common causes: an unclosed <#if>/<#list>, an unknown ?built-in, a ${…} left open, a <tr> or <td> outside its <table> or <tr>, position:absolute on a direct child of <body>, position:fixed.';
    exports.PRINT_CHECKS_REFUSAL = 'this template loops over `records` (a Print Checks batch layout), which a one-record preview cannot fill, so NetSuite would fail the render; validating and saving it still work — print a check batch in NetSuite to see it';
    // The Print Checks batch hands the template a `records` sequence; a single-record render never sets it.
    const PRINT_CHECKS_LOOP = /<#list\s+records\s/;
    exports.NATIVE_REFUSAL = 'native must be true or left out';
    exports.NATIVE_TEMPLATE_REFUSAL = 'native renders what the form prints, so it takes no templateId, scriptId or source';
    exports.RAW_REFUSAL = 'xml must be BFO markup: an <?xml …?> declaration and a <pdf>, <pdfset> or <html> root';
    exports.RAW_FREEMARKER_REFUSAL = 'raw XML has no FreeMarker; use source';
    const BACKUP_KEYS = ['id', 'scriptid'];
    const TRANSACTION_RENDER_KEYS = ['templateId', 'scriptId', 'source', 'record', 'printType'];
    const STATEMENT_RENDER_KEYS = ['printType', 'entityId', 'formId', 'statementDate', 'startDate', 'openTransactionsOnly'];
    const DRAFT_STATEMENT_RENDER_KEYS = ['printType', 'source', 'entityId', 'statementDate', 'startDate', 'openTransactionsOnly'];
    const SEARCH_RENDER_KEYS = ['printType', 'templateId', 'scriptId', 'source', 'searchId', 'limit', 'resultsAlias'];
    const NATIVE_TRANSACTION_KEYS = ['printType', 'native', 'record', 'formId'];
    const RAW_KEYS = ['xml'];
    const PICKING_TICKET_KEYS = ['printType', 'templateId', 'scriptId', 'source', 'record', 'native', 'formId', 'shipgroup', 'location'];
    const PACKING_SLIP_KEYS = ['printType', 'templateId', 'scriptId', 'source', 'record', 'native', 'formId'];
    const NATIVE_ONLY_KEYS = ['formId', 'shipgroup', 'location'];
    exports.RETURN_FORM_NOTE = "returnForm isn't supplied by the preview, so the return-form section stays hidden";
    exports.SEARCH_DEFAULT_LIMIT = 50;
    exports.SEARCH_MAX_LIMIT = 1000;
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
        if ('xml' in request)
            return translateRenderErrors(() => renderRaw(request));
        const printType = request.printType ?? 'TRANSACTION';
        if (printType === 'TRANSACTION') {
            return translateRenderErrors(() => ('native' in request ? renderNativeTransaction(request) : renderTransaction(request)));
        }
        if (printType === 'STATEMENT')
            return translateRenderErrors(() => ('source' in request ? renderDraftStatement(request) : renderStatement(request)));
        if (printType === 'SEARCH')
            return translateRenderErrors(() => renderSearch(request));
        if (printType === 'PICKINGTICKET')
            return translateRenderErrors(() => renderPickingTicket(request));
        if (printType === 'PACKINGSLIP')
            return translateRenderErrors(() => renderPackingSlip(request));
        throw new index_js_1.ValidationError(`${String(printType)} has no preview yet — supported: TRANSACTION, STATEMENT, SEARCH, PICKINGTICKET, PACKINGSLIP`);
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
        const template = parseTemplateChoice(request);
        const target = requireRecordRef(request.record);
        const { renderer, isDraft } = prepareRenderer(template);
        if (PRINT_CHECKS_LOOP.test(renderer.templateContent))
            throw new index_js_1.ValidationError(exports.PRINT_CHECKS_REFUSAL);
        const transaction = record.load({ type: target.type, id: target.id });
        renderer.addRecord({ templateName: 'record', record: transaction });
        addSubsidiaryRoot(renderer, transaction);
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
    // What NetSuite itself prints or attaches through the record's form (or formId); HTML mode returns the merged markup.
    const renderNativeTransaction = (body) => {
        requireNative(body.native);
        rejectTemplateWithNative(body);
        const request = asObject(body, NATIVE_TRANSACTION_KEYS);
        const target = requireRecordRef(request.record);
        const withForm = request.formId === undefined ? {} : { formId: requireId(request.formId) };
        const pdfFile = render.transaction({ entityId: target.id, printMode: render.PrintMode.PDF, ...withForm });
        const htmlFile = render.transaction({ entityId: target.id, printMode: render.PrintMode.HTML, ...withForm });
        return {
            mode: 'native',
            printType: 'TRANSACTION',
            record: { ...target, ...withForm },
            pdf: pdfFile.getContents(),
            pdfBytes: pdfFile.size,
            xml: htmlFile.getContents(),
        };
    };
    // xmlToPdf turns plain text into a PDF instead of failing, so the input is checked here.
    const renderRaw = (body) => {
        const request = asObject(body, RAW_KEYS);
        const input = typeof request.xml === 'string' ? request.xml.trimStart() : '';
        if (!input.startsWith('<?xml') || !/<(pdf|pdfset|html)[\s>]/.test(input))
            throw new index_js_1.ValidationError(exports.RAW_REFUSAL);
        if (/<#|\$\{/.test(input))
            throw new index_js_1.ValidationError(exports.RAW_FREEMARKER_REFUSAL);
        // NetSuite's HTML-mode merged markup names each document <html>; xmlToPdf accepts only <pdf> (SB2 QA 2026-10-24).
        const markup = input.replace(/<(\/?)html(?=[\s>])/g, '<$1pdf');
        const pdfFile = render.xmlToPdf({ xmlString: markup });
        const result = { mode: 'raw', printType: 'RAW', record: null, pdf: pdfFile.getContents(), pdfBytes: pdfFile.size, xml: markup };
        return withExtras(result, { adaptations: markup === input ? [] : ['root: html → pdf'] });
    };
    const renderStatement = (body) => {
        const request = asObject(body, STATEMENT_RENDER_KEYS);
        if (request.entityId === undefined)
            throw new index_js_1.ValidationError('entityId is required for a STATEMENT render');
        if (request.formId === undefined)
            throw new index_js_1.ValidationError('formId is required for a STATEMENT render — pass the id of the statement form that prints with the template');
        const entityId = requireId(request.entityId);
        const formId = requireId(request.formId);
        const period = (0, statement_data_js_1.parseStatementPeriod)(request);
        const options = {
            entityId,
            formId,
            ...(period.statementDate !== null && { statementDate: period.statementDate.display }),
            ...(period.startDate !== null && { startDate: period.startDate.display }),
            ...(period.openTransactionsOnly !== null && { openTransactionsOnly: period.openTransactionsOnly }),
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
            openTransactionsOnly: request.openTransactionsOnly,
            source,
        });
        const renderer = render.create();
        renderer.templateContent = draft.templateSource;
        const customer = record.load({ type: record.Type.CUSTOMER, id: entityId });
        renderer.addRecord({ templateName: 'record', record: customer });
        renderer.addRecord({ templateName: 'customer', record: customer });
        addSubsidiaryRoot(renderer, customer);
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
    // addSearchResults takes search.Result objects, so this one path uses N/search rather than SuiteQL.
    const renderSearch = (body) => {
        const request = asObject(body, SEARCH_RENDER_KEYS);
        const template = parseTemplateChoice(request);
        const searchId = requireSearchId(request.searchId);
        const limit = requireLimit(request.limit);
        const resultsAlias = requireResultsAlias(request.resultsAlias);
        const savedSearch = search.load({ id: searchId });
        // One row past the limit tells whether the search had more; getRange can't go past 1000.
        const fetched = savedSearch.run().getRange({ start: 0, end: Math.min(limit + 1, exports.SEARCH_MAX_LIMIT) });
        const truncated = fetched.length > limit || (limit === exports.SEARCH_MAX_LIMIT && fetched.length === exports.SEARCH_MAX_LIMIT);
        const rows = fetched.slice(0, limit);
        const { renderer, isDraft } = prepareRenderer(template);
        renderer.addSearchResults({ templateName: resultsAlias, searchResult: rows });
        const pdfFile = renderer.renderAsPdf();
        return {
            mode: isDraft ? 'draft' : 'saved',
            printType: 'SEARCH',
            record: { searchId, searchType: String(savedSearch.searchType), resultCount: rows.length, truncated },
            pdf: pdfFile.getContents(),
            pdfBytes: pdfFile.size,
            xml: renderer.renderAsString(),
        };
    };
    const renderPickingTicket = (body) => {
        if ('native' in body)
            return renderNativePickingTicket(body);
        const request = asObject(body, PICKING_TICKET_KEYS);
        rejectNativeOnlyKeys(request);
        const template = parseTemplateChoice(request);
        const target = requireRecordRef(request.record);
        if (target.type !== 'salesorder')
            throw new index_js_1.ValidationError('a picking ticket prints a sales order; record.type must be salesorder');
        const { renderer, isDraft } = prepareRenderer(template);
        const { adaptations } = adaptRendererTitle(renderer, 'Picking Ticket');
        const salesOrder = record.load({ type: target.type, id: target.id });
        renderer.addRecord({ templateName: 'record', record: salesOrder });
        addSubsidiaryRoot(renderer, salesOrder);
        return withExtras(renderToResult(renderer, isDraft, 'PICKINGTICKET', target), { adaptations });
    };
    const renderNativePickingTicket = (body) => {
        requireNative(body.native);
        rejectTemplateWithNative(body);
        const request = asObject(body, PICKING_TICKET_KEYS);
        const target = requireRecordRef(request.record);
        if (target.type !== 'salesorder')
            throw new index_js_1.ValidationError('a picking ticket prints a sales order; record.type must be salesorder');
        const options = {
            entityId: target.id,
            printMode: render.PrintMode.PDF,
            ...(request.formId !== undefined && { formId: requireId(request.formId) }),
            ...(request.shipgroup !== undefined && { shipgroup: requireId(request.shipgroup) }),
            ...(request.location !== undefined && { location: requireId(request.location) }),
        };
        const pdfFile = render.pickingTicket(options);
        return { mode: 'native', printType: 'PICKINGTICKET', record: target, pdf: pdfFile.getContents(), pdfBytes: pdfFile.size, xml: null };
    };
    const renderPackingSlip = (body) => {
        if ('native' in body)
            return renderNativePackingSlip(body);
        const request = asObject(body, PACKING_SLIP_KEYS);
        rejectNativeOnlyKeys(request);
        const template = parseTemplateChoice(request);
        const target = requirePackingSlipRecord(request.record);
        const { renderer, isDraft } = prepareRenderer(template);
        const { adaptations } = adaptRendererTitle(renderer, 'Packing Slip');
        const notes = renderer.templateContent.includes('returnForm') ? [exports.RETURN_FORM_NOTE] : [];
        const shipped = record.load({ type: target.type, id: target.id });
        const salesOrder = target.type === 'salesorder'
            ? shipped
            : record.load({ type: record.Type.SALES_ORDER, id: requireCreatedFrom(target.id, shipped.getValue({ fieldId: 'createdfrom' })) });
        renderer.addRecord({ templateName: 'record', record: shipped });
        renderer.addRecord({ templateName: 'salesorder', record: salesOrder });
        addSubsidiaryRoot(renderer, salesOrder);
        const result = renderToResult(renderer, isDraft, 'PACKINGSLIP', target);
        // Without a fulfillment the sales order stands in for it, so ship date, method and phone come from the order.
        return withExtras(target.type === 'salesorder' ? { ...result, approximate: true } : result, { adaptations, notes });
    };
    const renderNativePackingSlip = (body) => {
        requireNative(body.native);
        rejectTemplateWithNative(body);
        const request = asObject(body, PACKING_SLIP_KEYS);
        const target = requirePackingSlipRecord(request.record);
        const salesOrderId = target.type === 'salesorder' ? target.id : requireCreatedFrom(target.id, readFulfillmentSource(target.id));
        const pdfFile = render.packingSlip({
            entityId: salesOrderId,
            ...(target.type === 'itemfulfillment' && { fulfillmentId: target.id }),
            printMode: render.PrintMode.PDF,
            ...(request.formId !== undefined && { formId: requireId(request.formId) }),
        });
        return { mode: 'native', printType: 'PACKINGSLIP', record: target, pdf: pdfFile.getContents(), pdfBytes: pdfFile.size, xml: null };
    };
    const readFulfillmentSource = (fulfillmentId) => {
        const rows = query
            .runSuiteQL({ query: /* sql */ `SELECT createdfrom FROM transaction WHERE id = ?`, params: [fulfillmentId] })
            .asMappedResults();
        return rows.length > 0 ? rows[0].createdfrom : null;
    };
    // ============ Render helpers ============
    const prepareRenderer = (template) => {
        const renderer = render.create();
        if ('source' in template) {
            renderer.templateContent = template.source;
            return { renderer, isDraft: true };
        }
        if ('id' in template.ref)
            renderer.setTemplateById({ id: template.ref.id });
        else
            renderer.setTemplateByScriptId({ scriptId: template.ref.scriptid });
        return { renderer, isDraft: false };
    };
    // A saved template is adapted on the renderer's copy of its source; the template itself is never written.
    const adaptRendererTitle = (renderer, title) => {
        const adapted = (0, exports.adaptTitle)(renderer.templateContent, title);
        if (adapted.adaptations.length > 0)
            renderer.templateContent = adapted.source;
        return { adaptations: adapted.adaptations };
    };
    // record@title would print the loaded record's type ("Sales Order"); NetSuite's own print shows the print type's title.
    const adaptTitle = (source, title) => {
        const adapted = source.replace(/\$\{\s*record@title\s*\}/g, title);
        return adapted === source ? { source, adaptations: [] } : { source: adapted, adaptations: [`title: ${title}`] };
    };
    exports.adaptTitle = adaptTitle;
    const renderToResult = (renderer, isDraft, printType, target) => {
        const pdfFile = renderer.renderAsPdf();
        return {
            mode: isDraft ? 'draft' : 'saved', printType, record: target, pdf: pdfFile.getContents(), pdfBytes: pdfFile.size, xml: renderer.renderAsString(),
        };
    };
    const withExtras = (result, extras) => ({
        ...result,
        ...(extras.adaptations && extras.adaptations.length > 0 && { adaptations: extras.adaptations }),
        ...(extras.notes && extras.notes.length > 0 && { notes: extras.notes }),
    });
    // Accounts without subsidiaries (non-OneWorld) leave the field empty, so the root is skipped.
    const addSubsidiaryRoot = (renderer, owner) => {
        const subsidiaryId = owner.getValue({ fieldId: 'subsidiary' });
        if (subsidiaryId === '' || subsidiaryId === null || subsidiaryId === undefined)
            return;
        renderer.addRecord({ templateName: 'subsidiary', record: record.load({ type: record.Type.SUBSIDIARY, id: Number(subsidiaryId) }) });
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
    const requireSearchId = (value) => {
        const trimmed = typeof value === 'string' ? value.trim() : value;
        const searchId = typeof trimmed === 'string' && /^\d+$/.test(trimmed) ? Number(trimmed) : trimmed;
        if (typeof searchId === 'number' && Number.isInteger(searchId) && searchId > 0)
            return searchId;
        if (typeof searchId === 'string' && searchId !== '')
            return searchId;
        throw new index_js_1.ValidationError('searchId is required: a saved search internal id or script id (customsearch_…)');
    };
    const requireLimit = (value) => {
        if (value === undefined)
            return exports.SEARCH_DEFAULT_LIMIT;
        const limit = typeof value === 'string' && /^\d+$/.test(value) ? Number(value) : value;
        if (typeof limit === 'number' && Number.isInteger(limit) && limit >= 1 && limit <= exports.SEARCH_MAX_LIMIT)
            return limit;
        throw new index_js_1.ValidationError(`limit must be a whole number from 1 to ${exports.SEARCH_MAX_LIMIT}, got ${JSON.stringify(value)}`);
    };
    const requireResultsAlias = (value) => {
        if (value === undefined)
            return 'results';
        if (typeof value === 'string' && /^[A-Za-z_][A-Za-z0-9_]*$/.test(value))
            return value;
        throw new index_js_1.ValidationError(`resultsAlias must be a FreeMarker name like results, got ${JSON.stringify(value)}`);
    };
    // Only JSON true: a "true" string or a false would otherwise switch modes silently.
    const requireNative = (value) => {
        if (value !== true)
            throw new index_js_1.ValidationError(exports.NATIVE_REFUSAL);
        return value;
    };
    const rejectTemplateWithNative = (request) => {
        if (['templateId', 'scriptId', 'source'].some((key) => key in request))
            throw new index_js_1.ValidationError(exports.NATIVE_TEMPLATE_REFUSAL);
    };
    const rejectNativeOnlyKeys = (request) => {
        if (NATIVE_ONLY_KEYS.some((key) => key in request))
            throw new index_js_1.ValidationError('formId, shipgroup and location are only for native: true');
    };
    const parseTemplateChoice = (request) => ('source' in request ? { source: requireSource(request.source) } : { ref: parseSavedTemplateRef(request) });
    const requirePackingSlipRecord = (value) => {
        const target = requireRecordRef(value);
        if (target.type !== 'itemfulfillment' && target.type !== 'salesorder') {
            throw new index_js_1.ValidationError('a packing slip prints an item fulfillment (or, approximately, a sales order); record.type must be itemfulfillment or salesorder');
        }
        return target;
    };
    const requireCreatedFrom = (fulfillmentId, createdFrom) => {
        const salesOrderId = Number(createdFrom);
        if (createdFrom === null || createdFrom === undefined || createdFrom === '' || !Number.isInteger(salesOrderId) || salesOrderId <= 0) {
            throw new index_js_1.ValidationError(`item fulfillment ${fulfillmentId} has no created-from sales order`);
        }
        return salesOrderId;
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
