# Builds a throwaway git repo shaped like sdf-creative-planning: committed deployment XMLs and
# a `build` script that writes the compiled JS, which (as in the real repo) is not committed.
# Branches: main (good), missing-file, bad-dep, bad-module-dep, build-fails.
make_fake_source() {
  local dir="$1"
  mkdir -p "$dir/Objects/Scripts/RESTlet"
  git -C "$dir" init -q -b main
  for name in saved_search file_cabinet mr_driver email_template; do
    printf '<restlet scriptid="customscript_cp_%s_rl"/>\n' "$name" \
      > "$dir/Objects/Scripts/RESTlet/customscript_cp_${name}_rl.xml"
  done
  cat > "$dir/package.json" <<'EOF'
{ "name": "fake-sdf", "version": "1.0.0", "private": true, "scripts": { "build": "sh build.sh" } }
EOF
  cat > "$dir/package-lock.json" <<'EOF'
{ "name": "fake-sdf", "version": "1.0.0", "lockfileVersion": 3, "requires": true,
  "packages": { "": { "name": "fake-sdf", "version": "1.0.0" } } }
EOF
  cat > "$dir/build.sh" <<'EOF'
out=FileCabinet/SuiteScripts/CreativePlanning
mkdir -p "$out/RESTlet" "$out/netsuite_modules/saved-search-serializer" "$out/netsuite_modules/file-cabinet" "$out/netsuite_modules/email-template"
echo 'define(["require", "exports", "N/log", "../netsuite_modules/saved-search-serializer/index.js"], function () {});' > "$out/RESTlet/cp_saved_search_rl.js"
echo 'define(["require", "exports", "N/log", "../netsuite_modules/file-cabinet/index.js"], function () {});' > "$out/RESTlet/cp_file_cabinet_rl.js"
echo 'define(["require", "exports", "N/log", "N/task"], function () {});' > "$out/RESTlet/cp_mr_driver_rl.js"
echo 'define(["require", "exports"], function () {});' > "$out/netsuite_modules/saved-search-serializer/index.js"
echo 'define(["require", "exports"], function () {});' > "$out/netsuite_modules/file-cabinet/index.js"
echo 'define(["require", "exports", "N/log", "../netsuite_modules/email-template/index.js"], function () {});' > "$out/RESTlet/cp_email_template_rl.js"
echo 'define(["require", "exports", "N/render", "../file-cabinet/index.js"], function () {});' > "$out/netsuite_modules/email-template/index.js"
EOF
  printf 'FileCabinet/\nnode_modules/\n' > "$dir/.gitignore"
  fake_commit "$dir" base

  git -C "$dir" checkout -q -b missing-file main
  grep -v cp_mr_driver_rl "$dir/build.sh" > "$dir/build.tmp" && mv "$dir/build.tmp" "$dir/build.sh"
  fake_commit "$dir" "drop mr driver output"

  git -C "$dir" checkout -q -b bad-dep main
  cat >> "$dir/build.sh" <<'EOF'
echo 'define(["require", "exports", "../netsuite_modules/not-packaged/index.js"], function () {});' > "$out/RESTlet/cp_saved_search_rl.js"
EOF
  fake_commit "$dir" "depend on an unpackaged module"

  git -C "$dir" checkout -q -b bad-module-dep main
  cat >> "$dir/build.sh" <<'EOF'
echo 'define(["require", "exports", "../shared/helpers.js"], function () {});' > "$out/netsuite_modules/file-cabinet/index.js"
EOF
  fake_commit "$dir" "module depends on an unpackaged file"

  git -C "$dir" checkout -q -b build-fails main
  echo 'exit 1' >> "$dir/build.sh"
  fake_commit "$dir" "break the build"

  git -C "$dir" checkout -q main
}

fake_commit() {
  git -C "$1" add -A
  git -C "$1" -c user.name=test -c user.email=test -c commit.gpgsign=false commit -qm "$2"
}
