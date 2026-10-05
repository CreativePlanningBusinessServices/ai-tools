#!/usr/bin/env bash
# Checks that the CP RESTlets are installed and answering in one account, and that the
# deployed files match this package. Read-only: it never writes to the account.
set -uo pipefail

alias_name="${1:?usage: verify.sh <netsuite-cli account alias>}"
package_dir="$(cd "$(dirname "$0")" && pwd)"
js_root=FileCabinet/SuiteScripts/CreativePlanning
# The files to compare are exactly the ones deploy.xml ships.
js_files=()
while IFS= read -r file; do
  js_files+=("$file")
done < <(sed -n "s#.*<path>~/$js_root/\(.*\)</path>.*#\1#p" "$package_dir/deploy.xml")
if [ "${#js_files[@]}" -eq 0 ]; then
  echo "verify: no files listed in $package_dir/deploy.xml"
  exit 1
fi
expected_scripts="customscript_cp_email_template_rl customscript_cp_file_cabinet_rl customscript_cp_mr_driver_rl customscript_cp_saved_search_rl "
failures=0

check() { # <label> <status>
  if [ "$2" -eq 0 ]; then echo "PASS $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi
}
restlet() { # <name> <restlet call args...>
  local name="$1"; shift
  netsuite-cli restlet call --account "$alias_name" \
    --script "customscript_cp_${name}_rl" --deploy "customdeploy_cp_${name}_rl" "$@" 2>&1
}

script_rows="$(netsuite-cli suiteql --account "$alias_name" "SELECT scriptid FROM script WHERE scriptid IN ('customscript_cp_saved_search_rl', 'customscript_cp_file_cabinet_rl', 'customscript_cp_mr_driver_rl', 'customscript_cp_email_template_rl')" 2>&1)"
if ! printf '%s' "$script_rows" | jq -e '.items' > /dev/null 2>&1; then
  echo "verify: couldn't query account '$alias_name' with netsuite-cli: $(printf '%s' "$script_rows" | head -n 1)"
  exit 1
fi
installed="$(printf '%s' "$script_rows" | jq -r '.items[].scriptid' | sort | tr '\n' ' ')"
[ "$installed" = "$expected_scripts" ]
check "all four scripts installed (found: ${installed:-none})" $?

restlet file_cabinet --method GET --param "folder=/" | jq -e '.folders | type == "array"' > /dev/null 2>&1
check "file cabinet: list the root folder" $?

search_id="$(netsuite-cli suiteql --account "$alias_name" "SELECT id FROM savedsearch FETCH FIRST 1 ROWS ONLY" 2> /dev/null | jq -r '.items[0].id // empty' 2> /dev/null)"
if [ -n "$search_id" ]; then
  restlet saved_search --method GET --param "id=$search_id" | jq -e 'has("type") and (has("error") | not)' > /dev/null 2>&1
  check "saved search: describe search $search_id" $?
else
  check "saved search: describe (no saved search in the account to describe)" 1
fi

restlet mr_driver --method GET --param "taskid=MAPREDUCETASK_0000000000" | grep -q 'no task found'
check "mr driver: answers a poll with its own not-found error" $?

template_id="$(netsuite-cli suiteql --account "$alias_name" "SELECT id FROM emailtemplate WHERE isinactive = 'F' FETCH FIRST 1 ROWS ONLY" 2> /dev/null | jq -r '.items[0].id // empty' 2> /dev/null)"
if [ -n "$template_id" ]; then
  restlet email_template --method GET --param "id=$template_id" | jq -e 'has("body") and (has("error") | not)' > /dev/null 2>&1
  check "email template: describe template $template_id" $?
else
  check "email template: describe (no active email template in the account to describe)" 1
fi

deployed="$(mktemp)"
trap 'rm -f "$deployed"' EXIT
for file in "${js_files[@]}"; do
  restlet file_cabinet --method GET --param "path=/SuiteScripts/CreativePlanning/$file" --param contents=T \
    | jq -j 'if .contentsEncoding == "base64" then .contents | @base64d else .contents end' > "$deployed" 2> /dev/null
  cmp -s "$deployed" "$package_dir/$js_root/$file"
  check "deployed $file matches package" $?
done

if [ "$failures" -eq 0 ]; then
  echo "verify: all checks passed for $alias_name"
else
  echo "verify: $failures check(s) failed for $alias_name"
fi
[ "$failures" -eq 0 ]
