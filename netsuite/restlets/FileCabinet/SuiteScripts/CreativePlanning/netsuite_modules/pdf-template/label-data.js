define(["require", "exports", "N/query", "../file-cabinet/index.js"], function (require, exports, query, index_js_1) {
    "use strict";
    Object.defineProperty(exports, "__esModule", { value: true });
    exports.toFreemarkerString = exports.loadLabelRows = exports.injectLabels = exports.parseLabelInput = exports.LABEL_BARCODE_NOTE = exports.LABEL_BODY_REFUSAL = exports.LABEL_RECORDS_REFUSAL = exports.LABEL_CAPTIONS = exports.LABEL_ID_KEYS = exports.LABEL_MAX_ROWS = exports.LABEL_PRINT_TYPES = void 0;
    exports.LABEL_PRINT_TYPES = ['SHIPPINGLABEL', 'MAILINGLABEL', 'ITEMLABEL'];
    exports.LABEL_MAX_ROWS = 100;
    exports.LABEL_ID_KEYS = {
        SHIPPINGLABEL: 'transactionIds',
        MAILINGLABEL: 'entityIds',
        ITEMLABEL: 'itemIds',
    };
    // Guesses until compared with a label printed from the NetSuite UI: custom data has nothing behind @label.
    exports.LABEL_CAPTIONS = {
        refNumber: 'Ref #', shipAddress: 'Ship To', address: 'Address', price: 'Price', upc: 'UPC', id: 'Item',
    };
    exports.LABEL_RECORDS_REFUSAL = 'this template never reads records, so label rows would not show — a label template lays out records[…] (start from a standard label template)';
    exports.LABEL_BODY_REFUSAL = 'a label template needs a <body> tag to receive the label rows';
    exports.LABEL_BARCODE_NOTE = 'numeric UPC/EAN codes print as Code 128 barcodes in this preview; NetSuite prints them as UPC-A or EAN-13';
    // The fields each standard label template reads, in the order they're injected.
    const LABEL_FIELDS = {
        SHIPPINGLABEL: { refNumber: 'count', shipAddress: 'text' },
        MAILINGLABEL: { address: 'text' },
        ITEMLABEL: { id: 'text', price: 'text', upc: 'flag', serialnumber: 'text', skuUpcBarcode: 'text' },
    };
    const FIELD_DEFAULTS = { text: '', count: 0, flag: false };
    const parseLabelInput = (printType, request) => {
        const idKey = exports.LABEL_ID_KEYS[printType];
        const hasIds = request[idKey] !== undefined;
        if (hasIds === (request.labels !== undefined))
            throw new index_js_1.ValidationError(`pass exactly one of ${idKey} or labels`);
        const startLabel = requireStartLabel(request.startLabel);
        return hasIds
            ? { ids: requireIds(idKey, request[idKey]), rows: null, startLabel }
            : { ids: null, rows: requireLabelRows(printType, idKey, request.labels), startLabel };
    };
    exports.parseLabelInput = parseLabelInput;
    const injectLabels = (source, rows, startLabel) => {
        if (!readsRecords(source))
            throw new index_js_1.ValidationError(exports.LABEL_RECORDS_REFUSAL);
        const bodyTag = /<body\b[^>]*>/i.exec(source);
        if (bodyTag === null)
            throw new index_js_1.ValidationError(exports.LABEL_BODY_REFUSAL);
        const assigns = `<#assign records = [${rows.map(toFreemarkerHash).join(', ')}]><#assign startlabel = ${startLabel}>`;
        const insertAt = bodyTag.index + bodyTag[0].length;
        const injected = source.slice(0, insertAt) + assigns + source.slice(insertAt);
        const captioned = replaceCaptions(injected);
        return {
            source: captioned.source,
            adaptations: [
                `injected ${rows.length} label rows, startlabel ${startLabel}`,
                ...(captioned.fields.length > 0 ? [`captions: ${captioned.fields.join(', ')}`] : []),
            ],
        };
    };
    exports.injectLabels = injectLabels;
    // One query per request; rows come back in the caller's id order, a repeated id once per mention.
    const loadLabelRows = (printType, ids) => {
        const distinctIds = [...new Set(ids)];
        const placeholders = distinctIds.map(() => '?').join(', ');
        const loadRows = printType === 'SHIPPINGLABEL' ? loadShippingLabels : printType === 'MAILINGLABEL' ? loadMailingLabels : loadItemLabels;
        const loaded = loadRows(distinctIds, placeholders);
        const missing = distinctIds.filter((id) => !loaded.has(id));
        if (missing.length > 0)
            throw new index_js_1.ValidationError(`no ${LABEL_RECORD_NOUNS[printType]} with id(s) ${missing.join(', ')}`);
        return ids.map((id) => loaded.get(id));
    };
    exports.loadLabelRows = loadLabelRows;
    const LABEL_RECORD_NOUNS = {
        SHIPPINGLABEL: 'transaction',
        MAILINGLABEL: 'customer, vendor or contact',
        ITEMLABEL: 'item',
    };
    // NetSuite's own print showed no ref line for invoices, cash sales or orders, even with a numeric PO # (SB2,
    // 2026-10-26), and what feeds refNumber is unknown, so loaded rows leave it at 0; synthetic labels can set it.
    const loadShippingLabels = (ids, placeholders) => {
        const rows = query.runSuiteQL({
            query: /* sql */ `
      SELECT txn.id, address.addrtext AS shipaddress
      FROM transaction txn
      LEFT JOIN transactionshippingaddress address ON address.nkey = txn.shippingaddress
      WHERE txn.id IN (${placeholders})`,
            params: ids,
        }).asMappedResults();
        return new Map(rows.map((row) => [Number(row.id), { refNumber: 0, shipAddress: row.shipaddress ?? '' }]));
    };
    // The generic entity table fails this join (SB2, 2026-10-26), so each addressable entity type is queried in turn.
    const loadMailingLabels = (ids, placeholders) => {
        const rows = query.runSuiteQL({
            query: /* sql */ `
      SELECT customer.id, address.addrtext AS address
      FROM customer LEFT JOIN entityaddress address ON address.nkey = customer.defaultbillingaddress
      WHERE customer.id IN (${placeholders})
      UNION ALL
      SELECT vendor.id, address.addrtext
      FROM vendor LEFT JOIN entityaddress address ON address.nkey = vendor.defaultbillingaddress
      WHERE vendor.id IN (${placeholders})
      UNION ALL
      SELECT contact.id, address.addrtext
      FROM contact LEFT JOIN entityaddress address ON address.nkey = contact.defaultbillingaddress
      WHERE contact.id IN (${placeholders})`,
            params: [...ids, ...ids, ...ids],
        }).asMappedResults();
        return new Map(rows.map((row) => [Number(row.id), { address: row.address ?? '' }]));
    };
    const loadItemLabels = (ids, placeholders) => {
        const rows = query.runSuiteQL({
            query: /* sql */ `
      SELECT item.id, item.itemid, NVL(item.upccode, item.itemid) AS skuupcbarcode,
        CASE WHEN LENGTH(item.upccode) = 12 THEN 'T' ELSE 'F' END AS isupca,
        TO_CHAR(pricing.unitprice, 'FM999,999,990.00') AS price
      FROM item
      LEFT JOIN pricing ON pricing.item = item.id AND pricing.pricelevel = 1 AND pricing.quantity = 1
        AND pricing.currency = (SELECT id FROM currency WHERE isbasecurrency = 'T')
      WHERE item.id IN (${placeholders})`,
            params: ids,
        }).asMappedResults();
        return new Map(rows.map((row) => [Number(row.id), {
                id: row.itemid, price: row.price ?? '', upc: row.isupca === 'T', serialnumber: '', skuUpcBarcode: row.skuupcbarcode,
            }]));
    };
    // \{ keeps a value like "${x}" from interpolating; FreeMarker prints it as "${x}".
    const toFreemarkerString = (text) => `"${text.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\{/g, '\\{')}"`;
    exports.toFreemarkerString = toFreemarkerString;
    const toFreemarkerHash = (row) => `{${Object.entries(row).map(([field, value]) => `${(0, exports.toFreemarkerString)(field)}: ${toFreemarkerValue(value)}`).join(', ')}}`;
    const toFreemarkerValue = (value) => (typeof value === 'string' ? (0, exports.toFreemarkerString)(toLabelMarkup(value)) : String(value));
    // Record addresses render with <br /> between lines, and data is never markup.
    const toLabelMarkup = (text) => text
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;')
        .replace(/\r\n|\n|\r/g, '<br />');
    const readsRecords = (source) => (source.match(/\$\{[^}]*\}|<#[^>]*>/g) ?? []).some((code) => /\brecords\b/.test(code));
    const replaceCaptions = (source) => {
        const fields = [];
        const replaced = source.replace(/\$\{\s*label\.(\w+)@label\s*\}/g, (match, field) => {
            if (!fields.includes(field))
                fields.push(field);
            return exports.LABEL_CAPTIONS[field] ?? field;
        });
        return { source: replaced, fields };
    };
    const requireStartLabel = (value) => {
        if (value === undefined)
            return 1;
        const startLabel = typeof value === 'string' && /^\d+$/.test(value) ? Number(value) : value;
        if (typeof startLabel === 'number' && Number.isInteger(startLabel) && startLabel >= 1)
            return startLabel;
        throw new index_js_1.ValidationError(`startLabel must be a whole number of 1 or more, got ${JSON.stringify(value)}`);
    };
    const requireIds = (idKey, value) => {
        if (!Array.isArray(value))
            throw new index_js_1.ValidationError(`${idKey} must be a list of ids`);
        if (value.length === 0)
            throw new index_js_1.ValidationError(`${idKey} must list at least one id`);
        if (value.length > exports.LABEL_MAX_ROWS)
            throw new index_js_1.ValidationError(`at most ${exports.LABEL_MAX_ROWS} ${idKey} or labels per preview`);
        return value.map((id, index) => {
            if (typeof id === 'number' && Number.isInteger(id) && id > 0)
                return id;
            if (typeof id === 'string' && /^\d+$/.test(id))
                return Number(id);
            throw new index_js_1.ValidationError(`${idKey}[${index}] must be a numeric internal id, got ${JSON.stringify(id)}`);
        });
    };
    const requireLabelRows = (printType, idKey, value) => {
        if (!Array.isArray(value))
            throw new index_js_1.ValidationError('labels must be a list of label objects');
        if (value.length === 0)
            throw new index_js_1.ValidationError('labels must list at least one label');
        if (value.length > exports.LABEL_MAX_ROWS)
            throw new index_js_1.ValidationError(`at most ${exports.LABEL_MAX_ROWS} ${idKey} or labels per preview`);
        return value.map((row, index) => requireLabelRow(printType, row, index));
    };
    const requireLabelRow = (printType, value, index) => {
        if (typeof value !== 'object' || value === null || Array.isArray(value))
            throw new index_js_1.ValidationError(`labels[${index}] must be an object`);
        const supplied = value;
        const fields = LABEL_FIELDS[printType];
        const unknownFields = Object.keys(supplied).filter((field) => !(field in fields));
        if (unknownFields.length > 0) {
            throw new index_js_1.ValidationError(`labels[${index}] has unknown field(s): ${unknownFields.join(', ')} — ${printType} labels take: ${Object.keys(fields).join(', ')}`);
        }
        const row = {};
        for (const [field, kind] of Object.entries(fields)) {
            row[field] = supplied[field] === undefined ? FIELD_DEFAULTS[kind] : requireFieldValue(kind, supplied[field], `labels[${index}].${field}`);
        }
        if (printType === 'ITEMLABEL' && supplied.skuUpcBarcode === undefined)
            row.skuUpcBarcode = row.id;
        return row;
    };
    const requireFieldValue = (kind, value, name) => {
        if (kind === 'count' && typeof value === 'number' && Number.isInteger(value) && value >= 0)
            return value;
        if (kind === 'flag' && typeof value === 'boolean')
            return value;
        if (kind === 'text' && typeof value === 'string')
            return value;
        const expected = { count: 'a whole number of 0 or more', flag: 'true or false', text: 'text' }[kind];
        throw new index_js_1.ValidationError(`${name} must be ${expected}`);
    };
});
