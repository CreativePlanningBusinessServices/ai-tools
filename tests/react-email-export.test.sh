#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib.sh"
script="$here/../skills/netsuite-email-designer/react-email-starter/scripts/export-netsuite.mjs"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
b64() { printf '%s' "$1" | base64 | tr -d '\n'; }
tranid="$(b64 'transaction.tranid')"
payLink="$(b64 'transaction.custbody_pay_link_url')"
dateExpr="$(b64 'transaction.trandate?string("MM/dd/yyyy")')"
ifOpen="$(b64 '<#if transaction.memo?has_content>')"
ifClose="$(b64 '</#if>')"

mkdir -p "$tmp/out"
cat > "$tmp/out/invoice.html" <<EOF
<p>Invoice [[ns:${tranid}|wrap]] dated [[ns:${dateExpr}|wrap]]</p>
<a href="[[ns:${payLink}|wrap]]">Pay now</a>
[[ns:${ifOpen}|raw]]<p>[[ns:${tranid}|wrap]]</p>[[ns:${ifClose}|raw]]
EOF

output="$(node "$script" "$tmp/out" --no-export 2>&1)"; status=$?
assert_eq "$status" 0 "export script exits 0 on a clean token file"
html="$(cat "$tmp/out/invoice.html")"
assert_contains "$html" 'Invoice ${transaction.tranid} dated' "wrap token becomes a FreeMarker field"
assert_contains "$html" '${transaction.trandate?string("MM/dd/yyyy")}' "quotes inside an expression survive"
assert_contains "$html" 'href="${transaction.custbody_pay_link_url}"' "token inside an attribute survives"
assert_contains "$html" '<#if transaction.memo?has_content><p>${transaction.tranid}</p></#if>' "raw tokens become directives verbatim"
assert_not_contains "$html" '[[ns:' "no token is left behind"
assert_contains "$output" "netsuite-ready: $tmp/out/invoice.html" "the script names each file it rewrote"

mkdir -p "$tmp/bad"
printf '<p>${transaction.tranid}</p>\n' > "$tmp/bad/typed.html"
output="$(node "$script" "$tmp/bad" --no-export 2>&1)"; status=$?
assert_eq "$status" 1 "a literal \${ typed into JSX fails the export"
assert_contains "$output" 'typed.html: contains a literal "${"' "the failure names the file and the cause"

mkdir -p "$tmp/broken"
printf '<p>[[ns:%s|wrap]] and [[ns:!!!|wrap]]</p>\n' "$tranid" > "$tmp/broken/odd.html"
output="$(node "$script" "$tmp/broken" --no-export 2>&1)"; status=$?
assert_eq "$status" 1 "an unrecognised token fails the export"
assert_contains "$output" 'odd.html: unrecognised token left behind' "the leftover token is reported"

finish
