# Tests for scripts/set-claude-multi-repos.sh. Sourced by tests/run.sh.

# multi <missing-repo> [branch-exists]: runs the script against a stub gh where only
# <missing-repo> lacks the workflow; argv of every gh call lands in $WORK/multi.log.
multi() {
  mkdir -p "$WORK/multibin"
  : >"$WORK/multi.log"
  cat >"$WORK/multibin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$MULTI_LOG"
case "$*" in
  "api repos/Ronnasayd/claude-pr-review/contents/caller/claude-review.yml?ref=v1"*) echo "name: x" ;;
  "api repos/$MISSING/contents/.github/workflows/claude-review.yml"*) exit 1 ;;
  "api repos/$MISSING/branches/"*) [ -n "$BRANCH_EXISTS" ] || exit 1 ;;
  "api repos/$MISSING --jq .default_branch") echo main ;;
  "api repos/$MISSING/git/ref/heads/main --jq .object.sha") echo abc123 ;;
esac
EOF
  chmod +x "$WORK/multibin/gh"
  PATH="$WORK/multibin:$PATH" MULTI_LOG="$WORK/multi.log" MISSING="$1" BRANCH_EXISTS="${2:-}" \
    CLAUDE_TOKENS=tok bash "$ROOT/scripts/set-claude-multi-repos.sh"
}

multi_opens_pr_only_where_missing() {
  multi Ronnasayd/dotfiles
  [ "$(grep -c '^secret set CLAUDE_TOKENS --body tok --repo ' "$WORK/multi.log")" -eq 8 ]
  grep -qx 'api repos/Ronnasayd/dotfiles/git/refs -f ref=refs/heads/add-claude-review -f sha=abc123 --silent' "$WORK/multi.log"
  [ "$(grep -c -- '-X PUT' "$WORK/multi.log")" -eq 1 ]
  grep -q -- "-X PUT repos/Ronnasayd/dotfiles/contents/.github/workflows/claude-review.yml .*-f content=$(printf 'name: x\n' | base64 -w0) -f branch=add-claude-review" "$WORK/multi.log"
  [ "$(grep -c '^pr create' "$WORK/multi.log")" -eq 1 ]
  grep -q '^pr create --repo Ronnasayd/dotfiles --base main --head add-claude-review ' "$WORK/multi.log"
}

multi_skips_when_branch_exists() {
  multi Ronnasayd/dotfiles yes
  ! grep -q -- '-X PUT' "$WORK/multi.log"
  ! grep -q '^pr create' "$WORK/multi.log"
}

t "set_multi_repos: opens install PR only where workflow is missing" multi_opens_pr_only_where_missing
t "set_multi_repos: skips repo whose install branch already exists" multi_skips_when_branch_exists
