#!/usr/bin/env bash
# Sets CLAUDE_TOKENS on each repo, lets Actions approve PRs, and opens a PR installing the review workflow where it is missing.
# hazard: writing under .github/workflows via the API needs a gh token with the `workflow` scope.
set -uo pipefail
repos=(
  Ronnasayd/mcp-manager
  Ronnasayd/custom-mcps
  Ronnasayd/keycloak-mcp-server
  Ronnasayd/aipp
  Ronnasayd/dotfiles
  Ronnasayd/claude-warmup
  Ronnasayd/vrep-mcp
  Ronnasayd/ulauncher-css-unit-converter
)
wf=.github/workflows/claude-review.yml
branch=add-claude-review
title="ci: add Claude PR review workflow"

content=$(gh api 'repos/Ronnasayd/claude-pr-review/contents/caller/claude-review.yml?ref=v1' \
  -H 'Accept: application/vnd.github.raw' | base64 -w0) || exit 1

install_workflow() {
  local repo=$1 base sha
  # why: an existing branch means an earlier run already opened (or is opening) the install PR.
  if gh api "repos/$repo/branches/$branch" --silent 2>/dev/null; then
    echo "$repo: branch $branch exists, skipping"
    return 0
  fi
  base=$(gh api "repos/$repo" --jq .default_branch) || return
  sha=$(gh api "repos/$repo/git/ref/heads/$base" --jq .object.sha) || return
  gh api "repos/$repo/git/refs" -f ref="refs/heads/$branch" -f sha="$sha" --silent || return
  gh api -X PUT "repos/$repo/contents/$wf" -f message="$title" -f content="$content" -f branch="$branch" --silent || return
  gh pr create --repo "$repo" --base "$base" --head "$branch" --title "$title" \
    --body "Installs the Claude PR review caller workflow from Ronnasayd/claude-pr-review@v1."
}

for repo in "${repos[@]}"; do
  gh secret set CLAUDE_TOKENS --body "$CLAUDE_TOKENS" --repo "$repo"
  # why: without it APPROVE / REQUEST_CHANGES fall back to COMMENT; a 409 means the org forbids it.
  gh api -X PUT "repos/$repo/actions/permissions/workflow" -F can_approve_pull_request_reviews=true --silent \
    || echo "$repo: could not set can_approve_pull_request_reviews (409: enable it in the org settings)" >&2
  gh api "repos/$repo/contents/$wf" --silent 2>/dev/null && continue
  install_workflow "$repo" || echo "$repo: workflow install failed" >&2
done
