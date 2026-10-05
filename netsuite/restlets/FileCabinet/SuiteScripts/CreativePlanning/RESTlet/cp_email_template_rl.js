/**
 * @NApiVersion 2.1
 * @NScriptType Restlet
 * @NModuleScope SameAccount
 * Author: Creative Planning Business Services
 * Date: 10/05/2026
 * Version: 1.0
 * Description: Describe, preview, save and create scriptable email templates over JSON. GET ?id=
 *   returns the template record plus its body (File Cabinet file or inline content); POST renders
 *   a preview with render.mergeEmail against real records (a draft body is merged through a
 *   temporary private template); PUT saves (backing the previous body up to the File Cabinet first)
 *   or, without id, creates a template. Called by netsuite-cli via `restlet call`; contract in the
 *   netsuite-email-designer skill. See docs/superpowers/specs/2026-10-05-netsuite-email-designer-design.html.
 */
define(["require", "exports", "N/log", "../netsuite_modules/email-template/index.js"], function (require, exports, log, index_js_1) {
    "use strict";
    // Bodyless GET requests carry no Content-Type, so NetSuite can't serialize an object response —
    // return a JSON string (same contract as cp_file_cabinet_rl; restlet call parses it).
    const get = (params) => JSON.stringify(handle(() => (0, index_js_1.describeTemplate)(parseIdParam(params.id))));
    const post = (body) => handle(() => {
        const rendered = (0, index_js_1.renderTemplate)(body);
        log.audit('template rendered', { mode: rendered.mode, merged: rendered.merged, warning: rendered.warning ?? null });
        return rendered;
    });
    const put = (body) => handle(() => {
        const request = (0, index_js_1.parseJsonObject)(body);
        if (request.id !== undefined) {
            const saved = (0, index_js_1.saveTemplate)(request);
            log.audit('template saved', { id: saved.id, storage: saved.storage, backup: saved.backup?.id ?? null });
            return saved;
        }
        const created = (0, index_js_1.createTemplate)(request);
        log.audit('template created', { id: created.id, storage: created.storage, mediaItem: created.mediaItem?.id ?? null });
        return created;
    });
    const parseIdParam = (value) => {
        if (value === undefined || value === '')
            throw new index_js_1.ValidationError('id is required — GET ?id=<email template internal id>');
        if (!/^\d+$/.test(value)) {
            throw new index_js_1.ValidationError(`id must be a numeric internal id, got ${JSON.stringify(value)} — paste only the id, not the emailtemplate.nl URL`);
        }
        return Number(value);
    };
    const handle = (operation) => {
        try {
            return operation();
        }
        catch (err) {
            if (err instanceof index_js_1.ValidationError)
                return { error: err.message };
            log.error('cp_email_template_rl error', err);
            return { error: err.message || String(err) };
        }
    };
    return { get, post, put };
});
