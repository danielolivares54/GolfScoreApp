# Working Agreement (SSOT-Aligned)

Project: Caddie V2T Digital Scorecard (MVP)
SSOT Version: v1.0

## 1. Purpose
This agreement defines how we collaborate to build the MVP described in the SSOT. The SSOT is the single source of truth for architecture, scope, and data model.

## 2. Scope
1. Implement the MVP exactly as defined in the SSOT v1.0.
2. The LLM handles conversational extraction only.
3. All validation, persistence, and betting logic is deterministic.
4. Any change to scope, schema, or rules must be recorded in an SSOT addendum before coding.

## 3. Responsibilities
User provides:
1. API keys and hosting credentials.
2. Final requirements and decisions on open questions.
3. Access to the repo and approval of milestones.

Codex provides:
1. Implementation and integration.
2. Code review and updates.
3. Progress notes, risks, and blockers.

## 4. Design Rules (Non-Negotiable)
1. LLM must never calculate bets.
2. LLM must never write to the database.
3. All betting logic must be deterministic.
4. All LLM output must be validated against a strict JSON schema before persistence.
5. Player identity cannot be assumed when ambiguous.

## 5. Workflow
1. Work is done in small, verifiable increments.
2. Each increment has a clear goal and acceptance criteria.
3. We avoid UI polish until the core data flow is stable.
4. Every new rule or field change is added to SSOT or a versioned addendum.

## 6. Quality Bar
1. Deterministic layers have unit tests for edge cases.
2. LLM event validation failures are logged with reasons.
3. All validation failures return structured error responses.
4. No secrets are committed to Git.

## 7. Source Control
1. Git is the system of record.
2. Feature work uses branches with prefix `codex/`.
3. Only reviewed changes are merged to `main`.

## 8. Data & Security
1. API keys are stored in environment variables.
2. Minimal PII in the database.
3. Logs exclude secrets and raw audio.

## 9. Open Questions Log
Unresolved items must be tracked here or in SSOT addendum before implementation:
1. Match lifecycle transitions.
2. Revision strategy for hole re-entries.
3. Error recovery UX responsibility (LLM vs server).
4. Auth strategy (token/session/match secret).

## 10. Milestones (Initial)
1. Validate `HOLE_ENTRY` event schema and server response.
2. End-to-end flow: audio -> LLM -> server -> DB -> confirmation response.
3. Deterministic score engine + unit tests.
4. Minimal UI confirmation and scorecard display.

