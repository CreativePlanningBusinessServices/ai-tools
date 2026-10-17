#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib.sh"
helper="$here/../skills/netsuite-pdf-designer/scripts/sdf-template.sh"
fixtures="$here/fixtures/pdf"
export PATH="$here/bin:$PATH"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export FAKE_SUITECLOUD_LOG="$tmp/suitecloud.log"
export FAKE_SUITECLOUD_IMPORT_DIR="$tmp/import"
export FAKE_SUITECLOUD_DRYRUN="$tmp/dryrun.txt"
mkdir -p "$FAKE_SUITECLOUD_IMPORT_DIR"
: > "$FAKE_SUITECLOUD_LOG"

run_helper() { output="$(bash "$helper" "$@" 2>&1)"; status=$?; }

scriptid=custtmpl_acs_tax_inv_with_link
object_xml='<advancedpdftemplate scriptid="custtmpl_acs_tax_inv_with_link" standard="STDTMPLEMPTY">
  <preferred>T</preferred>
  <title>Existing</title>
</advancedpdftemplate>'
printf '%s\n' "$object_xml" > "$FAKE_SUITECLOUD_IMPORT_DIR/$scriptid.xml"
# NetSuite sources use CRLF; the account copy differs from the draft only by one word.
sed 's/$/\r/' "$fixtures/good.xml" > "$FAKE_SUITECLOUD_IMPORT_DIR/$scriptid.template.xml"
cp "$fixtures/good.xml" "$tmp/base.xml"
sed 's/INVOICE #/STATEMENT #/' "$fixtures/good.xml" > "$tmp/draft.xml"
cmp -s "$tmp/draft.xml" "$tmp/base.xml" && echo "fixture good.xml is unchanged by the draft edit" >&2

project="$tmp/project"

# init
run_helper init 1234567_SB1 "$project"
assert_eq "$status" 0 "init exits 0"
assert_contains "$(cat "$project/project.json")" '"defaultAuthId": "1234567_SB1"' "init writes the authid"
assert_contains "$(cat "$project/manifest.xml")" '<feature required="true">ADVANCEDPRINTING</feature>' "manifest requires ADVANCEDPRINTING"
assert_contains "$(cat "$project/manifest.xml")" 'projecttype="ACCOUNTCUSTOMIZATION"' "manifest is an ACP"
[ -f "$project/suitecloud.config.js" ] && pass "init writes suitecloud.config.js" || fail "init writes suitecloud.config.js"
[ -f "$project/deploy.xml" ] && [ -d "$project/Objects/Templates" ] && pass "init writes deploy.xml and Objects/Templates" || fail "init writes deploy.xml and Objects/Templates"
run_helper init 1234567_NOPE "$tmp/other"
assert_eq "$status" 1 "init with an unknown authid exits 1"
assert_contains "$output" "not a SuiteCloud auth id" "init explains an unknown authid"
run_helper init
assert_eq "$status" 2 "init without arguments is a usage error"

# import
run_helper import "$project" CUSTTMPL_ACS_TAX_INV_WITH_LINK
assert_eq "$status" 0 "import exits 0"
assert_contains "$(cat "$FAKE_SUITECLOUD_LOG")" "--scriptid custtmpl_acs_tax_inv_with_link" "import lowercases the scriptid"
assert_contains "$(cat "$FAKE_SUITECLOUD_LOG")" "--type advancedpdftemplate" "import passes the type"
assert_contains "$(cat "$FAKE_SUITECLOUD_LOG")" "--destinationfolder /Objects/Templates" "import passes the destination folder"
assert_contains "$(cat "$FAKE_SUITECLOUD_LOG")" "$project |" "import runs inside the project dir"

# stage
template="$project/Objects/Templates/$scriptid.template.xml"
run_helper stage "$project" "$scriptid" "$tmp/draft.xml" --base "$tmp/base.xml"
assert_eq "$status" 0 "stage with a matching base exits 0 (CRLF source vs LF base)"
cmp -s "$tmp/draft.xml" "$template" && pass "stage writes the draft byte for byte" || fail "stage writes the draft byte for byte"
assert_eq "$(grep -c '<path>' "$project/deploy.xml")" 2 "stage scopes deploy.xml to two paths"
assert_contains "$(cat "$project/deploy.xml")" "<path>~/Objects/Templates/$scriptid.xml</path>" "deploy.xml lists the object XML"
assert_contains "$(cat "$project/deploy.xml")" "<path>~/Objects/Templates/$scriptid.template.xml</path>" "deploy.xml lists the template source"
assert_eq "$(cat "$project/Objects/Templates/$scriptid.xml")" "$object_xml" "stage leaves the object XML untouched"

{ cat "$tmp/base.xml"; echo; } > "$tmp/base-extra-newline.xml"
run_helper stage "$project" "$scriptid" "$tmp/draft.xml" --base "$tmp/base-extra-newline.xml"
assert_eq "$status" 0 "stage ignores a trailing newline added by jq -r"

printf 'something else\n' > "$tmp/other-base.xml"
run_helper stage "$project" "$scriptid" "$tmp/draft.xml" --base "$tmp/other-base.xml"
assert_eq "$status" 1 "stage with a different base exits 1"
assert_contains "$output" "changed in NetSuite since" "stage explains the base mismatch"
run_helper stage "$project" "$scriptid" "$tmp/draft.xml" --base "$tmp/other-base.xml" --force
assert_eq "$status" 0 "stage --force proceeds past a base mismatch"

run_helper stage "$project" "$scriptid" "$fixtures/fm-unclosed-if.xml" --base "$tmp/base.xml"
assert_eq "$status" 1 "stage refuses a draft that fails the validator"
assert_contains "$output" "ERROR" "stage passes the validator's ERROR lines through"
run_helper stage "$project" "$scriptid" "$tmp/draft.xml"
assert_eq "$status" 2 "stage without --base is a usage error"

# a refused stage leaves nothing deployable
run_helper stage "$project" "$scriptid" "$tmp/draft.xml" --base "$tmp/other-base.xml"
assert_eq "$(grep -c '<path>' "$project/deploy.xml")" 0 "a base-mismatch refusal empties deploy.xml"
run_helper stage "$project" "$scriptid" "$fixtures/fm-unclosed-if.xml" --base "$tmp/base.xml"
assert_eq "$(grep -c '<path>' "$project/deploy.xml")" 0 "a validator refusal empties deploy.xml"

# scriptid validation: uppercase is fine, anything path-like or unescaped is refused
for bad_scriptid in ../x custtmpl_a/b "custtmpl_a b" 'custtmpl_a"b' custtmpl_; do
  run_helper stage "$project" "$bad_scriptid" "$tmp/draft.xml" --base "$tmp/base.xml"
  assert_eq "$status" 1 "stage refuses scriptid '$bad_scriptid'"
  run_helper create "$project" "$bad_scriptid" "$tmp/draft.xml" --title T --printtype TRANSACTION
  assert_eq "$status" 1 "create refuses scriptid '$bad_scriptid'"
  run_helper import "$project" "$bad_scriptid"
  assert_eq "$status" 1 "import refuses scriptid '$bad_scriptid'"
done
run_helper stage "$project" CUSTTMPL_ACS_TAX_INV_WITH_LINK "$tmp/draft.xml" --base "$tmp/base.xml"
assert_eq "$status" 0 "stage accepts an uppercase scriptid"
run_helper create "$project" CUSTTMPL_UPPER "$tmp/draft.xml" --title T --printtype TRANSACTION
assert_eq "$status" 0 "create accepts an uppercase scriptid"
[ -f "$project/Objects/Templates/custtmpl_upper.xml" ] && pass "create lowercases the file name" || fail "create lowercases the file name"

# init on existing directories
run_helper init 1234567_SB1 "$project"
assert_eq "$status" 0 "init is repeatable for the same project and authid"
run_helper init 1234567 "$project"
assert_eq "$status" 1 "init refuses an existing project with another authid"
mkdir -p "$tmp/real-sdf-repo/Objects/Templates"
echo '<manifest projecttype="ACCOUNTCUSTOMIZATION"><projectname>other</projectname></manifest>' > "$tmp/real-sdf-repo/manifest.xml"
echo '{ "defaultAuthId": "1234567_SB1" }' > "$tmp/real-sdf-repo/project.json"
run_helper init 1234567_SB1 "$tmp/real-sdf-repo"
assert_eq "$status" 1 "init refuses a non-empty directory that is not a designer project"
run_helper stage "$tmp/real-sdf-repo" "$scriptid" "$tmp/draft.xml" --base "$tmp/base.xml"
assert_eq "$status" 1 "stage refuses an SDF repo whose manifest is not the scratch project"
assert_contains "$output" "not a project made by" "stage explains the rejected project"

# create
run_helper create "$project" custtmpl_cp_x "$tmp/draft.xml" --title 'Fish & "Chips" <1>' --printtype TRANSACTION --trantype CUSTINVC
assert_eq "$status" 0 "create exits 0"
created="$(cat "$project/Objects/Templates/custtmpl_cp_x.xml")"
assert_contains "$created" 'scriptid="custtmpl_cp_x"' "create writes the scriptid"
assert_contains "$created" 'standard="STDTMPLEMPTY"' "create defaults to STDTMPLEMPTY"
assert_contains "$created" '<preferred>F</preferred>' "create writes preferred F"
assert_contains "$created" '<isinactive>F</isinactive>' "create writes isinactive F"
assert_contains "$created" '<displaysourcecode>T</displaysourcecode>' "create writes displaysourcecode T"
assert_contains "$created" '<title>Fish &amp; &quot;Chips&quot; &lt;1&gt;</title>' "create escapes the title"
assert_contains "$created" '<printtype>TRANSACTION</printtype>' "create writes the print type"
assert_contains "$created" '<trantype>CUSTINVC</trantype>' "create writes the transaction type"
cmp -s "$tmp/draft.xml" "$project/Objects/Templates/custtmpl_cp_x.template.xml" && pass "create writes the draft as the source" || fail "create writes the draft as the source"
assert_contains "$(cat "$project/deploy.xml")" "custtmpl_cp_x.template.xml" "create scopes deploy.xml"
assert_not_contains "$(cat "$project/deploy.xml")" "$scriptid" "create's deploy.xml drops the previous object"
run_helper create "$project" custtmpl_cp_y "$tmp/draft.xml" --title T --printtype STATEMENT --standard STDTMPLCUSTINVCST
created="$(cat "$project/Objects/Templates/custtmpl_cp_y.xml")"
assert_contains "$created" 'standard="STDTMPLCUSTINVCST"' "create honors --standard"
assert_not_contains "$created" '<trantype>' "create omits trantype when not given"
run_helper create "$project" cp_no_prefix "$tmp/draft.xml" --title T --printtype TRANSACTION
assert_eq "$status" 1 "create without the custtmpl_ prefix exits 1"
run_helper create "$project" custtmpl_cp_z "$tmp/draft.xml" --title T --printtype TRANSACTION --preferred T
assert_eq "$status" 2 "create rejects a preferred flag"

# deploy
deploy_log_count() { grep -c 'project:deploy' "$FAKE_SUITECLOUD_LOG"; }
real_deploys() { grep 'project:deploy' "$FAKE_SUITECLOUD_LOG" | grep -vc -- '--dryrun'; }
printf '%s\n' '✔ Step 6: CUSTOM_OBJECT_VALIDATION --- custtmpl_cp_x (advancedpdftemplate)' \
  '✔ Step 19: CUSTOM_OBJECT_UPDATE --- custtmpl_cp_x (advancedpdftemplate)' > "$FAKE_SUITECLOUD_DRYRUN"
: > "$FAKE_SUITECLOUD_LOG"
run_helper deploy "$project" custtmpl_cp_x --expect Update --authid 1234567_SB1
assert_eq "$status" 0 "deploy with a matching dry run exits 0"
assert_contains "$output" "1234567_SB1" "deploy prints the project's authid"
assert_eq "$(real_deploys)" 1 "deploy runs the real project:deploy once"

printf '%s\n' '✔ Step 19: Update object -- custtmpl_cp_x' > "$FAKE_SUITECLOUD_DRYRUN"
: > "$FAKE_SUITECLOUD_LOG"
run_helper deploy "$project" custtmpl_cp_x --expect Update --authid 1234567_SB1
assert_eq "$status" 0 "deploy accepts the older 'Update object --' wording"

printf '%s\n' '✔ Step 19: CUSTOM_OBJECT_UPDATE --- custtmpl_cp_x (advancedpdftemplate)' \
  '✔ Step 20: CUSTOM_OBJECT_UPDATE --- custtmpl_other (advancedpdftemplate)' > "$FAKE_SUITECLOUD_DRYRUN"
: > "$FAKE_SUITECLOUD_LOG"
run_helper deploy "$project" custtmpl_cp_x --expect Update --authid 1234567_SB1
assert_eq "$status" 1 "deploy refuses a dry run naming a second object"
assert_eq "$(real_deploys)" 0 "a second object never reaches the real deploy"

printf '%s\n' '✔ Step 19: CUSTOM_OBJECT_CREATION --- custtmpl_cp_x (advancedpdftemplate)' > "$FAKE_SUITECLOUD_DRYRUN"
: > "$FAKE_SUITECLOUD_LOG"
run_helper deploy "$project" custtmpl_cp_x --expect Update --authid 1234567_SB1
assert_eq "$status" 1 "deploy refuses Create when Update was expected"
assert_eq "$(real_deploys)" 0 "a wrong verb never reaches the real deploy"
assert_eq "$(deploy_log_count)" 1 "only the dry run was invoked"

printf '%s\n' '✔ Step 1: PROJECT_VALIDATION' > "$FAKE_SUITECLOUD_DRYRUN"
: > "$FAKE_SUITECLOUD_LOG"
run_helper deploy "$project" custtmpl_cp_x --expect Update --authid 1234567_SB1
assert_eq "$status" 1 "deploy refuses an empty object preview"
assert_eq "$(real_deploys)" 0 "an empty preview never reaches the real deploy"


# authid guard
printf '%s\n' '✔ Step 19: CUSTOM_OBJECT_UPDATE --- custtmpl_cp_x (advancedpdftemplate)' > "$FAKE_SUITECLOUD_DRYRUN"
: > "$FAKE_SUITECLOUD_LOG"
run_helper deploy "$project" custtmpl_cp_x --expect Update --authid 1234567
assert_eq "$status" 1 "deploy refuses when project.json targets another account"
assert_contains "$output" "project.json targets 1234567_SB1, not 1234567" "deploy names both account ids"
assert_eq "$(deploy_log_count)" 0 "an authid mismatch never calls project:deploy"
run_helper deploy "$project" custtmpl_cp_x --expect Update
assert_eq "$status" 2 "deploy without --authid is a usage error"

# prefix scriptids stay separate; project paths may contain spaces
printf '%s\n' '✔ Step 19: CUSTOM_OBJECT_UPDATE --- custtmpl_cp_x2 (advancedpdftemplate)' > "$FAKE_SUITECLOUD_DRYRUN"
: > "$FAKE_SUITECLOUD_LOG"
run_helper deploy "$project" custtmpl_cp_x --expect Update --authid 1234567_SB1
assert_eq "$status" 1 "deploy refuses custtmpl_cp_x2 when custtmpl_cp_x was expected"
assert_eq "$(real_deploys)" 0 "a prefix-only match never reaches the real deploy"

spaced_project="$tmp/my project"
run_helper init 1234567_SB1 "$spaced_project"
assert_eq "$status" 0 "init works in a path with a space"
run_helper stage "$spaced_project" "$scriptid" "$tmp/draft.xml" --base "$tmp/base.xml"
assert_eq "$status" 0 "stage works in a path with a space"
printf '%s\n' "✔ Step 19: CUSTOM_OBJECT_UPDATE --- $scriptid (advancedpdftemplate)" > "$FAKE_SUITECLOUD_DRYRUN"
: > "$FAKE_SUITECLOUD_LOG"
run_helper deploy "$spaced_project" CUSTTMPL_ACS_TAX_INV_WITH_LINK --expect Update --authid 1234567_SB1
assert_eq "$status" 0 "deploy works in a spaced path with an uppercase scriptid"
assert_eq "$(real_deploys)" 1 "the spaced project reached the real deploy"

finish
