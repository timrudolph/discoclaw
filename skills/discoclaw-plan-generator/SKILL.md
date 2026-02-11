---
name: discoclaw-plan-generator
description: Generate a spec-compliant `plans/*.discoclaw-plan.md` file for shareable Discoclaw integrations (runtime, actions, or context), including risk-gated JSON blocks, safety details, and a consumer handoff prompt.
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

- `plans/<kebab-slug>.discoclaw-plan.md`

The file must include all required headings from `docs/discoclaw-plan-spec.md`.

Risk-gated JSON behavior:

- `low` risk: JSON blocks are recommended; allow lite mode without JSON if prose is complete.
- `medium/high` risk: include `metadata`, `implementation_contract`, and `acceptance_contract` fenced JSON blocks.

## Safety Requirements

Always include in `## Risk, Permissions, Rollback`:

- Risk rationale
- Required permissions/capabilities
- Explicit rollback steps

Always include attribution fields:

- `author`
- `source`
- `license`

## Final Self-Check

Before finalizing, verify:

1. Filename ends with `.discoclaw-plan.md`.
2. Required headings exist exactly once.
3. Metadata fields are complete.
4. JSON blocks satisfy risk-level rules.
5. Handoff prompt is present and plan-first (no auto-code by default).
