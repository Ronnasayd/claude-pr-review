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

# invariant: all three skip conditions must hold together; asserting substrings would accept `||`.
JOB_IF="!github.event.pull_request.draft && github.event.pull_request.head.repo.full_name == github.repository && github.event.pull_request.user.login != 'dependabot[bot]'"

job_if_exact() { [ "$(wq '.jobs.review.if')" = "\${{ $JOB_IF }}" ]; }

wf_skips_drafts() {
  job_if_exact
  case $JOB_IF in '!github.event.pull_request.draft && '*) ;; *) false ;; esac
}

wf_skips_forks() {
  job_if_exact
  case $JOB_IF in *' && github.event.pull_request.head.repo.full_name == github.repository && '*) ;; *) false ;; esac
}

wf_skips_dependabot() {
  job_if_exact
  case $JOB_IF in *" && github.event.pull_request.user.login != 'dependabot[bot]'") ;; *) false ;; esac
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

C=$ROOT/caller/claude-review.yml
cq() { yq -r "$1" "$C"; }

caller_triggers() {
  [ "$(cq '.on | keys | join(",")')" = pull_request ]
  [ "$(cq '.on.pull_request.types | join(",")')" = "opened,synchronize,reopened,ready_for_review" ]
}

caller_one_job() {
  [ "$(cq '.jobs | keys | join(",")')" = review ]
  [ "$(cq '.jobs.review | keys | join(",")')" = "permissions,uses,secrets" ]
}

caller_uses_central() {
  [ "$(cq '.jobs.review.uses')" = Ronnasayd/claude-pr-review/.github/workflows/claude-review.yml@v1 ]
  [ "$(cq '.jobs.review.permissions | to_entries | map(.key + "=" + .value) | join(",")')" = "contents=read,pull-requests=write" ]
  [ "$(cq '.jobs.review.secrets | to_entries | map(.key + "=" + .value) | join(",")')" = 'CLAUDE_TOKENS=${{ secrets.CLAUDE_TOKENS }}' ]
}

caller_no_secrets_inherit() {
  [ -f "$C" ]
  ! grep -q 'inherit' "$C"
}

central_never_reviews_itself() {
  local f
  [ -f "$C" ]
  [ ! -e "$ROOT/.github/workflows/$(basename "$C")" ] || [ "$(yq -r '.on | keys | join(",")' "$ROOT/.github/workflows/$(basename "$C")")" = workflow_call ]
  for f in "$ROOT"/.github/workflows/*.yml "$ROOT"/.github/workflows/*.yaml; do
    [ -e "$f" ] || continue
    [ "$(yq -r '.on | has("pull_request") or has("pull_request_target")' "$f")" = false ]
    if grep -q 'CLAUDE_TOKENS' "$f"; then [ "$(yq -r '.on | keys | join(",")' "$f")" = workflow_call ]; fi
  done
}

t "caller: triggers on open, sync, reopen and ready for review" caller_triggers
t "caller: one job" caller_one_job
t "caller: uses central workflow at v1 with permissions and secret" caller_uses_central
t "caller: no secrets inherit" caller_no_secrets_inherit
t "caller: central repo never reviews itself" central_never_reviews_itself
