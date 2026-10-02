/**
 * @NApiVersion 2.1
 * @NScriptType Restlet
 * @NModuleScope SameAccount
 * Author: Jon Lamb
 * Date: 08/10/2026
 * Version: 1.0
 * Description: Describe, download, list, create, edit and delete File Cabinet files over JSON —
 *   NetSuite's REST API has no file-content support. Primarily called by netsuite-cli via
 *   `restlet call`. Contract: GET ?id=|path= describes; &contents=T downloads; ?folder= lists;
 *   POST creates (overwrite-guarded); PUT patches (contents/name/folder/description/flags);
 *   DELETE removes a file. See docs/superpowers/specs/2026-08-10-file-cabinet-restlet-design.html.
 */
define(["require", "exports", "N/log", "../netsuite_modules/file-cabinet/index.js"], function (require, exports, log, index_js_1) {
    "use strict";
    // NetSuite picks a RESTlet response's serialization from the REQUEST's Content-Type header.
    // Bodyless GET/DELETE calls (how netsuite-cli issues them) carry none, so returning an object
    // fails at platform serialization. Returning a JSON string sidesteps that — same contract as
    // cp_saved_search_rl; JSON-parsing callers see the identical object.
    const get = (params) => JSON.stringify(handle(() => {
        if (isPresent(params.folder)) {
            rejectFileParamsOnList(params);
            return (0, index_js_1.listFolder)(params.folder, params.nameContains);
        }
        if (isPresent(params.nameContains)) {
            throw new index_js_1.ValidationError('nameContains is only valid on a list call — add folder= or remove it');
        }
        const fileId = (0, index_js_1.resolveFileId)(emptyToUndefined(params.id), emptyToUndefined(params.path));
        return isFlagSet(params.contents, 'contents') ? (0, index_js_1.downloadFile)(fileId) : (0, index_js_1.describeFile)(fileId);
    }));
    const post = (body) => handle(() => {
        const created = (0, index_js_1.createFile)(body);
        log.audit('file created', { id: created.id, path: created.path, size: created.size });
        return created;
    });
    const put = (body) => handle(() => {
        const edited = (0, index_js_1.editFile)(body);
        log.audit('file edited', { id: edited.id, path: edited.path, size: edited.size });
        return edited;
    });
    const deleteEntryPoint = (params) => JSON.stringify(handle(() => {
        const result = (0, index_js_1.deleteFile)(emptyToUndefined(params.id), emptyToUndefined(params.path));
        log.audit('file deleted', { id: result.id, path: result.path });
        return result;
    }));
    const rejectFileParamsOnList = (params) => {
        for (const name of ['id', 'path', 'contents']) {
            if (isPresent(params[name])) {
                throw new index_js_1.ValidationError(`${name} is not valid on a list call — a GET is either a file operation (id/path) or a list (folder), not both`);
            }
        }
    };
    // Empty/absent means unset; "T"/"true" (either case) means set; anything else is a caller typo
    // that must not silently fall back — same rule as cp_saved_search_rl's run=.
    const isFlagSet = (value, name) => {
        if (value === undefined || value === '')
            return false;
        const normalized = value.toLowerCase();
        if (normalized === 't' || normalized === 'true')
            return true;
        throw new index_js_1.ValidationError(`${name} must be "T" or "true" (case-insensitive), got ${JSON.stringify(value)}`);
    };
    const isPresent = (value) => value !== undefined && value !== '';
    const emptyToUndefined = (value) => (value === '' ? undefined : value);
    const handle = (operation) => {
        try {
            return operation();
        }
        catch (err) {
            if (err instanceof index_js_1.ValidationError)
                return { error: err.message };
            log.error('cp_file_cabinet_rl error', err);
            return { error: err.message || String(err) };
        }
    };
    return { get, post, put, delete: deleteEntryPoint };
});
