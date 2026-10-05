#!/bin/sh
# Resolve the platform-correct editester binary, downloading it on first use.
# Prints the absolute path of a ready-to-execute binary on stdout. Exit 0 on
# success, non-zero on failure with a message on stderr.

set -eu

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
BIN_DIR="$PLUGIN_ROOT/bin"
BASE_URL="https://storageukgreadyedi.blob.core.windows.net/ai-tools/editester-cli"

uname_s="$(uname -s)"
uname_m="$(uname -m)"

case "$uname_s" in
  Darwin)
    case "$uname_m" in
      arm64)   asset="editester-darwin-arm64" ;;
      x86_64)  asset="editester-darwin-x64" ;;
      *)       printf 'ensure-editester: unsupported macOS arch: %s\n' "$uname_m" >&2; exit 1 ;;
    esac
    ;;
  Linux)
    case "$uname_m" in
      x86_64)  asset="editester-linux-x64" ;;
      *)       printf 'ensure-editester: unsupported Linux arch: %s\n' "$uname_m" >&2; exit 1 ;;
    esac
    ;;
  MINGW*|MSYS*|CYGWIN*)
    asset="editester-windows-x64.exe"
    ;;
  *)
    printf 'ensure-editester: unsupported OS: %s\n' "$uname_s" >&2
    exit 1
    ;;
esac

target="$BIN_DIR/$asset"

if [ -x "$target" ] && [ -s "$target" ]; then
  printf '%s\n' "$target"
  exit 0
fi

mkdir -p "$BIN_DIR"

url="$BASE_URL/$asset"
printf 'edi-template-builder: downloading %s (one-time setup)...\n' "$asset" >&2

# Atomic-ish download: write to .part then rename so a partial download never
# masquerades as a usable binary.
tmp="$target.part"
if command -v curl >/dev/null 2>&1; then
  if ! curl -fL --retry 3 --connect-timeout 15 -o "$tmp" "$url"; then
    rm -f "$tmp"
    printf 'ensure-editester: download failed from %s\n' "$url" >&2
    exit 1
  fi
elif command -v wget >/dev/null 2>&1; then
  if ! wget -qO "$tmp" "$url"; then
    rm -f "$tmp"
    printf 'ensure-editester: download failed from %s\n' "$url" >&2
    exit 1
  fi
else
  printf 'ensure-editester: neither curl nor wget is installed; cannot download %s\n' "$asset" >&2
  exit 1
fi

chmod +x "$tmp"
mv "$tmp" "$target"

printf '%s\n' "$target"
