# Codex Adapter

Codex support lives in an adapter layer so the repository can stay agent-neutral at the source level.

## Codex maintenance surfaces

- `catalog/skills.yaml` is the repo-level registry used by this repository's docs and scripts workflow.
- `skills/<skill-name>/agents/openai.yaml` is the per-skill Codex adapter file.
- `.codex-plugin/plugin.json` holds Codex plugin packaging metadata for the repo pack.
- The current plugin pack points `skills` at `./skills/`, so Codex plugin discovery currently comes from the skill directories directly rather than from `catalog/skills.yaml`.
- `scripts/install-codex-skill.sh` installs one catalog-registered skill into a target project's `.codex/skills/<skill-name>`.
- Validation scripts under `scripts/` should check that catalog entries and per-skill adapter files stay aligned.

## Expectations

- Keep the cross-agent workflow and core business rules in `skills/<skill-name>/SKILL.md`.
- Use `skills/<skill-name>/agents/openai.yaml` for Codex-facing interface text, prompt wording, and adapter guardrails that shape Codex invocation.
- Keep a top-level `interface` block in `skills/<skill-name>/agents/openai.yaml` with required `interface.display_name` and `interface.short_description` fields.
- Keep `skills/<skill-name>/agents/openai.yaml` aligned with `SKILL.md`; adapter wording can specialize for Codex, but it must not contradict the skill's core rules.
- Use `catalog/skills.yaml` to keep the repository's own registry, scripts, and docs workflow accurate.
- Do not treat `catalog/skills.yaml` and `.codex-plugin/plugin.json` as identical sources of truth. They are related maintenance surfaces with different consumers.
- Keep all sample values sanitized.
- Avoid secrets, private endpoints, and machine-specific absolute paths in adapter examples.
- Make install scripts idempotent, non-destructive, and clear about missing inputs or unsupported environments.

## Change flow

1. Add or update the canonical skill under `skills/<skill-name>/`.
2. Add or update `skills/<skill-name>/agents/openai.yaml` for that skill's Codex-facing interface text, including required `interface.display_name` and `interface.short_description`.
3. Register or update the skill in `catalog/skills.yaml`.
4. Update `.codex-plugin/plugin.json` only if repo-pack metadata changes.
5. Update or verify install and validation scripts if the packaging flow changes.
6. Validate referenced paths and packaging assumptions.
