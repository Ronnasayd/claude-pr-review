# LESSONS - auto-maintained by scripts/lessons.py

> Machine-owned. Do NOT hand-edit. Changes are overwritten on the next `lessons.py` write.
> Canonical state lives in `.specs/lessons.json`. Edit lessons only via the script.
> promote_threshold=2 distinct features · window_days=45 · quarantine_threshold=2

## Confirmed (load these at Plan/Checks)

Corroborated across multiple features. Safe to apply as guidance.

_none_

## Candidates (under observation - do NOT load as guidance yet)

Seen once or not yet corroborated. Tracked, not trusted.

### L-001 - Bash 'read -ra' stops at the first newline; read multi-line secrets with 'read -rd "" -a ... || true' and test a value with embedded newlines.
- signal: `ac_gap` · recurrence: 1 feature(s) · scope: `shell` · harmful: 0
- features: ci-claude-code-review
- evidence: scripts/pick-token.sh:8 (shell)
- last seen: 2026-11-11T23:08:29Z

### L-002 - Assert a compound condition as the whole expression, not per-clause substrings, or swapping && for || stays green.
- signal: `weak_test` · recurrence: 1 feature(s) · scope: `yaml` · harmful: 0
- features: ci-claude-code-review
- evidence: tests/test_workflows.sh:C24-C26 (yaml)
- last seen: 2026-11-11T23:08:29Z

### L-003 - Give every fake CLI a failure switch per call it answers, so each precondition-failure path in the spec has a test.
- signal: `weak_test` · recurrence: 1 feature(s) · scope: `tests` · harmful: 0
- features: ci-claude-code-review
- evidence: tests/fake-gh (tests)
- last seen: 2026-11-11T23:08:29Z

### L-004 - When a skill encodes logic in a shell or jq snippet, extract and run that snippet against a fixture instead of grepping its text.
- signal: `weak_test` · recurrence: 1 feature(s) · scope: `skills` · harmful: 0
- features: ci-claude-code-review
- evidence: skills/the-judge/SKILL.md:57 (skills)
- last seen: 2026-11-11T23:08:29Z

### L-005 - List endpoints on GitHub need --paginate when the count drives behaviour; per_page alone caps at 100.
- signal: `ac_gap` · recurrence: 1 feature(s) · scope: `github-api` · harmful: 0
- features: ci-claude-code-review
- evidence: skills/the-judge/SKILL.md:57 (github-api)
- last seen: 2026-11-11T23:08:29Z

## Quarantined (failed when applied - ignore)

A confirmed lesson that recurred alongside failure. Kept for the maintainer to review.

_none_
