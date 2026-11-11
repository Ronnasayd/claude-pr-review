# Static tests for the central workflow (CCR-03..05, 10, 19..23) and caller template (CCR-02, 24).
# Sourced by tests/run.sh. Needs mikefarah yq v4.
W=$ROOT/.github/workflows/claude-review.yml

wq() { yq -r "$1" "$W"; }
step() { wq ".jobs.review.steps[$1]$2"; }
claude_step() { wq '.jobs.review.steps[] | select(.uses == "anthropics/claude-code-action@v1")'"$1"; }
step_index() { wq ".jobs.review.steps | to_entries | .[] | select($1) | .key"; }

wf_only_claude_tokens_secret() {
  [ "$(wq '.on | keys | join(",")')" = workflow_call ]
  [ "$(wq '.on.workflow_call.secrets | keys | join(",")')" = CLAUDE_TOKENS ]
  [ "$(wq '.on.workflow_call.secrets.CLAUDE_TOKENS.required')" = true ]
  [ "$(wq '.on.workflow_call.inputs')" = null ]
  ! grep -q 'CI_TEMPLATES_TOKEN' "$W"
}

wf_permissions_exact() {
  [ "$(wq '.jobs.review.permissions | to_entries | map(.key + "=" + .value) | join(",")')" = "contents=read,pull-requests=write" ]
  [ "$(wq '.permissions')" = null ]
  [ "$(wq '.jobs | keys | join(",")')" = review ]
}

wf_no_id_token() {
  [ -f "$W" ]
  ! grep -q 'id-token' "$W"
}

wf_skips_drafts() {
  wq '.jobs.review.if' | grep -qF '!github.event.pull_request.draft'
}

wf_skips_forks() {
  wq '.jobs.review.if' | grep -qF 'github.event.pull_request.head.repo.full_name == github.repository'
}

wf_skips_dependabot() {
  wq '.jobs.review.if' | grep -qF "github.event.pull_request.user.login != 'dependabot[bot]'"
}

wf_concurrency() {
  [ "$(wq '.jobs.review.concurrency.group')" = 'claude-review-${{ github.repository }}-${{ github.event.pull_request.number }}' ]
  [ "$(wq '.jobs.review.concurrency.cancel-in-progress')" = true ]
  [ "$(wq '.concurrency')" = null ]
}

wf_pr_checkout() {
  [ "$(step 0 .uses)" = actions/checkout@v7 ]
  [ "$(step 0 '.with.fetch-depth')" = 0 ]
}

wf_central_checkout() {
  [ "$(step 1 .uses)" = actions/checkout@v7 ]
  [ "$(step 1 '.with | to_entries | map(.key + "=" + (.value | tostring)) | join(",")')" = \
    "repository=Ronnasayd/claude-pr-review,ref=v1,path=_ci,persist-credentials=false" ]
}

wf_picker_step() {
  [ "$(step 2 .id)" = pick ]
  [ "$(step 2 .run)" = 'bash _ci/scripts/pick-token.sh' ]
  [ "$(step 2 '.env | to_entries | map(.key + "=" + .value) | join(",")')" = 'TOKENS=${{ secrets.CLAUDE_TOKENS }}' ]
}

wf_token_via_output() {
  [ "$(claude_step .with.claude_code_oauth_token)" = '${{ steps.pick.outputs.token }}' ]
  [ "$(grep -c 'secrets.CLAUDE_TOKENS' "$W")" -eq 1 ]
  ! grep -Eq '>>? *"?\$\{?GITHUB_ENV' "$W" "$ROOT/scripts/pick-token.sh"
  ! grep -q 'GITHUB_ENV' "$W"
}

wf_installs_skill() {
  local install claude
  install=$(step_index '.value.name == "Install skill"')
  claude=$(step_index '.value.uses == "anthropics/claude-code-action@v1"')
  [ "$install" -eq 3 ]
  [ "$claude" -eq 4 ]
  [ "$(step 3 .run)" = 'mkdir -p ~/.claude/skills && cp -r _ci/skills/the-judge ~/.claude/skills/ && rm -rf _ci' ]
  [ "$(wq '.jobs.review.steps | length')" -eq 5 ]
}

wf_claude_prompt_and_args() {
  [ "$(claude_step .with.prompt)" = '/the-judge Review PR #${{ github.event.pull_request.number }} in ${{ github.repository }}. Write the review in Portuguese.' ]
  [ "$(claude_step .with.github_token)" = '${{ github.token }}' ]
  [ "$(claude_step .with.claude_args | tr -s ' \n' '  ' | sed 's/ $//')" = \
    '--max-turns 60 --allowedTools "Skill,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,Bash"' ]
}

wf_bot_login_env() {
  [ "$(claude_step '.env | to_entries | map(.key + "=" + .value) | join(",")')" = 'JUDGE_BOT_LOGIN=github-actions[bot]' ]
}

t "workflow: only CLAUDE_TOKENS secret, required" wf_only_claude_tokens_secret
t "workflow: permissions exactly contents read and pull-requests write" wf_permissions_exact
t "workflow: no id-token permission" wf_no_id_token
t "workflow: skips drafts" wf_skips_drafts
t "workflow: skips forks" wf_skips_forks
t "workflow: skips dependabot" wf_skips_dependabot
t "workflow: concurrency per repo and pr cancels in progress" wf_concurrency
t "workflow: pr checkout with full history" wf_pr_checkout
t "workflow: central checkout at v1 without persisted credentials" wf_central_checkout
t "workflow: picker step reads CLAUDE_TOKENS" wf_picker_step
t "workflow: token only via step output" wf_token_via_output
t "workflow: installs skill to home and removes _ci before claude" wf_installs_skill
t "workflow: claude prompt and args" wf_claude_prompt_and_args
t "workflow: bot login env on claude step" wf_bot_login_env
