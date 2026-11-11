# CI Claude Code Review Specification

**Approved**: 2026-11-11 - user: "Aprovo"
**Amended**: 2026-11-11 - verifier gap fixes, user: "Tudo (Recommended)"; visibility user: "Mudar para público"; round 4+ user: "Review curta só resolução"; tools user: "Adicionar Write,Edit"

## Problem Statement

Pull requests in the owner's repositories get no automatic review. The owner wants every opened or updated PR reviewed by Claude with the `the-judge` skill, posted as one consolidated GitHub review with inline comments, without copying review logic into each repository. The review logic and the workflow live in one central repository (`Ronnasayd/claude-pr-review`); every other repository calls it with a ~15-line file.

## Goals

- [ ] A non-draft PR opened or updated in any caller repo (public or private) receives exactly one consolidated review from `github-actions[bot]`, proven by a smoke PR whose run and review URLs are recorded in `tasks.md` `## Handoff`.
- [ ] Changing the workflow or the skill in the central repo (and moving the `v1` tag) changes the review for every caller repo, with zero edits in caller repos.
- [ ] Usage spreads across several Claude subscription tokens with no stored rotation state.

## Out of Scope

| Feature                                                                      | Reason                                                                                                                                               |
| ---------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Installing project dependencies (`npm ci`, `uv sync`) before the review      | Plan caveat: checks that need them fail and the skill reports it in "Checks run"; add a per-stack setup step later if the signal is worth it         |
| Fallback to another token when the picked one is rate-limited                | Plan decision: re-running the job picks again; no state is stored                                                                                    |
| Reviewing fork PRs                                                           | GitHub passes no secrets to fork PRs; they are skipped                                                                                               |
| `anthropic_api_key` authentication path                                      | Plan names it as the official team alternative; not built now                                                                                        |
| Restricting `Bash` to `gh`/`python3`                                         | Plan decision: the-judge must run the repo's own lint/tests; the exposure is limited to people who can push branches                                 |
| Automatic sync of the skill copy with `aipp`                                 | Plan decision: the copy is re-synced on purpose and the tag moved                                                                                    |
| The central repo reviewing its own PRs                                       | The central repo holds no `CLAUDE_TOKENS` secret (see CCR-24)                                                                                        |
| Choosing the Claude model                                                    | Not requested; the action default applies                                                                                                            |
| Confirming with Anthropic that several subscription tokens may be used in CI | Owner's responsibility (plan caveat "Terms of use"); documented in the README, not enforced by code                                                  |
| Hiding the workflow and skill from third parties                             | Central repo is public (user: "Mudar para público"); a private central repo under a personal account can be called only by the owner's private repos |

---

## Assumptions & Open Questions

| Assumption / decision                                  | Chosen default                                                                                                                                                                                                                         | Rationale                                                                                                                                                                                                                                                                                                                                               | Confirmed?                          |
| ------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------- |
| Central repo location and owner                        | This repo, `Ronnasayd/claude-pr-review`, personal account (no organization)                                                                                                                                                            | user: "Este repo, conta pessoal"                                                                                                                                                                                                                                                                                                                        | y                                   |
| Central repo visibility                                | Public                                                                                                                                                                                                                                 | user first chose "Privado"; the verifier then showed GitHub's `user` access level "allows sharing across user owned private repositories only", so public callers could not adopt; user: "Mudar para público". Secrets stay only in caller repos (GitHub docs: called workflows get secrets only from the caller's `secrets:` block)                    | y                                   |
| Secrets model                                          | One repository secret `CLAUDE_TOKENS` in each caller repo, passed explicitly in the caller's `secrets:` block                                                                                                                          | Personal accounts have no organization secrets (`gh api user/orgs` returned nothing); explicit passing avoids depending on `secrets: inherit` rules for personal accounts                                                                                                                                                                               | y                                   |
| Caller job permissions                                 | Caller job declares `permissions: {contents: read, pull-requests: write}`                                                                                                                                                              | GitHub docs: a called workflow can only downgrade the `GITHUB_TOKEN` permissions it receives; new personal-account repos default to read-only, so without this the central job cannot get `pull-requests: write`                                                                                                                                        | y - verifier H1, user: "Tudo"       |
| GitHub identity that reads the PR and posts the review | Workflow `GITHUB_TOKEN` passed as the action's `github_token`; reviews authored by `github-actions[bot]`; no `id-token: write`                                                                                                         | user: "GITHUB_TOKEN do workflow"; without `github_token` the action exchanges OIDC for the Claude GitHub App token (claude-code-action `src/github/token.ts`), which needs the app installed per repo                                                                                                                                                   | y                                   |
| How faithful the CI skill is to `aipp` the-judge       | The-judge is the base; the CI copy diverges where the original needs a human (identity via `gh api user`, "ask the user to authenticate", reliance on the checked-out branch, cwd-relative script paths) and in the round cap (CCR-29) | user: "usar the-judge como base mas nao precisa ser exatamente igual principalmente nessas partes que necessitam de ação humana"                                                                                                                                                                                                                        | y                                   |
| Draft PRs                                              | Not reviewed; reviewed when marked ready for review                                                                                                                                                                                    | user: "Pular drafts"                                                                                                                                                                                                                                                                                                                                    | y                                   |
| Verification approach                                  | `actionlint` (pinned Docker image) for YAML, `bash` tests for scripts with a fake `gh`, one smoke PR on a test repo as final proof                                                                                                     | user: "Lint + teste bash + smoke PR"; the smoke PR needs `git push`, asked for at that step                                                                                                                                                                                                                                                             | y                                   |
| Where the skill is installed on the runner             | `~/.claude/skills/the-judge` (user scope), not `.claude/skills/`                                                                                                                                                                       | claude-code-action `docs/security.md`: on PRs it restores `.claude/` from the base branch and deletes paths absent there. claude-code-action@v1 `base-action/src/parse-sdk-options.ts` defaults `settingSources` to `["user","project","local"]`, which supports user-scope loading; the smoke PR proves it. Fallback: the one-line prompt in design.md | n - proven by smoke PR (CCR-01)     |
| `gh` authentication inside Claude's `Bash`             | No extra env: the action sets `GH_TOKEN` from `github_token`                                                                                                                                                                           | claude-code-action@v1 `src/entrypoints/run.ts` sets `process.env.GH_TOKEN = githubToken`; `parse-sdk-options.ts` passes `process.env` to Claude                                                                                                                                                                                                         | y - action source                   |
| Tools Claude may use                                   | `Skill,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,Bash`                                                                                                                                                                              | the-judge writes and rewrites `findings.json` until the gate passes; agent mode adds no tools beyond `claude_args` (claude-code-action@v1 `src/modes/agent/index.ts`). `Bash` is already unrestricted, so `Write`/`Edit` add no new exposure                                                                                                            | y - user: "Adicionar Write,Edit"    |
| Rounds after the third                                 | Round 4 and later still post, limited to the Resolution table and new 🔴 findings                                                                                                                                                      | the-judge forbids a fourth round, but in CI every push starts one; user: "Review curta só resolução"                                                                                                                                                                                                                                                    | y                                   |
| Which posting failures trigger the COMMENT retry       | Any rejected submission whose event is `APPROVE` or `REQUEST_CHANGES`                                                                                                                                                                  | No official source states the HTTP status GitHub returns when Actions may not approve PRs, so the retry does not depend on the status code; an anchor error repeats on the retry and then fails loudly                                                                                                                                                  | y - verifier M3, user: "Tudo"       |
| Review language                                        | Portuguese, fixed in the prompt                                                                                                                                                                                                        | Plan prompt: "Write the review in Portuguese."                                                                                                                                                                                                                                                                                                          | y                                   |
| Turn cap                                               | `--max-turns 60`                                                                                                                                                                                                                       | Plan value; tune after real PRs                                                                                                                                                                                                                                                                                                                         | y                                   |
| Concurrent runs for the same PR                        | Concurrency group per repository + PR number with `cancel-in-progress: true`                                                                                                                                                           | A newer push makes the running review stale; the review is posted in one API call, so cancelling never leaves a partial review                                                                                                                                                                                                                          | y - agent default, correct if wrong |
| Self-checkout ref of the central repo                  | Fixed `v1`, equal to the tag callers use                                                                                                                                                                                               | Plan: "keep equal to the tag callers use"                                                                                                                                                                                                                                                                                                               | y                                   |
| Dependabot PRs                                         | Skipped                                                                                                                                                                                                                                | Dependabot runs get Dependabot secrets, not Actions secrets, so `CLAUDE_TOKENS` is empty there                                                                                                                                                                                                                                                          | y - agent default, correct if wrong |

**Open questions:** none - all resolved or logged above.

---

## User Stories

### P1: Review posted on every PR update ⭐ MVP

**User Story**: As the owner of several repositories, I want every non-draft PR reviewed by the-judge when it is opened or updated so that I get one evidence-backed review without running anything by hand.

**Why P1**: This is the feature.

**Acceptance Criteria**:

1. WHEN a non-draft PR is opened, synchronized, reopened or marked ready for review in a caller repo THEN the system SHALL post exactly one GitHub review on that PR authored by `github-actions[bot]`. <!-- CCR-01 -->
2. The caller workflow SHALL be one file `.github/workflows/claude-review.yml` with one job that declares `permissions: {contents: read, pull-requests: write}`, uses `Ronnasayd/claude-pr-review/.github/workflows/claude-review.yml@v1` and passes `CLAUDE_TOKENS` in its `secrets:` block. <!-- CCR-02 -->
3. The central workflow SHALL install the CI skill at `~/.claude/skills/the-judge` and SHALL leave no `_ci/` directory in the workspace when the Claude step starts. <!-- CCR-03 -->
4. The central workflow SHALL run claude-code-action with the prompt `/the-judge Review PR #<number> in <owner>/<repo>. Write the review in Portuguese.`, `--max-turns 60` and `--allowedTools "Skill,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,Bash"`. <!-- CCR-04 -->
5. The central workflow job SHALL declare exactly the permissions `contents: read` and `pull-requests: write`. <!-- CCR-05 -->

**Independent Test**: Open a PR on a test repo that has the caller file and `CLAUDE_TOKENS`; the run succeeds and the PR shows one review by `github-actions[bot]`.

---

### P1: Random token selection

**User Story**: As the owner of several Claude accounts, I want each run to use one token picked at random from `CLAUDE_TOKENS` so that usage spreads across accounts without stored state.

**Why P1**: Without a token the review cannot run.

**Acceptance Criteria**:

1. WHEN `CLAUDE_TOKENS` holds one or more entries separated by `;` THEN the picker SHALL return exactly one of the non-empty entries, with surrounding whitespace trimmed. <!-- CCR-06 -->
2. WHEN `CLAUDE_TOKENS` holds N non-empty entries THEN the picker SHALL be able to return each of the N entries (no entry is unreachable). <!-- CCR-07 -->
3. The picker SHALL register the chosen token with `::add-mask::` before writing it to the step output and SHALL log only `Using token <i> of <N>`. <!-- CCR-08 -->
4. IF `CLAUDE_TOKENS` holds no non-empty entry THEN the picker SHALL exit with status 1 and print `CLAUDE_TOKENS is empty or has no token`. <!-- CCR-09 -->
5. The chosen token SHALL reach only the claude-code-action step, through a step output and never through `$GITHUB_ENV`. <!-- CCR-10 -->

**Independent Test**: `bash tests/run.sh` exercises the picker with one, three, whitespace-padded, trailing-`;` and empty inputs.

---

### P1: CI-adapted the-judge

**User Story**: As the owner, I want the-judge to run unattended in CI so that no step waits for or depends on a human.

**Why P1**: The `aipp` version calls `gh api user` (fails with a bot token) and tells the agent to ask the user to authenticate.

**Acceptance Criteria**:

1. The CI skill and its scripts SHALL NOT call `GET /user`; they SHALL take their own login from `JUDGE_BOT_LOGIN`, defaulting to `github-actions[bot]`. <!-- CCR-11 -->
2. WHEN `post_review.py` posts a review THEN the review body SHALL end with the marker `<!-- the-judge -->`. <!-- CCR-12 -->
3. WHEN the PR already has N reviews authored by `JUDGE_BOT_LOGIN` whose body contains `<!-- the-judge -->` THEN the skill SHALL run round N+1 under the Convergence Contract, using the latest such review's `commit_id` as the last reviewed commit. <!-- CCR-13 -->
4. WHEN the PR has no such review THEN the skill SHALL run round 1. <!-- CCR-14 -->
5. IF GitHub rejects a review submission whose event is `APPROVE` or `REQUEST_CHANGES` THEN `post_review.py` SHALL retry once with event `COMMENT` and the footer `Intended verdict: <VERDICT>. Posted as a comment because GitHub rejected the <VERDICT> event for this repository.` <!-- CCR-15 -->
6. `post_review.py` SHALL target the PR given by `--pr <number>` and the repository given by `--repo <owner/repo>`, without reading the checked-out branch. <!-- CCR-16 -->
7. IF a precondition fails (`gh` unauthenticated, PR not found, gate non-zero, a `COMMENT` submission rejected, the retry rejected) THEN the CI skill SHALL stop and `post_review.py` SHALL exit non-zero with the reason in the job log, never asking for human input. <!-- CCR-17 -->
8. The CI skill SHALL keep the-judge's review passes, verification pass, `review_gate.py` rules, reference guides and Convergence Contract unchanged, except the script paths (absolute under `~/.claude/skills/the-judge/scripts/`) and the round cap replaced by CCR-29. <!-- CCR-18 -->
9. WHEN the computed round is 4 or higher THEN the skill SHALL post a review containing only the Resolution table and new 🔴 findings. <!-- CCR-29 -->

**Independent Test**: `bash tests/run.sh` runs `post_review.py` against a fake `gh` on `PATH` and asserts the calls made and the payload sent.

---

### P2: Runs that must not review

**User Story**: As the owner, I want drafts, forks and Dependabot PRs skipped and stale runs cancelled so that the Claude limits are spent only on reviews that matter.

**Why P2**: Saves Pro-plan limits; the MVP works without it.

**Acceptance Criteria**:

1. WHILE a PR is a draft the central workflow SHALL skip the review job. <!-- CCR-19 -->
2. IF the PR head repository differs from the base repository THEN the central workflow SHALL skip the review job. <!-- CCR-20 -->
3. IF the PR author is `dependabot[bot]` THEN the central workflow SHALL skip the review job. <!-- CCR-21 -->
4. WHEN a new run starts for the same repository and PR while a previous run is in progress THEN the system SHALL cancel the previous run. <!-- CCR-22 -->

**Independent Test**: `actionlint` passes and a test reads the job `if:` and `concurrency:` keys from the YAML and asserts the conditions above.

---

### P2: Central repo access

**User Story**: As the owner, I want any of my repositories, public or private, to call the central workflow so that adopting needs one secret.

**Why P2**: Visibility decides which repos can adopt; public lets both public and private repos call the workflow.

**Acceptance Criteria**:

1. The central workflow SHALL check out `Ronnasayd/claude-pr-review` at ref `v1` into `_ci/` with the workflow's default token and `persist-credentials: false`. <!-- CCR-23 -->
2. The central repo SHALL hold no secret and SHALL contain no workflow triggered by its own PRs that uses `CLAUDE_TOKENS`. <!-- CCR-24 -->
3. The central repo `Ronnasayd/claude-pr-review` SHALL be public. <!-- CCR-25 -->

**Independent Test**: `gh api repos/Ronnasayd/claude-pr-review --jq .visibility` prints `public` and `gh secret list -R Ronnasayd/claude-pr-review` prints nothing.

---

### P3: Setup and maintenance guide

**User Story**: As the owner, I want a README with the one-time setup and maintenance steps so that adding a repo or renewing a token needs no rediscovery.

**Why P3**: Documentation; the workflow runs without it.

**Acceptance Criteria**:

1. The README SHALL list the one-time setup: `claude setup-token` per account, `CLAUDE_TOKENS` per caller repo, the caller job's `permissions:` block (needed because new repos default to a read-only `GITHUB_TOKEN`), "Allow GitHub Actions to create and approve pull requests" per caller repo, and the `v1` tag. <!-- CCR-26 -->
2. The README SHALL describe the skill re-sync procedure from `aipp` and list every way the CI skill diverges from `aipp` the-judge. <!-- CCR-27 -->
3. The README SHALL state the one-year token expiry, the terms-of-use caveat, the unrestricted-`Bash` exposure, that no project dependencies are installed before the review, and that a review uses far more of the plan limits than a one-shot prompt. <!-- CCR-28 -->

**Independent Test**: A test greps the README for each listed item.

---

## Edge Cases

- IF `CLAUDE_TOKENS` is `tok1;;tok2;` THEN the picker SHALL choose only between `tok1` and `tok2`. <!-- covered by CCR-06 -->
- IF the picked token is rate-limited THEN the job SHALL fail with the action's error and a re-run SHALL pick again. <!-- plan decision, no code -->
- IF a review anchor line is not in the diff THEN `post_review.py` SHALL exit non-zero naming the anchors sent. <!-- inherited from aipp, kept under CCR-17 -->
- WHEN the PR author equals `JUDGE_BOT_LOGIN` THEN `post_review.py` SHALL post as `COMMENT` with the inherited own-PR footer. <!-- own-PR fallback, kept under CCR-18 -->
- IF a re-run happens after a review was already posted THEN the skill SHALL run as round N+1. <!-- covered by CCR-13 -->

---

## Requirement Traceability

| Requirement ID | Story                                | Phase | Status   |
| -------------- | ------------------------------------ | ----- | -------- |
| CCR-01         | P1: Review posted on every PR update | Tasks | In Tasks |
| CCR-02         | P1: Review posted on every PR update | Tasks | In Tasks |
| CCR-03         | P1: Review posted on every PR update | Tasks | In Tasks |
| CCR-04         | P1: Review posted on every PR update | Tasks | In Tasks |
| CCR-05         | P1: Review posted on every PR update | Tasks | In Tasks |
| CCR-06         | P1: Random token selection           | Tasks | In Tasks |
| CCR-07         | P1: Random token selection           | Tasks | In Tasks |
| CCR-08         | P1: Random token selection           | Tasks | In Tasks |
| CCR-09         | P1: Random token selection           | Tasks | In Tasks |
| CCR-10         | P1: Random token selection           | Tasks | In Tasks |
| CCR-11         | P1: CI-adapted the-judge             | Tasks | In Tasks |
| CCR-12         | P1: CI-adapted the-judge             | Tasks | In Tasks |
| CCR-13         | P1: CI-adapted the-judge             | Tasks | In Tasks |
| CCR-14         | P1: CI-adapted the-judge             | Tasks | In Tasks |
| CCR-15         | P1: CI-adapted the-judge             | Tasks | In Tasks |
| CCR-16         | P1: CI-adapted the-judge             | Tasks | In Tasks |
| CCR-17         | P1: CI-adapted the-judge             | Tasks | In Tasks |
| CCR-18         | P1: CI-adapted the-judge             | Tasks | In Tasks |
| CCR-29         | P1: CI-adapted the-judge             | Tasks | In Tasks |
| CCR-19         | P2: Runs that must not review        | Tasks | In Tasks |
| CCR-20         | P2: Runs that must not review        | Tasks | In Tasks |
| CCR-21         | P2: Runs that must not review        | Tasks | In Tasks |
| CCR-22         | P2: Runs that must not review        | Tasks | In Tasks |
| CCR-23         | P2: Central repo access              | Tasks | In Tasks |
| CCR-24         | P2: Central repo access              | Tasks | In Tasks |
| CCR-25         | P2: Central repo access              | Tasks | In Tasks |
| CCR-26         | P3: Setup and maintenance guide      | Tasks | In Tasks |
| CCR-27         | P3: Setup and maintenance guide      | Tasks | In Tasks |
| CCR-28         | P3: Setup and maintenance guide      | Tasks | In Tasks |

**Coverage:** 29 total, 29 mapped to tasks (T1-T11), 0 unmapped

---

## Sources

- `docs/adr/ADR-001-public-central-review-repo.md`, `docs/adr/ADR-002-ci-adapted-the-judge-copy.md` - recorded decisions behind CCR-24/25 and CCR-11..18, 29
- `docs/plans/ci-claude-code-review.md` - the proposal: central reusable workflow, the-judge as review logic, random token from `CLAUDE_TOKENS`, caveats
- `aipp/skills/tech-leads-club/the-judge` (v1.4.0) - base for the CI skill; `scripts/post_review.py:45-47` calls `gh api user --jq .login` and exits on failure; SKILL.md Step 6 runs `python3 scripts/review_gate.py` relative to cwd
- https://github.com/anthropics/claude-code-action/blob/main/docs/security.md - on PRs the action restores `.claude/` from the base branch and deletes paths absent there
- https://github.com/anthropics/claude-code-action/blob/main/src/github/token.ts - `github_token` input overrides the OIDC → Claude GitHub App exchange
- claude-code-action@v1 `src/entrypoints/run.ts` (sets `GH_TOKEN`), `base-action/src/parse-sdk-options.ts` (passes env; default `settingSources`), `src/modes/agent/index.ts` (no extra tools) - read by the verifier at tag `v1`
- https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations - secrets reach a called workflow only through the caller's `secrets:` block; the called workflow can only downgrade `GITHUB_TOKEN` permissions; re-runs reuse the reusable workflow's first-attempt SHA
- https://docs.github.com/en/rest/actions/permissions#get-the-level-of-access-for-workflows-outside-of-the-repository - `user` access level allows sharing across user-owned private repositories only
- https://github.blog/changelog/2022-05-03-github-actions-prevent-github-actions-from-creating-and-approving-pull-requests/ - the setting that blocks `GITHUB_TOKEN` approvals

---

## Success Criteria

- [ ] Smoke PR on a test repo: run green, one review by `github-actions[bot]`; run and review URLs recorded in `tasks.md` `## Handoff`.
- [ ] Second commit pushed to the smoke PR: run green, second review is round 2 (has a Resolution section).
- [ ] `bash tests/run.sh` and `actionlint` exit 0.
