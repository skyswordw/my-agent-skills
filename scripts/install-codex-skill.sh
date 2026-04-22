#!/bin/sh

set -eu

usage() {
  cat >&2 <<'EOF'
Usage: scripts/install-codex-skill.sh [--force] <skill-name> <target-project-dir>

Install one registered skill from this repository into:
  <target-project-dir>/.codex/skills/<skill-name>
EOF
  exit 64
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

script_dir=$(
  CDPATH= cd -- "$(dirname "$0")" && pwd
)
repo_root=$(
  CDPATH= cd -- "$script_dir/.." && pwd
)
catalog_file="$repo_root/catalog/skills.yaml"
catalog_builder="$repo_root/scripts/build-catalog.py"
validator="$repo_root/scripts/validate-skill.sh"

force=0

while [ $# -gt 0 ]; do
  case "$1" in
    --force)
      force=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      break
      ;;
  esac
done

[ $# -eq 2 ] || usage

skill_name=$1
target_project_dir=$2

[ -f "$catalog_file" ] || die "missing catalog file: $catalog_file"
[ -f "$catalog_builder" ] || die "missing catalog builder: $catalog_builder"
[ -x "$validator" ] || die "missing validator script: $validator"
[ -d "$target_project_dir" ] || die "target project directory does not exist: $target_project_dir"

if source_skill_dir=$(
  python3 - "$catalog_builder" "$catalog_file" "$repo_root" "$skill_name" <<'PY'
from pathlib import Path
import importlib.util
import sys

builder_path, catalog_path, repo_root, target_name = sys.argv[1:]

spec = importlib.util.spec_from_file_location("catalog_builder", builder_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

repo_root_path = Path(repo_root).resolve()
skills = module.parse_catalog(Path(catalog_path).read_text(encoding="utf-8"))

for skill in skills:
    if skill["name"] != target_name:
        continue
    resolved = (repo_root_path / skill["path"]).resolve()
    try:
        resolved.relative_to(repo_root_path)
    except ValueError:
        raise SystemExit(3)
    if not resolved.is_dir():
        raise SystemExit(4)
    if resolved.name != skill["name"]:
        raise SystemExit(5)
    print(resolved)
    raise SystemExit(0)

raise SystemExit(2)
PY
); then
  :
else
  case $? in
    2) die "skill is not registered in catalog/skills.yaml: $skill_name" ;;
    3) die "catalog path escapes the repository root for skill: $skill_name" ;;
    4) die "catalog path does not resolve to a skill directory for skill: $skill_name" ;;
    5) die "catalog name does not match the resolved skill directory for skill: $skill_name" ;;
    *) die "failed to resolve skill from catalog: $skill_name" ;;
  esac
fi

target_skill_dir="$target_project_dir/.codex/skills/$skill_name"

"$validator" "$source_skill_dir"

mkdir -p "$target_project_dir/.codex/skills"

if [ -e "$target_skill_dir" ]; then
  if [ "$force" -ne 1 ]; then
    die "target skill already exists: $target_skill_dir (use --force to replace it)"
  fi
  rm -rf "$target_skill_dir"
fi

python3 - "$source_skill_dir" "$target_skill_dir" <<'PY'
from pathlib import Path
import shutil
import sys

source_dir = Path(sys.argv[1])
target_dir = Path(sys.argv[2])
ignore = shutil.ignore_patterns(
    "node_modules",
    "__pycache__",
    "*.pyc",
    "eng.traineddata",
    ".DS_Store",
)

shutil.copytree(source_dir, target_dir, ignore=ignore)
PY

printf 'Installed %s to %s\n' "$skill_name" "$target_skill_dir"
