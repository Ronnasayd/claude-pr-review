# ci-claude-code-review proofs

**HEAD**: 286e1d9
**Tree**: clean
**Shell**: /bin/sh
**Result**: 35 pass, 0 fail

| Check | Proof                                                                                                            | Result |
| ----- | ---------------------------------------------------------------------------------------------------------------- | ------ |
| C1    | `bash tests/smoke.sh Ronnasayd/claude-pr-review-smoke 1`                                                         | pass   |
| C2    | `run unit / ok - caller: uses central workflow at v1 with permissions and secret`                                | pass   |
| C3    | `run unit / ok - workflow: installs skill to home and removes _ci before claude`                                 | pass   |
| C4    | `run unit / ok - workflow: claude prompt and args`                                                               | pass   |
| C5    | `run unit / ok - workflow: permissions exactly contents read and pull-requests write`                            | pass   |
| C6    | `run unit / ok - pick_token: trims whitespace and skips empty entries`                                           | pass   |
| C7    | `run unit / ok - pick_token: every token reachable`                                                              | pass   |
| C8    | `run unit / ok - pick_token: masks token and logs index only`                                                    | pass   |
| C9    | `run unit / ok - pick_token: empty input fails with message`                                                     | pass   |
| C10   | `run unit / ok - workflow: token only via step output`                                                           | pass   |
| C11   | `run unit / ok - post_review: no gh api user and default bot login`                                              | pass   |
| C12   | `run unit / ok - post_review: body ends with marker`                                                             | pass   |
| C13   | `run unit / ok - skill: round from marked bot reviews`                                                           | pass   |
| C14   | `run unit / ok - skill: round 1 when no marked review`                                                           | pass   |
| C15   | `run unit / ok - post_review: rejected approve retries as comment`                                               | pass   |
| C16   | `run unit / ok - post_review: requires and uses pr and repo`                                                     | pass   |
| C17   | `run unit / ok - skill: no human ask in skill`                                                                   | pass   |
| C18   | `run unit / ok - post_review: rejected comment exits without retry`                                              | pass   |
| C19   | `run unit / ok - post_review: rejected retry exits 1`                                                            | pass   |
| C20   | `run unit / ok - post_review: gate failure posts nothing`                                                        | pass   |
| C21   | `run unit / ok - skill: unchanged sections equal aipp`                                                           | pass   |
| C22   | `run unit / ok - post_review: own pr posts as comment`                                                           | pass   |
| C23   | `run unit / ok - skill: round 4 and later resolution only`                                                       | pass   |
| C24   | `run unit / ok - workflow: skips drafts`                                                                         | pass   |
| C25   | `run unit / ok - workflow: skips forks`                                                                          | pass   |
| C26   | `run unit / ok - workflow: skips dependabot`                                                                     | pass   |
| C27   | `run unit / ok - workflow: concurrency per repo and pr cancels in progress`                                      | pass   |
| C28   | `run unit / ok - workflow: central checkout at v1 without persisted credentials`                                 | pass   |
| C29   | `run unit / ok - caller: central repo never reviews itself`                                                      | pass   |
| C30   | `test "$(gh api repos/Ronnasayd/claude-pr-review --jq .visibility)" = public && test -z "$(gh secret list -R Ro` | pass   |
| C31   | `run unit / ok - readme: one-time setup`                                                                         | pass   |
| C32   | `run unit / ok - readme: re-sync and divergences`                                                                | pass   |
| C33   | `run unit / ok - readme: caveats`                                                                                | pass   |
| Build | `docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12 .github/workflows/claude-review.yml caller/cl` | pass   |
| Build | `bash tests/run.sh`                                                                                              | pass   |

## Output

`Run unit` - exit 0

```
ok - workflow: skips dependabot
ok - workflow: concurrency per repo and pr cancels in progress
ok - workflow: pr checkout with full history
ok - workflow: central checkout at v1 without persisted credentials
ok - workflow: picker step reads CLAUDE_TOKENS
ok - workflow: token only via step output
ok - workflow: installs skill to home and removes _ci before claude
ok - workflow: claude prompt and args
ok - workflow: bot login env on claude step
ok - caller: triggers on open, sync, reopen and ready for review
ok - caller: one job
ok - caller: uses central workflow at v1 with permissions and secret
ok - caller: no secrets inherit
ok - caller: central repo never reviews itself
# passed 48, failed 0
```

`bash tests/smoke.sh Ronnasayd/claude-pr-review-smoke 1` - exit 0

```
run: success https://github.com/Ronnasayd/claude-pr-review-smoke/actions/runs/43115716567
review: https://github.com/Ronnasayd/claude-pr-review-smoke/pull/1#pullrequestreview-5866364859
review: https://github.com/Ronnasayd/claude-pr-review-smoke/pull/1#pullrequestreview-5866398646
PASS: smoke Ronnasayd/claude-pr-review-smoke#1
```

`test "$(gh api repos/Ronnasayd/claude-pr-review --jq .visibility)" = public && test -z "$(gh secret list -R Ro` - exit 0

```
(no output)
```
