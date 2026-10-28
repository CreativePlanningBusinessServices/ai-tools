define(["require", "exports", "N/format", "N/query", "N/runtime", "../file-cabinet/index.js"], function (require, exports, format, query, runtime, index_js_1) {
    "use strict";
    Object.defineProperty(exports, "__esModule", { value: true });
    exports.parseStatementPeriod = exports.buildDraftStatement = void 0;
    const BODY_FIELD_PATTERN = /^custbody_[a-z0-9_]+$/;
    const DRAFT_DATA_ALIAS = 'cpDraftStatement';
    const BARE_STATEMENTS = /(?<![\w.])statements(?!\w)/;
    const STRING_LITERAL = /("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/;
    const CONSTRUCT_OPENER = /<#--|<\/?#|<\/?@|\[\/?[#@]|\$\{/g;
    const CONSTRUCT_CLOSERS = { directive: '>', macro: '>', squareTag: ']', interpolation: '}' };
    const DRAFT_NOT_SUPPORTED = "draft preview isn't supported — use a saved render through a statement form (formId)";
    const STATEMENT_LABELS = {
        amountDue: 'Amount Due', billaddress: 'Billing Address', agingbal: 'Amount Due',
        aging1: 'Current', aging2: '1-30 Days', aging3: '31-60 Days', aging4: '61-90 Days', aging5: 'Over 90 Days',
    };
    const LINE_LABELS = {
        datecol: 'Date', description: 'Description', charge: 'Charge', payment: 'Payment', balance: 'Balance',
    };
    /**
     * Rebuilds the `statements` data NetSuite's statement engine would hand a statement template, from
     * SuiteQL. Single currency (the customer's), approximate: open amounts are as of today, not as of
     * statementDate, and same-day transactions are ordered by internal id.
     */
    const buildDraftStatement = (options) => {
        const period = (0, exports.parseStatementPeriod)(options);
        const statementDate = period.statementDate ?? today();
        const { startDate } = period;
        const references = findTemplateReferences(options.source);
        const { source: templateSource, adaptations } = adaptSourceToDraftData(options.source, references);
        const customer = loadCustomer(options.entityId);
        const filter = {
            entityId: options.entityId,
            currencyId: customer.currency,
            statementDate,
            startDate,
            openOnly: period.openTransactionsOnly === true,
            bodyFields: existingBodyFields(references.linePaths),
        };
        const currency = { symbol: customer.currencysymbol ?? '', symbolAfter: Number(customer.symbolplacement) === 2 };
        const money = (value) => formatMoney(Number(value ?? 0), currency);
        const summary = loadSummary(filter);
        const lines = loadLines(filter).map((row) => toTemplateLine(row, filter.bodyFields, money));
        if (startDate !== null) {
            lines.unshift({ datecol: startDate.display, duedate: '', description: 'Balance Forward', charge: '', payment: '', balance: money(summary.openingbalance) });
        }
        const statement = {
            trandate: statementDate.display,
            billaddress: escapeXml(customer.billaddress ?? '').replace(/\r?\n/g, '<br />'),
            amountDue: money(summary.amountdue),
            agingbal: money(summary.agingbal),
            aging1: money(summary.aging1),
            aging2: money(summary.aging2),
            aging3: money(summary.aging3),
            aging4: money(summary.aging4),
            aging5: money(summary.aging5),
            lines,
        };
        for (const path of references.statementPaths)
            fillPath(statement, path);
        for (const line of lines)
            for (const path of references.linePaths)
                fillPath(line, path);
        return { templateSource, adaptations, dataSource: { alias: DRAFT_DATA_ALIAS, data: { statements: [statement] } } };
    };
    exports.buildDraftStatement = buildDraftStatement;
    /** The statement options saved and draft renders share, validated the same way for both. */
    const parseStatementPeriod = (options) => {
        const statementDate = parseStatementDate(options.statementDate, 'statementDate');
        const startDate = parseStatementDate(options.startDate, 'startDate');
        const effectiveStatementDate = statementDate ?? today();
        if (startDate !== null && startDate.iso > effectiveStatementDate.iso) {
            throw new index_js_1.ValidationError(`startDate must not be after statementDate (${startDate.display} > ${effectiveStatementDate.display})`);
        }
        const { openTransactionsOnly } = options;
        if (openTransactionsOnly !== undefined && openTransactionsOnly !== null && typeof openTransactionsOnly !== 'boolean') {
            throw new index_js_1.ValidationError(`openTransactionsOnly must be true or false — got ${JSON.stringify(openTransactionsOnly)}`);
        }
        return { statementDate, startDate, openTransactionsOnly: openTransactionsOnly ?? null };
    };
    exports.parseStatementPeriod = parseStatementPeriod;
    const loadCustomer = (entityId) => {
        const rows = query
            .runSuiteQL({
            query: /* sql */ `
        SELECT customer.id, customer.currency,
          BUILTIN.DF(customer.defaultbillingaddress) AS billaddress,
          customerCurrency.displaysymbol AS currencysymbol, customerCurrency.symbolplacement
        FROM customer
        LEFT JOIN currency customerCurrency ON customerCurrency.id = customer.currency
        WHERE customer.id = ?`,
            params: [entityId],
        })
            .asMappedResults();
        if (rows.length === 0)
            throw new index_js_1.ValidationError(`no customer with id ${entityId} — entityId must be a customer's internal id`);
        return rows[0];
    };
    const loadSummary = (filter) => {
        const openingBalance = filter.startDate === null
            ? '0'
            : /* sql */ `SUM(CASE WHEN statementLine.trandate < TO_DATE(?, 'YYYY-MM-DD') THEN statementLine.statementamount ELSE 0 END)`;
        const base = arLinesQuery(filter);
        return query
            .runSuiteQL({
            query: /* sql */ `
        SELECT
          NVL(${openingBalance}, 0) AS openingbalance,
          NVL(SUM(statementLine.statementamount), 0) AS amountdue,
          NVL(SUM(CASE WHEN statementLine.dayspastdue <= 0 THEN statementLine.openamount ELSE 0 END), 0) AS aging1,
          NVL(SUM(CASE WHEN statementLine.dayspastdue BETWEEN 1 AND 30 THEN statementLine.openamount ELSE 0 END), 0) AS aging2,
          NVL(SUM(CASE WHEN statementLine.dayspastdue BETWEEN 31 AND 60 THEN statementLine.openamount ELSE 0 END), 0) AS aging3,
          NVL(SUM(CASE WHEN statementLine.dayspastdue BETWEEN 61 AND 90 THEN statementLine.openamount ELSE 0 END), 0) AS aging4,
          NVL(SUM(CASE WHEN statementLine.dayspastdue > 90 THEN statementLine.openamount ELSE 0 END), 0) AS aging5,
          NVL(SUM(statementLine.openamount), 0) AS agingbal
        FROM (${base.query}) statementLine`,
            params: [...(filter.startDate === null ? [] : [filter.startDate.iso]), ...base.params],
        })
            .asMappedResults()[0];
    };
    const LINE_PAGE_SIZE = 1000;
    // Cast needed: this id is documented by NetSuite but missing from @hitc/netsuite-types' feature union.
    const MULTI_BOOK_FEATURE = 'MULTIBOOK';
    // The running balance is windowed over every line up to statementDate, so lines before startDate
    // carry into the first printed balance; the outer filter then drops them.
    const loadLines = (filter) => {
        const base = arLinesQuery(filter);
        const bodyColumns = filter.bodyFields.map((field) => `, arLine.${field}`).join('');
        const startClause = filter.startDate === null ? '' : /* sql */ `AND arLine.trandate >= TO_DATE(?, 'YYYY-MM-DD')`;
        const pagedLines = query.runSuiteQLPaged({
            query: /* sql */ `
        SELECT arLine.transactionid, arLine.trandate, arLine.duedate, arLine.description, arLine.amount, arLine.balance${bodyColumns}
        FROM (
          SELECT statementLine.*,
            SUM(statementLine.statementamount) OVER (ORDER BY statementLine.trandate, statementLine.transactionid ROWS UNBOUNDED PRECEDING) AS balance
          FROM (${base.query}) statementLine
        ) arLine
        WHERE (? = 'F' OR arLine.openamount <> 0) ${startClause}
        ORDER BY arLine.trandate, arLine.transactionid`,
            params: [...base.params, filter.openOnly ? 'T' : 'F', ...(filter.startDate === null ? [] : [filter.startDate.iso])],
            pageSize: LINE_PAGE_SIZE,
        });
        return pagedLines.pageRanges.flatMap((pageRange) => pagedLines.fetch({ index: pageRange.index }).data.asMappedResults());
    };
    /**
     * Posting accounts-receivable lines for the customer in its own currency, up to statementDate, from
     * the primary accounting book only (Multi-Book accounts carry one accounting line per book; the
     * accountingbook table exists only when the feature is on, so the filter is added conditionally).
     */
    const arLinesQuery = (filter) => {
        const openAmount = /* sql */ `SIGN(transactionLine.foreignamount) * (NVL(txn.foreignamountunpaid, 0) + NVL(txn.foreignpaymentamountunused, 0))`;
        const bodyColumns = filter.bodyFields.map((field) => `, BUILTIN.DF(txn.${field}) AS ${field}`).join('');
        const primaryBookClause = runtime.isFeatureInEffect({ feature: MULTI_BOOK_FEATURE })
            ? /* sql */ `AND accountingLine.accountingbook = (SELECT primaryBook.id FROM accountingbook primaryBook WHERE primaryBook.isprimary = 'T')`
            : '';
        return {
            query: /* sql */ `
      SELECT
        txn.id AS transactionid, txn.trandate, txn.duedate,
        BUILTIN.DF(txn.type) || NVL2(txn.tranid, ' #' || txn.tranid, '') AS description,
        transactionLine.foreignamount AS amount,
        ${openAmount} AS openamount,
        CASE WHEN ? = 'T' THEN ${openAmount} ELSE transactionLine.foreignamount END AS statementamount,
        TO_DATE(?, 'YYYY-MM-DD') - NVL(txn.duedate, txn.trandate) AS dayspastdue${bodyColumns}
      FROM transactionaccountingline accountingLine
      JOIN transaction txn ON txn.id = accountingLine.transaction
      JOIN transactionline transactionLine
        ON transactionLine.transaction = accountingLine.transaction AND transactionLine.id = accountingLine.transactionline
      JOIN account arAccount ON arAccount.id = accountingLine.account
      WHERE transactionLine.entity = ? AND txn.currency = ?
        AND accountingLine.posting = 'T' AND arAccount.accttype = 'AcctRec'
        ${primaryBookClause}
        AND txn.trandate <= TO_DATE(?, 'YYYY-MM-DD')`,
            params: [filter.openOnly ? 'T' : 'F', filter.statementDate.iso, filter.entityId, filter.currencyId, filter.statementDate.iso],
        };
    };
    const toTemplateLine = (row, bodyFields, money) => {
        const amount = Number(row.amount);
        const line = {
            datecol: row.trandate,
            duedate: row.duedate ?? '',
            description: escapeXml(row.description ?? ''),
            charge: amount > 0 ? money(amount) : '',
            payment: amount < 0 ? money(-amount) : '',
            balance: money(Number(row.balance)),
        };
        for (const field of bodyFields)
            line[field] = escapeXml(String(row[field] ?? ''));
        return line;
    };
    // ============ Template references ============
    const findTemplateReferences = (source) => {
        const statementVariable = /<#list\s+statements\s+as\s+(\w+)\s*>/.exec(source)?.[1] ?? 'statement';
        const lineVariable = new RegExp(`<#list\\s+${statementVariable}\\.lines\\s+as\\s+(\\w+)\\s*>`).exec(source)?.[1] ?? 'line';
        return { statementVariable, lineVariable, statementPaths: findPaths(source, statementVariable), linePaths: findPaths(source, lineVariable) };
    };
    const findPaths = (source, variable) => {
        const pattern = new RegExp(`(?<![\\w.])${variable}((?:\\.\\w+)+)`, 'g');
        return [...source.matchAll(pattern)].map((match) => match[1].slice(1).split('.'));
    };
    const existingBodyFields = (linePaths) => {
        const candidates = [...new Set(linePaths.map((path) => path[0].toLowerCase()).filter((field) => BODY_FIELD_PATTERN.test(field)))];
        if (candidates.length === 0)
            return [];
        const existing = query
            .runSuiteQL({
            query: /* sql */ `SELECT scriptid FROM customfield WHERE UPPER(scriptid) IN (${candidates.map(() => '?').join(', ')})`,
            params: candidates.map((field) => field.toUpperCase()),
        })
            .asMappedResults()
            .map((row) => row.scriptid.toLowerCase());
        return candidates.filter((field) => existing.includes(field));
    };
    // NetSuite silently drops a whole directive whose expression hits a missing custom-data key (an
    // <#if> prints neither branch), while its own statement data reads unknown fields as empty. So every
    // path the template reads gets at least an empty string.
    const fillPath = (target, path) => {
        let node = target;
        for (const [index, segment] of path.entries()) {
            const isLeaf = index === path.length - 1;
            if (!(segment in node))
                node[segment] = isLeaf ? '' : {};
            const next = node[segment];
            if (isLeaf || typeof next !== 'object' || Array.isArray(next))
                return;
            node = next;
        }
    };
    /**
     * Three things NetSuite's statement engine provides that a custom data source can't, patched into the
     * draft source: a custom data source must be an object, so `statements` moves inside it; `@label`
     * on custom data prints empty, so known labels become their English text; and `record@title` would
     * name the customer record type, so it becomes "Statement".
     */
    const adaptSourceToDraftData = (source, references) => {
        const captionedFields = [];
        const labelFrom = (labels) => (interpolation, field) => {
            if (labels[field] === undefined)
                return interpolation;
            if (!captionedFields.includes(field))
                captionedFields.push(field);
            return labels[field];
        };
        const redirected = rewriteConstructCode(source, (kind) => kind === 'directive' || kind === 'interpolation', (code) => code.replace(new RegExp(BARE_STATEMENTS.source, 'g'), `${DRAFT_DATA_ALIAS}.statements`));
        assertDraftCanFeed(redirected);
        const titled = redirected.replace(/\$\{\s*record@title\s*\}/g, 'Statement');
        const captioned = titled
            .replace(new RegExp(`\\$\\{\\s*${references.statementVariable}\\.(\\w+)@label\\s*\\}`, 'g'), labelFrom(STATEMENT_LABELS))
            .replace(new RegExp(`\\$\\{\\s*${references.lineVariable}\\.(\\w+)@label\\s*\\}`, 'g'), labelFrom(LINE_LABELS));
        return {
            source: captioned,
            adaptations: [
                ...(redirected !== source ? ['statements: rebuilt statement data'] : []),
                ...(titled !== redirected ? ['title: Statement'] : []),
                ...(captionedFields.length > 0 ? [`captions: ${captionedFields.join(', ')}`] : []),
            ],
        };
    };
    // Without this, a template the rewrite can't feed (a legacy layout reading `record.lines`, or
    // `statements` passed through a macro call or square-bracket tag) renders a plausible empty PDF.
    const assertDraftCanFeed = (redirected) => {
        const unredirected = findConstructs(redirected).find((construct) => construct.kind !== 'comment' && codeSegments(redirected.slice(construct.start, construct.end)).some((code) => BARE_STATEMENTS.test(code)));
        if (unredirected !== undefined) {
            const snippet = redirected.slice(unredirected.start, Math.min(unredirected.end, unredirected.start + 60));
            throw new index_js_1.ValidationError(`this template reads \`statements\` inside \`${snippet}\`, which draft preview can't redirect to its rebuilt data; ${DRAFT_NOT_SUPPORTED}`);
        }
        if (!redirected.includes(`${DRAFT_DATA_ALIAS}.statements`)) {
            throw new index_js_1.ValidationError(`this template reads statement data from \`record\` (legacy layout); ${DRAFT_NOT_SUPPORTED}`);
        }
    };
    /** Applies `transform` to the code of matching FreeMarker constructs, leaving their string literals and all other text unchanged. */
    const rewriteConstructCode = (source, applies, transform) => {
        let rewritten = '';
        let copiedUpTo = 0;
        for (const construct of findConstructs(source)) {
            if (!applies(construct.kind))
                continue;
            const parts = source.slice(construct.start, construct.end).split(STRING_LITERAL);
            rewritten += source.slice(copiedUpTo, construct.start) + parts.map((part, index) => (index % 2 === 0 ? transform(part) : part)).join('');
            copiedUpTo = construct.end;
        }
        return rewritten + source.slice(copiedUpTo);
    };
    const codeSegments = (constructText) => constructText.split(STRING_LITERAL).filter((_part, index) => index % 2 === 0);
    /**
     * FreeMarker tags, macro calls, square-bracket tags, interpolations and comments, in order. A tag ends
     * at its closer only outside string literals and brackets, as FreeMarker reads `<#if (x > 0)>`.
     */
    const findConstructs = (source) => {
        const constructs = [];
        const opener = new RegExp(CONSTRUCT_OPENER.source, 'g');
        for (let match = opener.exec(source); match !== null; match = opener.exec(source)) {
            const kind = constructKindOf(match[0]);
            const end = kind === 'comment'
                ? endOfComment(source, match.index)
                : endOfTag(source, match.index + match[0].length, CONSTRUCT_CLOSERS[kind]);
            constructs.push({ kind, start: match.index, end });
            opener.lastIndex = end;
        }
        return constructs;
    };
    const constructKindOf = (openerText) => {
        if (openerText === '<#--')
            return 'comment';
        if (openerText === '${')
            return 'interpolation';
        if (openerText.startsWith('['))
            return 'squareTag';
        return openerText.includes('@') ? 'macro' : 'directive';
    };
    const endOfComment = (source, start) => {
        const close = source.indexOf('-->', start + '<#--'.length);
        return close === -1 ? source.length : close + '-->'.length;
    };
    const endOfTag = (source, from, closer) => {
        let depth = 0;
        let quote = null;
        for (let position = from; position < source.length; position++) {
            const character = source[position];
            if (quote !== null) {
                if (character === '\\')
                    position++;
                else if (character === quote)
                    quote = null;
            }
            else if (character === '"' || character === "'") {
                quote = character;
            }
            else if (depth === 0 && character === closer) {
                return position + 1;
            }
            else if ('([{'.includes(character)) {
                depth++;
            }
            else if (')]}'.includes(character)) {
                depth = Math.max(0, depth - 1);
            }
        }
        return source.length;
    };
    // ============ Formatting ============
    const parseStatementDate = (value, field) => {
        if (value === undefined || value === null || value === '')
            return null;
        const invalid = new index_js_1.ValidationError(`${field} must be a date in your NetSuite date format, e.g. 10/15/2026 — got ${JSON.stringify(value)}`);
        if (typeof value !== 'string')
            throw invalid;
        let parsed;
        try {
            parsed = format.parse({ value: value.trim(), type: format.Type.DATE });
        }
        catch {
            throw invalid;
        }
        if (!(parsed instanceof Date) || Number.isNaN(parsed.getTime()))
            throw invalid;
        return toStatementDate(parsed);
    };
    const today = () => toStatementDate(new Date());
    const toStatementDate = (date) => {
        const pad = (part) => String(part).padStart(2, '0');
        return {
            iso: `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`,
            display: String(format.format({ value: date, type: format.Type.DATE })),
        };
    };
    const formatMoney = (value, currency) => {
        const digits = String(format.format({ value: Math.abs(value), type: format.Type.CURRENCY }));
        const sign = value < 0 ? '-' : '';
        return currency.symbolAfter ? `${sign}${digits} ${currency.symbol}`.trimEnd() : `${sign}${currency.symbol}${digits}`;
    };
    const escapeXml = (text) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
});
