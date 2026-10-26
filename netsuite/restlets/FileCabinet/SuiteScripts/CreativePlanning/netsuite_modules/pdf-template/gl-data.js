define(["require", "exports", "N/query", "../file-cabinet/index.js", "./freemarker-literal.js"], function (require, exports, query, index_js_1, freemarker_literal_js_1) {
    "use strict";
    Object.defineProperty(exports, "__esModule", { value: true });
    exports.loadGlImpactData = exports.injectGlImpact = exports.GL_IMPACT_FIELD_CAPTIONS = exports.GL_IMPACT_LABELS = exports.GL_IMPACT_BODY_REFUSAL = void 0;
    exports.GL_IMPACT_BODY_REFUSAL = 'a GL impact template needs a <body> tag to receive the GL data';
    // The captions NetSuite's own GL impact print shows (SB2, 2026-10-26); noLinesMessage is a guess (never printed).
    exports.GL_IMPACT_LABELS = {
        title: 'GL Impact',
        postingPeriod: 'Posting Period',
        transactionType: 'Transaction Type',
        rowNumber: 'Row Number',
        subsidiary: 'Subsidiary',
        transactionCurrency: 'Transaction Currency',
        baseCurrency: 'Base Currency',
        debit: 'Debit',
        credit: 'Credit',
        total: 'Total',
        noLinesMessage: 'No GL impact lines',
    };
    // `${record.X@label}` / `line.X@label` have nothing behind them on injected data, so these replace them in the source.
    exports.GL_IMPACT_FIELD_CAPTIONS = {
        trandate: 'Date',
        tranid: 'Document Number',
        exchangerate: 'Exchange Rate',
        linefxrate: 'Exchange Rate',
        account: 'Account',
        accountingtransaction_account: 'Account',
        memo: 'Memo',
    };
    // Injected amounts must stay numbers for the template's sums, so its line-amount interpolations are rewritten to
    // print as NetSuite does (currency, blank when 0); amounts a custom template prints under other names stay plain.
    const LINE_AMOUNT_CURRENCIES = {
        'line.debitfxamount': 'record.transaction_currency_iso',
        'line.creditfxamount': 'record.transaction_currency_iso',
        line_debitamount: 'record.base_currency_iso',
        line_creditamount: 'record.base_currency_iso',
    };
    const injectGlImpact = (source, data) => {
        const options = { autoEscapes: (0, freemarker_literal_js_1.templateAutoEscapes)(source), breakLines: () => false };
        const assigns = `<#assign record = ${(0, freemarker_literal_js_1.toFreemarkerLiteral)(data.record, options)}><#assign label = ${(0, freemarker_literal_js_1.toFreemarkerLiteral)(data.label, options)}>`;
        const injected = (0, freemarker_literal_js_1.injectAfterBody)(source, assigns, exports.GL_IMPACT_BODY_REFUSAL);
        const captioned = replaceFieldCaptions(injected);
        const formatted = formatLineAmounts(captioned.source);
        const lineCount = Array.isArray(data.record.line) ? data.record.line.length : 0;
        return {
            source: formatted.source,
            adaptations: [
                `injected GL impact data: ${lineCount} lines`,
                ...(captioned.fields.length > 0 ? [`captions: ${captioned.fields.join(', ')}`] : []),
                ...(formatted.changed ? ['line amounts formatted'] : []),
            ],
        };
    };
    exports.injectGlImpact = injectGlImpact;
    const replaceFieldCaptions = (source) => {
        const fields = [];
        const caption = (field) => {
            if (!fields.includes(field))
                fields.push(field);
            return exports.GL_IMPACT_FIELD_CAPTIONS[field] ?? field;
        };
        // One pass keeps the fields in source order: ${x.f@label} prints the caption, a bare x.f@label (in a directive) becomes a string.
        const replaced = source.replace(/\$\{\s*(?:record|line)\.(\w+)@label\s*\}|\b(?:record|line)\.(\w+)@label\b/g, (match, interpolated, bare) => (interpolated === undefined
            ? JSON.stringify(caption(String(bare)))
            : caption(interpolated)));
        return { source: replaced, fields };
    };
    const formatLineAmounts = (source) => {
        const formatted = source.replace(/\$\{\s*(line\.debitfxamount|line\.creditfxamount|line_debitamount|line_creditamount)\s*\}/g, (match, amount) => `<#if ${amount} != 0>\${nsformat_currency(${amount}, ${LINE_AMOUNT_CURRENCIES[amount]})}</#if>`);
        return { source: formatted, changed: formatted !== source };
    };
    // Base and transaction currency are the same here: SB2 has no foreign-currency transactions to build the other from.
    const loadGlImpactData = (transactionId) => {
        const header = loadHeader(transactionId);
        const currency = header.currencyiso ?? '';
        return {
            record: {
                trandate: header.trandate,
                postingperiod: header.postingperiod ?? '',
                type: header.typename ?? '',
                typeid: header.type,
                tranid: header.tranid ?? '',
                subsidiary: header.subsidiary === null ? '' : String(header.subsidiary),
                exchangerate: header.exchangerate ?? '',
                currency,
                basecurrency: currency,
                transaction_currency_iso: currency,
                base_currency_iso: currency,
                line: loadLines(transactionId).map((line) => toTemplateLine(line, currency)),
            },
            label: exports.GL_IMPACT_LABELS,
        };
    };
    exports.loadGlImpactData = loadGlImpactData;
    const loadHeader = (transactionId) => {
        const rows = query.runSuiteQL({
            query: /* sql */ `
      SELECT txn.trandate, BUILTIN.DF(txn.postingperiod) AS postingperiod, BUILTIN.DF(txn.type) AS typename, txn.type,
        txn.tranid,
        (SELECT MAX(mainLine.subsidiary) FROM transactionline mainLine WHERE mainLine.transaction = txn.id AND mainLine.mainline = 'T') AS subsidiary,
        TO_CHAR(txn.exchangerate, 'FM999990.00') AS exchangerate,
        BUILTIN.DF(txn.currency) AS currencyiso
      FROM transaction txn
      WHERE txn.id = ?`,
            params: [transactionId],
        }).asMappedResults();
        if (rows.length === 0)
            throw new index_js_1.ValidationError(`no transaction with id ${transactionId}`);
        return rows[0];
    };
    const loadLines = (transactionId) => query.runSuiteQL({
        query: /* sql */ `
    SELECT CASE WHEN account.acctnumber IS NULL THEN account.fullname ELSE account.acctnumber || ' ' || account.fullname END AS accountname,
      BUILTIN.DF(accountingLine.accountingbook) AS accountingbook,
      NVL(accountingLine.debit, 0) AS debit, NVL(accountingLine.credit, 0) AS credit,
      line.memo, BUILTIN.DF(line.subsidiary) AS subsidiary
    FROM transactionaccountingline accountingLine
    JOIN transactionline line ON line.transaction = accountingLine.transaction AND line.id = accountingLine.transactionline
    JOIN account ON account.id = accountingLine.account
    WHERE accountingLine.transaction = ?
      AND accountingLine.accountingbook = (SELECT id FROM accountingbook WHERE isprimary = 'T')
    ORDER BY accountingLine.transactionline`,
        params: [transactionId],
    }).asMappedResults();
    const toTemplateLine = (line, currency) => {
        const debit = Number(line.debit);
        const credit = Number(line.credit);
        const accountingBook = line.accountingbook ?? '';
        return {
            account: line.accountname,
            accountingbook: accountingBook,
            debitamount: debit,
            creditamount: credit,
            debitfxamount: debit,
            creditfxamount: credit,
            memo: line.memo ?? '',
            currency,
            linefxrate: '',
            subsidiarynohierarchy: line.subsidiary ?? '',
            subsidiary_currency: currency,
            accountingtransaction_account: line.accountname,
            accountingtransaction_accountingbook: accountingBook,
            accountingtransaction_debitamount: debit,
            accountingtransaction_creditamount: credit,
        };
    };
});
