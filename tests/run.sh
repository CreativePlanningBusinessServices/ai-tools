#!/usr/bin/env bash
# tests/run.sh — runs every tests/*.test.sh and fails if any of them fails.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
status=0
for test_script in "$here"/*.test.sh; do
  echo "== $(basename "$test_script")"
  bash "$test_script" || status=1
done
exit "$status"
