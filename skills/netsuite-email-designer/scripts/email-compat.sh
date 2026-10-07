#!/usr/bin/env bash
# Check an email's HTML/CSS against caniemail.com's support data.
#
# Usage: email-compat.sh <email.html> [--data caniemail.json] [--clients all]
#
# Needs only bash (3.2+), awk, jq and curl. Without --data it downloads
# https://www.caniemail.com/api/data.json into the temp dir and reuses that copy for a day.
set -euo pipefail

data_url="https://www.caniemail.com/api/data.json"
default_clients='[["outlook","windows"],["outlook","windows-mail"],["outlook","macos"],["outlook","outlook-com"],
  ["outlook","ios"],["outlook","android"],["gmail","desktop-webmail"],["gmail","ios"],["gmail","android"],
  ["apple-mail","macos"],["apple-mail","ios"],["yahoo","desktop-webmail"],["samsung-email","android"]]'

main() {
  local html_file="" data_file="" clients="default"
  while [ $# -gt 0 ]; do
    case "$1" in
      --data) data_file="${2:?--data needs a file}"; shift 2 ;;
      --clients) clients="${2:?--clients needs default or all}"; shift 2 ;;
      -h|--help) sed -n '2,7s/^# \{0,1\}//p' "$0"; exit 0 ;;
      *) html_file="$1"; shift ;;
    esac
  done
  [ -n "$html_file" ] || { echo "usage: email-compat.sh <email.html> [--data caniemail.json] [--clients all]" >&2; exit 1; }
  [ -f "$html_file" ] || { echo "email-compat: no such file: $html_file" >&2; exit 1; }
  [ -n "$data_file" ] || data_file="$(cached_caniemail_data)"

  work_dir="$(mktemp -d)"
  trap 'rm -rf "$work_dir"' EXIT
  jq -r '.data[].slug' "$data_file" > "$work_dir/slugs.txt"
  awk "$extract_features_awk" "$work_dir/slugs.txt" "$html_file" > "$work_dir/found.tsv"
  build_report "$html_file" "$data_file" "$work_dir/found.tsv" "$clients"
}

cached_caniemail_data() {
  local cache="${TMPDIR:-/tmp}"
  cache="${cache%/}/caniemail-data.json"
  if [ -z "$(find "$cache" -mmin -1440 2>/dev/null)" ]; then
    curl -fsSL --max-time 60 -o "$cache.part" "$data_url" && mv "$cache.part" "$cache" || {
      rm -f "$cache.part"
      echo "email-compat: could not download $data_url; download it another way and pass --data <file>" >&2
      exit 1
    }
  fi
  printf '%s\n' "$cache"
}

build_report() {
  local html_file="$1" data_file="$2" found_tsv="$3" clients="$4"
  jq -r \
    --arg htmlFile "$html_file" \
    --arg clientChoice "$clients" \
    --argjson defaultClients "$default_clients" \
    --rawfile found "$found_tsv" \
    "$report_jq" "$data_file"
}

# Reads the caniemail slug list, then the email HTML. Prints "<slug>\t<where>" for every caniemail
# feature the email uses, and "?\t<property>" for CSS properties caniemail has no entry for.
# POSIX awk only (no gawk extensions, no regex intervals) so it runs on macOS, Linux and Git Bash.
read -r -d '' extract_features_awk <<'AWK' || true
FNR == NR { known[$0] = 1; next }
{ html = html $0 " " }
END {
  lowered = tolower(html)
  if (lowered ~ /<!doctype/) emit("html-doctype", "<!DOCTYPE>")
  html = strip_comments(html)
  scan_style_blocks(html)
  rest = html
  while (match(rest, /<[A-Za-z][A-Za-z0-9]*[^>]*>/)) {
    tag = substr(rest, RSTART, RLENGTH)
    rest = substr(rest, RSTART + RLENGTH)
    scan_tag(tag)
  }
  for (property in unknown) print "?\t" property
}

function emit(slug, where) { if (slug in known) print slug "\t" where }

function trim(text) { gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", text); return text }

function strip_comments(text,    start, finish, kept) {
  kept = ""
  while ((start = index(text, "<!--")) > 0) {
    emit("html-comments", "<!-- -->")
    finish = index(substr(text, start + 4), "-->")
    if (finish == 0) return kept substr(text, 1, start - 1)
    kept = kept substr(text, 1, start - 1)
    text = substr(text, start + 4 + finish + 2)
  }
  return kept text
}

function scan_style_blocks(text,    lowered, open_at, body_start, close_at) {
  lowered = tolower(text)
  while ((open_at = index(lowered, "<style")) > 0) {
    body_start = open_at + index(substr(lowered, open_at), ">")
    close_at = index(substr(lowered, body_start), "</style>")
    if (close_at == 0) return
    scan_stylesheet(substr(text, body_start, close_at - 1))
    text = substr(text, body_start + close_at)
    lowered = substr(lowered, body_start + close_at)
  }
}

function scan_tag(tag,    name, attributes, attribute, equals_at, attribute_name, value, where, slug) {
  match(tag, /^<[A-Za-z][A-Za-z0-9]*/)
  name = tolower(substr(tag, 2, RLENGTH - 1))
  attributes = substr(tag, RLENGTH + 1)
  sub(/\/?>$/, "", attributes)
  where = "<" name ">"
  delete attribute_values
  while (match(attributes, /[A-Za-z_:][-A-Za-z0-9_:.]*[ \t]*(=[ \t]*("[^"]*"|'[^']*'|[^ \t"'>]+))?/)) {
    attribute = substr(attributes, RSTART, RLENGTH)
    attributes = substr(attributes, RSTART + RLENGTH)
    equals_at = index(attribute, "=")
    if (equals_at > 0) {
      attribute_name = tolower(trim(substr(attribute, 1, equals_at - 1)))
      value = trim(substr(attribute, equals_at + 1))
      if (value ~ /^["']/) value = substr(value, 2, length(value) - 2)
    } else {
      attribute_name = tolower(attribute)
      value = ""
    }
    attribute_values[attribute_name] = value
  }

  emit(tag_slug(name), where)
  if (name == "meta" && tolower(attribute_values["name"]) ~ /^(color-scheme|supported-color-schemes)$/) emit("html-meta-color-scheme", where)
  if (name == "img") emit(image_format_slug(attribute_values["src"]), where)
  for (attribute_name in attribute_values) {
    if (attribute_name ~ /^(align|valign|width|height|cellpadding|cellspacing|background|dir|lang|role|target|srcset|loading|hidden|required|popover)$/) {
      emit("html-" attribute_name, attribute_name "=\"\" on " where)
    } else if (attribute_name ~ /^aria-/) {
      emit("html-" attribute_name, attribute_name " on " where)
    } else if (attribute_name == "style" && trim(attribute_values["style"]) != "") {
      scan_declarations(attribute_values["style"], "style on " where)
    }
  }
}

function tag_slug(name,    href, type) {
  if (name ~ /^h[1-6]$/) return "html-h1-h6"
  if (name ~ /^(ul|ol|li|dl|dt|dd)$/) return "html-lists"
  if (name ~ /^(article|aside|details|figcaption|figure|footer|header|main|mark|nav|section|summary|time)$/) return "html-semantics"
  if (name == "s" || name == "strike") return "html-strike"
  if (name == "a") {
    href = tolower(attribute_values["href"])
    if (href ~ /^mailto:/) return "html-mailto-links"
    if (href ~ /^#/) return "html-anchor-links"
  }
  if (name == "input" || name == "button") {
    type = tolower(attribute_values["type"])
    if (type == "") type = (name == "input") ? "text" : "submit"
    return "html-" name "-" type
  }
  return "html-" name
}

function image_format_slug(url,    lowered, extension) {
  lowered = tolower(url)
  if (lowered ~ /^data:image\//) return "image-base64"
  if (match(lowered, /_xt=\.[a-z0-9]+/)) {
    extension = substr(lowered, RSTART + 5, RLENGTH - 5)
  } else if (match(lowered, /\.[a-z0-9][a-z0-9][a-z0-9][a-z0-9]?([?#&]|$)/)) {
    extension = substr(lowered, RSTART + 1, RLENGTH - 1)
    sub(/[?#&]$/, "", extension)
  } else {
    return ""
  }
  return (extension == "jpeg") ? "image-jpg" : "image-" extension
}

function scan_stylesheet(css,    start, finish, rest, at_rule, rule, brace_at, selector) {
  if (index(css, "/*") > 0) {
    emit("css-comments", "<style>")
    while ((start = index(css, "/*")) > 0) {
      finish = index(substr(css, start + 2), "*/")
      if (finish == 0) { css = substr(css, 1, start - 1); break }
      css = substr(css, 1, start - 1) substr(css, start + 2 + finish + 1)
    }
  }
  rest = tolower(css)
  while (match(rest, /@[a-z-]+/)) {
    at_rule = substr(rest, RSTART + 1, RLENGTH - 1)
    rest = substr(rest, RSTART + RLENGTH)
    if (at_rule ~ /^(media|font-face|import|supports|keyframes)$/) emit("css-at-" at_rule, "@" at_rule)
  }
  rest = tolower(css)
  while (match(rest, /@media[^{]*/)) {
    at_rule = substr(rest, RSTART, RLENGTH)
    rest = substr(rest, RSTART + RLENGTH)
    if (at_rule ~ /prefers-color-scheme/) emit("css-at-media-prefers-color-scheme", "@media (prefers-color-scheme)")
    if (at_rule ~ /prefers-reduced-motion/) emit("css-at-media-prefers-reduced-motion", "@media (prefers-reduced-motion)")
    if (at_rule ~ /orientation/) emit("css-at-media-orientation", "@media (orientation)")
    if (at_rule ~ /hover/) emit("css-at-media-hover", "@media (hover)")
    if (at_rule ~ /device-pixel-ratio/) emit("css-at-media-device-pixel-ratio", "@media (device-pixel-ratio)")
  }
  rest = css
  while (match(rest, /[^{}]+\{[^{}]*\}/)) {
    rule = substr(rest, RSTART, RLENGTH)
    rest = substr(rest, 1, RSTART - 1) substr(rest, RSTART + RLENGTH)
    brace_at = index(rule, "{")
    selector = trim(substr(rule, 1, brace_at - 1))
    scan_selector(selector)
    scan_declarations(substr(rule, brace_at + 1, length(rule) - brace_at - 1), "<style> " substr(selector, 1, 40))
  }
}

function scan_selector(selector,    rest, pseudo) {
  if (selector ~ /^@/ || selector == "") return
  rest = tolower(selector)
  while (match(rest, /::[a-z-]+/)) {
    emit("css-pseudo-element-" substr(rest, RSTART + 2, RLENGTH - 2), selector)
    rest = substr(rest, 1, RSTART - 1) " " substr(rest, RSTART + RLENGTH)
  }
  while (match(rest, /:[a-z-]+/)) {
    pseudo = substr(rest, RSTART + 1, RLENGTH - 1)
    rest = substr(rest, RSTART + RLENGTH)
    # CSS2's single-colon spelling of the four original pseudo-elements, still common in email CSS
    if (pseudo ~ /^(before|after|first-letter|first-line)$/) emit("css-pseudo-element-" pseudo, selector)
    else emit("css-pseudo-class-" pseudo, selector)
  }
  if (selector ~ /\.[A-Za-z_-]/) emit("css-selector-class", selector)
  if (selector ~ /#[A-Za-z_-]/) emit("css-selector-id", selector)
  if (index(selector, "[") > 0) emit("css-selector-attribute", selector)
}

function scan_declarations(declarations, where,    parts, count, i, colon_at, name, value, slug, found_at, units, unit_count, j, rest, url) {
  count = split(declarations, parts, ";")
  for (i = 1; i <= count; i++) {
    colon_at = index(parts[i], ":")
    if (colon_at == 0) continue
    name = tolower(trim(substr(parts[i], 1, colon_at - 1)))
    value = tolower(trim(substr(parts[i], colon_at + 1)))
    if (name == "" || name ~ /^mso-/ || name ~ /^-/) continue
    found_at = name " in " where
    slug = property_slug(name, value)
    if (slug != "") emit(slug, found_at); else unknown[name] = 1
    if (index(value, "!important") > 0) emit("css-important", found_at)
    if (value ~ /(^|[^a-z])linear-gradient\(/) emit("css-linear-gradient", found_at)
    if (value ~ /(^|[^a-z])radial-gradient\(/) emit("css-radial-gradient", found_at)
    if (value ~ /(^|[^a-z])conic-gradient\(/) emit("css-conic-gradient", found_at)
    if (value ~ /(^|[^a-z])rgba\(/) emit("css-rgba", found_at)
    if (value ~ /(^|[^a-z])rgb\(/) emit("css-rgb", found_at)
    if (value ~ /(^|[^a-z])calc\(/) emit("css-unit-calc", found_at)
    if (value ~ /(^|[^a-z])var\(/) emit("css-variables", found_at)
    if (value ~ /(^|[^a-z])clamp\(/) emit("css-function-clamp", found_at)
    if (value ~ /(^|[^a-z])min\(/) emit("css-function-min", found_at)
    if (value ~ /(^|[^a-z])max\(/) emit("css-function-max", found_at)
    if (value ~ /(^|[^a-z])light-dark\(/) emit("css-function-light-dark", found_at)
    unit_count = split("px em rem vh vw vmin vmax pt pc cm mm in ch ex", units, " ")
    for (j = 1; j <= unit_count; j++) {
      if (value ~ ("[0-9]" units[j] "([^a-z]|$)")) emit("css-unit-" units[j], found_at)
    }
    if (value ~ /[0-9]%/) emit("css-unit-percent", found_at)
    rest = trim(substr(parts[i], colon_at + 1))
    while (match(rest, /url\([ \t]*["']?[^"')]+/)) {
      url = substr(rest, RSTART + 4, RLENGTH - 4)
      rest = substr(rest, RSTART + RLENGTH)
      gsub(/^[ \t"']+/, "", url)
      emit(image_format_slug(url), found_at)
    }
  }
}

function property_slug(name, value,    without_side) {
  if (name == "display") {
    if (value ~ /(^|[^a-z])flex([^a-z-]|$)/) return "css-display-flex"
    if (value ~ /(^|[^a-z])grid([^a-z-]|$)/) return "css-display-grid"
    if (value ~ /(^|[^a-z])none([^a-z-]|$)/) return "css-display-none"
    return "css-display"
  }
  if (name ~ /^(top|right|bottom|left)$/) return "css-left-right-top-bottom"
  if (name ~ /^border(-[a-z]+)*-radius$/) return "css-border-radius"
  if (("css-" name) in known) return "css-" name
  without_side = name
  gsub(/-(top|right|bottom|left)/, "", without_side)
  if (("css-" without_side) in known) return "css-" without_side
  if (name ~ /^border-/ && ("css-border" in known)) return "css-border"
  return ""
}
AWK

# Input: caniemail data.json. Builds the report from the "<slug>\t<where>" lines in $found.
read -r -d '' report_jq <<'JQ' || true
.nicenames as $names
| (.data | map({key: .slug, value: .}) | from_entries) as $features
| ($found | split("\n") | map(select(length > 0) | split("\t"))) as $rows
| ($rows | map(select(.[0] != "?")) | group_by(.[0])
    | map({key: .[0][0], value: (map(.[1]) | unique)}) | from_entries) as $used
| ($rows | map(select(.[0] == "?") | .[1]) | unique) as $unknown
| (if $clientChoice == "all"
     then [.data[].stats | to_entries[] | .key as $family | .value | keys[] | [$family, .]] | unique
     else $defaultClients end) as $clients
| def client_label($family; $platform):
    ($names.family[$family] // $family) as $familyName
    | ($names.platform[$platform] // $platform) as $platformName
    | if ($platformName | startswith($familyName)) then $platformName else "\($familyName) \($platformName)" end;
  def assess($feature):
    [ $clients[] as [$family, $platform]
      | ($feature.stats[$family][$platform] // empty) | to_entries | last
      | (.value | split(" ")) as $result
      | select($result[0] == "n" or $result[0] == "a")
      | {support: $result[0], label: "\(client_label($family; $platform)) (\(.key))",
         notes: ($result[1:] | map(ltrimstr("#")))} ];
  def describe($feature; $failures):
    "- \($feature.title)  [\($feature.slug)]  \($feature.url)",
    "    used: \($used[$feature.slug][:3] | join("; "))\(if ($used[$feature.slug] | length) > 3 then " …" else "" end)",
    ($failures[] | "    \(if .support == "n" then "no     " else "partial" end)  \(.label)"),
    ($failures | map(.notes[]) | unique | sort_by(tonumber? // 0)[]
      | . as $number | ($feature.notes_by_num // {})[$number] // empty
      | "    note \($number): \(.)");
  ($used | keys | map($features[.] as $feature | {feature: $feature, failures: assess($feature)})) as $assessed
  | ($assessed | map(select(any(.failures[]; .support == "n")))) as $unsupported
  | ($assessed | map(select((.failures | length) > 0 and all(.failures[]; .support != "n")))) as $partial
  | ($assessed | map(select((.failures | length) == 0) | .feature.title)) as $supported
  | "Email compatibility: \($htmlFile)",
    "caniemail data updated \(.last_update_date // "?"); latest tested version per client; \($clients | length) clients checked; \($used | length) features found in the template.",
    "",
    "NOT SUPPORTED in at least one client (\($unsupported | length))",
    (if ($unsupported | length) == 0 then "  none" else ($unsupported[] | describe(.feature; .failures)) end),
    "",
    "PARTIAL support (\($partial | length))",
    (if ($partial | length) == 0 then "  none" else ($partial[] | describe(.feature; .failures)) end),
    "",
    "Supported everywhere checked (\($supported | length)): \($supported | join(", "))",
    (if ($unknown | length) > 0 then "No caniemail data for: \($unknown | join(", "))" else empty end)
JQ

main "$@"
