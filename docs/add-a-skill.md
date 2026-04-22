# Add a Skill

In this repository, adding a skill always means updating both the canonical skill content and the thin metadata that exposes it to Codex.

## 1. Create the canonical skill directory

Create `skills/<skill-name>/` and use lowercase kebab-case for the directory name.

## 2. Write `SKILL.md`

Keep `SKILL.md` as the canonical description of the skill. It should cover:

- What the skill is for
- When an agent should use it
- Required context or inputs
- The workflow, checklist, or decision rules for that skill
- Expected outputs or completion criteria

The validator requires YAML frontmatter at the top of `SKILL.md` with:

- `name`, matching the skill directory name
- `description`, with a non-empty summary

Skill-specific business rules belong here, not in repo-level docs.

## 3. Add the per-skill Codex adapter file

Create `skills/<skill-name>/agents/openai.yaml`.

This file is the Codex-specific adapter surface for the skill. It may include user-facing interface text, default prompt wording, and adapter guardrails. Keep it aligned with `SKILL.md`, and do not let it contradict the skill's core workflow or business rules.

The validator requires a top-level `interface` block with:

- `interface.display_name`
- `interface.short_description`

## 4. Place support files and tests in the right location

- Put scripts, templates, references, assets, and publishable fixtures inside `skills/<skill-name>/` when they belong to the installed skill package.
- Put repo-level tests and external validation fixtures under `tests/<skill-name>/` when they are used to validate the skill from the repository root and should not ship inside the skill directory.
- Keep every file sanitized and safe for a public repository.

## 5. Register the skill in the repo catalog

Add the new entry to `catalog/skills.yaml` with the skill name, path, title, and summary.

The catalog is the repo-level registry for this repository's docs and scripts workflow. It should point at `skills/<skill-name>/` and stay consistent with the canonical files already added.

## 6. Verify Codex packaging surfaces

Confirm that the Codex-facing files still line up:

- `skills/<skill-name>/agents/openai.yaml` exists and matches the skill directory
- `.codex-plugin/plugin.json` still describes the repo pack correctly and points Codex discovery at `./skills/`
- `scripts/install-codex-skill.sh` can discover the new skill through `catalog/skills.yaml`

## 7. Validate before merging

- The path is `skills/<skill-name>/`
- The directory name is lowercase kebab-case
- `SKILL.md` is present and readable
- `SKILL.md` frontmatter includes `name` and `description`
- `skills/<skill-name>/agents/openai.yaml` is present and readable
- `skills/<skill-name>/agents/openai.yaml` includes `interface.display_name` and `interface.short_description`
- `catalog/skills.yaml` includes the new skill
- Links and referenced paths resolve
- Sample values are sanitized
- Run `scripts/validate-skill.sh skills/<skill-name>`
- Run `scripts/validate-repo.sh`
