---
name: discoclaw-plan-consumer
description: Consume a shared `*.discoclaw-plan.md` file and produce a decision-complete, local-repo implementation checklist with risk-gated validation and plan-first execution behavior.
---

# Discoclaw Plan Consumer

Consume a shared Discoclaw integration plan without immediately coding.

Default mode is plan-first apply.

## Use This Skill When

- A user provides a `.discoclaw-plan.md` and asks to implement/adapt it.
- A user asks for feasibility or migration mapping from a shared integration plan.
- A user wants a safe checklist before code changes.

## Validation Workflow

1. Confirm filename pattern and required headings from `docs/discoclaw-plan-spec.md`.
2. Read `risk_level` from metadata.
3. Apply risk-gated JSON checks:
   - `low`: JSON blocks optional, but section prose must still be complete.
   - `medium/high`: `metadata`, `implementation_contract`, and `acceptance_contract` JSON blocks are mandatory.
4. Verify mandatory attribution and safety fields exist:
   - Author/source/license
   - Risk rationale
   - Required permissions/capabilities
   - Rollback steps

If required data is missing, stop and request a corrected plan before implementation.

## Output Contract

Produce a decision-complete implementation checklist that includes:

- Local file mapping (`files_add`, `files_modify`, equivalents if repo differs)
- Environment/config changes
- Test and verification sequence
- Rollback and risk gates
- Explicit assumptions

Do not begin code edits unless the user explicitly asks to execute.

## Adaptation Guidance

When local repo structure differs:

- Map each contract path to the closest actual path.
- Record each path mapping explicitly.
- Preserve stated out-of-scope constraints.

## Final Self-Check

1. Validation result is explicit (`pass` or `blocked`).
2. Missing fields are listed with exact corrections needed.
3. Implementation checklist is file-specific and complete.
4. Plan-first behavior is preserved unless user overrides.
