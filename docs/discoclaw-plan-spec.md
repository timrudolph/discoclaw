# Discoclaw Plan Specification v1

`discoclaw-plan` is a shareable markdown scaffold for describing integration work that another Discoclaw user (or agent) can safely implement.

## Goals

- Keep plans small, explicit, and auditable.
- Make plan exchange easy between users.
- Preserve safety and provenance (author/source/license).
- Support machine-assisted consumption without requiring new runtime code.

## Canonical Location And Filename

Store plans under:

- `plans/<kebab-slug>.discoclaw-plan.md`

Example:

- `plans/openai-compatible-runtime-adapter.discoclaw-plan.md`

## Required Headings

Every file must include these headings exactly once:

1. `# Discoclaw Plan`
2. `## Metadata`
3. `## Use Case`
4. `## Scope`
5. `## Integration Contract`
6. `## Implementation Steps`
7. `## Acceptance Tests`
8. `## Risk, Permissions, Rollback`
9. `## Handoff Prompt (Consumer Agent)`
10. `## Changelog`

## Required Metadata Fields

Every plan must include all fields below, either in a `metadata` JSON block or explicit markdown key/value lines in `## Metadata`.

- `spec_version`
- `plan_id`
- `title`
- `author`
- `source`
- `license`
- `created_at`
- `integration_type`
- `discoclaw_min_version`
- `risk_level`

### Field Constraints

- `spec_version`: string. For this spec use `"1.0"`.
- `plan_id`: stable kebab-case identifier.
- `source`: origin URL/repo/path, or `manual`.
- `created_at`: ISO 8601 UTC timestamp.
- `integration_type`: one of `runtime`, `actions`, `context`.
- `risk_level`: one of `low`, `medium`, `high`.

## Risk-Based JSON Requirements

The format uses required markdown headings for all plans, and risk-gated JSON strictness.

- `low` risk:
  - `metadata`, `implementation_contract`, and `acceptance_contract` JSON fences are recommended.
  - A plan may omit those JSON fences if section prose is complete.
- `medium` or `high` risk:
  - `metadata`, `implementation_contract`, and `acceptance_contract` JSON fences are required.
  - Missing required JSON is a validation failure for consumers.

## JSON Block Contracts

For `medium/high`, include these fenced blocks.

### `metadata`

```json
{
  "spec_version": "1.0",
  "plan_id": "example-plan-id",
  "title": "Example Integration",
  "author": "Name or handle",
  "source": "manual",
  "license": "MIT",
  "created_at": "2026-02-11T00:00:00Z",
  "integration_type": "runtime",
  "discoclaw_min_version": "0.1.0",
  "risk_level": "medium"
}
```

### `implementation_contract`

```json
{
  "files_add": ["path/to/new-file"],
  "files_modify": ["path/to/existing-file"],
  "env_changes": [
    {
      "name": "ENV_VAR",
      "required": true,
      "default": "",
      "description": "What it controls"
    }
  ],
  "runtime_behavior_changes": ["Behavior change summary"],
  "out_of_scope": ["Explicit non-goal"]
}
```

### `acceptance_contract`

```json
{
  "scenarios": [
    {
      "name": "Happy path",
      "type": "integration",
      "steps": ["Action"],
      "expected": ["Outcome"]
    }
  ],
  "required_checks": ["pnpm build", "pnpm test"]
}
```

## Safety Requirements

Every plan must include all of the following in `## Risk, Permissions, Rollback`:

- Risk rationale for the chosen `risk_level`.
- Required permissions/capabilities (Discord, runtime tools, env variables).
- Rollback procedure with explicit file or config reversions.

## Integration Type Guidance

Use `integration_type` to classify plans:

- `runtime`: runtime adapter behavior, model/tool routing, runtime config/env integration.
- `actions`: Discord action categories, action handlers, or command/action plumbing.
- `context`: prompt/context behavior, templates, markdown context scaffolds, or non-runtime content rules.

## Consumer Agent Behavior (Default)

Consumers should use plan-first apply:

1. Validate required headings.
2. Read risk level.
3. Enforce risk-based JSON rules.
4. Produce a local implementation checklist mapped to actual repo paths.
5. Do not start coding until explicitly asked.

## Versioning And Compatibility

- `spec_version` is the primary compatibility key.
- Consumers must treat unknown major versions as incompatible.
- Minor field additions should be additive and backward compatible.

## Author Checklist

Before sharing, verify:

- Filename uses `.discoclaw-plan.md` suffix.
- All required headings exist.
- Metadata includes author/source/license.
- Risk/permissions/rollback is explicit.
- `medium/high` plans include all three required JSON blocks.
