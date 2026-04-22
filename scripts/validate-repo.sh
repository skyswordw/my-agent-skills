#!/bin/sh

set -eu

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

required_files="
.codex-plugin/plugin.json
catalog/skills.yaml
scripts/install-codex-skill.sh
scripts/validate-skill.sh
scripts/validate-repo.sh
scripts/build-catalog.py
"

OLD_IFS=$IFS
IFS='
'
for rel_path in $required_files; do
  [ -n "$rel_path" ] || continue
  [ -f "$repo_root/$rel_path" ] || die "required repo file is missing: $rel_path"
done
IFS=$OLD_IFS

[ -x "$repo_root/scripts/install-codex-skill.sh" ] || die "install script must be executable"
[ -x "$validator" ] || die "skill validator must be executable"
[ -x "$repo_root/scripts/validate-repo.sh" ] || die "repo validator must be executable"
[ -f "$catalog_builder" ] || die "catalog builder is missing"

python3 "$catalog_builder" --catalog "$catalog_file" --check >/dev/null

catalog_entries=$(
  python3 - "$catalog_builder" "$catalog_file" "$repo_root/.codex-plugin/plugin.json" "$repo_root" <<'PY'
from pathlib import Path
import importlib.util
import json
import sys

builder_path, catalog_path, plugin_path, repo_root = sys.argv[1:]

spec = importlib.util.spec_from_file_location("catalog_builder", builder_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

repo_root_path = Path(repo_root).resolve()
plugin_manifest_path = Path(plugin_path)

try:
    plugin_manifest = json.loads(plugin_manifest_path.read_text(encoding="utf-8"))
except json.JSONDecodeError as exc:
    print(
        f"ERROR: plugin.json is not valid JSON: {exc.msg}",
        file=sys.stderr,
    )
    raise SystemExit(2)

if not isinstance(plugin_manifest, dict):
    print("ERROR: plugin.json root must be a JSON object", file=sys.stderr)
    raise SystemExit(3)

skills_path = plugin_manifest.get("skills")
if not isinstance(skills_path, str):
    print("ERROR: plugin.json must define a string skills path", file=sys.stderr)
    raise SystemExit(4)

if skills_path != "./skills/":
    print(
        f"ERROR: plugin.json must publish skills from ./skills/, got: {skills_path}",
        file=sys.stderr,
    )
    raise SystemExit(5)

published_skills_root = (repo_root_path / skills_path).resolve()
try:
    published_skills_root.relative_to(repo_root_path)
except ValueError:
    print(
        f"ERROR: plugin skills path escapes the repository root: {skills_path}",
        file=sys.stderr,
    )
    raise SystemExit(6)

if not published_skills_root.exists():
    print(
        f"ERROR: plugin skills path does not exist: {skills_path}",
        file=sys.stderr,
    )
    raise SystemExit(7)

if not published_skills_root.is_dir():
    print(
        f"ERROR: plugin skills path is not a directory: {skills_path}",
        file=sys.stderr,
    )
    raise SystemExit(8)

skills = module.parse_catalog(Path(catalog_path).read_text(encoding="utf-8"))
catalog_by_name = {}
catalog_by_path = {}

for skill in skills:
    resolved = (repo_root_path / skill["path"]).resolve()
    try:
        resolved.relative_to(repo_root_path)
    except ValueError:
        print(
            f"ERROR: catalog path escapes the repository root for skill {skill['name']}: {skill['path']}",
            file=sys.stderr,
        )
        raise SystemExit(2)
    if not resolved.exists():
        print(
            f"ERROR: catalog path does not exist for skill {skill['name']}: {skill['path']}",
            file=sys.stderr,
        )
        raise SystemExit(3)
    if not resolved.is_dir():
        print(
            f"ERROR: catalog path is not a directory for skill {skill['name']}: {skill['path']}",
            file=sys.stderr,
        )
        raise SystemExit(11)
    if resolved.name != skill["name"]:
        print(
            f"ERROR: catalog name does not match resolved skill directory for skill {skill['name']}: {resolved.name}",
            file=sys.stderr,
        )
        raise SystemExit(12)
    try:
        resolved.relative_to(published_skills_root)
    except ValueError:
        print(
            f"ERROR: catalog path is outside the published skills tree for skill {skill['name']}: {skill['path']}",
            file=sys.stderr,
        )
        raise SystemExit(13)
    if skill["name"] in catalog_by_name:
        print(
            f"ERROR: duplicate skill name in catalog/skills.yaml: {skill['name']}",
            file=sys.stderr,
        )
        raise SystemExit(14)
    if resolved in catalog_by_path:
        print(
            f"ERROR: duplicate skill path in catalog/skills.yaml: {skill['path']}",
            file=sys.stderr,
        )
        raise SystemExit(15)
    catalog_by_name[skill["name"]] = resolved
    catalog_by_path[resolved] = skill["name"]

published_skill_dirs = []
for skill_md in sorted(
    published_skills_root.rglob("SKILL.md"),
    key=lambda path: (len(path.parts), str(path)),
):
    if "node_modules" in skill_md.parts:
        continue
    skill_dir = skill_md.parent.resolve()
    try:
        skill_dir.relative_to(published_skills_root)
    except ValueError:
        continue
    if any(parent == skill_dir or parent in skill_dir.parents for parent in published_skill_dirs):
        continue
    published_skill_dirs.append(skill_dir)

for skill_dir in published_skill_dirs:
    skill_name = skill_dir.name
    catalog_resolved = catalog_by_name.get(skill_name)
    if catalog_resolved is None:
        print(
            f"ERROR: published skill is missing from catalog/skills.yaml: {skill_name}",
            file=sys.stderr,
        )
        raise SystemExit(16)
    if catalog_resolved != skill_dir:
        print(
            f"ERROR: catalog path for skill {skill_name} does not match the published skill directory: {skill_dir}",
            file=sys.stderr,
        )
        raise SystemExit(17)

for skill_name in sorted(catalog_by_name):
    resolved = catalog_by_name[skill_name]
    print(f"{skill_name}\t{resolved}")
PY
) || exit $?

tab=$(printf '\t')
OLD_IFS=$IFS
IFS='
'
for catalog_entry in $catalog_entries; do
  [ -n "$catalog_entry" ] || continue
  IFS=$tab
  set -- $catalog_entry
  IFS='
'
  skill_name=$1
  skill_dir=$2
  "$validator" "$skill_dir"
done
IFS=$OLD_IFS

printf 'Validated repository: %s\n' "$repo_root"
