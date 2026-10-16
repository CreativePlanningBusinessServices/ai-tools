#!/usr/bin/env bash
# pdf-validate.sh — checks a NetSuite Advanced PDF/HTML template (FreeMarker + BFO XML) before it reaches NetSuite.
# usage: pdf-validate.sh [--merged] [--json] [--data <bfo-support.json>] <file>
# Prints "ERROR|WARN <line>:<col> <rule> <message>" per finding and a summary; exit 0 = no ERROR, 1 = ERROR, 2 = usage/input.
set -uo pipefail

usage() { echo "usage: pdf-validate.sh [--merged] [--json] [--data <bfo-support.json>] <file>" >&2; exit 2; }

script_dir="$(cd "$(dirname "$0")" && pwd)"
data_file="$script_dir/../data/bfo-support.json"
merged=0; json=0; input_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --merged) merged=1 ;;
    --json) json=1 ;;
    --data) [ $# -ge 2 ] || usage; data_file="$2"; shift ;;
    -*) usage ;;
    *) [ -z "$input_file" ] || usage; input_file="$1" ;;
  esac
  shift
done
[ -n "$input_file" ] || usage
if [ ! -f "$input_file" ] || [ ! -r "$input_file" ]; then echo "pdf-validate: cannot read $input_file" >&2; exit 2; fi
command -v xmllint >/dev/null 2>&1 || { echo "pdf-validate: xmllint is required" >&2; exit 2; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

if ! jq -e '(.elements|type) == "object" and (.css|type) == "object" and (.globalAttributes|type) == "object"
    and (.lengthUnits|type) == "object" and (.entities|type) == "array"
    and (.freemarker.builtins|type) == "array" and (.freemarker.directives|type) == "array"' \
    "$data_file" >/dev/null 2>&1; then
  echo "pdf-validate: $data_file is not a usable bfo-support.json" >&2; exit 2
fi
jq -r '
  (.elements | to_entries[] | ["E", .key, .value.status, (.value.effect // "unknown")]),
  (.elements | to_entries[] | .key as $element | (.value.attributeEffects // {}) as $effects
    | (.value.attributes // {}) | to_entries[] | ["A", $element, .key, .value, ($effects[.key] // "unknown")]),
  (.globalAttributes | to_entries[] | ["G", .key, .value]),
  (.css | to_entries[] | ["C", .key, .value.status, (.value.effect // "unknown")]),
  (.css | to_entries[] | .key as $property | .value as $entry | ($entry.values // {}) | to_entries[]
    | ["V", $property, .key, .value, (($entry.valueEffects // {})[.key] // $entry.effect // "unknown")]),
  (.lengthUnits | to_entries[] | select(.value | type == "array") | .key as $status | .value[] | ["U", ., $status]),
  ((.selectors.unsupported // [])[] | ["S", .]),
  (.freemarker.builtins[] | ["B", .]),
  (.freemarker.directives[] | ["D", .])
  | @tsv' "$data_file" > "$work/data.tsv"
# One prolog line declares every BFO named entity, so &nbsp; and friends parse; it is subtracted from xmllint's line numbers.
jq -r '"<?xml version=\"1.0\"?><!DOCTYPE pdf [" + ([.entities[] | select(IN("amp", "lt", "gt", "quot", "apos") | not)
  | "<!ENTITY \(.) \"&#160;\">"] | join("")) + "]>"' "$data_file" > "$work/prolog.xml"

stripped="$work/stripped.xml"; findings="$work/findings.tsv"; : > "$findings"
if [ "$merged" -eq 1 ]; then
  cp "$input_file" "$stripped"
else
  # FreeMarker pass: checks directive structure and built-ins, and writes a copy with every FreeMarker span blanked
  # (${…} becomes x's) so lines and columns still match the source.
  awk -v strippedFile="$stripped" -v corruptFile="$work/corrupt" '
    function blanks(count,   text) { text = ""; while (count > 512) { text = text SPACES; count -= 512 } return text substr(SPACES, 1, count) }
    function exes(count,   text) { text = ""; while (count > 512) { text = text EXES; count -= 512 } return text substr(EXES, 1, count) }
    function finding(severity, at_line, at_col, rule, message) { print severity "\t" at_line "\t" at_col "\t" rule "\t" message }
    function emit(text) { out = out (mode == "interpolation" ? exes(length(text)) : blanks(length(text))); if (mode == "directive") body = body text }
    function scan_expression(   ch, name) {
      while (pos <= len) {
        ch = substr(line, pos, 1)
        if (quote != "") {
          if (ch == "\\") { emit(substr(line, pos, 2)); pos += 2; continue }
          if (ch == quote) quote = ""
          emit(ch); pos++; continue
        }
        if (ch == "\"" || ch == "'\''") { quote = ch; emit(ch); pos++; continue }
        if (ch == "?") {
          if (substr(line, pos + 1, 1) == "?") { emit("??"); pos += 2; continue }
          if (match(substr(line, pos + 1), /^[a-zA-Z_][a-zA-Z0-9_]*/)) {
            name = substr(line, pos + 1, RLENGTH)
            if (!(name in builtin)) finding("WARN", FNR, pos, "freemarker.builtin", "?" name " is not a FreeMarker 2.3 built-in")
          }
        } else if (mode == "interpolation") {
          if (ch == "{") braces++
          else if (ch == "}" && --braces == 0) { out = out "x"; pos++; mode = ""; return }
          else if (ch == "<" && substr(line, pos + 1, 1) ~ /[\/#@a-zA-Z]/) {
            finding("ERROR", startLine, startCol, "freemarker.interpolation", "${ is never closed with }"); mode = ""; return
          }
        } else if (ch == "(") parens++
        else if (ch == ")") parens--
        else if (ch == ">" && parens <= 0) { out = out " "; pos++; mode = ""; end_directive(); return }
        emit(ch); pos++
      }
    }
    function end_directive(   name, parents) {
      if (kind == "@" || !match(body, /^[a-zA-Z_]+/)) return
      name = substr(body, 1, RLENGTH)
      if (!(name in directive)) { finding("ERROR", startLine, startCol, "freemarker.directive", "<#" name "> is not a FreeMarker directive"); return }
      if (closing) { close_block(name); return }
      if (name in allowedParents) {
        parents = allowedParents[name]; gsub(/ /, "> or <#", parents)
        if (index(" " allowedParents[name] " ", " " stackName[depth] " ") == 0)
          finding("ERROR", startLine, startCol, "freemarker.misplaced", "<#" name "> must sit directly inside <#" parents ">")
        return
      }
      if (!(name in blockDirective) || body ~ /\/[ \t\r\n]*$/) return
      if (name ~ /^(assign|global|local)$/ && body ~ /=/) return
      depth++; stackName[depth] = name; stackLine[depth] = startLine; stackCol[depth] = startCol
      if (name == "noparse") mode = "noparse"
    }
    function close_block(name,   level) {
      if (name == "sep") return
      for (level = depth; level > 0 && stackName[level] != name; level--) ;
      if (level == 0) { finding("ERROR", startLine, startCol, "freemarker.stray", "</#" name "> has no matching <#" name ">"); return }
      for (; depth > level; depth--)
        finding("ERROR", stackLine[depth], stackCol[depth], "freemarker.unclosed", "<#" stackName[depth] "> is not closed before </#" name "> on line " startLine)
      depth--
    }
    BEGIN {
      FS = "\t"; SPACES = sprintf("%512s", ""); EXES = SPACES; gsub(/ /, "x", EXES)
      split("if list items macro function attempt switch compress escape noescape autoesc noautoesc outputformat noparse assign global local", names, " ")
      for (i in names) blockDirective[names[i]] = 1
      allowedParents["else"] = "if list"; allowedParents["elseif"] = "if"; allowedParents["recover"] = "attempt"
      allowedParents["case"] = "switch"; allowedParents["default"] = "switch"; allowedParents["on"] = "switch"
    }
    FNR == NR { if ($1 == "B") builtin[$2] = 1; else if ($1 == "D") directive[$2] = 1; next }
    {
      line = $0; len = length(line); out = ""; pos = 1
      while (pos <= len) {
        if (mode == "comment") {
          found = index(substr(line, pos), "-->")
          if (!found) { out = out blanks(len - pos + 1); pos = len + 1 } else { out = out blanks(found + 2); pos += found + 2; mode = "" }
          continue
        }
        if (mode == "noparse") {
          found = index(substr(line, pos), "</#noparse")
          if (!found) { out = out substr(line, pos); pos = len + 1 } else { out = out substr(line, pos, found - 1); pos += found - 1; mode = "" }
          continue
        }
        if (mode == "directive" || mode == "interpolation") { scan_expression(); continue }
        rest = substr(line, pos)
        if (!match(rest, /<\/?[#@][a-zA-Z_-]|\$\{/)) { out = out rest; break }
        out = out substr(rest, 1, RSTART - 1); pos += RSTART - 1; startLine = FNR; startCol = pos; quote = ""
        if (substr(line, pos, 4) == "<#--") { mode = "comment"; out = out "    "; pos += 4 }
        else if (substr(line, pos, 2) == "${") { mode = "interpolation"; braces = 1; out = out "xx"; pos += 2 }
        else {
          closing = (substr(line, pos + 1, 1) == "/"); kind = substr(line, pos + 1 + closing, 1)
          mode = "directive"; body = ""; parens = 0; out = out blanks(2 + closing); pos += 2 + closing
        }
      }
      if (mode == "directive") body = body "\n"
      print out > strippedFile
    }
    END {
      if (mode == "comment") { finding("ERROR", startLine, startCol, "freemarker.comment", "<#-- is never closed with -->"); corrupt = 1 }
      if (mode == "directive") { finding("ERROR", startLine, startCol, "freemarker.tag", "this FreeMarker tag never ends with >"); corrupt = 1 }
      if (mode == "interpolation") finding("ERROR", startLine, startCol, "freemarker.interpolation", "${ is never closed with }")
      for (; depth > 0; depth--)
        finding("ERROR", stackLine[depth], stackCol[depth], "freemarker.unclosed", "<#" stackName[depth] "> is never closed with </#" stackName[depth] ">")
      if (corrupt) print "corrupt" > corruptFile
    }' "$work/data.tsv" "$input_file" >> "$findings"
fi

# Envelope, BFO allowlist and NetSuite pass over the blanked copy. Positions inside a multi-line tag or <style> block are
# offsets into a "chunk" (its text plus the line/column where it starts), turned back into line:column by locate().
awk '
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
    if (tagText ~ /^<\?xml[ \t\r\n]/) { if (tagLine == 1 && tagCol == 1) sawDeclaration = 1; return }
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
  }' "$work/data.tsv" "$stripped" >> "$findings"

# XML pass: xmllint reads the blanked copy behind a one-line prolog. Entity errors are all reported; for structure only
# the first error is, since libxml2 cascades after it.
if [ ! -f "$work/corrupt" ]; then
  awk 'function blanks(count) { return sprintf("%" count "s", "") }
    NR == 1 { while ((getline prolog < prologFile) > 0) print prolog }
    !inRoot {
      while (match($0, /<\?xml[^>]*\?>|<!DOCTYPE[^>]*>/)) $0 = substr($0, 1, RSTART - 1) blanks(RLENGTH) substr($0, RSTART + RLENGTH)
      if ($0 ~ /<[a-zA-Z]/) inRoot = 1
    }
    { print }' prologFile="$work/prolog.xml" "$stripped" > "$work/xmllint.xml"
  xmllint --noout --nonet "$work/xmllint.xml" 2> "$work/xmllint.err"
  awk -v prologLines="$(wc -l < "$work/prolog.xml")" '
    function open_tag_col(text, name,   col, offset) {
      col = 0; offset = 0
      while (match(substr(text, offset + 1), "<" name "([ \t\r/>]|$)")) { col = offset + RSTART; offset += RSTART }
      return col ? col : 1
    }
    function emit(rule, at_line, at_col, message) { gsub(/\t/, " ", message); print "ERROR\t" (at_line < 1 ? 1 : at_line) "\t" at_col "\t" rule "\t" message }
    FNR == NR { source[FNR] = $0; next }
    match($0, /xmllint\.xml:[0-9]+: [a-z ]*error : /) {
      header = substr($0, RSTART, RLENGTH); message = substr($0, RSTART + RLENGTH)
      sub(/^xmllint\.xml:/, "", header); error_line = (header + 0) - prologLines
      context = ""; caret = ""; getline context; getline caret
      caret_col = index(caret, "^"); context_at = context == "" ? 0 : index(source[error_line], context)
      col = context_at ? context_at + caret_col - 1 : (caret_col ? caret_col : 1)
      if (message ~ /EntityRef|Entity '\''/) {
        while (col > 1 && substr(source[error_line], col, 1) != "&") col--
        if (match(message, /Entity '\''[^'\'']+'\''/)) message = "&" substr(message, RSTART + 8, RLENGTH - 9) "; is not a named entity BFO knows; write &amp; or a numeric reference"
        else message = "bare & (write &amp;): " message
        emit("xml.entity", error_line, col, message); next
      }
      if (structural++) next
      if (match(message, /^Opening and ending tag mismatch: [^ ]+ line [0-9]+ and [^ ]+/)) {
        split(message, words, " "); open_name = words[6]; open_line = words[8] - prologLines
        hint = open_name ~ /^(br|img|hr|link|meta|pbr|pagenumber|totalpages)$/ ? "; empty elements must be self-closed, e.g. <" open_name " />" : ""
        emit("xml.mismatch", open_line, open_tag_col(source[open_line], open_name), "<" open_name "> opened here is closed by </" words[10] "> on line " error_line hint)
      } else if (match(message, /^Premature end of data in tag [^ ]+ line [0-9]+/)) {
        split(message, words, " "); open_line = words[9] - prologLines
        emit("xml.unclosed", open_line, open_tag_col(source[open_line], words[7]), "<" words[7] "> is never closed")
      } else {
        if (match(message, / line [0-9]+/)) message = substr(message, 1, RSTART + 5) (substr(message, RSTART + 6, RLENGTH - 6) - prologLines) substr(message, RSTART + RLENGTH)
        emit("xml.syntax", error_line, col, message)
      }
    }' "$stripped" "$work/xmllint.err" >> "$findings"
fi

tab="$(printf '\t')"
sort -s -t "$tab" -k2,2n -k3,3n "$findings" > "$work/sorted.tsv"
error_count="$(grep -c "^ERROR$tab" "$work/sorted.tsv")"
warning_count="$(grep -c "^WARN$tab" "$work/sorted.tsv")"
if [ "$json" -eq 1 ]; then
  jq -R -s 'split("\n") | map(select(length > 0) | split("\t")
    | {severity: .[0], line: (.[1] | tonumber), col: (.[2] | tonumber), rule: .[3], message: .[4]})' "$work/sorted.tsv"
else
  awk -F '\t' '{ printf "%s %s:%s %s %s\n", $1, $2, $3, $4, $5 }' "$work/sorted.tsv"
  echo "$error_count errors, $warning_count warnings"
fi
[ "$error_count" -eq 0 ]
