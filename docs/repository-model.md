# Repository Model

This repository separates canonical skill content from agent-specific packaging.

## Canonical source

- Each skill lives under `skills/<skill-name>/`.
- `skills/<skill-name>/SKILL.md` is the canonical cross-agent description of what the skill does, when to use it, and the core workflow or business rules it follows.
- Optional skill-local helpers can live beside `SKILL.md` if they directly support that skill and are safe to publish.

## Repository registry

- `catalog/skills.yaml` is the repository-level index of published skills in this repo.
- The catalog records stable metadata such as skill name, path, title, and summary.
- The catalog is used by this repository's docs and scripts workflow.
- The catalog is a maintenance surface, not the source of skill behavior and not the same layer as Codex plugin discovery.

## Adapter layer

- Adapter files expose canonical skills to a specific runtime without becoming the source of truth.
- For Codex, the repo-level pack metadata lives in `.codex-plugin/plugin.json`.
- The current Codex plugin pack points `skills` at `./skills/` directly for discovery.
- That means `.codex-plugin/plugin.json` and `catalog/skills.yaml` serve different purposes and should not be treated as identical sources of truth.
- For Codex, each skill's adapter file lives in `skills/<skill-name>/agents/openai.yaml`.
- `skills/<skill-name>/agents/openai.yaml` may carry Codex-facing prompt wording, interface copy, and adapter guardrails. It should align with `SKILL.md` and must not contradict the skill's core rules.
- Codex is the first supported adapter and is documented in `docs/codex.md`.
- Future adapters should map back to the same skill directory instead of copying skill logic into a new format.

## Tests and support files

- Put installed skill content, skill-local scripts, references, templates, and publishable fixtures inside `skills/<skill-name>/`.
- Put repo-level validation assets under `tests/<skill-name>/` when they exist to test the skill from outside the packaged skill directory.

## Why this model

- One skill definition can support multiple agents.
- Repo-level governance stays stable even if catalog entries, plugin-pack metadata, or adapter files change.
- Public sanitization is easier when the canonical content lives in one place.
- Catalog and adapter metadata can stay thin and mechanical.

## Boundary rule

- Repository-wide rules belong in `README.md`, `AGENTS.md`, and `docs/`.
- Skill-specific business rules belong in each skill's `SKILL.md`.
