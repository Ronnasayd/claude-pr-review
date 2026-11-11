# ADR-002 – CI-adapted copy of the-judge

> **Date:** 2026-11-11
> **Status:** Accepted
> **Deciders:** Repository owner

## Context

The review logic is the `the-judge` skill (v1.4.0) from `aipp/skills/tech-leads-club/the-judge`. It was written for an interactive session, and several parts of it break when it runs unattended in CI:

- `scripts/post_review.py` calls `gh api user`. A bot token cannot call that endpoint, and the script exits when the call fails.
- Troubleshooting tells the agent to ask the user to authenticate.
- Script paths are relative to the skill directory.
- The Convergence Contract forbids a fourth review round. In CI, every push starts a new round.

## Decision

The central repository holds its own copy of the-judge under `skills/the-judge/`. The copy deliberately differs from `aipp` only where CI cannot provide a human or a local branch:

- Its own login comes from `JUDGE_BOT_LOGIN`.
- Earlier rounds are found by matching the bot login together with a `<!-- the-judge -->` marker.
- Scripts take explicit `--pr`/`--repo` arguments and use absolute paths.
- A rejected APPROVE or REQUEST_CHANGES is retried once as COMMENT.
- Round 4 and later post only the Resolution table and new blockers.
- Every "ask the user" step becomes "stop and report".

The review passes, the gate rules and the reference guides stay unchanged. The owner's words: "usar the-judge como base mas nao precisa ser exatamente igual principalmente nessas partes que necessitam de ação humana".

## Considered Alternatives

| Alternative                       | Pros                                                         | Cons                                                                             |
| --------------------------------- | ------------------------------------------------------------ | -------------------------------------------------------------------------------- |
| CI-adapted copy (chosen)          | Runs unattended. `aipp` stays untouched for interactive use. | The copy drifts from `aipp`, so every re-sync has to re-apply the adaptations.   |
| Verbatim copy                     | Re-syncing is trivial.                                       | Posting fails on `gh api user`, and round detection depends on a human identity. |
| Patch `aipp` itself to support CI | Keeps one source of truth.                                   | Couples the interactive skill to CI concerns and changes another repository.     |

## Consequences

- A blind re-copy from `aipp` silently undoes the CI behaviour. The README lists every divergence (spec CCR-27), and the tests in `tests/test_skill.sh` fail if an adaptation is lost.
- A fix made upstream in `aipp` reaches CI only after a deliberate re-copy and a move of the `v1` tag.

## Related ADRs

- ADR-001 – Public central review repository with no secrets
