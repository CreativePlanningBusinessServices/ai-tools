/**
 * @NApiVersion 2.1
 * @NScriptType Restlet
 * @NModuleScope SameAccount
 * Author: Creative Planning Business Services
 * Date: 10/16/2026
 * Version: 1.0
 * Description: Describe, render and back up advanced PDF/HTML templates over JSON. GET ?id= or
 *   ?scriptid= returns the template metadata plus its raw source; PUT backs the template's current
 *   source up to the File Cabinet; POST renders a saved or draft template to PDF plus merged XML/HTML against a
 *   transaction or any record type record.load accepts (custom records included), a statement, a saved search's
 *   results, a picking ticket, a packing slip or shipping, mailing and item labels (rows injected as literals); renders natively (a GL impact natively only) through a form (native: true); or renders raw
 *   BFO XML. Called by netsuite-cli
 *   via `restlet call`; contract in the netsuite-pdf-designer skill. See
 *   docs/superpowers/specs/2026-10-16-netsuite-pdf-designer-design.html.
 */
define(["require", "exports", "N/log", "../netsuite_modules/pdf-template/index.js"], function (require, exports, log, index_js_1) {
    "use strict";
    // Bodyless GET requests carry no Content-Type, so NetSuite can't serialize an object response —
    // return a JSON string (same contract as cp_file_cabinet_rl; restlet call parses it).
    const get = (params) => JSON.stringify(handle(() => (0, index_js_1.describeTemplate)((0, index_js_1.parseTemplateRef)(params))));
    const post = (body) => handle(() => {
        const rendered = (0, index_js_1.renderTemplate)(body);
        log.audit('template rendered', { mode: rendered.mode, printType: rendered.printType, record: rendered.record, pdfBytes: rendered.pdfBytes });
        return rendered;
    });
    const put = (body) => handle(() => {
        const backed = (0, index_js_1.backupTemplate)(body);
        log.audit('template backed up', { id: backed.id, scriptid: backed.scriptid, backup: backed.backup.id });
        return backed;
    });
    const handle = (operation) => {
        try {
            return operation();
        }
        catch (err) {
            if (err instanceof index_js_1.ValidationError)
                return { error: err.message };
            log.error('cp_pdf_template_rl error', err);
            return { error: err.message || String(err) };
        }
    };
    return { get, post, put };
});
