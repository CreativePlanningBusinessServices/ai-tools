import * as React from 'react';

// FreeMarker can't be written into JSX: React escapes quotes and angle brackets, which breaks
// ${trandate?string("MM/dd/yyyy")} and every <#…> directive. These helpers emit a base64 token
// that survives rendering; scripts/export-netsuite.mjs swaps it back after `email export`.
const token = (expression: string, mode: 'wrap' | 'raw'): string =>
  `[[ns:${Buffer.from(expression, 'utf8').toString('base64')}|${mode}]]`;

/** A NetSuite field, rendered as ${expr}. Use in attributes: href={ns('transaction.custbody_pay_link_url')}. */
export const ns = (expression: string): string => token(expression, 'wrap');

/** A raw FreeMarker directive, rendered verbatim: fm('<#if transaction.memo?has_content>'). */
export const fm = (directive: string): string => token(directive, 'raw');

/** <NS expr="recipient.firstName" /> in text. */
export const NS = ({ expr }: { expr: string }): React.JSX.Element => <>{ns(expr)}</>;

/** <FreeMarker>{'<#if transaction.memo?has_content>'}</FreeMarker> around other elements. */
export const FreeMarker = ({ children }: { children: string }): React.JSX.Element => <>{fm(children)}</>;
