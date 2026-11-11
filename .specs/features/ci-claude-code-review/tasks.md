# CI Claude Code Review Tasks

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill: **activate it by name and follow its Execute flow and Critical Rules.** Do not search for skill files by filesystem path. The skill is the source of truth for the full flow (per-task cycle, sub-agent delegation, the walk, check_proofs, the Verifier and the screens sub-agent).

**If the skill cannot be activated, STOP and tell the user - do not proceed without it.**

---

**Design**: `.specs/features/ci-claude-code-review/design.md`
**Status**: Approved
**Approved**: 2026-11-11 - user: "Aprovo"
**Amended**: 2026-11-11 - verifier gap fixes, user: "Tudo (Recommended)"
**Build**: `docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12 .github/workflows/claude-review.yml caller/claude-review.yml; bash tests/run.sh`
**Run unit**: `bash tests/run.sh`

---

## Test Coverage Matrix

> Generated from project guidelines and user input - confirm before Execute. Guidelines found: `AGENTS.md` (TDD when a suite exists; evidence before review; "No test setup in repo → don't impose one unprompted"). The repo had no tests; the user chose "Lint + teste bash + smoke PR".

| Code Layer                                                     | Required Test Type                        | Coverage Expectation                                                                                                                                                                                                 | Location Pattern            | Run Command                                              |
| -------------------------------------------------------------- | ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------- | -------------------------------------------------------- |
| Shell scripts (`scripts/*.sh`)                                 | unit (bash)                               | Every AC of CCR-06..09 and every listed edge case (`;;`, trailing `;`, whitespace, empty)                                                                                                                            | `tests/test_pick_token.sh`  | `bash tests/run.sh`                                      |
| Python scripts (`skills/the-judge/scripts/post_review.py`)     | unit (bash + fake `gh` on `PATH`)         | Every adapted branch: targeting, identity, marker, own-PR fallback, verdict retry, failure exits                                                                                                                     | `tests/test_post_review.sh` | `bash tests/run.sh`                                      |
| Skill documents (`skills/the-judge/**/*.md`, verbatim scripts) | unit (content assertions)                 | Verbatim files byte-equal to aipp v1.4.0; adapted SKILL.md has no `gh api user`, no "ask the user", has the marker query with `commit_id`, absolute script paths, the round 4+ rule and `--pr`/`--repo` post command | `tests/test_skill.sh`       | `bash tests/run.sh`                                      |
| Workflow YAML (`.github/workflows/*.yml`, `caller/*.yml`)      | static (actionlint + `yq` key assertions) | Every key named by CCR-02..05, 10, 19..24 asserted by value                                                                                                                                                          | `tests/test_workflows.sh`   | `bash tests/run.sh` + actionlint in Build                |
| README                                                         | unit (content assertions)                 | Each item of CCR-26..28 present                                                                                                                                                                                      | `tests/test_readme.sh`      | `bash tests/run.sh`                                      |
| Remote repo setup (GitHub settings, tags)                      | none                                      | - (checked by `git ls-remote` / `gh api` in Done when)                                                                                                                                                               | -                           | -                                                        |
| End-to-end on GitHub                                           | e2e (smoke PR)                            | One review on open; round-2 review with Resolution section after a second commit                                                                                                                                     | `tests/smoke.sh`            | `bash tests/smoke.sh Ronnasayd/claude-pr-review-smoke 1` |

## Gate Check Commands

> Generated from user input - confirm before Execute.

| Gate Level | When to Use                          | Command                                                                                                                                            |
| ---------- | ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| Quick      | After tasks with unit tests only     | `bash tests/run.sh`                                                                                                                                |
| Full       | After the smoke task                 | `bash tests/run.sh; bash tests/smoke.sh Ronnasayd/claude-pr-review-smoke 1`                                                                        |
| Build      | After phase completion or YAML tasks | `docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12 .github/workflows/claude-review.yml caller/claude-review.yml; bash tests/run.sh` |

---

## Execution Plan

Phases are ordered and run sequentially - each phase completes before the next begins, and tasks within a phase execute in order.

### Phase 1: Token picker and CI skill

```
T1 → T2 → T3 → T4 → T5 → T6
```

### Phase 2: Workflows and docs

```
T6 → T7 → T8 → T9
```

### Phase 3: Remote and smoke (needs explicit go-ahead for each remote action)

```
T9 → T10 → T11
```

---

## Task Breakdown

### T1: Token picker script with test runner

**What**: `scripts/pick-token.sh` per design "Token picker", plus `tests/run.sh` (runs every `tests/test_*.sh`, prints `ok - <name>` / `not ok - <name>`, exits non-zero on any failure) and `tests/test_pick_token.sh`.
**Where**: `scripts/pick-token.sh`
**Depends on**: None
**Reuses**: plan's inline picker snippet
**Requirement**: CCR-06, CCR-07, CCR-08, CCR-09

**Done when**:

- [x] Tests written first and seen failing, then passing
- [x] Inputs covered: `tok1`, `tok1;tok2;tok3`, `tok1 ; tok2`, `tok1;;tok2;`, `""`, `;;`
- [x] Gate check passes: `bash tests/run.sh`
- [x] Test count: 7 tests pass (no silent deletions)

**Tests**: unit
**Gate**: quick

**Commit**: `feat(picker): pick one random token from CLAUDE_TOKENS`

---

### T2: Copy aipp the-judge verbatim

**What**: Copy `aipp/skills/tech-leads-club/the-judge` (v1.4.0) into `skills/the-judge/` unchanged; add `tests/test_skill.sh` asserting `references/*.md`, `scripts/review_gate.py` and `scripts/scan_bypasses.py` are byte-equal to the source.
**Where**: `skills/the-judge/`
**Depends on**: T1
**Reuses**: aipp the-judge v1.4.0
**Requirement**: CCR-18

**Done when**:

- [x] Verbatim-file test passes
- [x] Gate check passes: `bash tests/run.sh`
- [x] Test count: 8 tests pass

**Tests**: unit
**Gate**: quick

**Commit**: `chore(skill): vendor the-judge v1.4.0 from aipp`

---

### T3: post_review.py targets --pr/--repo and drops gh api user

**What**: `post_review.py` requires `--pr N --repo o/r`, calls `gh pr view N --repo o/r`, posts to `repos/o/r/pulls/N/reviews`, takes its login from `JUDGE_BOT_LOGIN` (default `github-actions[bot]`) and never calls `gh api user`; own-PR fallback kept. Adds `tests/fake-gh` and `tests/test_post_review.sh`.
**Where**: `skills/the-judge/scripts/post_review.py`
**Depends on**: T2
**Reuses**: aipp `post_review.py`
**Requirement**: CCR-11, CCR-16, CCR-18

**Done when**:

- [x] Fake `gh` log shows no `api user` call and `--repo o/r` on every `pr` call
- [x] Missing `--pr` or `--repo` exits 1 with usage
- [x] Author == login posts event COMMENT with the inherited own-PR footer
- [x] Gate check passes: `bash tests/run.sh`
- [x] Test count: 12 tests pass

**Tests**: unit
**Gate**: quick

**Commit**: `feat(skill): post_review targets explicit PR without gh api user`

---

### T4: post_review.py appends the review marker

**What**: Every posted review body ends with `\n\n<!-- the-judge -->`.
**Where**: `skills/the-judge/scripts/post_review.py`
**Depends on**: T3
**Reuses**: T3 test harness
**Requirement**: CCR-12

**Done when**:

- [x] Payload body captured by fake `gh` ends with `<!-- the-judge -->`, including with the own-PR footer
- [x] Gate check passes: `bash tests/run.sh`
- [x] Test count: 14 tests pass

**Tests**: unit
**Gate**: quick

**Commit**: `feat(skill): mark reviews posted by the-judge`

---

### T5: post_review.py retries rejected verdicts as COMMENT and fails loudly

**What**: On any rejected submission with event APPROVE or REQUEST_CHANGES, retry once with event COMMENT and the footer `Intended verdict: <V>. Posted as a comment because GitHub rejected the <V> event for this repository.`; a rejected COMMENT post, a rejected retry, or a gate failure exits 1 with the reason.
**Where**: `skills/the-judge/scripts/post_review.py`
**Depends on**: T4
**Reuses**: aipp anchor hint
**Requirement**: CCR-15, CCR-17

**Done when**:

- [x] Fake `gh` rejecting the first POST: two POSTs, second has event COMMENT and the footer, exit 0
- [x] Fake `gh` rejecting both POSTs: exit 1, stderr has `review submission failed` and the anchors
- [x] Rejection with event COMMENT: one POST only, exit 1
- [x] Gate failure: no POST, exit 1 with `refusing to post, gate failed`
- [x] Gate check passes: `bash tests/run.sh`
- [x] Test count: 18 tests pass

**Tests**: unit
**Gate**: quick

**Commit**: `feat(skill): retry rejected verdicts as comment`

---

### T6: SKILL.md adapted for unattended CI

**What**: Step 0 takes PR number and repo from the prompt, uses `$JUDGE_BOT_LOGIN`, finds previous reviews by login + `<!-- the-judge -->` selecting `commit_id` (round = count + 1, last reviewed commit = latest `commit_id`); Steps 1, 6 and 7 call scripts as `python3 ~/.claude/skills/the-judge/scripts/...`, Step 7 with `--pr`/`--repo`; Convergence Contract's "never runs a fourth round" sentence replaced by the round 4+ rule (CCR-29); own-PR paragraph and Troubleshooting replace every human ask with "stop and report the reason"; all other sections unchanged.
**Where**: `skills/the-judge/SKILL.md`
**Depends on**: T5
**Reuses**: aipp SKILL.md
**Requirement**: CCR-11, CCR-13, CCR-14, CCR-17, CCR-18, CCR-29

**Done when**:

- [x] `tests/test_skill.sh` asserts: no `gh api user`; no `ask the user`; marker query with `commit_id` present; round rule text present; no cwd-relative `python3 scripts/`; post command has `--pr` and `--repo`; round 4+ sentence present and "never runs a fourth round" absent; sections Non-Negotiables, Severity and Verdict, Steps 2-5 byte-equal to aipp; Convergence Contract equal to aipp except the replaced sentence
- [x] Gate check passes: `bash tests/run.sh`
- [x] Test count: 26 tests pass

**Tests**: unit
**Gate**: quick

**Commit**: `feat(skill): run the-judge unattended in CI`

---

### T7: Central reusable workflow

**What**: `.github/workflows/claude-review.yml` per design "Central reusable workflow", plus `tests/test_workflows.sh` asserting each key with `yq`.
**Where**: `.github/workflows/claude-review.yml`
**Depends on**: T6
**Reuses**: plan YAML, minus `CI_TEMPLATES_TOKEN`, `id-token: write` and the `_ci` checkout `token:` input
**Requirement**: CCR-03, CCR-04, CCR-05, CCR-10, CCR-19, CCR-20, CCR-21, CCR-22, CCR-23

**Done when**:

- [x] actionlint exits 0
- [x] `yq` assertions pass for: only `CLAUDE_TOKENS` secret, required; permissions exactly two; job `if:`; concurrency group and cancel; `_ci` checkout repository/ref/path, `persist-credentials: false`, no `token:`; install step copies to `~/.claude/skills` and removes `_ci`; picker step id and env; no `GITHUB_ENV` write anywhere; action inputs (oauth token from `steps.pick.outputs.token`, `github_token`, prompt, `--max-turns 60`, `--allowedTools` with `Write,Edit`); step env `JUDGE_BOT_LOGIN`; no `id-token`
- [x] Gate check passes: Build
- [x] Test count: 39 tests pass

**Tests**: unit
**Gate**: build

**Commit**: `feat(ci): reusable claude review workflow`

---

### T8: Caller workflow template

**What**: `caller/claude-review.yml` per design "Caller workflow template"; assertions added to `tests/test_workflows.sh`, including that the central repo's `.github/workflows/` has no `pull_request` trigger and no `CLAUDE_TOKENS` use outside `workflow_call`.
**Where**: `caller/claude-review.yml`
**Depends on**: T7
**Reuses**: plan caller YAML, with `secrets: inherit` replaced by explicit `CLAUDE_TOKENS` and a `permissions:` block
**Requirement**: CCR-02, CCR-24

**Done when**:

- [x] actionlint exits 0 on both files
- [x] Assertions pass: triggers `[opened, synchronize, reopened, ready_for_review]`, one job, job `permissions` exactly `contents: read` and `pull-requests: write`, `uses:` value exact, `CLAUDE_TOKENS` passed explicitly, no `secrets: inherit`
- [x] Gate check passes: Build
- [x] Test count: 44 tests pass

**Tests**: unit
**Gate**: build

**Commit**: `feat(ci): caller workflow template`

---

### T9: README setup and maintenance guide

**What**: `README.md` with one-time setup, re-sync procedure, divergence list and caveats; `tests/test_readme.sh` greps each item.
**Where**: `README.md`
**Depends on**: T8
**Reuses**: plan "One-time setup" and "Caveats"
**Requirement**: CCR-26, CCR-27, CCR-28

**Done when**:

- [x] Assertions pass for each item of CCR-26, CCR-27, CCR-28
- [x] Gate check passes: `bash tests/run.sh`
- [x] Test count: 47 tests pass

**Tests**: unit
**Gate**: quick

**Commit**: `docs: setup and maintenance guide`

---

### T10: Publish the central repo and tag v1

**What**: Create public `Ronnasayd/claude-pr-review` on GitHub, push `main`, create lightweight tag `v1`. Each remote action needs the user's explicit go-ahead at the time.
**Where**: GitHub remote (no file)
**Depends on**: T9
**Reuses**: none
**Requirement**: CCR-24, CCR-25

**Done when**:

- [x] `git ls-remote origin 'refs/tags/v1^{}' refs/tags/v1` shows the `HEAD` sha
- [x] `gh api repos/Ronnasayd/claude-pr-review --jq .visibility` prints `public`
- [x] `gh secret list -R Ronnasayd/claude-pr-review` prints nothing

**Tests**: none
**Gate**: build

**Commit**: none (remote-only task)

---

### T11: Smoke PR on a test repo

**What**: `tests/smoke.sh <owner/repo> <pr>` plus a run on a test repo `Ronnasayd/claude-pr-review-smoke` that has the caller file and `CLAUDE_TOKENS` (the user creates the secret with real `claude setup-token` tokens). Open a PR, then push a second commit; `tests/smoke.sh` asserts the outcome. If `/the-judge` is not recognised, apply the design's prompt fallback (amending CCR-04, C4 and its assertion), move `v1`, and push a new commit to the PR - never a re-run, which reuses the first attempt's workflow SHA.
**Where**: `tests/smoke.sh`
**Depends on**: T10
**Reuses**: none
**Requirement**: CCR-01, CCR-13

**Done when**:

- [x] `bash tests/smoke.sh Ronnasayd/claude-pr-review-smoke 1` exits 0: latest run on the PR concluded `success`; two reviews by `github-actions[bot]` with `<!-- the-judge -->`; the second contains a `Resolution` section
- [x] Run URL and review URLs recorded in `## Handoff` under `**Walked:**`

**Tests**: e2e
**Gate**: full

**Commit**: `test(smoke): end-to-end review on a test repo`

---

## Checks

**C1** - A non-draft PR in a caller repo gets one review authored by `github-actions[bot]`, and the second commit's review is round 2 with a Resolution section (CCR-01, AC 1; CCR-13, AC 3 live)
Proof: `bash tests/smoke.sh Ronnasayd/claude-pr-review-smoke 1`

**C2** - Caller file has one job granting `contents: read` and `pull-requests: write`, using `Ronnasayd/claude-pr-review/.github/workflows/claude-review.yml@v1` and passing `CLAUDE_TOKENS` explicitly (CCR-02, AC 2)
Proof: run unit | ok - caller: uses central workflow at v1 with permissions and secret

**C3** - Skill is copied to `~/.claude/skills/the-judge` and `_ci` is removed before the Claude step (CCR-03, AC 3)
Proof: run unit | ok - workflow: installs skill to home and removes _ci before claude

**C4** - Claude step prompt, `--max-turns 60` and `--allowedTools` list (with `Write,Edit`) match the spec (CCR-04, AC 4)
Proof: run unit | ok - workflow: claude prompt and args

**C5** - Job permissions are exactly `contents: read` and `pull-requests: write` (CCR-05, AC 5)
Proof: run unit | ok - workflow: permissions exactly contents read and pull-requests write

**C6** - Picker returns one trimmed non-empty entry (CCR-06, AC 1)
Proof: run unit | ok - pick_token: trims whitespace and skips empty entries

**C7** - Every one of three tokens is reachable in 200 draws (CCR-07, AC 2)
Proof: run unit | ok - pick_token: every token reachable

**C8** - Picker masks the token and logs only `Using token <i> of <N>` (CCR-08, AC 3)
Proof: run unit | ok - pick_token: masks token and logs index only

**C9** - Empty or separator-only `CLAUDE_TOKENS` exits 1 with `CLAUDE_TOKENS is empty or has no token` (CCR-09, AC 4)
Proof: run unit | ok - pick_token: empty input fails with message

**C10** - Token flows via `steps.pick.outputs.token` and nothing writes `GITHUB_ENV` (CCR-10, AC 5)
Proof: run unit | ok - workflow: token only via step output

**C11** - `post_review.py` never calls `gh api user` and uses `JUDGE_BOT_LOGIN` defaulting to `github-actions[bot]` (CCR-11, AC 1)
Proof: run unit | ok - post_review: no gh api user and default bot login

**C12** - Posted review body ends with `<!-- the-judge -->` (CCR-12, AC 2)
Proof: run unit | ok - post_review: body ends with marker

**C13** - SKILL.md selects previous reviews by bot login and marker with `commit_id` and sets round to count + 1 (CCR-13, AC 3)
Proof: run unit | ok - skill: round from marked bot reviews

**C14** - SKILL.md runs round 1 when no marked review exists (CCR-14, AC 4)
Proof: run unit | ok - skill: round 1 when no marked review

**C15** - A rejected APPROVE retries once as COMMENT with the intended-verdict footer (CCR-15, AC 5)
Proof: run unit | ok - post_review: rejected approve retries as comment

**C16** - `post_review.py` targets `--pr`/`--repo` and fails without them (CCR-16, AC 6)
Proof: run unit | ok - post_review: requires and uses pr and repo

**C17** - SKILL.md has no human ask (CCR-17, AC 7)
Proof: run unit | ok - skill: no human ask in skill

**C18** - A rejected COMMENT submission is not retried and exits 1 naming the anchors (CCR-17, AC 7)
Proof: run unit | ok - post_review: rejected comment exits without retry

**C19** - A rejected retry exits 1 with GitHub's message (CCR-17, AC 7)
Proof: run unit | ok - post_review: rejected retry exits 1

**C20** - Gate failure posts nothing and exits 1 (CCR-17, AC 7)
Proof: run unit | ok - post_review: gate failure posts nothing

**C21** - Review passes, verification, gate and references are unchanged from aipp; scripts are called by absolute path (CCR-18, AC 8)
Proof: run unit | ok - skill: unchanged sections equal aipp

**C22** - PR authored by the bot login posts as COMMENT with the inherited own-PR footer (CCR-18, AC 8)
Proof: run unit | ok - post_review: own pr posts as comment

**C23** - SKILL.md states round 4+ posts only the Resolution table and new 🔴 findings, and no longer forbids a fourth round (CCR-29, AC 9)
Proof: run unit | ok - skill: round 4 and later resolution only

**C24** - Job `if:` skips drafts (CCR-19, AC 1)
Proof: run unit | ok - workflow: skips drafts

**C25** - Job `if:` skips fork PRs (CCR-20, AC 2)
Proof: run unit | ok - workflow: skips forks

**C26** - Job `if:` skips `dependabot[bot]` (CCR-21, AC 3)
Proof: run unit | ok - workflow: skips dependabot

**C27** - Concurrency group is repo + PR with `cancel-in-progress: true` (CCR-22, AC 4)
Proof: run unit | ok - workflow: concurrency per repo and pr cancels in progress

**C28** - `_ci` checkout uses `Ronnasayd/claude-pr-review`, ref `v1`, no `token:` input, `persist-credentials: false` (CCR-23, AC 1)
Proof: run unit | ok - workflow: central checkout at v1 without persisted credentials

**C29** - The central repo's own workflows have no `pull_request` trigger (CCR-24, AC 2)
Proof: run unit | ok - caller: central repo never reviews itself

**C30** - The central repo is public and holds no secret (CCR-25, AC 3; CCR-24, AC 2)
Proof: `test "$(gh api repos/Ronnasayd/claude-pr-review --jq .visibility)" = public && test -z "$(gh secret list -R Ronnasayd/claude-pr-review)"`

**C31** - README lists the one-time setup items, including the caller `permissions:` block (CCR-26, AC 1)
Proof: run unit | ok - readme: one-time setup

**C32** - README describes re-sync and lists divergences (CCR-27, AC 2)
Proof: run unit | ok - readme: re-sync and divergences

**C33** - README states token expiry, terms of use, Bash exposure, no dependency install and heavier quota use (CCR-28, AC 3)
Proof: run unit | ok - readme: caveats

---

## Handoff

**Settled mid-build:** none
**Dispatched:** none
**Walked:** smoke PR https://github.com/Ronnasayd/claude-pr-review-smoke/pull/1 (private test repo, caller file on main, CLAUDE_TOKENS set). Round 1 on e18f1af: run https://github.com/Ronnasayd/claude-pr-review-smoke/actions/runs/43115342113 success, review https://github.com/Ronnasayd/claude-pr-review-smoke/pull/1#pullrequestreview-5866364859 (COMMENT, F1 should-fix, F2 nit, Portuguese, marker). Round 2 on f81be5a: run https://github.com/Ronnasayd/claude-pr-review-smoke/actions/runs/43115716567 success, review https://github.com/Ronnasayd/claude-pr-review-smoke/pull/1#pullrequestreview-5866398646 (APPROVE, Resolution table F1/F2 resolved). `/the-judge` loaded from ~/.claude/skills; prompt fallback not needed. `bash tests/smoke.sh Ronnasayd/claude-pr-review-smoke 1` -> PASS. The private smoke repo needs the gh account Ronnasayd: `GH_TOKEN=$(gh auth token --user Ronnasayd)`.

---

## Phase Execution Map

```
Phase 1 → Phase 2 → Phase 3

Phase 1:  T1 → T2 → T3 → T4 → T5 → T6
Phase 2:  T7 → T8 → T9
Phase 3:  T10 → T11
```

Execution is strictly sequential. 11 tasks pack into two batches (Phase 1 = 6; Phases 2-3 = 5), so Execute offers batch sub-agents first.
