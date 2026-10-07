#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib.sh"
scripts="$here/../skills/netsuite-email-designer/scripts"
data="$here/fixtures/caniemail-mini.json"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/email.html" <<'HTML'
<html><head><style>
@media (prefers-color-scheme: dark) { .card { background-color: #000; } }
a:hover { color: red; }
</style></head>
<body>
<table style="border-radius: 8px; background-color: #fff;"><tr>
<td style="padding: 8px; font-family: Georgia;"><div style="display: flex;">Hi ${entity.firstname}</div>
<img src="https://example.test/core/media/media.nl?id=1&_xt=.webp" width="10" />
<a href="mailto:someone">mail</a></td></tr></table>
</body></html>
HTML

output="$(bash "$scripts/email-compat.sh" "$tmp/email.html" --data "$data" 2>&1)"; status=$?
assert_eq "$status" 0 "checker exits 0"
unsupported="$(printf '%s\n' "$output" | sed -n '/^NOT SUPPORTED/,/^PARTIAL/p')"
partial="$(printf '%s\n' "$output" | sed -n '/^PARTIAL/,/^Supported everywhere/p')"
assert_contains "$unsupported" "[css-border-radius]" "inline border-radius is flagged unsupported"
assert_contains "$unsupported" "no       Outlook Windows (2019)" "the latest tested version is the one reported"
assert_not_contains "$unsupported" "Outlook Windows (2016)" "older versions are not reported"
assert_contains "$unsupported" "note 1: Use VML RoundRect." "caniemail's footnote is printed"
assert_contains "$unsupported" "[css-display-flex]" "display:flex maps to its own feature"
assert_contains "$unsupported" "[css-at-media-prefers-color-scheme]" "media features in a style block are found"
assert_contains "$unsupported" "[css-pseudo-class-hover]" "pseudo-classes in a style block are found"
assert_contains "$unsupported" "[image-webp]" "a media.nl _xt extension identifies the image format"
assert_contains "$partial" "[css-padding]" "partial support lands in the PARTIAL group"
assert_contains "$output" "Supported everywhere checked (2): background-color, mailto: links" "fully supported features are summarised"
assert_contains "$output" "No caniemail data for: color, font-family" "properties without data are listed, not dropped"
assert_not_contains "$output" "Outlook Outlook.com" "client labels don't repeat the family name"

output="$(bash "$scripts/email-compat.sh" "$tmp/missing.html" --data "$data" 2>&1)"; status=$?
assert_eq "$status" 1 "a missing input file fails"

printf '<html>\n<body bgcolor="#fff"\n  style="margin:0">\n<p>Hi</p>\n</body></html>\n' > "$tmp/preview.html"
bash "$scripts/preview-banner.sh" "$tmp/preview.html" 'Invoice ${transaction.tranid} \d' demo-account INV1 saved
preview="$(cat "$tmp/preview.html")"
assert_contains "$preview" 'style="margin:0"><div style="font:13px' "banner goes right after a multi-line <body> tag"
assert_contains "$preview" '<b>Subject:</b> Invoice ${transaction.tranid} \d &nbsp;' "subject text arrives unmangled"
assert_contains "$preview" '<b>Mode:</b> saved' "mode is shown"

printf '<p>no body</p>' > "$tmp/bare.html"
bash "$scripts/preview-banner.sh" "$tmp/bare.html" S demo-account X draft
assert_contains "$(head -c 4 "$tmp/bare.html")" '<div' "banner is prepended when there is no <body>"

bash "$scripts/preview-banner.sh" "$tmp/bare.html" S demo-account 2>/dev/null; status=$?
assert_eq "$status" 1 "banner script needs all five arguments"

finish
