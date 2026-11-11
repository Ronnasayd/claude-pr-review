#!/usr/bin/env bash
# Live check of a review run on a test repo (CCR-01, CCR-13). Network; not run by tests/run.sh.
# Usage: bash tests/smoke.sh <owner/repo> <pr>
# Passes when the latest review run on the PR succeeded and the PR has exactly two reviews by
# github-actions[bot] carrying <!-- the-judge -->, the second with a Resolution section.
set -euo pipefail
repo=${1:?usage: smoke.sh <owner/repo> <pr>}
pr=${2:?usage: smoke.sh <owner/repo> <pr>}

head_sha=$(gh pr view "$pr" --repo "$repo" --json headRefOid --jq .headRefOid)
run=$(gh run list --repo "$repo" --workflow claude-review.yml --commit "$head_sha" --limit 1 \
  --json conclusion,url --jq '.[0] | "\(.conclusion) \(.url)"')
echo "run: $run"
[ "${run%% *}" = success ] || { echo "FAIL: latest run on $head_sha is not success"; exit 1; }

reviews=$(gh api "repos/$repo/pulls/$pr/reviews?per_page=100" --jq \
  '[.[] | select(.user.login == "github-actions[bot]" and (.body | contains("<!-- the-judge -->")))]')
count=$(jq length <<<"$reviews")
jq -r '.[] | "review: \(.html_url)"' <<<"$reviews"
[ "$count" -eq 2 ] || { echo "FAIL: expected 2 marked reviews, got $count"; exit 1; }
# why: the review is written in Portuguese, so the heading may read "Resolução"; the gate matches "resolu" too.
jq -r '.[1].body' <<<"$reviews" | grep -qi 'resolu' || { echo "FAIL: second review has no Resolution section"; exit 1; }
echo "PASS: smoke $repo#$pr"
