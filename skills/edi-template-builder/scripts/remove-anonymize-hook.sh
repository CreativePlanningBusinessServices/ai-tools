#!/bin/sh
# Unregister the anonymize-on-read PreToolUse hook that older versions of this
# skill installed into the user's Claude Code settings (~/.claude/settings.json).
# The skill no longer anonymizes anything, and a registered hook whose script is
# gone fails on every Read -- so run this BEFORE deleting an old skill folder.
#
# Re-runnable: if the hook is not registered, the script is a no-op. Every other
# hook in the file is left exactly as it is. Exit codes:
#   0 -- hook is now (or already was) unregistered
#   1 -- jq missing, or settings file is not valid JSON

set -eu

if ! command -v jq >/dev/null 2>&1; then
  echo "remove-anonymize-hook: jq is not on PATH. Install jq first (see INSTALL.md)." >&2
  exit 1
fi

SETTINGS_FILE="${CLAUDE_SETTINGS_FILE:-${HOME}/.claude/settings.json}"

if [ ! -f "$SETTINGS_FILE" ]; then
  echo "remove-anonymize-hook: $SETTINGS_FILE does not exist. Nothing to do."
  exit 0
fi

if ! jq -e . "$SETTINGS_FILE" >/dev/null 2>&1; then
  echo "remove-anonymize-hook: $SETTINGS_FILE is not valid JSON. Fix it manually before re-running." >&2
  exit 1
fi

IS_ANONYMIZE_HOOK='def is_anonymize_hook: (.command // "") | endswith("hooks/anonymize-on-read.sh");'

if ! jq -e "$IS_ANONYMIZE_HOOK"'
      [ .hooks.PreToolUse[]?.hooks[]? | select(is_anonymize_hook) ] | length > 0
    ' "$SETTINGS_FILE" >/dev/null 2>&1; then
  echo "remove-anonymize-hook: anonymize-on-read hook is not registered. Nothing to do."
  exit 0
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
jq "$IS_ANONYMIZE_HOOK"'
  .hooks.PreToolUse |= [
    .[]
    | if any(.hooks[]?; is_anonymize_hook) then
        (.hooks |= map(select(is_anonymize_hook | not))) | select(.hooks | length > 0)
      else . end
  ]
  | if (.hooks.PreToolUse | length) == 0 then del(.hooks.PreToolUse) else . end
' "$SETTINGS_FILE" > "$TMP"

# Write through the existing path rather than mv, so a symlinked settings file
# and its permissions survive.
cat "$TMP" > "$SETTINGS_FILE"

echo "remove-anonymize-hook: unregistered anonymize-on-read hook from $SETTINGS_FILE"
echo "remove-anonymize-hook: restart Claude Code for the change to take effect."
