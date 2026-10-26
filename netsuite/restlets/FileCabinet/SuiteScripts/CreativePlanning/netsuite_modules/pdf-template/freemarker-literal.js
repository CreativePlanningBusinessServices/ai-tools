define(["require", "exports", "../file-cabinet/index.js"], function (require, exports, index_js_1) {
    "use strict";
    Object.defineProperty(exports, "__esModule", { value: true });
    exports.injectAfterBody = exports.templateAutoEscapes = exports.toFreemarkerString = exports.toFreemarkerLiteral = void 0;
    const toFreemarkerLiteral = (value, options, field = '') => {
        if (typeof value === 'string')
            return (0, exports.toFreemarkerString)(toTemplateText(value, options, field));
        if (typeof value === 'number' || typeof value === 'boolean')
            return String(value);
        if (Array.isArray(value))
            return `[${value.map((item) => (0, exports.toFreemarkerLiteral)(item, options, field)).join(', ')}]`;
        return `{${Object.entries(value)
            .map(([key, item]) => `${(0, exports.toFreemarkerString)(key)}: ${(0, exports.toFreemarkerLiteral)(item, options, key)}`)
            .join(', ')}}`;
    };
    exports.toFreemarkerLiteral = toFreemarkerLiteral;
    // \{ keeps a value like "${x}" from interpolating; FreeMarker prints it as "${x}".
    const toFreemarkerString = (text) => `"${text.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\{/g, '\\{')}"`;
    exports.toFreemarkerString = toFreemarkerString;
    // An <#ftl output_format=…> header auto-escapes unless it says auto_esc=false: NetSuite's item label (26) does,
    // its shipping and mailing labels (23, 25) don't.
    const templateAutoEscapes = (source) => {
        const header = /^\s*<#ftl\b([^>]*)>/.exec(source);
        if (header === null)
            return false;
        return /\boutput_format\s*=\s*"(XML|HTML|XHTML)"/i.test(header[1]) && !/\bauto_esc\s*=\s*false\b/.test(header[1]);
    };
    exports.templateAutoEscapes = templateAutoEscapes;
    const injectAfterBody = (source, assigns, missingBodyRefusal) => {
        const bodyTag = /<body\b[^>]*>/i.exec(source);
        if (bodyTag === null)
            throw new index_js_1.ValidationError(missingBodyRefusal);
        const insertAt = bodyTag.index + bodyTag[0].length;
        return source.slice(0, insertAt) + assigns + source.slice(insertAt);
    };
    exports.injectAfterBody = injectAfterBody;
    // Data is never markup. An auto-escaping template escapes it on output, so escaping here would show "&amp;".
    // Only fields the caller names break lines; others can sit in attributes (template 26's barcodes).
    const toTemplateText = (text, options, field) => {
        const escaped = options.autoEscapes ? text : text
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
        const lineBreak = options.breakLines(field) && !options.autoEscapes ? '<br />' : ' ';
        return escaped.replace(/\r\n|\n|\r/g, lineBreak);
    };
});
