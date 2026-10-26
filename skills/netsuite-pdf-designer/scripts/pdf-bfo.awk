# pdf-bfo.awk — envelope, BFO allowlist and NetSuite pass of pdf-validate.sh. Input: data.tsv (plus the FreeMarker pass's
# M rows, macro and function bodies), then the FreeMarker-blanked copy (or, with structureOnly=1, the branch-blanked
# copy, reporting only the <head>/<body> counts and table nesting).
function locate(offset,   head, newlines, index_back) {
  head = substr(chunkText, 1, offset - 1); newlines = gsub(/\n/, "\n", head)
  if (newlines == 0) { foundLine = chunkLine; foundCol = chunkCol + offset - 1; return }
  for (index_back = length(head); substr(head, index_back, 1) != "\n"; index_back--) ;
  foundLine = chunkLine + newlines; foundCol = offset - index_back
}
function report(severity, offset, rule, message) {
  # <head>/<body> counts and table nesting come from a second run over the branch-blanked copy (structureOnly=1), so
  # one <pdf> or <tr> opener per <#if>/<#else> arm counts once; every other rule reads the copy that keeps each branch.
  if ((rule ~ /^(envelope\.(head|body)|bfo\.table)$/) != (structureOnly == 1)) return
  locate(offset); gsub(/[\t\r\n]+/, " ", message)
  print severity "\t" foundLine "\t" foundCol "\t" rule "\t" message
}
function severity_of(effect) { return effect == "breaks" ? "ERROR" : "WARN" }
function trim(text) { gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", text); return text }
function check_declarations(text, base_offset, inline,   remaining, consumed, semicolon, declaration, colon, lead) {
  remaining = text; consumed = 0
  while (remaining != "") {
    semicolon = index(remaining, ";"); declaration = semicolon ? substr(remaining, 1, semicolon - 1) : remaining
    colon = index(declaration, ":"); lead = match(declaration, /[^ \t\r\n]/)
    if (colon && lead && lead < colon)
      check_property(tolower(trim(substr(declaration, 1, colon - 1))), trim(substr(declaration, colon + 1)), base_offset + consumed + lead - 1, inline)
    if (!semicolon) break
    consumed += semicolon; remaining = substr(remaining, semicolon + 1)
  }
}
function check_property(property, value, offset, inline) {
  if (property == "" || property ~ /^x+$/) return
  if (property in cssStatus) {
    if (!(property in hasValues) && cssStatus[property] != "supported")
      report(severity_of(cssEffect[property]), offset, "bfo.css", property " is " cssStatus[property] " in BFO (" cssEffect[property] ")")
  } else if (!(property in knownAttribute)) report("WARN", offset, "bfo.css", property " is not in the BFO data (unknown)")
  check_value(property, value, offset, inline)
}
function check_value(property, value, offset, inline,   keyword, known, effect, tokens, count, i, unit) {
  if (property == "background-image" || property == "src") { check_image(value, offset); return }
  value = tolower(value); sub(/!important/, "", value); keyword = trim(value); sub(/[ \t\r\n,].*/, "", keyword)
  known = (property, keyword) in valueStatus
  if (known && valueStatus[property, keyword] == "supported") { }
  else if (known && property == "position" && keyword == "absolute") {
    # Sandbox probes: absolute fails the render only on a direct child of <body>; nested anywhere else it renders.
    if (!inline) report("WARN", offset, "bfo.position", "position:absolute in a <style> rule: selectors are not matched, so make sure no element it applies to sits directly inside <body> (that fails the render)")
    else if (stackSize && stack[stackSize] == "body") report("ERROR", offset, "bfo.position", "position:absolute on a direct child of <body> fails the render (UNEXPECTED_ERROR); put it inside a block or table cell, or use a background macro")
  } else if (known) {
    effect = valueEffect[property, keyword]
    report(severity_of(effect), offset, "bfo.css-value", property ":" keyword " is " valueStatus[property, keyword] " in BFO (" effect ")")
  } else if ((property in hasValues) && (keyword ~ /^[a-z-]+$/ || keyword ~ /^[0-9]+$/) && keyword !~ /^(x+|inherit|initial)$/)
    report("WARN", offset, "bfo.css-value", property ":" keyword " is not in the BFO data (unknown)")
  gsub(/url\([^)]*\)|"[^"]*"|\047[^\047]*\047/, " ", value)
  count = split(value, tokens, /[ \t\r\n,()\/]+/)
  for (i = 1; i <= count; i++) {
    if (!match(tokens[i], /^[-+]?[0-9]*\.?[0-9]+/) || RLENGTH == length(tokens[i])) continue
    unit = substr(tokens[i], RLENGTH + 1)
    if (unit !~ /^([a-z]+|%)$/) continue
    if (!(unit in unitStatus)) report("WARN", offset, "bfo.unit", tokens[i] ": unit " unit " is not in the BFO data (unknown); use pt, mm, in, em, % or px")
    else if (unitStatus[unit] != "supported") report("WARN", offset, "bfo.unit", tokens[i] ": unit " unit " is " unitStatus[unit] " in BFO" (unitStatus[unit] == "unsupported" ? " (ignored)" : "") "; use em, pt or px")
  }
}
function check_image(url, offset,   host) {
  url = trim(url); sub(/^url\([ \t"\047]*/, "", url)
  if (url ~ /^http:\/\//) report("WARN", offset, "netsuite.image-http", "image URL uses http:; use an https File Cabinet URL")
  else if (url ~ /^https:\/\//) {
    host = substr(url, 9); sub(/[\/:?#].*/, "", host)
    if (host !~ /(^|\.)netsuite\.com$/) report("WARN", offset, "netsuite.image-host", "image is not on the account NetSuite file host (" host "); upload it to the File Cabinet")
  }
}
function check_stylesheet(text,   comment, start, match_at, ch, prelude, at_rule, closing_brace, selector) {
  while (match(text, /\/\*([^*]|\*+[^*\/])*\*+\//)) {
    comment = substr(text, RSTART, RLENGTH); gsub(/[^\n]/, " ", comment)
    text = substr(text, 1, RSTART - 1) comment substr(text, RSTART + RLENGTH)
  }
  chunkText = text; start = 1
  while (match(substr(text, start), /[{};]/)) {
    match_at = start + RSTART - 1; ch = substr(text, match_at, 1); prelude = substr(text, start, match_at - start)
    start = match_at + 1
    if (ch == "}") continue
    selector = trim(prelude)
    if (selector ~ /^@/) {
      at_rule = selector; sub(/[ \t\r\n({;].*/, "", at_rule)
      if (!(at_rule in cssStatus)) report("WARN", start - 1 - length(prelude) + match(prelude, /@/) - 1, "bfo.css", at_rule " is not in the BFO data (unknown)")
      else if (cssStatus[at_rule] != "supported") report(severity_of(cssEffect[at_rule]), start - 1 - length(prelude) + match(prelude, /@/) - 1, "bfo.css", at_rule " is " cssStatus[at_rule] " in BFO (" cssEffect[at_rule] ")")
      if (ch == ";" || at_rule ~ /^@(media|supports)$/) continue
    } else if (ch == ";") continue
    else for (pseudo in badSelector) if (index(selector, pseudo)) {
      report("WARN", start - 1 - length(prelude) + match(prelude, /[^ \t\r\n]/) - 1, "bfo.css", "selector " pseudo " is not supported by BFO"); break
    }
    closing_brace = index(substr(text, start), "}"); if (!closing_brace) closing_brace = length(text) - start + 2
    check_declarations(substr(text, start, closing_brace - 1), start, 0)
    start += closing_brace
  }
}
function process_tag(   name, name_length, junk_at, self_closing, depth, status, check_attributes, scan, scan_base, attribute_start, attribute_length, attribute, equals, attribute_name, quote_at, attribute_value, value_offset, attribute_status) {
  chunkText = tagText; chunkLine = tagLine; chunkCol = tagCol
  if (tagText ~ /^<\?xml[ \t\r\n]/) { if ((tagLine == 1 && tagCol == 1) || tagLine == declarationAfterFreemarker) sawDeclaration = 1; return }
  if (tagText ~ /^<!DOCTYPE/) {
    sawDoctype = 1
    if (index(tagText, "-//big.faceless.org//report") == 0 || index(tagText, "report-1.1.dtd") == 0)
      report("ERROR", 1, "envelope.doctype", "DOCTYPE must be <!DOCTYPE pdf PUBLIC \"-//big.faceless.org//report\" \"report-1.1.dtd\">")
    return
  }
  if (tagText ~ /^<[!?]/) return
  if (substr(tagText, 2, 1) == "/") {
    name = substr(tagText, 3); sub(/[ \t\r\n>].*/, "", name)
    for (depth = stackSize; depth > 0 && stack[depth] != name; depth--) ;
    if (depth == 0) return
    stackSize = depth - 1
    if (name == "style" && inStyle) { inStyle = 0; chunkLine = styleLine; chunkCol = styleCol; check_stylesheet(styleText) }
    return
  }
  match(tagText, /^<[^ \t\r\n\/>]+/); name_length = RLENGTH - 1; name = substr(tagText, 2, name_length)
  if ((junk_at = match(name, /[^A-Za-z0-9_.:-]/)) > 1) {
    name = substr(name, 1, junk_at - 1); report_tag_text(substr(tagText, junk_at + 1, name_length - junk_at + 1), junk_at + 1, name)
  }
  self_closing = (tagText ~ /\/[ \t\r\n]*>$/); depth = stackSize
  if (depth == 0 && !rootName) {
    rootName = name
    # NetSuite's HTML-mode merged markup (native transaction renders) names the document <html>.
    if (name == "html" && mergedInput == 1) start_document(name)
    else if (name != "pdf" && name != "pdfset") report("ERROR", 1, "envelope.root", "root element is <" name ">; it must be <pdf> or <pdfset>")
    else if (name == "pdf") start_document(name)
  } else if (rootName == "pdfset" && depth == 1) {
    if (name == "pdf" || name == "html") start_document(name)
    else report("ERROR", 1, "envelope.root", "<pdfset> may hold only <pdf> or <html> documents, not <" name ">")
  } else if (documents && depth == documentDepth + 1) {
    if (name == "head") { headCount[documents]++; if (!headLine) { headLine = tagLine; headCol = tagCol } }
    if (name == "body") bodyCount[documents]++
  }
  # An HTML void element left open (<input>) is already an XML error; don't blame every cell after it on it too.
  if ((name in tableParent) && index(" " tableParent[name] " ", " " stack[stackSize] " ") == 0 && !in_macro(tagLine, tagCol) \
      && stack[stackSize] !~ /^(area|base|br|col|hr|img|input|link|meta|source|wbr)$/)
    report("ERROR", 1, "bfo.table", "<" name "> must sit directly inside " tableParentText[name] ", not " (stackSize ? "<" stack[stackSize] ">" : "outside every element") "; NetSuite fails the render")
  status = (name in elementStatus) ? elementStatus[name] : "unknown"; check_attributes = (status == "supported" || status == "partial" || status == "unsupported")
  if (status == "unknown" || status == "unverified") {
    if (!(name in elementReported)) report("WARN", 1, "bfo.element", "<" name "> is " (status == "unknown" ? "not in the BFO data (unknown)" : "unverified in BFO") "; it may be dropped")
    elementReported[name] = 1
  } else if (status != "supported") report(severity_of(elementEffect[name]), 1, "bfo.element", "<" name "> is " status " in BFO (" elementEffect[name] ")")
  scan = substr(tagText, name_length + 2); scan_base = name_length + 1
  while (match(scan, /[^ \t\r\n=\/>"\047]+[ \t\r\n]*=[ \t\r\n]*("[^"]*"|\047[^\047]*\047)/)) {
    attribute_start = RSTART; attribute_length = RLENGTH
    check_tag_gap(substr(scan, 1, attribute_start - 1), scan_base + 1, name)
    attribute = substr(scan, attribute_start, attribute_length); attribute_offset = scan_base + attribute_start
    scan_base += attribute_start + attribute_length - 1; scan = substr(scan, attribute_start + attribute_length)
    equals = index(attribute, "="); attribute_name = trim(substr(attribute, 1, equals - 1))
    quote_at = match(substr(attribute, equals + 1), /["\047]/); value_offset = attribute_offset + equals + quote_at
    attribute_value = substr(attribute, equals + quote_at + 1, length(attribute) - equals - quote_at - 1)
    if (attribute_name ~ /^(xmlns|xml:)/) continue
    if (check_attributes) {
      attribute_status = ((name, attribute_name) in attributeStatus) ? attributeStatus[name, attribute_name] : ((attribute_name in globalStatus) ? globalStatus[attribute_name] : "unknown")
      if (attribute_status == "unknown") report("WARN", attribute_offset, "bfo.attribute", "<" name " " attribute_name "> is not in the BFO data (unknown)")
      else if (attribute_status != "supported") report(severity_of(attributeEffect[name, attribute_name]), attribute_offset, "bfo.attribute", "<" name " " attribute_name "> is " attribute_status " in BFO (" attributeEffect[name, attribute_name] ")")
    }
    if (name == "link" && attribute_name == "type" && attribute_value == "font") hasFontLink = 1
    if (attribute_name == "style") check_declarations(attribute_value, value_offset, 1)
    else if (attribute_name in cssStatus || (name == "img" && attribute_name == "src")) check_value(attribute_name, attribute_value, attribute_offset, 1)
  }
  sub(/\/?[ \t\r\n]*>$/, "", scan); check_tag_gap(scan, scan_base + 1, name)
  if (self_closing) return
  stack[++stackSize] = name; divTextReported[stackSize] = 0
  if (name == "style") { inStyle = 1; styleText = ""; locate(length(tagText) + 1); styleLine = foundLine; styleCol = foundCol }
}
# Text between a tag's attributes (a {TOKEN} placeholder) is not XML. Spans of x's are ${…} the FreeMarker pass blanked.
function check_tag_gap(text, offset, name) {
  if (text ~ /^[ \t\r\n]*(x+[ \t\r\n]*)?$/) return
  report_tag_text(trim(text), offset + match(text, /[^ \t\r\n]/) - 1, name)
}
function report_tag_text(text, offset, name,   hint) {
  hint = text ~ /^\{/ ? " (a {TOKEN} placeholder must be replaced before NetSuite sees the template)" : ""
  if (length(text) > 40) text = substr(text, 1, 37) "..."
  report("ERROR", offset, "xml.tag-text", "\"" text "\" inside the <" name "> tag is not a name=\"value\" attribute, so the XML does not parse; NetSuite fails the render" hint)
}
function in_macro(at_line, at_col,   range) {
  for (range = 1; range <= macroCount; range++)
    if ((at_line > macroStartLine[range] || (at_line == macroStartLine[range] && at_col > macroStartCol[range])) \
        && (at_line < macroEndLine[range] || (at_line == macroEndLine[range] && at_col < macroEndCol[range]))) return 1
  return 0
}
function start_document(name) { documents++; documentDepth = (rootName == "pdfset"); documentName[documents] = name; documentLine[documents] = tagLine; documentCol[documents] = tagCol }
function handle_text(text, at_col,   lead) {
  if (inStyle) { styleText = styleText text; return }
  if (stackSize && stack[stackSize] == "div" && !divTextReported[stackSize] && (lead = match(text, /[^ \t\r\n]/))) {
    chunkText = text; chunkLine = FNR; chunkCol = at_col; divTextReported[stackSize] = 1
    report("WARN", lead, "netsuite.div-text", "text directly inside <div> is not drawn; wrap it in <p>, <span> or a table cell")
  }
}
BEGIN {
  FS = "\t"
  # Sandbox probes: each of these outside its parent fails the render with UNEXPECTED_ERROR.
  tableParent["tr"] = "table thead tbody tfoot"; tableParentText["tr"] = "<table>, <thead>, <tbody> or <tfoot>"
  tableParent["td"] = tableParent["th"] = "tr"; tableParentText["td"] = tableParentText["th"] = "<tr>"
  tableParent["thead"] = tableParent["tbody"] = tableParent["tfoot"] = "table"
  tableParentText["thead"] = tableParentText["tbody"] = tableParentText["tfoot"] = "<table>"
}
FNR == NR {
  if ($1 == "E") { elementStatus[$2] = $3; elementEffect[$2] = $4 }
  else if ($1 == "A") { attributeStatus[$2, $3] = $4; attributeEffect[$2, $3] = $5; knownAttribute[$3] = 1 }
  else if ($1 == "G") { globalStatus[$2] = $3; knownAttribute[$2] = 1 }
  else if ($1 == "C") { cssStatus[$2] = $3; cssEffect[$2] = $4 }
  else if ($1 == "V") { valueStatus[$2, $3] = $4; valueEffect[$2, $3] = $5; hasValues[$2] = 1 }
  else if ($1 == "U") unitStatus[$2] = $3
  else if ($1 == "S" && $2 ~ /^:/) badSelector[$2] = 1
  else if ($1 == "M") { macroCount++; macroStartLine[macroCount] = $2; macroStartCol[macroCount] = $3; macroEndLine[macroCount] = $4; macroEndCol[macroCount] = $5 }
  next
}
{
  line = $0; len = length(line); pos = 1
  while (pos <= len) {
    if (mode == "comment" || mode == "cdata") {
      found = index(substr(line, pos), mode == "comment" ? "-->" : "]]>")
      if (!found) break
      pos += found + 2; mode = ""; continue
    }
    if (mode == "tag") {
      rest = substr(line, pos)
      if (quote != "") {
        found = index(rest, quote)
        if (!found) { tagText = tagText rest; break }
        tagText = tagText substr(rest, 1, found); pos += found; quote = ""; continue
      }
      if (!match(rest, /[>"\047]/)) { tagText = tagText rest; break }
      ch = substr(rest, RSTART, 1); tagText = tagText substr(rest, 1, RSTART); pos += RSTART
      if (ch == ">") { mode = ""; process_tag() } else quote = ch
      continue
    }
    rest = substr(line, pos); found = index(rest, "<")
    handle_text(found ? substr(rest, 1, found - 1) : rest, pos)
    if (!found) break
    pos += found - 1
    if (substr(line, pos, 4) == "<!--") { mode = "comment"; pos += 4 }
    else if (substr(line, pos, 9) == "<![CDATA[") { mode = "cdata"; pos += 9 }
    else if (substr(line, pos + 1, 1) ~ /[a-zA-Z_\/!?]/) { mode = "tag"; tagText = "<"; tagLine = FNR; tagCol = pos; quote = ""; pos++ }
    else { handle_text("<", pos); pos++ }
  }
  if (mode == "tag") tagText = tagText "\n"
  else if (mode == "" && inStyle) styleText = styleText "\n"
}
END {
  chunkText = ""; chunkLine = 1; chunkCol = 1
  if (!sawDeclaration) report("ERROR", 1, "envelope.xml-declaration", "the file must start with <?xml version=\"1.0\"?>")
  if (!sawDoctype) report("ERROR", 1, "envelope.doctype", "missing <!DOCTYPE pdf PUBLIC \"-//big.faceless.org//report\" \"report-1.1.dtd\">")
  if (!rootName) report("ERROR", 1, "envelope.root", "no root element; it must be <pdf> or <pdfset>")
  for (document = 1; document <= documents; document++) {
    chunkLine = documentLine[document]; chunkCol = documentCol[document]
    if (headCount[document] != 1) report("ERROR", 1, "envelope.head", "<" documentName[document] "> needs exactly one <head> (found " headCount[document] + 0 ")")
    if (bodyCount[document] != 1) report("ERROR", 1, "envelope.body", "<" documentName[document] "> needs exactly one <body> (found " bodyCount[document] + 0 ")")
  }
  if (documents && !hasFontLink) {
    chunkLine = headLine ? headLine : documentLine[1]; chunkCol = headLine ? headCol : documentCol[1]
    report("WARN", 1, "netsuite.nsfont", "no nsfont <link type=\"font\"> in <head>; add <link name=\"NotoSans\" type=\"font\" subtype=\"truetype\" src=\"${nsfont.NotoSans_Regular}\" ... bytes=\"2\"/> so non-Latin text renders")
  }
}
