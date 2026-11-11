# Proposal: Claude Code Review via centralized CI/CD

## Goal

Every PR that is opened or updated gets an automatic Claude review, posted as
one consolidated GitHub review with inline comments. The review logic is the
**`the-judge` skill**, not an inline prompt. Workflow and skill live in **one
repository**. Every other repo just calls it.

## How it works

```
repo-a ─┐
repo-b ─┼──► ci-templates (reusable workflow + skills/the-judge)
repo-c ─┘          │
                   ├─ picks 1 random token from CLAUDE_TOKENS ("tok1;tok2;tok3")
                   ├─ copies skills/the-judge → .claude/skills/the-judge
                   └─ runs "/the-judge" ──► one GitHub review with inline comments
```

1. **Central repo `ci-templates`**: holds the reusable workflow and a copy of
   `the-judge` (from `aipp/skills/tech-leads-club/the-judge`). Changing either
   one changes the review for every repo.
2. **Each repo**: a ~10-line file that points to the central workflow.
3. **Skill delivery**: the workflow checks out `ci-templates` into `_ci/` and
   copies the skill into `.claude/skills/`, where Claude Code loads project
   skills. The prompt is just the skill invocation.
4. **Tokens**: one organization secret, `CLAUDE_TOKENS`, holding several keys
   separated by `;`. Each run **picks one at random**, which spreads usage
   across accounts without storing "which key ran last".
5. **One-year token**: each account generates its own with `claude setup-token`.

## What the-judge does in CI

The skill only needs `gh`, `python3` and web access, all available on
`ubuntu-latest`:

- Reads the PR with `gh pr view` / `gh pr diff`.
- Runs the repo's own lint/typecheck/tests and `scripts/scan_bypasses.py`.
- Checks official docs for every external library or API the diff touches.
- Runs six review passes, then a verification pass that drops anything without
  evidence.
- Passes every comment through `scripts/review_gate.py`, then posts one review
  (APPROVE / COMMENT / REQUEST_CHANGES) with `scripts/post_review.py`.
- On later pushes it only checks earlier findings and new blockers (round 2+),
  so reviews converge instead of growing.

## Central repo layout

```
ci-templates/
├── .github/workflows/claude-review.yml
└── skills/the-judge/          # copied from aipp, keep in sync
    ├── SKILL.md
    ├── references/
    └── scripts/
```

`ci-templates/.github/workflows/claude-review.yml`

```yaml
name: Claude Review

on:
  workflow_call:
    secrets:
      CLAUDE_TOKENS:
        required: true
      CI_TEMPLATES_TOKEN:
        required: false

jobs:
  review:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
      id-token: write
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0

      - name: Fetch the-judge
        uses: actions/checkout@v6
        with:
          repository: <org>/ci-templates
          ref: v1 # keep equal to the tag callers use
          path: _ci
          token: ${{ secrets.CI_TEMPLATES_TOKEN || github.token }}

      - name: Install skill
        run: |
          mkdir -p .claude/skills
          cp -r _ci/skills/the-judge .claude/skills/
          rm -rf _ci

      - name: Pick token
        id: pick
        env:
          TOKENS: ${{ secrets.CLAUDE_TOKENS }}
        run: |
          IFS=';' read -ra list <<< "$TOKENS"
          token="${list[RANDOM % ${#list[@]}]}"
          echo "::add-mask::$token"
          echo "token=$token" >> "$GITHUB_OUTPUT"

      - uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ steps.pick.outputs.token }}
          prompt: |
            /the-judge Review PR #${{ github.event.pull_request.number }} in ${{ github.repository }}. Write the review in Portuguese.
          claude_args: |
            --max-turns 60
            --allowedTools "Skill,Read,Glob,Grep,WebSearch,WebFetch,Bash"
```

The token goes through a step output, not `$GITHUB_ENV`, so it reaches only
the Claude step instead of every later step in the job.

## File in each repo

`.github/workflows/claude-review.yml`

```yaml
name: Claude Review

on:
  pull_request:
    types: [opened, synchronize]

jobs:
  review:
    uses: <org>/ci-templates/.github/workflows/claude-review.yml@v1
    secrets: inherit
```

## One-time setup

| Where                                          | What                                                                                                                                                 |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Each Claude account                            | Run `claude setup-token` and keep the token                                                                                                          |
| Org → Settings → Secrets → Actions             | Create `CLAUDE_TOKENS` = `tok1;tok2;tok3` and grant it to the target repos                                                                           |
| Org secret (only if `ci-templates` is private) | `CI_TEMPLATES_TOKEN`: fine-grained PAT or GitHub App token with read access to `ci-templates`. The default `GITHUB_TOKEN` only sees the calling repo |
| `ci-templates` → Settings → Actions → Access   | If the repo is private, allow access from the organization's repos                                                                                   |
| `ci-templates`                                 | Copy `the-judge` into `skills/`, then create the `v1` tag                                                                                            |

## Caveats

- **Bash is unrestricted, and it has to be.** the-judge runs the repo's own
  lint and tests, which means running PR code on the runner. A malicious PR
  author inside the org could try to read the Claude token from that process.
  Fork PRs never get secrets, so the exposure is limited to people who can
  already push branches. If that is not acceptable, restrict Bash to
  `Bash(gh:*),Bash(python3:*)` and accept that the "Checks run" section will
  be empty.
- **No dependencies installed.** The runner does not run `npm ci` / `uv sync`
  before the review, so repo checks that need them fail, and the skill reports
  that in "Checks run". A setup step per stack can be added later if the
  signal is worth it.
- **Heavier than a plain prompt.** Research, six passes and verification use
  far more of a Pro plan's 5-hour and weekly limits than a one-shot prompt.
  `--max-turns` caps a single run; tune it after a few real PRs.
- **The skill is a copy.** `ci-templates/skills/the-judge` does not update when
  `aipp` does. Re-copy it and move the `v1` tag (or release `v2`) on purpose.
- **Self-review fallback.** If the token's account is also the PR author, the
  skill posts COMMENT instead of APPROVE/REQUEST_CHANGES (GitHub returns 422).
  Here the review is posted with the action's GitHub token, so this mostly
  won't apply, but the footer explains it when it does.
- **No fallback on the random pick:** if the chosen token is rate-limited, the
  job fails. Re-running it fixes this, because the next pick will most likely
  be a different token.
- **Expiry:** tokens expire after one year. Keep a list of renewal dates.
- **Fork PRs:** GitHub does not pass secrets to them, so they get no review.
- **Terms of use:** confirm with Anthropic that subscription tokens from
  several accounts may be used in CI. The official option for teams is
  `anthropic_api_key`, which the same action already accepts.
