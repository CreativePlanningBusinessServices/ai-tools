define(["require", "exports", "N/format", "N/query", "../file-cabinet/index.js"], function (require, exports, format, query, index_js_1) {
    "use strict";
    Object.defineProperty(exports, "__esModule", { value: true });
    exports.buildDraftStatement = void 0;
    const BODY_FIELD_PATTERN = /^custbody_[a-z0-9_]+$/;
    const DRAFT_DATA_ALIAS = 'cpDraftStatement';
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
        const statementDate = parseStatementDate(options.statementDate, 'statementDate') ?? today();
        const startDate = parseStatementDate(options.startDate, 'startDate');
        if (startDate !== null && startDate.iso > statementDate.iso) {
            throw new index_js_1.ValidationError(`startDate must not be after statementDate (${startDate.display} > ${statementDate.display})`);
        }
        const customer = loadCustomer(options.entityId);
        const references = findTemplateReferences(options.source);
        const filter = {
            entityId: options.entityId,
            currencyId: customer.currency,
            statementDate,
            startDate,
            openOnly: options.openTransactionsOnly === true,
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
        return {
            subsidiaryId: customer.subsidiary === null || customer.subsidiary === undefined ? null : Number(customer.subsidiary),
            templateSource: adaptSourceToDraftData(options.source, references),
            dataSource: { alias: DRAFT_DATA_ALIAS, data: { statements: [statement] } },
        };
    };
    exports.buildDraftStatement = buildDraftStatement;
    const loadCustomer = (entityId) => {
        const rows = query
            .runSuiteQL({
            query: /* sql */ `
        SELECT customer.id, customer.currency, customer.subsidiary,
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
    // The running balance is windowed over every line up to statementDate, so lines before startDate
    // carry into the first printed balance; the outer filter then drops them.
    const loadLines = (filter) => {
        const base = arLinesQuery(filter);
        const bodyColumns = filter.bodyFields.map((field) => `, arLine.${field}`).join('');
        const startClause = filter.startDate === null ? '' : /* sql */ `AND arLine.trandate >= TO_DATE(?, 'YYYY-MM-DD')`;
        return query
            .runSuiteQL({
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
        })
            .asMappedResults();
    };
    /** Posting accounts-receivable lines for the customer in its own currency, up to statementDate. */
    const arLinesQuery = (filter) => {
        const openAmount = /* sql */ `SIGN(transactionLine.foreignamount) * (NVL(txn.foreignamountunpaid, 0) + NVL(txn.foreignpaymentamountunused, 0))`;
        const bodyColumns = filter.bodyFields.map((field) => `, BUILTIN.DF(txn.${field}) AS ${field}`).join('');
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
        const labelFrom = (labels) => (interpolation, field) => labels[field] ?? interpolation;
        return source
            .replace(/<#[^>]*>|\$\{[^}]*\}/g, (construct) => construct.replace(/(?<![\w.])statements(?!\w)/g, `${DRAFT_DATA_ALIAS}.statements`))
            .replace(/\$\{\s*record@title\s*\}/g, 'Statement')
            .replace(new RegExp(`\\$\\{\\s*${references.statementVariable}\\.(\\w+)@label\\s*\\}`, 'g'), labelFrom(STATEMENT_LABELS))
            .replace(new RegExp(`\\$\\{\\s*${references.lineVariable}\\.(\\w+)@label\\s*\\}`, 'g'), labelFrom(LINE_LABELS));
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
