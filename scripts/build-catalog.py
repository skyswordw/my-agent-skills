#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path
import sys


START_MARKER = "<!-- BEGIN GENERATED SKILL CATALOG -->"
END_MARKER = "<!-- END GENERATED SKILL CATALOG -->"


def parse_scalar(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    return value


def parse_catalog(text: str) -> list[dict[str, str]]:
    in_skills = False
    current: dict[str, str] | None = None
    skills: list[dict[str, str]] = []

    for lineno, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.rstrip()
        stripped = line.strip()

        if not stripped or stripped.startswith("#"):
            continue

        if not in_skills:
            if stripped == "skills:":
                in_skills = True
                continue
            raise ValueError(f"line {lineno}: expected top-level 'skills:'")

        indent = len(line) - len(line.lstrip(" "))
        if indent == 2 and stripped.startswith("- "):
            if current is not None:
                skills.append(current)
            current = {}
            tail = stripped[2:]
            if tail:
                key, value = parse_key_value(tail, lineno)
                current[key] = value
            continue

        if current is None:
            raise ValueError(f"line {lineno}: found fields before first list item")

        if indent != 4:
            raise ValueError(f"line {lineno}: unsupported indentation")

        key, value = parse_key_value(stripped, lineno)
        current[key] = value

    if current is not None:
        skills.append(current)

    if not in_skills:
        raise ValueError("missing top-level 'skills:' key")
    if not skills:
        raise ValueError("catalog contains no skills")

    for index, skill in enumerate(skills, start=1):
        for required in ("name", "title", "path", "summary"):
            if not skill.get(required):
                raise ValueError(f"skill #{index} is missing '{required}'")

    return skills


def parse_key_value(text: str, lineno: int) -> tuple[str, str]:
    if ":" not in text:
        raise ValueError(f"line {lineno}: expected key: value")
    key, value = text.split(":", 1)
    key = key.strip()
    value = parse_scalar(value)
    if not key:
        raise ValueError(f"line {lineno}: empty key")
    if not value:
        raise ValueError(f"line {lineno}: empty value for '{key}'")
    return key, value


def render_section(skills: list[dict[str, str]]) -> str:
    lines = [
        START_MARKER,
        "## Skill Catalog",
        "",
        "_Generated from `catalog/skills.yaml` by `scripts/build-catalog.py`._",
        "",
    ]
    for skill in skills:
        lines.append(
            f"- `{skill['name']}` ({skill['path']}) - {skill['title']}. {skill['summary']}"
        )
    lines.extend(["", END_MARKER])
    return "\n".join(lines) + "\n"


def upsert_section(readme_text: str, section: str) -> str:
    start = readme_text.find(START_MARKER)
    end = readme_text.find(END_MARKER)

    if start == -1 and end == -1:
        base = readme_text.rstrip()
        if base:
            return base + "\n\n" + section
        return section

    if start == -1 or end == -1 or end < start:
        raise ValueError(
            f"README markers must either both be absent or both be present: {START_MARKER} / {END_MARKER}"
        )

    end += len(END_MARKER)
    prefix = readme_text[:start].rstrip()
    suffix = readme_text[end:].lstrip("\n")

    if prefix and suffix:
        return prefix + "\n\n" + section + "\n" + suffix
    if prefix:
        return prefix + "\n\n" + section
    if suffix:
        return section + "\n" + suffix
    return section


def build_parser() -> argparse.ArgumentParser:
    script_path = Path(__file__).resolve()
    repo_root = script_path.parent.parent
    parser = argparse.ArgumentParser(
        description=(
            "Render the generated skill catalog section. "
            f"Markers: {START_MARKER} ... {END_MARKER}"
        )
    )
    parser.add_argument(
        "--catalog",
        default=str(repo_root / "catalog" / "skills.yaml"),
        help="Path to catalog/skills.yaml",
    )
    parser.add_argument(
        "--readme",
        default=str(repo_root / "README.md"),
        help="README file to update when --stdout is not used",
    )
    parser.add_argument(
        "--stdout",
        action="store_true",
        help="Print the generated catalog section instead of updating README.md",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Exit non-zero if README.md is not up to date with catalog/skills.yaml",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    catalog_path = Path(args.catalog).resolve()
    readme_path = Path(args.readme).resolve()

    if not catalog_path.is_file():
        raise SystemExit(f"catalog file does not exist: {catalog_path}")

    skills = parse_catalog(catalog_path.read_text(encoding="utf-8"))
    section = render_section(skills)

    if args.stdout and args.check:
        raise SystemExit("--stdout and --check cannot be used together")

    if args.stdout:
        sys.stdout.write(section)
        return 0

    if not readme_path.exists():
        raise SystemExit(
            f"README file does not exist: {readme_path}\n"
            f"Create it first or use --stdout to preview the generated block."
        )

    readme_text = readme_path.read_text(encoding="utf-8")
    updated_text = upsert_section(readme_text, section)

    if args.check:
        if readme_text != updated_text:
            raise SystemExit(
                f"README skill catalog is out of date: {readme_path}\n"
                "Run python3 scripts/build-catalog.py to regenerate it."
            )
        return 0

    readme_path.write_text(updated_text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
