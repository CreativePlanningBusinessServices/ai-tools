# tests/lib.sh — shared helpers for the plain-bash test scripts in this directory.
fail_count=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }
assert_eq() { if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3 (missing '$2')" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) fail "$3 (unexpected '$2')" ;; *) pass "$3" ;; esac; }
finish() {
  if [ "$fail_count" -eq 0 ]; then echo "all passed"; exit 0; fi
  echo "$fail_count failed"; exit 1
}
