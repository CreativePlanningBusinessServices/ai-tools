# pdf-bfo.awk — envelope, BFO allowlist and NetSuite pass of pdf-validate.sh. Input: data.tsv, then the FreeMarker-blanked copy.
function locate(offset,   head, newlines, index_back) {
  head = substr(chunkText, 1, offset - 1); newlines = gsub(/\n/, "\n", head)
  if (newlines == 0) { foundLine = chunkLine; foundCol = chunkCol + offset - 1; return }
  for (index_back = length(head); substr(head, index_back, 1) != "\n"; index_back--) ;
  foundLine = chunkLine + newlines; foundCol = offset - index_back
}
function report(severity, offset, rule, message) {
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
  if (known && valueStatus[property, keyword] == "supported") { if (property == "position" && keyword == "relative") ownRelative = 1 }
  else if (known && property == "position" && keyword == "absolute") {
    # spec 6 makes this a WARN although the data says breaks: SB2 only tested the top-level case
    if (!inline) report("WARN", offset, "bfo.position", "position:absolute in a <style> rule: selectors are not matched, so make sure the element has a position:relative ancestor (absolute without one failed the SB2 render)")
    else if (relativeAncestors == 0) report("WARN", offset, "bfo.position", "position:absolute with no position:relative ancestor failed the SB2 render (UNEXPECTED_ERROR); only style attributes are checked, not <style> rules")
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
function process_tag(   name, name_length, self_closing, depth, status, check_attributes, scan, scan_base, attribute, equals, attribute_name, quote_at, attribute_value, value_offset, attribute_status) {
  chunkText = tagText; chunkLine = tagLine; chunkCol = tagCol
  if (tagText ~ /^<\?xml[ \t\r\n]/) { if (tagLine == 1 && (tagCol == 1 || declarationAfterFreemarker)) sawDeclaration = 1; return }
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
    for (; stackSize >= depth; stackSize--) relativeAncestors -= relative[stackSize]
    if (name == "style" && inStyle) { inStyle = 0; chunkLine = styleLine; chunkCol = styleCol; check_stylesheet(styleText) }
    return
  }
  match(tagText, /^<[^ \t\r\n\/>]+/); name_length = RLENGTH - 1; name = substr(tagText, 2, name_length)
  self_closing = (tagText ~ /\/[ \t\r\n]*>$/); depth = stackSize; ownRelative = 0
  if (depth == 0 && !rootName) {
    rootName = name
    if (name != "pdf" && name != "pdfset") report("ERROR", 1, "envelope.root", "root element is <" name ">; it must be <pdf> or <pdfset>")
    else if (name == "pdf") start_document(name)
  } else if (rootName == "pdfset" && depth == 1) {
    if (name == "pdf" || name == "html") start_document(name)
    else report("ERROR", 1, "envelope.root", "<pdfset> may hold only <pdf> or <html> documents, not <" name ">")
  } else if (documents && depth == documentDepth + 1) {
    if (name == "head") { headCount[documents]++; if (!headLine) { headLine = tagLine; headCol = tagCol } }
    if (name == "body") bodyCount[documents]++
  }
  status = (name in elementStatus) ? elementStatus[name] : "unknown"; check_attributes = (status == "supported" || status == "partial" || status == "unsupported")
  if (status == "unknown" || status == "unverified") {
    if (!(name in elementReported)) report("WARN", 1, "bfo.element", "<" name "> is " (status == "unknown" ? "not in the BFO data (unknown)" : "unverified in BFO") "; it may be dropped")
    elementReported[name] = 1
  } else if (status != "supported") report(severity_of(elementEffect[name]), 1, "bfo.element", "<" name "> is " status " in BFO (" elementEffect[name] ")")
  scan = substr(tagText, name_length + 2); scan_base = name_length + 1
  while (match(scan, /[^ \t\r\n=\/>"\047]+[ \t\r\n]*=[ \t\r\n]*("[^"]*"|\047[^\047]*\047)/)) {
    attribute = substr(scan, RSTART, RLENGTH); attribute_offset = scan_base + RSTART
    scan_base += RSTART + RLENGTH - 1; scan = substr(scan, RSTART + RLENGTH)
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
  if (self_closing) return
  stack[++stackSize] = name; relative[stackSize] = ownRelative; relativeAncestors += ownRelative; divTextReported[stackSize] = 0
  if (name == "style") { inStyle = 1; styleText = ""; locate(length(tagText) + 1); styleLine = foundLine; styleCol = foundCol }
}
function start_document(name) { documents++; documentDepth = (rootName == "pdfset"); documentName[documents] = name; documentLine[documents] = tagLine; documentCol[documents] = tagCol }
function handle_text(text, at_col,   lead) {
  if (inStyle) { styleText = styleText text; return }
  if (stackSize && stack[stackSize] == "div" && !divTextReported[stackSize] && (lead = match(text, /[^ \t\r\n]/))) {
    chunkText = text; chunkLine = FNR; chunkCol = at_col; divTextReported[stackSize] = 1
    report("WARN", lead, "netsuite.div-text", "text directly inside <div> is not drawn; wrap it in <p>, <span> or a table cell")
  }
}
BEGIN { FS = "\t" }
FNR == NR {
  if ($1 == "E") { elementStatus[$2] = $3; elementEffect[$2] = $4 }
  else if ($1 == "A") { attributeStatus[$2, $3] = $4; attributeEffect[$2, $3] = $5; knownAttribute[$3] = 1 }
  else if ($1 == "G") { globalStatus[$2] = $3; knownAttribute[$2] = 1 }
  else if ($1 == "C") { cssStatus[$2] = $3; cssEffect[$2] = $4 }
  else if ($1 == "V") { valueStatus[$2, $3] = $4; valueEffect[$2, $3] = $5; hasValues[$2] = 1 }
  else if ($1 == "U") unitStatus[$2] = $3
  else if ($1 == "S" && $2 ~ /^:/) badSelector[$2] = 1
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
