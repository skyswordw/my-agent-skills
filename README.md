# my-agent-skills

`my-agent-skills` is a public personal toolbox of reusable skills for AI agents. The source repo is agent-neutral, and Codex is the first adapter layer, not the only intended consumer.

## What lives here

- Canonical skill content under `skills/<skill-name>/`
- Repo workflow registry under `catalog/`
- Repository governance docs under `README.md`, `AGENTS.md`, and `docs/`
- Agent-specific adapter metadata, starting with Codex
- Packaging and validation scripts under `scripts/`

## Principles

- Personal toolbox, but safe to publish
- One canonical skill directory per skill
- Codex-first distribution without making the repo Codex-only
- Concise, practical documentation
- Cross-agent workflow and business rules belong in each skill's `SKILL.md`
- Codex-facing prompt and adapter guardrails belong in `skills/<skill-name>/agents/openai.yaml` and must stay aligned with `SKILL.md`
- `catalog/skills.yaml` is the repo-level registry for this repository's docs and scripts workflow
- `.codex-plugin/plugin.json` is the Codex pack definition and currently points at `./skills/` directly for discovery

## Layout

```text
catalog/skills.yaml
.codex-plugin/plugin.json
scripts/install-codex-skill.sh
scripts/validate-skill.sh
scripts/validate-repo.sh
skills/<skill-name>/agents/openai.yaml
skills/<skill-name>/SKILL.md
AGENTS.md
.github/copilot-instructions.md
docs/repository-model.md
docs/add-a-skill.md
docs/codex.md
```

## Start here

- `docs/repository-model.md` explains the source-repo-plus-adapter model.
- `docs/add-a-skill.md` explains how to add a new skill.
- `docs/codex.md` explains the Codex adapter layer.

All examples in this repository should use sanitized, public-safe sample values.

<!-- BEGIN GENERATED SKILL CATALOG -->
## Skill Catalog

_Generated from `catalog/skills.yaml` by `scripts/build-catalog.py`._

- `msi-repair-status` (skills/msi-repair-status) - MSI Repair Status. Query MSI China repair progress with an RMA number and product serial number.
- `captcha-auto-skill` (skills/captcha-auto-skill) - Captcha Auto Skill. Solve and submit captchas with local OCR first and a default DashScope fallback.

<!-- END GENERATED SKILL CATALOG -->
