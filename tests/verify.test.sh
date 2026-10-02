#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib.sh"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pkg="$tmp/pkg"
js_root="$pkg/FileCabinet/SuiteScripts/CreativePlanning"
for file in RESTlet/cp_saved_search_rl.js RESTlet/cp_file_cabinet_rl.js RESTlet/cp_mr_driver_rl.js \
            netsuite_modules/saved-search-serializer/index.js netsuite_modules/file-cabinet/index.js; do
  mkdir -p "$js_root/$(dirname "$file")"
  printf 'define([], function () {});\n// %s\n' "$file" > "$js_root/$file"
done
cp "$here/../netsuite/restlets/verify.sh" "$pkg/verify.sh"
export PATH="$here/bin:$PATH" STUB_PACKAGE_DIR="$pkg"

run_verify() { STUB_MODE="$1" bash "$pkg/verify.sh" testalias > "$tmp/out.log" 2>&1; echo $?; }

assert_eq "$(run_verify ok)" 0 "healthy install exits 0"
assert_contains "$(cat "$tmp/out.log")" "all checks passed" "healthy install says so"
assert_not_contains "$(cat "$tmp/out.log")" "FAIL" "healthy install has no FAIL lines"

assert_eq "$(run_verify missing-script)" 1 "missing script exits 1"
assert_contains "$(cat "$tmp/out.log")" "FAIL all three scripts installed" "missing script is named"

assert_eq "$(run_verify mismatch)" 1 "changed deployed file exits 1"
assert_contains "$(cat "$tmp/out.log")" "FAIL deployed RESTlet/cp_saved_search_rl.js matches package" "mismatched file is named"

assert_eq "$(run_verify auth-fail)" 1 "unreachable account exits 1"
assert_contains "$(cat "$tmp/out.log")" "couldn't query account 'testalias'" "unreachable account is explained"
assert_not_contains "$(cat "$tmp/out.log")" "PASS" "unreachable account stops before running checks"

bash "$pkg/verify.sh" > "$tmp/out.log" 2>&1
assert_eq "$?" 1 "no alias exits 1"
assert_contains "$(cat "$tmp/out.log")" "usage" "no alias prints usage"

finish
