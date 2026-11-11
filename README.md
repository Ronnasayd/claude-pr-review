# claude-pr-review

Central, reusable GitHub Actions workflow that reviews every non-draft pull request with the `the-judge` skill and posts one consolidated review, authored by `github-actions[bot]`, with inline comments.

Each repository to review holds one small caller file. The review logic, the workflow and the skill live here. Changing them and moving the `v1` tag changes the review for every caller, with no edit in the callers.

## How it works

1. The caller workflow (`caller/claude-review.yml`, copied to `.github/workflows/claude-review.yml` in each repository) runs on `opened`, `synchronize`, `reopened` and `ready_for_review`, and calls `.github/workflows/claude-review.yml@v1` from this repository.
2. The central job skips drafts, fork PRs and `dependabot[bot]`, and cancels a running review of the same PR when a newer push arrives.
3. `scripts/pick-token.sh` picks one token at random from `CLAUDE_TOKENS` and passes it to the Claude step only, through a masked step output.
4. The skill is copied to `~/.claude/skills/the-judge`, then `anthropics/claude-code-action@v1` runs `/the-judge` on the PR and posts the review in Portuguese.

## Quick setup

Run from the root of a clone of the repository to review, with `gh` logged in as a user with admin rights on it:

```bash
# 1. Download the caller workflow, pinned to the same tag it calls.
mkdir -p .github/workflows
gh api 'repos/Ronnasayd/claude-pr-review/contents/caller/claude-review.yml?ref=v1' \
  -H 'Accept: application/vnd.github.raw' > .github/workflows/claude-review.yml

# 2. Store the Claude tokens (from `claude setup-token`). gh prompts for the value,
#    so the tokens stay out of the shell history. Format: tok1;tok2;tok3
gh secret set CLAUDE_TOKENS

# 3. Let the bot post APPROVE / REQUEST_CHANGES. Fails with 409 when the organization
#    forbids it; then enable it in the organization settings first.
gh api -X PUT 'repos/{owner}/{repo}/actions/permissions/workflow' \
  -F can_approve_pull_request_reviews=true

# 4. Commit and push the workflow.
git add .github/workflows/claude-review.yml
git commit -m "ci: add Claude PR review"
git push
```

The table below explains each step.

## One-time setup

| Where                                                               | What                                                                                                                                                                                                                                                                                        |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Each Claude account                                                 | Run `claude setup-token` and keep the token.                                                                                                                                                                                                                                                |
| Each caller repository → Settings → Secrets and variables → Actions | Create the repository secret `CLAUDE_TOKENS` holding every token separated by `;`, for example `tok1;tok2;tok3`. <!-- # pragma: allowlist secret -->                                                                                                                                        |
| Each caller repository                                              | Copy `caller/claude-review.yml` to `.github/workflows/claude-review.yml`. Keep its job `permissions:` block (`contents: read`, `pull-requests: write`): new repositories default to a read-only `GITHUB_TOKEN`, and a called workflow can only downgrade the permissions the caller grants. |
| Each caller repository → Settings → Actions → General               | Enable "Allow GitHub Actions to create and approve pull requests". Without it an APPROVE or REQUEST_CHANGES verdict is posted as a COMMENT with the intended verdict in a footer.                                                                                                           |
| This repository                                                     | Keep it public and without secrets. Create the tag callers use: `git tag v1 && git push origin v1`. The workflow checks itself out at ref `v1`, so keep that ref equal to the tag.                                                                                                          |

## Re-sync the skill from aipp

`skills/the-judge` is a copy of `aipp/skills/tech-leads-club/the-judge` (v1.4.0) adapted for CI. It does not follow `aipp` on its own. To pick up upstream changes:

1. Save the CI copy, then copy the upstream skill over it: `cp -r ../aipp/skills/tech-leads-club/the-judge skills/`.
2. Re-apply every divergence listed below to `SKILL.md` and `scripts/post_review.py`.
3. Run `bash tests/run.sh`; the skill tests compare the unchanged files and sections with `aipp` (override the source path with `AIPP_JUDGE`).
4. Commit, then move the tag: `git tag -f v1 && git push -f origin v1` (or release `v2` and update the callers).

## Divergences from aipp the-judge

- `SKILL.md` Step 0 takes the PR number and repository from the prompt and passes `--repo <owner>/<repo>` to every `gh pr` call; it never reads the checked-out branch.
- Neither the skill nor `post_review.py` calls `gh api user` (it fails with a bot token). The own login is `JUDGE_BOT_LOGIN`, default `github-actions[bot]`.
- Previous rounds are the reviews by that login whose body contains `<!-- the-judge -->`; round = count + 1, and the latest one's `commit_id` is the last reviewed commit.
- `post_review.py` appends `<!-- the-judge -->` to every review body.
- `post_review.py` requires `--pr <number> --repo <owner>/<repo>`.
- A rejected APPROVE or REQUEST_CHANGES is retried once as COMMENT with the footer `Intended verdict: <VERDICT>. Posted as a comment because GitHub rejected the <VERDICT> event for this repository.`; a rejected COMMENT or a rejected retry exits 1.
- Scripts are called by absolute path, `python3 ~/.claude/skills/the-judge/scripts/<name>.py`, because the working directory is the caller's checkout.
- Convergence Contract: in CI every push starts a round, so round 4 and later post only the Resolution table and new 🔴 findings, instead of never running a fourth round.
- Troubleshooting and Step 0 never ask the user to act: on a failed precondition the skill must stop and report the reason in the output, and the job log carries it.

## Caveats

- **Bash is unrestricted, and it has to be.** the-judge runs the repository's own lint and tests, which runs PR code on the runner. A PR author with push access could read the Claude token and `GH_TOKEN` from that process. Fork PRs get no secrets, so the exposure is limited to people who can already push branches.
- **No dependencies installed.** The workflow does not run `npm ci` or `uv sync` before the review, so checks that need them fail and the skill reports that in "Checks run".
- **Heavier than a plain prompt.** Research, six review passes and verification use far more of the plan limits than a one-shot prompt. `--max-turns 60` caps one run.
- **Tokens expire after one year.** Keep a list of renewal dates.
- **No fallback on the random pick.** A rate-limited or expired token fails the job; re-running picks again.
- **Terms of use.** Confirm with Anthropic that subscription tokens from several accounts may be used in CI. The official option for teams is `anthropic_api_key`, which the same action accepts.

## Tests

```bash
bash tests/run.sh
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12 .github/workflows/claude-review.yml caller/claude-review.yml
```

`tests/smoke.sh <owner/repo> <pr>` checks a live run on a test repository.
