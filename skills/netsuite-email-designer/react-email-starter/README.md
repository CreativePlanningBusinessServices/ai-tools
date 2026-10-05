# react.email starter for NetSuite email templates

A minimal [react.email](https://react.email/) project whose export is ready to upload as a
NetSuite scriptable email template: every dynamic value stays a FreeMarker field, so NetSuite
fills it from the real record at send time.

## Use it

1. Copy this folder to wherever the template's source should live (one folder per template),
   then `npm install` there.
2. Author in `emails/<slug>.tsx`. Start from `emails/example.tsx`.
3. `npm run dev` opens react.email's live preview. Tokens such as `[[ns:…|wrap]]` show where
   NetSuite fields will go; that is expected.
4. `npm run export` writes NetSuite-ready HTML to `out/<slug>.html`. The `netsuite-email-designer`
   skill previews that file against a real record and uploads it.

## The one rule

Never type `${…}` or `<#…>` into JSX. React escapes quotes and angle brackets, which corrupts
`${transaction.trandate?string("MM/dd/yyyy")}` and every directive, and the export fails on
purpose when it finds a literal `${`. Use the helpers in `emails/_components/netsuite.tsx`:

| Need | Write |
|---|---|
| A field in text | `<NS expr="transaction.tranid" />` |
| A field in an attribute | `href={ns('transaction.custbody_pay_link_url')}` |
| A directive | `<FreeMarker>{'<#if transaction.memo?has_content>'}</FreeMarker>` … `<FreeMarker>{'</#if>'}</FreeMarker>` |

They emit base64 tokens that survive rendering; `scripts/export-netsuite.mjs` swaps them back
after `email export`.

Two react.email details: `<Preview>` accepts string children only, so write
``<Preview>{`Invoice ${ns('transaction.tranid')} is ready`}</Preview>`` rather than `<NS />` inside
it; and the export puts `<!-- -->` separators between adjacent text nodes (`Hello <!-- -->${…}`),
which is harmless in email clients and must not be "cleaned up" by hand.

Field names follow NetSuite's SuiteScript ids under the root hash the template is merged with:
`transaction`, `entity`, `customrecord`, `case`, `recipient`, `companyInformation`,
`preferences`. Joins are dot paths (`transaction.entity.email`).

`recipient` and `sender` are not in scope when NetSuite validates the template record on save, so
reference them null-safely or the template cannot be created: `<NS expr='(recipient.firstName)!""' />`
(the parentheses matter). The other roots can be referenced plainly.

## Verified with

react-email 6.11.0, @react-email/components 1.0.12, react 19.3.0, Node 24 (2026-10-05).
