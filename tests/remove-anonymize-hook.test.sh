#!/usr/bin/env bash
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib.sh"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
script="$here/../skills/edi-template-builder/scripts/remove-anonymize-hook.sh"
settings="$tmp/claude home/settings.json"
mkdir -p "$(dirname "$settings")"
anonymize_command='/Users/someone/.claude/skills/edi-template-builder/hooks/anonymize-on-read.sh'

run_remove() { CLAUDE_SETTINGS_FILE="$settings" sh "$script" > "$tmp/out.log" 2>&1; echo $?; }
commands() { jq -c '[.hooks.PreToolUse[]?.hooks[]?.command]' "$settings"; }

jq -n --arg cmd "$anonymize_command" '{
  env: { KEEP: "me" },
  hooks: {
    PreToolUse: [
      { matcher: "Read", hooks: [ { type: "command", command: $cmd } ] },
      { matcher: "Bash", hooks: [ { type: "command", command: "/usr/local/bin/other.sh", timeout: 120 } ] }
    ],
    PostToolUse: [ { matcher: "Write", hooks: [ { type: "command", command: "echo done" } ] } ]
  }
}' > "$settings"
assert_eq "$(run_remove)" 0 "removing a registered hook exits 0"
assert_contains "$(cat "$tmp/out.log")" "unregistered anonymize-on-read hook" "the removal is reported"
assert_eq "$(commands)" '["/usr/local/bin/other.sh"]' "only the anonymize hook is removed"
assert_eq "$(jq -c '.hooks.PreToolUse | map(.matcher)' "$settings")" '["Bash"]' "the emptied Read matcher is dropped"
assert_eq "$(jq -c '[.env.KEEP, .hooks.PreToolUse[0].hooks[0].timeout, .hooks.PostToolUse[0].matcher]' "$settings")" \
  '["me",120,"Write"]' "everything else in the file is untouched"

before="$(cat "$settings")"
assert_eq "$(run_remove)" 0 "re-running exits 0"
assert_contains "$(cat "$tmp/out.log")" "not registered" "re-running reports nothing to do"
assert_eq "$(cat "$settings")" "$before" "re-running leaves the file byte-for-byte unchanged"

jq -n --arg cmd "$anonymize_command" '{
  hooks: { PreToolUse: [ { matcher: "Read", hooks: [
    { type: "command", command: $cmd },
    { type: "command", command: "/usr/local/bin/read-audit.sh" }
  ] } ] }
}' > "$settings"
assert_eq "$(run_remove)" 0 "a Read matcher shared with another hook exits 0"
assert_eq "$(commands)" '["/usr/local/bin/read-audit.sh"]' "the other hook under the same matcher survives"

jq -n --arg cmd "$anonymize_command" '{
  hooks: { PreToolUse: [ { matcher: "Read", hooks: [ { type: "command", command: $cmd } ] } ] }
}' > "$settings"
assert_eq "$(run_remove)" 0 "a file whose only hook is ours exits 0"
assert_eq "$(jq -c '.hooks' "$settings")" '{}' "an emptied PreToolUse list is dropped"

echo '{ not json' > "$settings"
assert_eq "$(run_remove)" 1 "invalid JSON exits 1"
assert_eq "$(cat "$settings")" '{ not json' "an invalid settings file is left alone"

rm "$settings"
assert_eq "$(run_remove)" 0 "a missing settings file exits 0"
assert_contains "$(cat "$tmp/out.log")" "Nothing to do" "a missing settings file is explained"

finish
