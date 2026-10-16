# BFO syntax for NetSuite Advanced PDF templates

NetSuite renders Advanced PDF/HTML templates with the Big Faceless (BFO) Report Generator after FreeMarker has merged the data. The machine-readable allowlist is `data/bfo-support.json`; this page is the prose. Every claim names its source in brackets. A claim marked **unverified** is not pinned to a fetched source or an SB2 render.

Sources (fetched 2026-10-16):
- [bfo-userguide] http://bfo.com/products/report/docs/userguide.pdf (v1.1.63)
- [bfo-tags] http://bfo.com/products/report/docs/tags/ (element and attribute reference; attribute pages under `tags/atts/`)
- [ns-bfo] https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/subsect_163732124124.html
- [ns-html4] https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/subsect_163732214401.html
- [ns-source] https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_4454208098.html
- [ns-editor] https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_4454200103.html
- [ns-barcodes] https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_N2868543.html
- [ns-fonts] https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/bridgehead_3963046048.html
- [ns-pagebreaks] https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/bridgehead_4418819945.html
- [sb2] SB2 probe, 2026-10-15/16 (design spec section 2). Where it disagrees with a document, the probe wins.

Versions: BFO's reference is for 1.1.x; NetSuite's help lists BFO 1.2.10 (https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_N2862977.html). Treat BFO documentation as "documented", and only [sb2] items as "tested in NetSuite".

## Document model

```xml
<?xml version="1.0"?>
<!DOCTYPE pdf PUBLIC "-//big.faceless.org//report" "report-1.1.dtd">
<pdf>
  <head> ...meta, link, style, macrolist... </head>
  <body> ...content... </body>
</pdf>
```

- One `<pdf>`, an optional `<head>`, a mandatory `<body>` [bfo-userguide, "Document Structure"]. NetSuite requires the XML declaration and the DOCTYPE, uses `<pdf>` rather than `<html>`, and forbids HTML5 declarations [ns-source].
- XML rules: close every element, quote every attribute, self-close empty elements (`<br />`, `<img ... />`) [ns-source]. Escape `&` as `&amp;` (also in URLs). Named entities need the DOCTYPE; the list is `entities` in the JSON [bfo-userguide, Appendix "Named Entities"].
- `&nbsp;` is defined by BFO. NetSuite help claims it isn't rendered [ns-html4], but SB2 shows it is: template 135's header source contains `Phone: 913-303-4356&nbsp; &nbsp;Fax`, it rendered, and the merged output kept the entity [sb2]. Leave it alone.
- `<pdfset>` wraps several `<pdf>` documents (statement templates). The merged output of a statement render uses `<html>` as the root of each document inside `<pdfset>`, not `<pdf>` [sb2]. A PDF template printed as HTML also gets `<pdf>` converted to `<html>` [ns-source].
- Invalid CSS is an error, not ignored (CSS2 differences 4.2) [bfo-userguide]. Unknown tags and unsupported CSS values that parse are silently ignored [sb2].

## Pages, size and margins

- `size` on `<body>` or `<pbr>` takes names such as `A4`, `Letter`, `Legal`, with `-landscape` appended to rotate (`Letter-landscape`); `size="A4"` equals `width="210mm" height="297mm"`. Default is Letter for en_US/en_CA, else A4 [bfo-userguide "Page Sizes"; bfo-tags `size`].
- Page margins are the `margin` attributes (`margin-top` etc.) on `<body>`/`<pbr>` [bfo-userguide "Pagination": `<pbr>` can set "page margins"].
- A percentage body width fails with "no size specified": use an absolute value, for example `<body width="595">` [ns-editor].
- Pagination: an element that does not fit moves to the next page or, if it can split, splits [bfo-userguide]. Only `table`, `ul`, `ol`, `p`, `pre`, `h1`-`h4` and `blockquote` split; a table nested in a `td` is cut off at the page bottom [bfo-userguide; ns-pagebreaks].
- `page-break-before/after/inside` are only recognised on direct children of `<body>` (and `join` on `tr`) [bfo-userguide, CSS2 differences 13.3]. For an explicit break use `<pbr/>`.

## Headers, footers and watermarks

```xml
<head><macrolist>
  <macro id="nlheader"> ...block content... </macro>
  <macro id="nlfooter"><p align="center">Page <pagenumber/> of <totalpages/></p></macro>
</macrolist></head>
<body header="nlheader" header-height="2.5in" footer="nlfooter" footer-height="0.5in"
      background-macro="nlwatermark" size="Letter"> ...
<pbr header="nlalt" header-height="2.2in" footer="nlfooter" footer-height="0.3in"/>
```

- Macros live in `<head><macrolist>`, each with an `id`; content cannot be bare text. Apply them with `header`, `footer`, `background-macro` on `body` or `pbr` [bfo-userguide "Headers, Footers and Macros"; bfo-tags `macro`].
- Header and footer need `header-height` / `footer-height`, or they are not applied; a template cannot have several headers [ns-bfo].
- `<pbr>` passes its attributes to the new page and all following pages [bfo-tags `pbr`].
- `background-macro` is how to place something at a fixed spot on the page; a plain `position:absolute` cannot be a child of `<body>` [bfo-tags `position`] (also failed in [sb2]).

## Page numbers

- `<pagenumber/>` and `<totalpages/>` print the current page and the total. `size="2"` sets the digit allowance (default 3); `type="roman-lower"` etc. changes the format; `<pagenumber idref="id"/>` prints another element's page [bfo-userguide "Displaying the Page number"].
- They resolve at the end of layout, so they cannot be used inside FreeMarker declarations (`<#assign>`) [ns-bfo].
- NetSuite re-parses closed empty BFO tags as open/close pairs with a space [ns-editor]; keep `<pagenumber/>` self-closed in source.

## Tables

- Cells use `colspan`/`rowspan`; `<th>` is styled like `<td>` and has no extra behaviour [bfo-userguide "Tables"].
- `border` on `<table>` is the table's outer border; use `cellborder` for every cell. `cellspacing` is not supported: use `cellmargin` [bfo-userguide; ns-editor]. `cellpadding` exists [bfo-tags `table`].
- `table-layout="fixed"` sizes columns only from `width` and needs an explicit table `width`, else it falls back to `auto` [bfo-userguide "Table Layout algorithms"]. NetSuite's own example: `<table table-layout="fixed" width="200"><tr><td width="60%">` [ns-html4].
- Repeating headers: put header rows in `<thead>` (and totals in `<tfoot>`); they repeat on every page the table spans and have no effect otherwise. At most one of each per table; loose rows go into an implicit `<tbody>` [bfo-tags `tbody`].
- Line items from FreeMarker: put `<#list record.item as item>` around the `<tr>`; NetSuite's page-break page puts the header row inside the loop on `item_index==0` [ns-pagebreaks]. Very long cell text (over about 2,000 characters per NetSuite) can overflow one row; split it across rows with `?split(...)` as shown there.
- Collapsing borders are not implemented (`border-collapse: collapse` has no BFO effect; borders always draw around empty cells) [bfo-userguide, CSS2 differences 17.6]. Whether NetSuite ignores or rejects it is **unverified**.
- Nested tables hurt performance [ns FAQ https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_159984373188.html].

## Text, divs and spans

- Text lives in paragraphs: `p`, `pre`, `h1`-`h4`, `blockquote`; inline elements (`b`, `i`, `u`, `span`, `a`...) only inside a paragraph [bfo-userguide "Text Elements"].
- Bare text directly in `body`, `li` or `td` gets an anonymous `<p>`; `div` is not on that list [bfo-userguide "Anonymous Paragraphs"]. In SB2, `<div>FLEX-A</div>` drew nothing and `<p>` around it drew [sb2]. Wrap text in `p`, `span` or a cell.
- `display` is `block`, `inline` or `none` only; the default is block, not inline [bfo-tags `display`; bfo-userguide, CSS2 differences 9.2.5]. Flex and grid are ignored: children stack [sb2].
- `float="left|right"` makes a block inline and wraps text around it [bfo-userguide "Float positioning"].
- `position:relative` offsets with `left`/`top` (not `right`/`bottom`) [bfo-userguide, CSS2 differences 9.4]. `position:absolute` is relative to its parent and is not allowed as a child of `<body>` [bfo-tags `position`]. In SB2 it failed the render (UNEXPECTED_ERROR) on a top-level `div`/`p` and worked inside a `position:relative` parent [sb2].
- `max-width`, `max-height`, `z-index`, `word-spacing`, `text-shadow`, `font-size-adjust` are ignored [bfo-userguide, CSS2 differences]. `border-radius` is ignored [sb2]; BFO's `corner-radius` exists [bfo-tags], not render-tested here.
- Units: `pt`, `mm`, `in`, `em`, `%` and bare numbers (points) appear in BFO's pages; `px` appears in NetSuite's font sample [ns-fonts] but is **unverified** in BFO's pages. `rem` is ignored [sb2]. See `lengthUnits` in the JSON.

## Images

- Formats: PNG, JPEG, GIF, PBM, PGM, TIFF; animated GIF shows frame 1; size follows `dpi` (default from the file, else 72) unless `width`/`height` are set [bfo-userguide "Images"].
- Self-close `<img ... />`. URLs must be absolute and reachable without login: File Cabinet files need Available Without Login or Company-Wide Usage; Company-Wide files need the `<@filecabinet nstype="image" src="..."/>` directive https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/subsect_156630695265.html
- `background-image: url(...)` on a block works and draws behind its text; use `background-repeat: no-repeat` for a single copy [sb2]. BFO's own controls are `background-image-position` (`stretch` default, `repeat`, `center middle`...) and `background-image-dpi` [bfo-userguide "Drawing the Background"].
- Escape `&` in image URLs as `&amp;`.

## Fonts and nsfont

- Built in: Times/`serif`, Helvetica/`sans-serif`, Courier/`monospace`, Symbol, ZapfDingbats, plus CJK names. Any other face must be linked [bfo-userguide "Fonts"].
- A font is linked in `<head>`: `<link name="NotoSans" type="font" subtype="truetype" src="${nsfont.NotoSans_Regular}" src-bold="${nsfont.NotoSans_Bold}" src-italic="${nsfont.NotoSans_Italic}" src-bolditalic="${nsfont.NotoSans_BoldItalic}" bytes="2" />`, then `* { font-family: NotoSans, sans-serif; }` [ns-fonts]. `bytes="2"` for glyphs beyond Latin-1 [bfo-userguide "OpenType"].
- `nsfont` is a root populated without `addRecord` (`nsfont.NotoSans_Regular` is a `file:///...WEB-INF/fonts/NotoSans-Regular.ttf` path) [sb2]. NetSuite's help does not enumerate its keys; the families it names are NotoSans, NotoSerif, NotoSansCJKsc/tc/jp/kr, NotoSansThai, NotoSansArabic, NotoSansHebrew and a few Indic scripts, each with Regular and Bold (NotoSans/NotoSerif also Italic and BoldItalic) [ns-fonts].
- Your own font: upload the TTF to the File Cabinet and reference it with `subtype="opentype"` (not `truetype`) and the media URL [ns-fonts; https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_4549515329.html]. `subset="false"` embeds the whole font (Arabic ligature fixes) [ns-fonts].
- `font-weight` only knows `normal` and `bold`; `font-family` with a list means per-character fallback [bfo-userguide "Text Attributes"].

## Barcodes

`<barcode codetype="code128" showtext="true" value="${record.tranid}"/>`; `<barcode codetype="qrcode" showtext="false" height="150" width="150" value="..."/>` [ns-barcodes].

- `codetype`, `showtext` and `value` are required; `height` and `width` are required for `qrcode`. Wrong characters for the code type raise an error, so the render fails [ns-barcodes; bfo-userguide "Barcodes"].
- NetSuite's table: aztec, codabar, code25, code25checksum, code25deutschenpost, code39, code39checksum, code128, databar, datamatrix, deutchepostmatrix, ean8, ean13/upca, intelligentmail, maxicode, pdf417, postnet, qrcode, rm4scc. `bar-width` (0.6 to 1) sets the narrowest bar on linear codes [bfo-userguide]. Preview in the editor shows nothing; render a PDF to see it [ns-barcodes].

## Silently ignored or breaking: quick list

| Construct | What happens | Source |
|---|---|---|
| `display:flex`, `display:grid` | ignored, children stack | [sb2] |
| `border-radius` | ignored | [sb2] |
| `rem` units | ignored (use em, pt) | [sb2] |
| Text directly in `<div>` | not drawn | [sb2] |
| `position:absolute` with no relative ancestor | render fails, UNEXPECTED_ERROR | [sb2] |
| `position:absolute` as a child of body | not allowed | [bfo-tags] |
| `&nbsp;` | NOT a problem: NetSuite help says unrendered, SB2 renders it (template 135) | [sb2] |
| `cellspacing` | not supported, use `cellmargin` | [ns-editor] |
| Percentage body width | "no size specified" error | [ns-editor] |
| `max-width`, `max-height`, `z-index`, `word-spacing`, `text-shadow` | ignored | [bfo-userguide] |
| `border-collapse: collapse` | collapsing model not implemented | [bfo-userguide] |
| `double`/`groove`/`ridge`/`inset`/`outset` borders | not used | [bfo-userguide] |
| `@media`, `@import`, `@page`, `:hover`, `::before` | not supported | [bfo-userguide] |
| Unclosed tags, bare `&`, unquoted attributes | XML parse error | [ns-source] |
| Unknown element (e.g. `<blink>`) | silently ignored | [sb2] |
