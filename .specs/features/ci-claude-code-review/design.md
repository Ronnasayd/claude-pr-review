# CI Claude Code Review Design

**Spec**: `.specs/features/ci-claude-code-review/spec.md`
**Status**: Approved (approach chosen by user: "~/.claude/skills + fallback"; amended after verifier pass, user: "Tudo (Recommended)")

---

## Architecture Overview

One public central repo (`Ronnasayd/claude-pr-review`) holds a reusable workflow, a token picker script and a CI-adapted copy of the-judge. It holds no secrets. Each caller repo holds one ~15-line workflow that grants the job's token permissions, calls the central workflow and passes one repository secret.

```mermaid
sequenceDiagram
    participant PR as Caller repo PR event
    participant CW as Caller workflow (permissions: contents read, pull-requests write)
    participant RW as Central reusable workflow (job "review")
    participant CR as Central repo @v1 (_ci/)
    participant CCA as claude-code-action@v1
    participant GH as GitHub API

    PR->>CW: opened / synchronize / reopened / ready_for_review
    CW->>RW: uses ...claude-review.yml@v1 + CLAUDE_TOKENS
    Note over RW: job if: not draft, same-repo head, author != dependabot[bot]<br/>concurrency: repo+PR, cancel-in-progress
    RW->>RW: checkout PR (fetch-depth 0)
    RW->>CR: checkout ref v1 into _ci/ (default token, public repo, persist-credentials false)
    RW->>RW: bash _ci/scripts/pick-token.sh -> steps.pick.outputs.token (masked)
    RW->>RW: cp _ci/skills/the-judge ~/.claude/skills/ ; rm -rf _ci
    RW->>CCA: claude_code_oauth_token, github_token, prompt "/the-judge Review PR #N in o/r. Write the review in Portuguese."
    Note over CCA: restores .claude/ from base (user-scope skill untouched)<br/>sets GH_TOKEN from github_token
    CCA->>GH: gh pr view / gh pr diff / reviews (round detection by login + marker)
    CCA->>GH: post_review.py --pr N --repo o/r -> one review, marker <!-- the-judge -->
    GH-->>CCA: APPROVE/REQUEST_CHANGES rejected? retry once as COMMENT + footer
```

**Why the skill goes to `~/.claude/skills`**: claude-code-action restores `.claude/` from the PR base branch and deletes paths absent there (`docs/security.md`, `src/github/operations/restore-config.ts`). A copy under the workspace `.claude/skills/` would be deleted before Claude starts. The action's default `settingSources` includes `user` (`base-action/src/parse-sdk-options.ts`), which supports loading it; the smoke PR proves it.

**Fallback** if the smoke PR shows `/the-judge` is not recognised: change the prompt to `Read and follow ~/.claude/skills/the-judge/SKILL.md. Review PR #N in o/r. Write the review in Portuguese.` and amend CCR-04, C4 and its `yq` assertion in the same commit. Apply it by pushing a new commit to the smoke PR after moving `v1` - a re-run reuses the first attempt's reusable-workflow SHA (GitHub docs, reusing workflows).

---

## Code Reuse Analysis

### Existing Components to Leverage

| Component                                                       | Location                                         | How to Use                                                                                                                                                                                         |
| --------------------------------------------------------------- | ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| the-judge v1.4.0 SKILL.md                                       | `aipp/skills/tech-leads-club/the-judge/SKILL.md` | Copy, then adapt Step 0, script paths in Steps 1, 6 and 7, the own-PR paragraph, the Convergence Contract round cap and Troubleshooting (CCR-11, 13, 14, 17, 18, 29); every other section verbatim |
| `references/review-standards.md`, `references/comment-voice.md` | `aipp/.../the-judge/references/`                 | Copy verbatim                                                                                                                                                                                      |
| `scripts/review_gate.py`                                        | `aipp/.../the-judge/scripts/review_gate.py`      | Copy verbatim (already handles Portuguese, e.g. `nao (apenas                                                                                                                                       | so  | somente)` pattern at line 32; accepts any round >= 2 at lines 149-161) |
| `scripts/scan_bypasses.py`                                      | `aipp/.../the-judge/scripts/scan_bypasses.py`    | Copy verbatim                                                                                                                                                                                      |
| `scripts/post_review.py`                                        | `aipp/.../the-judge/scripts/post_review.py`      | Copy, then adapt identity, targeting, marker and rejected-verdict retry                                                                                                                            |
| Workflow YAML in the plan                                       | `docs/plans/ci-claude-code-review.md`            | Starting point for both workflows; changes listed under Components                                                                                                                                 |

### Integration Points

| System                            | Integration Method                                                                                                                                                                             |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GitHub Actions reusable workflows | `on: workflow_call` with one required secret; caller grants token permissions                                                                                                                  |
| claude-code-action@v1             | Inputs `claude_code_oauth_token`, `github_token`, `prompt`, `claude_args`; step `env` adds `JUDGE_BOT_LOGIN`. The action itself sets `GH_TOKEN` from `github_token` (`src/entrypoints/run.ts`) |
| GitHub REST                       | `gh pr view`, `gh pr diff`, `GET/POST repos/{o}/{r}/pulls/{n}/reviews`                                                                                                                         |

---

## Components

### Central reusable workflow

- **Purpose**: Run the-judge on one PR of the calling repo.
- **Location**: `.github/workflows/claude-review.yml`
- **Interfaces**:
  - `on.workflow_call.secrets`: `CLAUDE_TOKENS` (required)
  - Job `review`: `runs-on: ubuntu-latest`; `permissions: {contents: read, pull-requests: write}` (CCR-05)
  - Job `if:` `!github.event.pull_request.draft && github.event.pull_request.head.repo.full_name == github.repository && github.event.pull_request.user.login != 'dependabot[bot]'` (CCR-19, 20, 21)
  - Job `concurrency`: `group: claude-review-${{ github.repository }}-${{ github.event.pull_request.number }}`, `cancel-in-progress: true` (CCR-22). Job level, not workflow level, so it cannot collide with a caller-defined group.
  - Steps, in order:
    1. `actions/checkout@v7` with `fetch-depth: 0`
    2. `actions/checkout@v7` with `repository: Ronnasayd/claude-pr-review`, `ref: v1`, `path: _ci`, `persist-credentials: false`; no `token:` input, the default token reads a public repo (CCR-23)
    3. `Pick token` (`id: pick`): `bash _ci/scripts/pick-token.sh` with `env: TOKENS: ${{ secrets.CLAUDE_TOKENS }}` (CCR-06..10)
    4. `Install skill`: `mkdir -p ~/.claude/skills && cp -r _ci/skills/the-judge ~/.claude/skills/ && rm -rf _ci` (CCR-03)
    5. `anthropics/claude-code-action@v1` with `claude_code_oauth_token: ${{ steps.pick.outputs.token }}`, `github_token: ${{ github.token }}`, the CCR-04 prompt and `claude_args` (`--max-turns 60`, `--allowedTools "Skill,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,Bash"`); `env: JUDGE_BOT_LOGIN: github-actions[bot]`
- **Dependencies**: `actions/checkout@v7` (latest release v7.0.1; v7.0.0 only adds a block on fork checkout for `pull_request_target`/`workflow_run`), `anthropics/claude-code-action@v1`
- **Reuses**: plan YAML, minus `CI_TEMPLATES_TOKEN`, `id-token: write` and the `_ci` checkout `token:` input (superseded by spec decisions)

### Caller workflow template

- **Purpose**: The file each caller repo copies (CCR-02).
- **Location**: `caller/claude-review.yml` (outside `.github/workflows/`, so the central repo never runs it - CCR-24)
- **Interfaces**: `on.pull_request.types: [opened, synchronize, reopened, ready_for_review]`; one job `review` with `permissions: {contents: read, pull-requests: write}`, `uses: Ronnasayd/claude-pr-review/.github/workflows/claude-review.yml@v1` and `secrets: {CLAUDE_TOKENS: ${{ secrets.CLAUDE_TOKENS }}}`
- **Why `permissions:`**: a called workflow can only downgrade the `GITHUB_TOKEN` permissions it receives (GitHub docs, reusing workflows); new personal-account repos default to read-only contents
- **Dependencies**: central workflow
- **Reuses**: plan YAML, with `secrets: inherit` replaced by explicit `CLAUDE_TOKENS` passing and a `permissions:` block added

### Token picker

- **Purpose**: Choose one token at random and expose it to one step only.
- **Location**: `scripts/pick-token.sh`
- **Interfaces**:
  - Input: env `TOKENS` (`;`-separated); env `GITHUB_OUTPUT` (file path)
  - Output on success: stdout `::add-mask::<token>` then `Using token <i> of <N>`; appends `token=<token>` to `$GITHUB_OUTPUT`; exit 0
  - Output on no token: stdout `::error::CLAUDE_TOKENS is empty or has no token`; exit 1
  - Rules: split on `;`, trim surrounding whitespace, drop empty entries, index `RANDOM % N`
- **Dependencies**: bash
- **Reuses**: plan's inline snippet

### CI the-judge skill

- **Purpose**: Review one PR unattended and post one review.
- **Location**: `skills/the-judge/` (`SKILL.md`, `references/`, `scripts/`)
- **Interfaces**:
  - `SKILL.md` Step 0: PR number and repo come from the prompt; every `gh` call passes `--repo <o/r>` or uses `repos/<o/r>/...`; login from `$JUDGE_BOT_LOGIN` (default `github-actions[bot]`); previous reviews = reviews where `user.login == $JUDGE_BOT_LOGIN` and body contains `<!-- the-judge -->`, selecting `{id, submitted_at, commit_id, body}`; round = count + 1; last reviewed commit = latest such review's `commit_id` (CCR-11, 13, 14)
  - `SKILL.md` Steps 1, 6, 7: scripts called as `python3 ~/.claude/skills/the-judge/scripts/<name>.py` (cwd is the caller checkout); Step 7 adds `--pr <N> --repo <o/r>`
  - `SKILL.md` Convergence Contract: the sentence "The Judge never runs a fourth round on the same finding set." is replaced by "In CI every push starts a round; round 4 and later post only the Resolution table and new 🔴 findings." (CCR-29); the rest verbatim
  - `SKILL.md` own-PR paragraph and Troubleshooting: every "ask the user" replaced by "stop and report the reason in the output; the job log carries it" (CCR-17)
  - `scripts/post_review.py findings.json --pr N --repo o/r` (both required; CCR-16):
    - runs `review_gate.py` from its own directory; non-zero → exit 1 `refusing to post, gate failed` (inherited)
    - `gh pr view N --repo o/r --json number,author`
    - login = `$JUDGE_BOT_LOGIN` or `github-actions[bot]`; no `gh api user` (CCR-11)
    - author == login and verdict != COMMENT → event COMMENT + inherited own-PR footer
    - body ends with `\n\n<!-- the-judge -->` (CCR-12)
    - POST `repos/o/r/pulls/N/reviews`; on any failure with event in {APPROVE, REQUEST_CHANGES} → retry once with event COMMENT and footer `Intended verdict: <V>. Posted as a comment because GitHub rejected the <V> event for this repository.` (CCR-15); a failed COMMENT post or failed retry → exit 1 with GitHub's message and the inherited anchor hint (CCR-17)
- **Dependencies**: `gh`, `python3` (both on `ubuntu-latest`)
- **Reuses**: aipp the-judge v1.4.0

### Tests

- **Purpose**: Prove CCR-02..29 locally; CCR-01 and the live round 2 are proven by the smoke PR.
- **Location**: `tests/run.sh` (runs every `tests/test_*.sh`, prints `ok - <name>` / `not ok - <name>`, exits non-zero on any failure), `tests/fake-gh` (records argv to `$FAKE_GH_LOG`, answers from env `FAKE_GH_*`), `tests/smoke.sh` (network; not run by `run.sh`)
- **Interfaces**: `bash tests/run.sh`; `bash tests/smoke.sh <owner/repo> <pr>`
- **Dependencies**: bash, python3, `yq` (mikefarah, local v4.45.4) for YAML key assertions, Docker for `rhysd/actionlint:1.7.12`

### README

- **Purpose**: One-time setup, maintenance, divergence list (CCR-26..28).
- **Location**: `README.md`

---

## Error Handling Strategy

| Error Scenario                                                           | Handling                                                    | User Impact                                                  |
| ------------------------------------------------------------------------ | ----------------------------------------------------------- | ------------------------------------------------------------ |
| `CLAUDE_TOKENS` empty or only separators                                 | Picker exits 1 with `::error::`                             | Red check, message names the secret                          |
| Caller job without `permissions:` on a read-only-default repo            | Run fails at startup (called workflow cannot elevate)       | Red check; README and caller template carry the block        |
| Picked token rate-limited or expired                                     | claude-code-action fails                                    | Red check; re-run picks again (plan decision)                |
| APPROVE / REQUEST_CHANGES rejected (e.g. Actions not allowed to approve) | Retry once as COMMENT + intended-verdict footer             | Review posted as comment, footer states intended verdict     |
| Anchor line not in diff                                                  | COMMENT post (or the retry) fails; exit 1 with anchors sent | Red check; skill's troubleshooting re-anchors before posting |
| Draft / fork / Dependabot PR                                             | Job skipped by `if:`                                        | Grey "skipped" check                                         |
| Newer push during a run                                                  | Older run cancelled                                         | Only the newest run posts                                    |

---

## Risks & Concerns

| Concern                                                                                                                         | Location (file:line)                         | Impact                                                   | Mitigation                                                                                    |
| ------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- | -------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Security: `actions/checkout` v6+ persists credentials to a file under `$RUNNER_TEMP`; Claude's unrestricted `Bash` runs PR code | `.github/workflows/claude-review.yml` step 2 | Extra copy of the job token on disk                      | `persist-credentials: false` on the `_ci` checkout; `rm -rf _ci` before Claude starts         |
| Security: unrestricted `Bash` can read the Claude OAuth token and `GH_TOKEN` from the process env                               | central workflow step 5                      | A PR author with push access could exfiltrate them       | Accepted by plan (fork PRs get no secrets; personal-account repos); stated in README (CCR-28) |
| Public central repo: workflow and skill are readable by anyone                                                                  | repo visibility                              | Review logic is visible; no secret is in the repo        | Accepted (user: "Mudar para público"); CCR-24 keeps `CLAUDE_TOKENS` out of the central repo   |
| Unproven: claude-code-action loads user-scope skills from `~/.claude/skills`                                                    | central workflow steps 4-5                   | `/the-judge` not recognised; no review                   | Default `settingSources` includes `user`; smoke PR proves it; one-line prompt fallback above  |
| Unproven: `Read` can open files under `~/.claude` outside the working directory                                                 | central workflow step 5                      | Skill references cannot be read                          | Smoke PR proves it; if blocked, add `--add-dir ~/.claude/skills/the-judge` to `claude_args`   |
| Unverified: HTTP status GitHub returns when Actions may not approve                                                             | `post_review.py` retry                       | A status-code match could miss the case                  | Retry keys on event type, not status code (CCR-15)                                            |
| Tech debt: the CI skill is a diverging copy of aipp the-judge                                                                   | `skills/the-judge/`                          | Upstream fixes are missed                                | README re-sync procedure + explicit divergence list (CCR-27)                                  |
| Test gap: aipp the-judge scripts have no tests (`rg review_gate\|post_review` in aipp finds only the skill's own files)         | `aipp/.../the-judge/scripts/`                | Inherited behaviour unverified                           | Tests in this repo cover the adapted `post_review.py` paths                                   |
| Self-checkout ref is hard-coded `v1`                                                                                            | central workflow step 2                      | Calling `@main` or `@v2` still loads the skill from `v1` | Plan decision; README says to keep tag and `ref` equal                                        |
| Unverified: whether a skipped fork/Dependabot run fails permission validation before `if:` is evaluated                         | caller `permissions:` block                  | Red instead of grey check on those PRs                   | Observed on the first such PR; not blocking                                                   |

---

## Tech Decisions (only non-obvious ones)

| Decision                 | Choice                                                | Rationale                                                                                                 |
| ------------------------ | ----------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Skill install path       | `~/.claude/skills/the-judge`                          | `.claude/` in the workspace is restored from the base branch by the action                                |
| GitHub identity          | Workflow `GITHUB_TOKEN` via `github_token` input      | No Claude GitHub App install per repo (user choice)                                                       |
| Token permissions        | Granted by the caller job                             | A called workflow can only downgrade what the caller grants                                               |
| Round detection key      | Bot login + hidden marker `<!-- the-judge -->`        | Other actions also post as `github-actions[bot]`; `GET /user` is unavailable to bot tokens                |
| Round cap                | Round 4+ = Resolution table + new 🔴 only             | Every push starts a round in CI (user choice)                                                             |
| Verdict retry trigger    | Event type (APPROVE/REQUEST_CHANGES), not status code | No official source gives the status code for the Actions-approval block                                   |
| Secrets passing          | Explicit `secrets:` map in caller                     | Personal account, no org secrets; avoids depending on `secrets: inherit` rules                            |
| Central repo visibility  | Public                                                | A private repo under a personal account is callable only by private repos (user choice after verifier H2) |
| Caller template location | `caller/claude-review.yml`                            | Keeps it out of the central repo's own `.github/workflows/` (CCR-24)                                      |
| `actions/checkout` major | `v7`                                                  | Latest release (v7.0.1); v7.0.0 change does not touch `pull_request`                                      |
