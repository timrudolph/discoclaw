---
name: discoclaw-plan-generator
description: Generate a spec-compliant `plans/*.discoclaw-plan.md` file for shareable Discoclaw integrations (runtime, actions, or context), including YAML frontmatter metadata, risk-gated JSON contracts, safety details, and a consumer handoff prompt.
---

# Discoclaw Plan Generator

Generate shareable Discoclaw integration plans using `docs/discoclaw-plan-spec.md`.

## Use This Skill When

- A user asks to create a reusable integration plan for another Discoclaw user.
- A user wants a PRD-style handoff file for agent implementation.
- A user asks for a `.discoclaw-plan.md` scaffold or draft.

## Inputs To Collect

Collect only missing values:

- Integration title and short use case
- Integration type: `runtime` | `actions` | `context`
- Risk level: `low` | `medium` | `high`
- Author, source, license
- Target Discoclaw minimum version

## Output Contract

Create exactly one markdown file at:

- `plans/community/<kebab-slug>.discoclaw-plan.md`

The file must include:

- YAML frontmatter with all required metadata fields
- All required headings from `docs/discoclaw-plan-spec.md`

Risk-gated JSON behavior:

- `low` risk: `implementation_contract` and `acceptance_contract` JSON blocks are recommended; prose-only is allowed if complete.
- `medium/high` risk: `implementation_contract` and `acceptance_contract` fenced JSON blocks are required.

## Safety Requirements

Always include in `## Risk, Permissions, Rollback`:

- Risk rationale
- Required permissions/capabilities
- Explicit rollback steps

Always include attribution fields in frontmatter:

- `author`
- `source`
- `license`

## Final Self-Check

Before finalizing, verify:

1. Filename ends with `.discoclaw-plan.md`.
2. YAML frontmatter is present and complete.
3. Required headings exist exactly once.
4. JSON contract blocks satisfy risk-level rules.
5. Handoff prompt is present and plan-first (no auto-code by default).
