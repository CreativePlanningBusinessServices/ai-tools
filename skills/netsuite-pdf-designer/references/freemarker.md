# FreeMarker in NetSuite PDF templates

FreeMarker merges data into the template before BFO sees it. NetSuite's help lists FreeMarker 2.3.26, but a draft render in SB2 printed `${.version}` as 2.3.34 and `${.locale}` as en_US [sb2], so use the 2.3.34 manual. Name lists for the validator are `freemarker.builtins` and `freemarker.directives` in `data/bfo-support.json`.

Sources (fetched 2026-10-16). A claim marked **unverified** has no fetched source or SB2 render behind it.
- [fm-builtins] https://freemarker.apache.org/docs/ref_builtins_alphaidx.html (and `ref_builtins_string.html`, `_number.html`, `_date.html`, `_boolean.html`, `_expert.html`)
- [fm-directives] https://freemarker.apache.org/docs/ref_directive_alphaidx.html
- [fm-exp] https://freemarker.apache.org/docs/dgui_template_exp.html (missing values, operators)
- [ns-body] https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/subsect_163585859063.html (body fields, roots, modifiers)
- [ns-sublist] https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/subsect_163585866237.html
- [ns-join] https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/subsect_163585876245.html
- [ns-format] https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/subsect_156624108232.html (`nsformat_*`)
- [ns-file] https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/subsect_156630695265.html (`<@filecabinet>`)
- [ns-faq] https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_159984373188.html
- [sb2] SB2 probe, 2026-10-15/16 (design spec section 2). It overrides documents.

## Processing order

On preview or print NetSuite parses FreeMarker, then BFO validates the XML, then generates the PDF [ns-faq]. A FreeMarker syntax error (unclosed `<#if>`, unknown built-in) comes back as UNEXPECTED_ERROR with no detail; malformed XML gives a clear "Error Parsing XML" message [sb2]. So validate FreeMarker structure locally first.

## Roots

`${object.fieldId}`; field ids match SuiteScript ids (look them up in the Records Browser), lower or camel case [ns-body].

| Root | What it is | Notes |
|---|---|---|
| `record` | the current transaction | `${record.trandate}`, `${record.entity.email}` (select fields can be dotted into the related record) [ns-body] |
| `companyInformation` | company info | auto-added [sb2]; `companyId`, `appDomain`, `customerCenterDomain`, `customerLoginUrl`, `extformsDomain` [ns-body]. `companyInformation.logoUrl` rendered as a broken image in SB2 [sb2] |
| `subsidiary` | the transaction's subsidiary | **not** auto-populated, with or without `record` [sb2]. The skill's render adds it by loading the record's subsidiary; whether NetSuite's own print fills it the same way was not tested [sb2]. `${subsidiary.mainaddress_text}`, `subsidiary.logo` are used by real templates [ns-body; sb2] |
| `user` | current user | auto-populated: `user.firstname`, `user.email` filled, `user.entityid` empty [sb2] |
| `preferences` | Setup > Company > Printing & Fax | auto-populated for keys like `preferences.RETURNFORM`; `preferences.dateformat`, `DATEFORMAT`, `NUMBERFORMAT` came back empty and `?keys` lists nothing [sb2] |
| `nsfont` | font file paths | auto-populated, e.g. `nsfont.NotoSans_Regular` [sb2]; see bfo.md |
| `customer` | statement templates only | `${customer.entityId}`, `${customer.subsidiary.legalname}` [ns-body] |
| `statement` | statement documents | `${statement.amountDue}` [ns-body]; statement templates loop `<#list statements as statement>` inside `<pdfset>` [sb2]. `statement.lines` is named in the design spec but not in a fetched NetSuite page: **unverified** |
| `salesorder` | packing slips | [ns-body] |
| `records` | multiple sources (label, check, statement templates) | [ns-body] |
| `results` | joined saved-search results | `${results[0].customer.phone}`, `<#list results as row>` [ns-join] |

Restrictions: subrecords are not supported except the inventory detail values; address records have their own syntax; fields on a joined record must come from records directly joined to the transaction [ns-sublist; ns-join].

## Sublists

```ftl
<#list record.item as item>
  ${item_index} ${item.item} ${item.quantity} ${item.amount}
</#list>
```

- `record.item` is the item sublist; `<#list record.expense as expense>` has the same shape (the `record.expense.custcol_...` form appears in [ns-body]). `item_index` is zero-based and provided by `#list` [ns-sublist].
- Single line: `${record.item[1].itemName}`. Sort: `<#list record.item?sort_by("quantity") as item>` [ns-sublist].
- Only first-level sublist fields: no sublist inside another sublist's loop [ns-sublist].
- When a sublist id equals a field id, append `@list`: `<#list customer.currency@list as c>` [ns-sublist].
- `item.inventorydetail` returns the bin and serial listing for the line [ns-sublist].
- Striping: `style="background-color: ${((item_index % 2)==0)?string('#ffffff', '#ccffcc')}"` (NetSuite's striping page https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_N2866065.html).
- Header row once: `<#if item_index==0><tr>...<th>${item.field@label}</th>...</tr></#if>` [https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/bridgehead_4418819945.html]. Alternative: put `<thead>` outside the loop so BFO repeats it (see bfo.md).

## Modifiers

| Syntax | Result | Source |
|---|---|---|
| `${record.entity@label}` | the field's label on the form ("Customer") | [ns-body] |
| `${record@title}` | the transaction type name; `record` only, blank elsewhere | [ns-body] |
| `${record.hyperlink@url}` | plain URL instead of the `<a>` markup | [ns-body] |
| `customer.currency@list` | sublist whose id equals a field id | [ns-sublist] |

## Formatting

- NetSuite fields print already formatted; arithmetic does not (`${record.custbody_int+1}` gives `1235`). Wrap computed values: `nsformat_number`, `nsformat_currency(10.2, "EUR")`, `nsformat_date`, `nsformat_datetime`, `nsformat_time`, `nsformat_rate`, `nsformat_boolean`, `nsformat_percent`, `nsformat_email`, `nsformat_url`, `nsformat_password`. Empty or null input gives an empty string [ns-format].
- Numbers: `?string` uses the locale and `number_format`; `?string.number`, `?string.currency`, `?string.percent`, `?string.c`; pattern `?string["0.##"]`. `?c` is locale-independent (use it for ids in URLs) and errors on missing values; `?cn` prints `null` instead [fm-builtins `_number`].
- Booleans: `flag?string("yes","no")`, or `flag?then(a, b)` which only evaluates one branch [fm-builtins `_boolean`].
- Dates: `?date`, `?time`, `?datetime`, `?string.short|medium|long` on date values [fm-builtins `_date`]. Whether a NetSuite date field is a date value or a string in a template was not tested: **unverified**. To change case use `?upper_case`; a date format with MONTH does not give an upper-case month (NetSuite help, https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_4454200103.html).
- `<@filecabinet nstype="image" src="https://<account>.app.netsuite.com/core/media/media.nl?id=21&amp;c=...&amp;h=..."/>` embeds a File Cabinet image, required when the file is Company-Wide Usage rather than Available Without Login [ns-file; ns-faq]. The page lists no other `nstype` values.
- Escape `&` as `&amp;` inside URLs in the template; FreeMarker does not do it for you.

## Null safety and missing fields

- FreeMarker's rule: a missing variable aborts processing; `x!default` supplies a value, `x??` tests, and a parenthesised chain `(a.b.c)!""` covers a missing `a` too, while `a.b.c!""` only covers a missing `c` [fm-exp]. Never write `x!y + 1`; use `(x!y) + 1` [fm-exp].
- `?has_content` is true for non-empty strings, sequences and hashes, and for numbers, dates and booleans (including 0 and false); `(a.b)?has_content` is safe when `a` is missing [fm-builtins `_expert`].
- **Observed in SB2, not what the manual says:** `${record.nosuchfield}` and a field on a missing root render an empty string without error [sb2]. A typo therefore prints a silent blank, so check the output for blanks. Using a missing value in arithmetic or a built-in (`?upper_case`, `?c`) was not tested: **unverified**; guard with `!` or `?has_content` to be safe.
- Hidden fields: a field not shown on the custom form is a string in the template, a visible one is a boolean. Test both: `<#if (f?is_boolean && f) || (f?is_string && f == "T")>` [ns-faq].
- `?is_string`, `?is_boolean`, `?is_hash` and the rest of the `is_*` family exist [fm-builtins `_expert`]. `preferences` is a hash that answers `?is_hash` true and `?is_hash_ex` false [sb2].

## Directives and operators

- Directive names are in `freemarker.directives` [fm-directives]: `if elseif else list items sep break continue assign local global macro nested return function attempt recover switch case default include import setting compress noparse t lt rt nt ftl visit recurse fallback flush stop on escape noescape autoesc noautoesc outputformat`. User-defined directives are called `<@name/>`.
- The validator checks that `<#if>`, `<#list>`, `<#macro>`, `<#attempt>`, `<#switch>` and `<#function>` have matching closers, and that `<#else>`, `<#elseif>`, `<#recover>` and `<#case>` sit inside their parent. Names come from [fm-directives]; the placement rules are in the manual's per-directive pages, which were not fetched: **unverified**.
- `<#attempt>...<#recover>...</#attempt>` is the error-handling pair; how it behaves with NetSuite data errors was not tested: **unverified**.
- Precedence: `?` built-ins bind tighter than `+`; `"a " + "b"?upper_case` upper-cases only `"b"` [fm-exp]. `>` and `<` inside `<#if>` can be mistaken for XML; writing `gt`, `lt` or parentheses is the usual FreeMarker practice, **unverified** here.
- Escaping: `?html` and `?xml` exist but the 2.3.34 manual marks them deprecated [fm-builtins `_string`]. Whether NetSuite escapes field values before the XML parse was not tested, so a value with `&` or `<` may break the merged XML: **unverified**.
- Names for the validator: `freemarker.netsuiteFunctions` (the `nsformat_*` set), `freemarker.netsuiteModifiers` (`@label @title @url @list`), `freemarker.netsuiteDirectives` (`@filecabinet`).
