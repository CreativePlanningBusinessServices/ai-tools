#!/usr/bin/env bash
# Rebuilds the CP RESTlets from sdf-creative-planning and copies the deployable output
# into this package. Builds in a temporary worktree so the source checkout's branch and
# uncommitted changes are never used or touched. Never commits.
set -euo pipefail

source_repo="${1:-$HOME/projects/creativeplanning/creative-planning}"
ref="${2:-origin/main}"
package_dir="${SYNC_OUT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

js_root=FileCabinet/SuiteScripts/CreativePlanning
xml_root=Objects/Scripts/RESTlet
restlet_files=(RESTlet/cp_saved_search_rl.js RESTlet/cp_file_cabinet_rl.js RESTlet/cp_mr_driver_rl.js RESTlet/cp_email_template_rl.js)
js_files=("${restlet_files[@]}" netsuite_modules/saved-search-serializer/index.js netsuite_modules/file-cabinet/index.js netsuite_modules/email-template/index.js)
xml_files=(customscript_cp_saved_search_rl.xml customscript_cp_file_cabinet_rl.xml customscript_cp_mr_driver_rl.xml customscript_cp_email_template_rl.xml)

die() { echo "sync: $*" >&2; exit 1; }

# deploy.xml lists files one by one; a packaged file it doesn't list would never reach the account.
deploy_xml="$(cd "$(dirname "$0")" && pwd)/deploy.xml"
[ -f "$deploy_xml" ] || die "deploy.xml not found next to sync.sh"
for file in "${js_files[@]}"; do
  grep -qF "<path>~/$js_root/$file</path>" "$deploy_xml" || die "packaged file not listed in deploy.xml: $file"
done
for file in "${xml_files[@]}"; do
  grep -qF "<path>~/$xml_root/$file</path>" "$deploy_xml" || die "packaged object not listed in deploy.xml: $file"
done

git -C "$source_repo" rev-parse --git-dir > /dev/null 2>&1 || die "not a git repo: $source_repo"
source_repo="$(cd "$source_repo" && pwd)"
if git -C "$source_repo" remote get-url origin > /dev/null 2>&1; then
  git -C "$source_repo" fetch --quiet origin || die "git fetch failed in $source_repo"
fi
commit="$(git -C "$source_repo" rev-parse --verify --quiet "$ref^{commit}")" || die "ref not found: $ref"

work_dir="$(mktemp -d)"
worktree="$work_dir/source"
staging="$work_dir/staging"
cleanup() {
  git -C "$source_repo" worktree remove --force "$worktree" > /dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

git -C "$source_repo" worktree add --quiet --detach "$worktree" "$commit" || die "could not create a worktree at $ref"

echo "sync: building $ref ($commit)" >&2
(cd "$worktree" && npm ci --no-audit --no-fund --silent && npm run build --silent) >&2 || die "build failed at $ref"

for file in "${js_files[@]}"; do
  [ -f "$worktree/$js_root/$file" ] || die "build did not produce $js_root/$file"
  mkdir -p "$staging/$js_root/$(dirname "$file")"
  cp "$worktree/$js_root/$file" "$staging/$js_root/$file"
done
mkdir -p "$staging/$xml_root"
for file in "${xml_files[@]}"; do
  [ -f "$worktree/$xml_root/$file" ] || die "missing $xml_root/$file at $ref"
  cp "$worktree/$xml_root/$file" "$staging/$xml_root/$file"
done

# Every relative module any packaged file loads must ship with it, or the RESTlet fails at
# runtime in the target account. Checking every file covers dependencies of dependencies.
for file in "${js_files[@]}"; do
  missing="$(node -e '
    const fs = require("fs"), path = require("path");
    const [file, root] = process.argv.slice(1);
    const match = fs.readFileSync(file, "utf8").match(/define\(\s*\[([^\]]*)\]/);
    if (!match) { console.log("(no define() call found)"); process.exit(0); }
    for (const [, dep] of match[1].matchAll(/"([^"]+)"/g)) {
      if (!dep.startsWith(".")) continue;
      const resolved = path.resolve(path.dirname(file), dep);
      if (!fs.existsSync(resolved)) console.log(path.relative(root, resolved));
    }' "$staging/$js_root/$file" "$staging/$js_root")"
  [ -z "$missing" ] || die "$file loads modules not in the package: $missing"
done

# The package is only touched once every check above has passed.
for file in "${js_files[@]}"; do
  mkdir -p "$package_dir/$js_root/$(dirname "$file")"
  cp "$staging/$js_root/$file" "$package_dir/$js_root/$file"
done
mkdir -p "$package_dir/$xml_root"
for file in "${xml_files[@]}"; do
  cp "$staging/$xml_root/$file" "$package_dir/$xml_root/$file"
done
printf 'commit %s\nref %s\n' "$commit" "$ref" > "$package_dir/SOURCE"
echo "sync: updated $package_dir from $ref ($commit). Review git diff, then commit." >&2
