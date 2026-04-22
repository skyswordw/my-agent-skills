# Repository Maintenance Rules

- Keep canonical skills under `skills/<skill-name>/`.
- Use lowercase kebab-case for every `<skill-name>`.
- Put cross-agent workflow details and business rules in that skill's `SKILL.md`.
- Put Codex-specific interface text, prompt wording, and adapter guardrails in `skills/<skill-name>/agents/openai.yaml`, and keep it aligned with `SKILL.md`.
- Keep `AGENTS.md` limited to repository-wide maintenance rules such as naming, sanitization, public-data constraints, and validation expectations.
- Treat this repository as public. Use only sanitized examples, placeholder secrets, sample domains, and fabricated IDs unless the data is already intentionally public.
- Do not commit private prompts, credentials, tokens, internal URLs, personal data, customer data, or machine-specific secrets.
- If a skill needs helper scripts, templates, or fixtures, keep them inside `skills/<skill-name>/` and make sure they are safe to publish.
- Put files under `tests/<skill-name>/` only when they are repo-level validation assets, fixtures, or harnesses that should not ship inside the installed skill directory.
- Keep repository docs concise and practical. Do not duplicate the same rule across repo-level docs and a skill's `SKILL.md` unless the duplication is necessary for navigation.
- When adding or changing a skill, validate referenced paths, relative links, and any adapter metadata that points at that skill.
- If documentation names a validation step, run it or update the documentation so it matches the real workflow.
