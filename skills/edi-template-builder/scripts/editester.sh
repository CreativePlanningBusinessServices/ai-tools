#!/bin/sh
# Thin wrapper around the editester CLI. Ensures the platform-correct binary
# is present (downloading it on first use), then execs it with all args.
#
# Usage: editester serialize --template ... --data ... [--out ...] [...]
#        editester deserialize --template ... --input ... [...]
#        editester --version
#        editester --help

set -eu

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

bin="$("$PLUGIN_ROOT/scripts/ensure-editester.sh")"
exec "$bin" "$@"
