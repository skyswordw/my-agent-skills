#!/bin/sh

set -eu

ROOT_DIR=$(
  CDPATH= cd -- "$(dirname "$0")/../.." && pwd
)
INSTALL_SCRIPT="$ROOT_DIR/scripts/install-codex-skill.sh"
PLUGIN_JSON="$ROOT_DIR/.codex-plugin/plugin.json"
TARGET_PROJECT=$(mktemp -d)
CAPTCHA_NODE_MODULES_DIR="$ROOT_DIR/skills/captcha-auto-skill/node_modules"
CAPTCHA_LEAK_FILE="$CAPTCHA_NODE_MODULES_DIR/.smoke-leak.txt"
CREATED_NODE_MODULES_DIR=0

cleanup() {
  rm -rf "$TARGET_PROJECT"
  rm -f "$CAPTCHA_LEAK_FILE"
  if [ "$CREATED_NODE_MODULES_DIR" -eq 1 ]; then
    rmdir "$CAPTCHA_NODE_MODULES_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

assert_not_exists() {
  [ ! -e "$1" ] || fail "unexpected path: $1"
}

if [ ! -d "$CAPTCHA_NODE_MODULES_DIR" ]; then
  mkdir -p "$CAPTCHA_NODE_MODULES_DIR"
  CREATED_NODE_MODULES_DIR=1
fi
printf 'smoke leak\n' > "$CAPTCHA_LEAK_FILE"

plugin_skills_path=$(
  python3 - "$PLUGIN_JSON" <<'PY'
import json
import sys

plugin_path = sys.argv[1]
with open(plugin_path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)
print(payload.get("skills", ""))
PY
)
[ "$plugin_skills_path" = "./skills/" ] || fail "plugin.json should publish ./skills/"

bash "$INSTALL_SCRIPT" msi-repair-status "$TARGET_PROJECT"
bash "$INSTALL_SCRIPT" captcha-auto-skill "$TARGET_PROJECT"
bash "$INSTALL_SCRIPT" codebase-to-course "$TARGET_PROJECT"

assert_file "$TARGET_PROJECT/.codex/skills/msi-repair-status/SKILL.md"
assert_file "$TARGET_PROJECT/.codex/skills/msi-repair-status/agents/openai.yaml"
assert_file "$TARGET_PROJECT/.codex/skills/captcha-auto-skill/SKILL.md"
assert_file "$TARGET_PROJECT/.codex/skills/captcha-auto-skill/agents/openai.yaml"
assert_file "$TARGET_PROJECT/.codex/skills/codebase-to-course/SKILL.md"
assert_file "$TARGET_PROJECT/.codex/skills/codebase-to-course/agents/openai.yaml"
assert_file "$TARGET_PROJECT/.codex/skills/codebase-to-course/scripts/init-course.sh"
assert_file "$TARGET_PROJECT/.codex/skills/codebase-to-course/scripts/build-course.sh"
assert_file "$TARGET_PROJECT/.codex/skills/codebase-to-course/runtime/templates/_base.html"
assert_file "$TARGET_PROJECT/.codex/skills/codebase-to-course/runtime/templates/_footer.html"
assert_file "$TARGET_PROJECT/.codex/skills/codebase-to-course/runtime/styles.css"
assert_file "$TARGET_PROJECT/.codex/skills/codebase-to-course/runtime/main.js"

assert_not_exists "$TARGET_PROJECT/.codex/skills/captcha-auto-skill/node_modules"
assert_not_exists "$TARGET_PROJECT/.codex/skills/captcha-auto-skill/eng.traineddata"

printf 'PASS\n'
