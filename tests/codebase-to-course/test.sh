#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(
  CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
)"
TEST_DIR="$ROOT_DIR/tests/codebase-to-course"
FIXTURE_DIR="$TEST_DIR/fixtures"
ASSERT_SCRIPT="$TEST_DIR/assert_course_contract.py"
INSTALL_SCRIPT="$ROOT_DIR/scripts/install-codex-skill.sh"
CATALOG_FILE="$ROOT_DIR/catalog/skills.yaml"
SKILL_NAME="codebase-to-course"
SKILL_SOURCE_DIR="$ROOT_DIR/skills/$SKILL_NAME"
EXPECTED_BUNDLE_PATHS="$FIXTURE_DIR/expected/required-installed-paths.txt"
EXPECTED_SKELETON_PATHS="$FIXTURE_DIR/expected/required-skeleton-paths.txt"
EXPECTED_REFERENCE_SECTIONS="$FIXTURE_DIR/expected/reference-sections.txt"
EXPECTED_INDEX_FRAGMENTS="$FIXTURE_DIR/expected/index-fragments.txt"

temp_dirs=()

usage() {
  cat >&2 <<'EOF'
Usage: tests/codebase-to-course/test.sh [--fixtures-only]

Default mode runs the full repo contract:
  - install the codebase-to-course bundle via scripts/install-codex-skill.sh
  - verify installed bundle contents and leak guards
  - run init-course.sh against the fixture repo
  - run build-course.sh against three fixture modules
  - assert assembled index.html DOM and asset contract

Use --fixtures-only to validate only the local fixtures and DOM checker without
requiring the repo skill implementation to exist yet.
EOF
  exit 64
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

make_temp_dir() {
  local dir
  dir="$(mktemp -d)"
  temp_dirs+=("$dir")
  printf '%s\n' "$dir"
}

cleanup() {
  local dir
  for dir in "${temp_dirs[@]:-}"; do
    rm -rf "$dir"
  done
}
trap cleanup EXIT

assert_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

assert_dir() {
  [ -d "$1" ] || fail "missing directory: $1"
}

assert_contains_file() {
  local file_path="$1"
  local needle="$2"
  local label="$3"

  if ! grep -Fq -- "$needle" "$file_path"; then
    fail "$label: missing [$needle] in $file_path"
  fi
}

assert_expected_paths() {
  local base_dir="$1"
  local manifest_path="$2"
  local rel_path abs_path

  while IFS= read -r rel_path || [ -n "$rel_path" ]; do
    [ -n "$rel_path" ] || continue
    case "$rel_path" in
      */)
        abs_path="$base_dir/${rel_path%/}"
        assert_dir "$abs_path"
        ;;
      *)
        abs_path="$base_dir/$rel_path"
        assert_file "$abs_path"
        ;;
    esac
  done < "$manifest_path"
}

assert_expected_fragments() {
  local html_path="$1"
  local fragment

  while IFS= read -r fragment || [ -n "$fragment" ]; do
    [ -n "$fragment" ] || continue
    assert_contains_file "$html_path" "$fragment" "assembled output should retain fixture content"
  done < "$EXPECTED_INDEX_FRAGMENTS"
}

assert_reference_sections() {
  local interactive_doc="$1/references/interactive-elements.md"
  local heading

  assert_file "$interactive_doc"

  while IFS= read -r heading || [ -n "$heading" ]; do
    [ -n "$heading" ] || continue
    assert_contains_file "$interactive_doc" "$heading" "interactive references should document expected primitive"
  done < "$EXPECTED_REFERENCE_SECTIONS"
}

assert_no_absolute_path_leaks() {
  local scan_root="$1"

  python3 - "$scan_root" "$ROOT_DIR" <<'PY'
from pathlib import Path
import sys

scan_root = Path(sys.argv[1])
repo_root = sys.argv[2]
patterns = (
    repo_root,
    "/Volumes/DataHouse",
    "/Users/skywalker",
)
text_suffixes = {
    ".css",
    ".html",
    ".js",
    ".json",
    ".md",
    ".mjs",
    ".py",
    ".sh",
    ".txt",
    ".yaml",
    ".yml",
}

hits = []
for path in scan_root.rglob("*"):
    if not path.is_file():
        continue
    if path.suffix not in text_suffixes and path.name not in {"SKILL.md", "_base.html", "_footer.html"}:
        continue
    try:
        content = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    for pattern in patterns:
        if pattern and pattern in content:
            hits.append(f"{path}: {pattern}")
            break

if hits:
    print("FAIL: local absolute path leakage detected:", file=sys.stderr)
    for hit in hits:
        print(hit, file=sys.stderr)
    raise SystemExit(1)
PY
}

assert_no_install_artifacts() {
  local scan_root="$1"
  local name_hits key_hits

  name_hits="$(
    find "$scan_root" \
      \( -type d -name node_modules -o -type d -name __pycache__ \) -print
  )"
  if [ -n "$name_hits" ]; then
    fail "installed bundle must not contain dependency caches:\n$name_hits"
  fi

  name_hits="$(
    find "$scan_root" -type f \( \
      -name '*.pem' -o \
      -name '*.key' -o \
      -name 'id_rsa' -o \
      -name 'id_rsa.pub' -o \
      -name 'id_ed25519' -o \
      -name 'id_ed25519.pub' -o \
      -name '.env' -o \
      -name '.env.local' -o \
      -name '.env.production' \
    \) -print
  )"
  if [ -n "$name_hits" ]; then
    fail "installed bundle must not contain secret-like filenames:\n$name_hits"
  fi

  key_hits="$(
    grep -R -nE 'BEGIN (OPENSSH|RSA|DSA|EC|PGP|PRIVATE) PRIVATE KEY' "$scan_root" 2>/dev/null || true
  )"
  if [ -n "$key_hits" ]; then
    fail "installed bundle must not contain private key material:\n$key_hits"
  fi
}

assemble_fixture_course() {
  local course_dir="$1"

  mkdir -p "$course_dir/modules"
  cp "$FIXTURE_DIR/modules/"*.html "$course_dir/modules/"
  : > "$course_dir/styles.css"
  : > "$course_dir/main.js"
  cat > "$course_dir/_base.html" <<'EOF'
<!DOCTYPE html>
<html lang="en" data-course-root>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Fixture Course</title>
  <link rel="stylesheet" href="styles.css">
  <script src="main.js" defer></script>
</head>
<body>
<main id="main">
EOF
  cat > "$course_dir/_footer.html" <<'EOF'
</main>
</body>
</html>
EOF
  cat "$course_dir/_base.html" "$course_dir"/modules/*.html "$course_dir/_footer.html" > "$course_dir/index.html"
}

run_fixture_smoke() {
  local fixture_course_dir
  fixture_course_dir="$(make_temp_dir)"
  assemble_fixture_course "$fixture_course_dir"
  python3 "$ASSERT_SCRIPT" "$fixture_course_dir/index.html" --expected-modules 3
  assert_expected_fragments "$fixture_course_dir/index.html"
}

run_full_contract() {
  local target_project installed_dir install_output
  local course_root course_dir init_output build_output

  [ -f "$CATALOG_FILE" ] || fail "missing catalog file: $CATALOG_FILE"
  [ -d "$SKILL_SOURCE_DIR" ] || fail "missing skill directory: $SKILL_SOURCE_DIR"
  grep -Fq "name: $SKILL_NAME" "$CATALOG_FILE" || fail "catalog/skills.yaml must register $SKILL_NAME before this test can pass"

  target_project="$(make_temp_dir)"
  if install_output="$(bash "$INSTALL_SCRIPT" "$SKILL_NAME" "$target_project" 2>&1)"; then
    :
  else
    fail "install-codex-skill.sh failed for $SKILL_NAME:\n$install_output"
  fi

  installed_dir="$target_project/.codex/skills/$SKILL_NAME"
  assert_dir "$installed_dir"
  assert_expected_paths "$installed_dir" "$EXPECTED_BUNDLE_PATHS"
  assert_reference_sections "$installed_dir"
  assert_no_absolute_path_leaks "$installed_dir"
  assert_no_install_artifacts "$installed_dir"

  course_root="$(make_temp_dir)"
  course_dir="$course_root/generated-course"
  if init_output="$(bash "$installed_dir/scripts/init-course.sh" --source "$FIXTURE_DIR/sample-repo" --out "$course_dir" 2>&1)"; then
    :
  else
    fail "init-course.sh failed against the sample repo:\n$init_output"
  fi

  assert_dir "$course_dir"
  assert_expected_paths "$course_dir" "$EXPECTED_SKELETON_PATHS"

  rm -f "$course_dir"/modules/*.html
  cp "$FIXTURE_DIR/modules/"*.html "$course_dir/modules/"

  if build_output="$(bash "$installed_dir/scripts/build-course.sh" --course-dir "$course_dir" 2>&1)"; then
    :
  else
    fail "build-course.sh failed while assembling fixture modules:\n$build_output"
  fi

  assert_file "$course_dir/index.html"
  python3 "$ASSERT_SCRIPT" "$course_dir/index.html" --expected-modules 3
  assert_expected_fragments "$course_dir/index.html"
}

mode="full"
case "${1:-}" in
  "")
    ;;
  --fixtures-only)
    mode="fixtures-only"
    ;;
  *)
    usage
    ;;
esac

assert_file "$ASSERT_SCRIPT"
assert_file "$EXPECTED_BUNDLE_PATHS"
assert_file "$EXPECTED_SKELETON_PATHS"
assert_file "$EXPECTED_REFERENCE_SECTIONS"
assert_file "$EXPECTED_INDEX_FRAGMENTS"

run_fixture_smoke

if [ "$mode" = "full" ]; then
  run_full_contract
fi

printf 'PASS\n'
