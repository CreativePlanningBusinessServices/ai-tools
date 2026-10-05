define(["require", "exports", "N/log", "N/query", "N/record", "N/render", "../file-cabinet/index.js"], function (require, exports, log, query, record, render, index_js_1) {
    "use strict";
    Object.defineProperty(exports, "__esModule", { value: true });
    exports.formatStamp = exports.slugify = exports.parseJsonObject = exports.createTemplate = exports.saveTemplate = exports.renderTemplate = exports.describeTemplate = exports.RECORD_TYPES = exports.DEFAULT_TEMPLATE_FOLDER = exports.BACKUP_FOLDER = exports.ValidationError = void 0;
    Object.defineProperty(exports, "ValidationError", { enumerable: true, get: function () { return index_js_1.ValidationError; } });
    // emailtemplate field ids as SuiteScript sees them (REST shows the same fields in camelCase).
    // One place to adjust if sandbox QA proves one wrong.
    const FIELD = {
        name: 'name', scriptId: 'scriptid', recordType: 'recordtype', subject: 'subject',
        isInactive: 'isinactive', isPrivate: 'isprivate', usesMedia: 'usesmedia',
        mediaItem: 'mediaitem', content: 'content',
    };
    exports.BACKUP_FOLDER = '/SuiteScripts/CreativePlanning/email-template-backups';
    // The emailtemplate mediaitem field only accepts files from this system folder (sandbox-verified:
    // /Templates/E-mail Templates was rejected).
    exports.DEFAULT_TEMPLATE_FOLDER = '/Templates/Marketing Templates';
    exports.RECORD_TYPES = ['ENTITY', 'TRANSACTION', 'CUSTOM', 'CASE', 'EVENT'];
    // ============ Describe ============
    const describeTemplate = (templateId) => describeLoaded(templateId, loadTemplate(templateId));
    exports.describeTemplate = describeTemplate;
    const describeLoaded = (templateId, loaded) => {
        const usesMedia = isFlagTrue(loaded.getValue({ fieldId: FIELD.usesMedia }));
        const mediaItemId = Number(loaded.getValue({ fieldId: FIELD.mediaItem }) || 0);
        const storage = usesMedia && mediaItemId > 0 ? 'file' : 'inline';
        const media = storage === 'file' ? loadMediaFile(mediaItemId) : null;
        return {
            id: templateId,
            name: String(loaded.getValue({ fieldId: FIELD.name }) ?? ''),
            scriptid: stringOrNull(loaded.getValue({ fieldId: FIELD.scriptId })),
            recordType: stringOrNull(loaded.getValue({ fieldId: FIELD.recordType })),
            subject: String(loaded.getValue({ fieldId: FIELD.subject }) ?? ''),
            isInactive: Boolean(loaded.getValue({ fieldId: FIELD.isInactive })),
            isPrivate: Boolean(loaded.getValue({ fieldId: FIELD.isPrivate })),
            storage,
            mediaItem: media ? { id: media.id, name: media.name, path: media.path } : null,
            body: media ? media.contents : String(loaded.getValue({ fieldId: FIELD.content }) ?? ''),
            lastModifiedDate: lastModifiedDate(templateId),
        };
    };
    const loadTemplate = (templateId) => {
        try {
            return record.load({ type: record.Type.EMAIL_TEMPLATE, id: templateId });
        }
        catch (err) {
            throw new index_js_1.ValidationError(`no email template with id ${templateId}: ${errorMessage(err)}`);
        }
    };
    const loadMediaFile = (mediaItemId) => {
        let downloaded;
        try {
            downloaded = (0, index_js_1.downloadFile)(mediaItemId);
        }
        catch (err) {
            throw new index_js_1.ValidationError(`the template's media file (id ${mediaItemId}) could not be read: ${errorMessage(err)}`);
        }
        if (downloaded.contentsEncoding !== 'utf8') {
            throw new index_js_1.ValidationError(`the template's media file (id ${mediaItemId}) is not a text file (${downloaded.fileType})`);
        }
        return downloaded;
    };
    const lastModifiedDate = (templateId) => {
        const rows = query
            .runSuiteQL({ query: /* sql */ `SELECT lastmodifieddate FROM emailtemplate WHERE id = ?`, params: [templateId] })
            .asMappedResults();
        return rows.length > 0 ? rows[0].lastmodifieddate : null;
    };
    // ============ Render ============
    const RENDER_KEYS = ['templateId', 'body', 'subject', 'recordType', 'transactionId', 'entity', 'recipient', 'customRecord', 'supportCaseId'];
    const REF_KEYS = ['entity', 'recipient', 'customRecord'];
    const renderTemplate = (body) => {
        const request = asObject(body, RENDER_KEYS);
        const refs = parseMergeRefs(request);
        const isDraft = request.body !== undefined || request.subject !== undefined;
        if (!isDraft) {
            const templateId = requireId(request.templateId, 'templateId');
            const merged = render.mergeEmail({ templateId, ...refs });
            return { mode: 'saved', subject: merged.subject, body: merged.body, merged: refs };
        }
        return renderDraft(request, refs);
    };
    exports.renderTemplate = renderTemplate;
    const renderDraft = (request, refs) => {
        const source = request.templateId !== undefined ? (0, exports.describeTemplate)(requireId(request.templateId, 'templateId')) : null;
        if (request.body === undefined && source === null) {
            throw new index_js_1.ValidationError('a draft preview needs body, or templateId to take the saved body from');
        }
        const draftBody = request.body !== undefined ? requireNonEmptyString(request.body, 'body') : source.body;
        const draftSubject = request.subject !== undefined ? requireString(request.subject, 'subject') : (source?.subject ?? '');
        const recordType = request.recordType !== undefined ? requireRecordType(request.recordType) : (source?.recordType ?? 'TRANSACTION');
        // Inactive templates still merge (verified in sandbox), so the temporary record is flagged
        // inactive as well as private: a failed cleanup can never leave a sendable template behind.
        const temporaryId = saveNewTemplate({
            name: `Email Designer preview ${new Date().toISOString()}`,
            recordType, subject: draftSubject, content: draftBody, isPrivate: true, isInactive: true,
        });
        let warning;
        const merged = (() => {
            try {
                return render.mergeEmail({ templateId: temporaryId, ...refs });
            }
            finally {
                try {
                    record.delete({ type: record.Type.EMAIL_TEMPLATE, id: temporaryId });
                }
                catch (err) {
                    warning = `temporary template ${temporaryId} could not be deleted — remove it by hand: ${errorMessage(err)}`;
                    log.error('temporary email template not deleted', { id: temporaryId, error: errorMessage(err) });
                }
            }
        })();
        return { mode: 'draft', subject: merged.subject, body: merged.body, merged: refs, ...(warning ? { warning } : {}) };
    };
    const parseMergeRefs = (request) => {
        const refs = {};
        if (request.transactionId !== undefined)
            refs.transactionId = requireId(request.transactionId, 'transactionId');
        if (request.supportCaseId !== undefined)
            refs.supportCaseId = requireId(request.supportCaseId, 'supportCaseId');
        for (const key of REF_KEYS) {
            if (request[key] !== undefined)
                refs[key] = requireRecordRef(request[key], key);
        }
        if (Object.keys(refs).length === 0) {
            throw new index_js_1.ValidationError('pass at least one record to merge: transactionId, entity, recipient, customRecord or supportCaseId');
        }
        return refs;
    };
    const requireRecordRef = (value, name) => {
        if (typeof value !== 'object' || value === null || Array.isArray(value)) {
            throw new index_js_1.ValidationError(`${name} must be an object {type, id}`);
        }
        const candidate = value;
        if (typeof candidate.type !== 'string' || candidate.type === '') {
            throw new index_js_1.ValidationError(`${name}.type must be a record type string (e.g. "customer")`);
        }
        return { type: candidate.type, id: requireId(candidate.id, `${name}.id`) };
    };
    const saveNewTemplate = (template) => {
        const created = record.create({ type: record.Type.EMAIL_TEMPLATE });
        created.setValue({ fieldId: FIELD.name, value: template.name });
        created.setValue({ fieldId: FIELD.recordType, value: template.recordType });
        created.setValue({ fieldId: FIELD.subject, value: template.subject });
        created.setValue({ fieldId: FIELD.isPrivate, value: template.isPrivate === true });
        created.setValue({ fieldId: FIELD.isInactive, value: template.isInactive === true });
        if (template.mediaItemId !== undefined) {
            created.setValue({ fieldId: FIELD.usesMedia, value: 'T' });
            created.setValue({ fieldId: FIELD.mediaItem, value: template.mediaItemId });
        }
        else {
            created.setValue({ fieldId: FIELD.usesMedia, value: 'F' });
            created.setValue({ fieldId: FIELD.content, value: template.content ?? '' });
        }
        try {
            return created.save();
        }
        catch (err) {
            throw explainTemplateSaveError(err);
        }
    };
    // NetSuite validates the template's FreeMarker when the record is saved, against a model that has
    // the record-type hashes, companyInformation and preferences but no recipient or sender. The raw
    // error only says "evaluated to null or missing: ==> recipient"; name the fix.
    const explainTemplateSaveError = (err) => {
        const message = errorMessage(err);
        const missingRoot = /evaluated to null or missing[^=]*==>\s*(\w+)/.exec(message);
        if (!missingRoot)
            return err;
        return new index_js_1.ValidationError(`NetSuite could not save the template because its FreeMarker references "${missingRoot[1]}", which is not in scope when a template record is validated on save. ` +
            `Reference it null-safe — e.g. \${(recipient.firstName)!""} (the parentheses matter) — then retry. NetSuite said: ${message}`);
    };
    // ============ Save ============
    const SAVE_KEYS = ['id', 'body', 'subject', 'name', 'allowNoFields'];
    const SAVE_EDITABLE_KEYS = ['body', 'subject', 'name'];
    const saveTemplate = (body) => {
        const request = asObject(body, SAVE_KEYS);
        const templateId = requireId(request.id, 'id');
        if (!SAVE_EDITABLE_KEYS.some((key) => request[key] !== undefined)) {
            throw new index_js_1.ValidationError(`nothing to save — pass at least one of ${SAVE_EDITABLE_KEYS.join(', ')}`);
        }
        const loaded = loadTemplate(templateId);
        const current = describeLoaded(templateId, loaded);
        const warnings = [];
        let backup = null;
        let recordChanged = false;
        if (request.body !== undefined) {
            const nextBody = requireBody(request.body);
            if (nextBody === current.body) {
                warnings.push('body is identical to the saved body — nothing written, no backup taken');
            }
            else {
                if (!nextBody.includes('${')) {
                    if (current.body.includes('${') && request.allowNoFields !== true) {
                        throw new index_js_1.ValidationError('body removes every ${…} field the saved template has — pass "allowNoFields": true if that is intended');
                    }
                    warnings.push('body contains no ${…} fields — it will render the same for every record');
                }
                backup = writeBackup(current);
                if (current.mediaItem !== null) {
                    (0, index_js_1.editFile)({ id: current.mediaItem.id, contents: nextBody });
                }
                else {
                    loaded.setValue({ fieldId: FIELD.content, value: nextBody });
                    recordChanged = true;
                }
            }
        }
        if (request.subject !== undefined) {
            loaded.setValue({ fieldId: FIELD.subject, value: requireString(request.subject, 'subject') });
            recordChanged = true;
        }
        if (request.name !== undefined) {
            loaded.setValue({ fieldId: FIELD.name, value: requireNonEmptyString(request.name, 'name') });
            recordChanged = true;
        }
        if (recordChanged)
            loaded.save();
        return { ...(0, exports.describeTemplate)(templateId), backup, ...(warnings.length > 0 ? { warning: warnings.join('; ') } : {}) };
    };
    exports.saveTemplate = saveTemplate;
    // A shell pipeline that loses its input tends to hand over "null"; saving that destroys a template.
    const requireBody = (value) => {
        const text = requireNonEmptyString(value, 'body');
        if (text.trim() === 'null' || text.trim() === 'undefined') {
            throw new index_js_1.ValidationError(`body is the literal string "${text.trim()}" — the caller lost its input`);
        }
        return text;
    };
    const writeBackup = (current) => {
        const label = current.scriptid ?? ((0, exports.slugify)(current.name) || 'template');
        const created = (0, index_js_1.createFile)({
            path: `${exports.BACKUP_FOLDER}/${current.id}-${label}-${(0, exports.formatStamp)(new Date())}.html`,
            contents: current.body,
            description: `Email Designer backup of email template ${current.id} (${current.name})`,
        });
        return { id: created.id, path: created.path };
    };
    // ============ Create ============
    const CREATE_KEYS = ['name', 'recordType', 'subject', 'body', 'storage', 'folder'];
    const createTemplate = (body) => {
        const request = asObject(body, CREATE_KEYS);
        const name = requireNonEmptyString(request.name, 'name');
        const recordType = requireRecordType(request.recordType);
        const subject = requireString(request.subject, 'subject');
        const templateBody = requireNonEmptyString(request.body, 'body');
        const storage = request.storage === undefined ? 'inline' : request.storage;
        if (storage !== 'file' && storage !== 'inline')
            throw new index_js_1.ValidationError('storage must be "file" or "inline"');
        if (storage === 'inline' && request.folder !== undefined)
            throw new index_js_1.ValidationError('folder only applies to storage "file"');
        if (storage === 'inline') {
            return (0, exports.describeTemplate)(saveNewTemplate({ name, recordType, subject, content: templateBody }));
        }
        const created = (0, index_js_1.createFile)({
            folder: request.folder === undefined ? exports.DEFAULT_TEMPLATE_FOLDER : requireNonEmptyString(request.folder, 'folder'),
            name: `${(0, exports.slugify)(name) || 'email-template'}.html`,
            contents: templateBody,
        });
        try {
            return (0, exports.describeTemplate)(saveNewTemplate({ name, recordType, subject, mediaItemId: created.id }));
        }
        catch (err) {
            (0, index_js_1.deleteFile)(created.id, undefined);
            throw err;
        }
    };
    exports.createTemplate = createTemplate;
    // ============ Request parsing helpers ============
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
    const requireId = (value, name) => {
        if (typeof value === 'number' && Number.isInteger(value) && value > 0)
            return value;
        if (typeof value === 'string' && /^\d+$/.test(value))
            return Number(value);
        throw new index_js_1.ValidationError(`${name} must be a positive integer internal id, got ${JSON.stringify(value)}`);
    };
    const requireString = (value, name) => {
        if (typeof value !== 'string')
            throw new index_js_1.ValidationError(`${name} must be a string`);
        return value;
    };
    const requireNonEmptyString = (value, name) => {
        const text = requireString(value, name);
        if (text.trim() === '')
            throw new index_js_1.ValidationError(`${name} must not be empty`);
        return text;
    };
    const requireRecordType = (value) => {
        const normalized = typeof value === 'string' ? value.toUpperCase() : '';
        if (exports.RECORD_TYPES.includes(normalized))
            return normalized;
        throw new index_js_1.ValidationError(`recordType must be one of ${exports.RECORD_TYPES.join(', ')}`);
    };
    // usesmedia is a T/F select (File vs Text Editor), not a checkbox: NetSuite rejects a boolean on
    // save and returns the string on read.
    const isFlagTrue = (value) => value === true || value === 'T';
    const stringOrNull = (value) => value === null || value === undefined || value === '' ? null : String(value);
    const errorMessage = (err) => err.message || String(err);
    const slugify = (text) => text.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 60);
    exports.slugify = slugify;
    const formatStamp = (date) => {
        const pad = (part) => String(part).padStart(2, '0');
        return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}-${pad(date.getHours())}${pad(date.getMinutes())}${pad(date.getSeconds())}`;
    };
    exports.formatStamp = formatStamp;
});
