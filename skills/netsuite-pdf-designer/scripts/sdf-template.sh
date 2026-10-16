#!/usr/bin/env bash
# sdf-template.sh — saves and creates Advanced PDF/HTML templates through a scratch SuiteCloud (SDF) project,
# because NetSuite has no API that writes them.
# usage:
#   sdf-template.sh init   <authid> <project-dir>
#   sdf-template.sh import <project-dir> <scriptid>
#   sdf-template.sh stage  <project-dir> <scriptid> <draft.xml> --base <base-source> [--force]
#   sdf-template.sh create <project-dir> <scriptid> <draft.xml> --title <t> --printtype <TRANSACTION|STATEMENT|…>
#                          [--trantype <CUSTINVC…>] [--standard <STDTMPL…>]
#   sdf-template.sh deploy <project-dir> <scriptid> --expect <Update|Create>
# exit 0 ok, 1 refused/failed (reason on stderr), 2 usage
set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
validator="$script_dir/pdf-validate.sh"
templates_folder="Objects/Templates"

usage() {
  cat >&2 <<'USAGE'
usage: sdf-template.sh init   <authid> <project-dir>
       sdf-template.sh import <project-dir> <scriptid>
       sdf-template.sh stage  <project-dir> <scriptid> <draft.xml> --base <base-source> [--force]
       sdf-template.sh create <project-dir> <scriptid> <draft.xml> --title <t> --printtype <type> [--trantype <t>] [--standard <STDTMPL…>]
       sdf-template.sh deploy <project-dir> <scriptid> --expect <Update|Create>
USAGE
  exit 2
}
refuse() { echo "sdf-template: $*" >&2; exit 1; }

main() {
  [ $# -ge 1 ] || usage
  local command="$1"; shift
  case "$command" in
    init) command_init "$@" ;;
    import) command_import "$@" ;;
    stage) command_stage "$@" ;;
    create) command_create "$@" ;;
    deploy) command_deploy "$@" ;;
    *) usage ;;
  esac
}

command_stage() {
  [ $# -ge 3 ] || usage
  local project_dir="$1" scriptid base_file="" force=0 draft_file="$3"
  scriptid="$(normalize_scriptid "$2")"; shift 3
  while [ $# -gt 0 ]; do
    case "$1" in
      --base) [ $# -ge 2 ] || usage; base_file="$2"; shift ;;
      --force) force=1 ;;
      *) usage ;;
    esac
    shift
  done
  [ -n "$base_file" ] || usage
  require_project "$project_dir"
  [ -r "$draft_file" ] || refuse "cannot read draft $draft_file"
  [ -r "$base_file" ] || refuse "cannot read base $base_file"

  local validator_output validator_status
  validator_output="$(bash "$validator" "$draft_file" 2>&1)"; validator_status=$?
  if [ "$validator_status" -ne 0 ]; then
    printf '%s\n' "$validator_output" | grep '^ERROR' >&2
    [ "$validator_status" -eq 1 ] || printf '%s\n' "$validator_output" >&2
    refuse "the draft did not pass pdf-validate.sh; nothing was staged"
  fi

  import_template "$project_dir" "$scriptid" || exit 1
  local template_file="$project_dir/$templates_folder/$scriptid.template.xml"
  if [ "$force" -eq 0 ] && [ "$(strip_carriage_returns "$template_file")" != "$(strip_carriage_returns "$base_file")" ]; then
    refuse "$scriptid changed in NetSuite since the draft's base was read; re-read it and merge, or pass --force to overwrite"
  fi
  cp "$draft_file" "$template_file" || exit 1
  write_deploy_xml "$project_dir" "$scriptid"
  echo "staged $scriptid in $project_dir"
}

command_create() {
  [ $# -ge 3 ] || usage
  local project_dir="$1" scriptid="$2" draft_file="$3"
  local title="" printtype="" trantype="" standard="STDTMPLEMPTY"
  shift 3
  while [ $# -gt 0 ]; do
    case "$1" in
      --title) [ $# -ge 2 ] || usage; title="$2"; shift ;;
      --printtype) [ $# -ge 2 ] || usage; printtype="$2"; shift ;;
      --trantype) [ $# -ge 2 ] || usage; trantype="$2"; shift ;;
      --standard) [ $# -ge 2 ] || usage; standard="$2"; shift ;;
      *) usage ;;
    esac
    shift
  done
  [ -n "$title" ] && [ -n "$printtype" ] || usage
  require_project "$project_dir"
  [ -r "$draft_file" ] || refuse "cannot read draft $draft_file"
  scriptid="$(normalize_scriptid "$scriptid")"
  case "$scriptid" in custtmpl_*) ;; *) refuse "scriptid must start with custtmpl_" ;; esac

  local validator_output validator_status
  validator_output="$(bash "$validator" "$draft_file" 2>&1)"; validator_status=$?
  if [ "$validator_status" -ne 0 ]; then
    printf '%s\n' "$validator_output" | grep '^ERROR' >&2
    refuse "the draft did not pass pdf-validate.sh; nothing was created"
  fi

  local trantype_line=""
  [ -z "$trantype" ] || trantype_line="  <trantype>$(xml_escape "$trantype")</trantype>"
  {
    printf '<advancedpdftemplate scriptid="%s" standard="%s">\n' "$scriptid" "$(xml_escape "$standard")"
    printf '  <description></description>\n'
    printf '  <displaysourcecode>T</displaysourcecode>\n'
    printf '  <isinactive>F</isinactive>\n'
    printf '  <preferred>F</preferred>\n'
    printf '  <printtype>%s</printtype>\n' "$(xml_escape "$printtype")"
    printf '  <title>%s</title>\n' "$(xml_escape "$title")"
    [ -z "$trantype_line" ] || printf '%s\n' "$trantype_line"
    printf '</advancedpdftemplate>\n'
  } > "$project_dir/$templates_folder/$scriptid.xml"
  cp "$draft_file" "$project_dir/$templates_folder/$scriptid.template.xml" || exit 1
  write_deploy_xml "$project_dir" "$scriptid"
  echo "created $scriptid in $project_dir"
}

command_deploy() {
  [ $# -ge 4 ] || usage
  local project_dir="$1" scriptid expected_verb=""
  scriptid="$(normalize_scriptid "$2")"; shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --expect) [ $# -ge 2 ] || usage; expected_verb="$2"; shift ;;
      *) usage ;;
    esac
    shift
  done
  case "$expected_verb" in Update|Create) ;; *) usage ;; esac
  require_project "$project_dir"

  local authid
  authid="$(jq -r '.defaultAuthId // empty' "$project_dir/project.json")"
  [ -n "$authid" ] || refuse "project.json has no defaultAuthId"
  echo "deploying with auth id $authid"

  local preview preview_status
  preview="$(cd "$project_dir" && suitecloud project:deploy --dryrun 2>&1)"; preview_status=$?
  if [ "$preview_status" -ne 0 ]; then
    printf '%s\n' "$preview" >&2
    refuse "the deploy dry run failed; nothing was deployed"
  fi

  local object_steps expected_step
  object_steps="$(printf '%s\n' "$preview" | strip_terminal_codes | awk '
    /CUSTOM_OBJECT_(CREATION|UPDATE) --- / { verb = ($0 ~ /CREATION/) ? "Create" : "Update"; id = $0; sub(/.*--- /, "", id); sub(/ .*/, "", id); print verb " " id; next }
    /(Create|Update) object -- / { verb = ($0 ~ /Create object/) ? "Create" : "Update"; id = $0; sub(/.*object -- /, "", id); sub(/[ (].*/, "", id); print verb " " id }')"
  expected_step="$expected_verb $scriptid"
  if [ "$object_steps" != "$expected_step" ]; then
    printf '%s\n' "$preview" >&2
    refuse "the dry run lists [$(printf '%s' "$object_steps" | tr '\n' ';')] but only [$expected_step] was expected; nothing was deployed"
  fi

  (cd "$project_dir" && suitecloud project:deploy) || refuse "project:deploy failed"
}

command_init() {
  [ $# -eq 2 ] || usage
  local authid="$1" project_dir="$2"
  if ! list_auth_ids | grep -Fxq "$authid"; then
    refuse "$authid is not a SuiteCloud auth id (see: suitecloud account:manageauth --list)"
  fi
  mkdir -p "$project_dir/$templates_folder" || exit 1
  printf '{ "defaultAuthId": "%s" }\n' "$authid" > "$project_dir/project.json"
  cat > "$project_dir/manifest.xml" <<'MANIFEST'
<manifest projecttype="ACCOUNTCUSTOMIZATION">
  <projectname>cp-pdf-designer</projectname>
  <frameworkversion>1.0</frameworkversion>
  <dependencies>
    <features>
      <feature required="true">SERVERSIDESCRIPTING</feature>
      <feature required="true">ADVANCEDPRINTING</feature>
    </features>
  </dependencies>
</manifest>
MANIFEST
  echo "module.exports = { defaultProjectFolder: '.', commands: {} };" > "$project_dir/suitecloud.config.js"
  write_deploy_xml "$project_dir"
  echo "initialized $project_dir for $authid"
}

command_import() {
  [ $# -eq 2 ] || usage
  require_project "$1"
  import_template "$1" "$(normalize_scriptid "$2")" || exit 1
}

import_template() {
  local project_dir="$1" scriptid="$2"
  rm -f "$project_dir/$templates_folder/$scriptid.xml" "$project_dir/$templates_folder/$scriptid.template.xml"
  (cd "$project_dir" && suitecloud object:import --type advancedpdftemplate --scriptid "$scriptid" \
    --destinationfolder "/$templates_folder") >&2 || { echo "sdf-template: object:import of $scriptid failed" >&2; return 1; }
  [ -f "$project_dir/$templates_folder/$scriptid.template.xml" ] || { echo "sdf-template: import produced no $scriptid.template.xml" >&2; return 1; }
}

# deploy.xml is rewritten for every staged object so a deploy can never carry another template along.
write_deploy_xml() {
  local project_dir="$1" scriptid="${2:-}"
  {
    echo '<deploy>'
    echo '  <objects>'
    if [ -n "$scriptid" ]; then
      echo "    <path>~/$templates_folder/$scriptid.xml</path>"
      echo "    <path>~/$templates_folder/$scriptid.template.xml</path>"
    fi
    echo '  </objects>'
    echo '</deploy>'
  } > "$project_dir/deploy.xml"
}

require_project() {
  [ -f "$1/project.json" ] && [ -d "$1/$templates_folder" ] || refuse "$1 is not a project made by 'sdf-template.sh init'"
}

list_auth_ids() {
  suitecloud account:manageauth --list 2>/dev/null | strip_terminal_codes | awk -F' [|] ' 'NF >= 2 { gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1 }'
}

strip_terminal_codes() { sed $'s/\x1b\\[[0-9;]*[A-Za-z]//g'; }
# Command substitution drops trailing newlines, so a base saved with `jq -r` (which appends one) still matches.
strip_carriage_returns() { tr -d '\r' < "$1"; }
normalize_scriptid() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
xml_escape() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }

main "$@"
