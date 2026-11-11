# Tests for skills/the-judge (CCR-11, 13, 14, 17, 18, 29). Sourced by tests/run.sh.
# why: the CI copy must track aipp the-judge v1.4.0; override AIPP_JUDGE when aipp lives elsewhere.
AIPP_JUDGE=${AIPP_JUDGE:-$ROOT/../aipp/skills/tech-leads-club/the-judge}
SKILL=$ROOT/skills/the-judge

skill_verbatim_files() {
  local f
  for f in references/review-standards.md references/comment-voice.md scripts/review_gate.py scripts/scan_bypasses.py; do
    cmp "$AIPP_JUDGE/$f" "$SKILL/$f"
  done
  [ "$(ls "$SKILL/references" | wc -l)" -eq 2 ]
}

t "skill: verbatim files equal aipp" skill_verbatim_files

FOURTH_ROUND_OLD="The Judge never runs a fourth round on the same finding set."
FOURTH_ROUND_NEW="In CI every push starts a round; round 4 and later post only the Resolution table and new 🔴 findings."

# section <file> <start-prefix> <end-prefix>: lines from the start heading up to, not including, the end heading.
section() { awk -v s="$2" -v e="$3" 'index($0, e) == 1 { f = 0 } index($0, s) == 1 { f = 1 } f' "$1"; }

skill_no_gh_api_user() {
  ! grep -q 'gh api user' "$SKILL/SKILL.md"
  grep -qF '$JUDGE_BOT_LOGIN' "$SKILL/SKILL.md"
}

skill_no_human_ask() {
  ! grep -qi 'ask the user' "$SKILL/SKILL.md"
  ! grep -qi 'gh auth login' "$SKILL/SKILL.md"
  grep -qF 'stop and report the reason in the output; the job log carries it' "$SKILL/SKILL.md"
}

# reviews_fixture: two marked bot reviews, one unmarked bot review, one marked review by another user.
reviews_fixture() {
  cat <<'JSON'
[{"id": 1, "submitted_at": "2026-01-01T00:00:00Z", "commit_id": "aaa", "user": {"login": "github-actions[bot]"}, "body": "r1\n\n<!-- the-judge -->"},
 {"id": 2, "submitted_at": "2026-01-02T00:00:00Z", "commit_id": "bbb", "user": {"login": "github-actions[bot]"}, "body": "other action"},
 {"id": 3, "submitted_at": "2026-01-03T00:00:00Z", "commit_id": "ccc", "user": {"login": "alice"}, "body": "<!-- the-judge -->"},
 {"id": 4, "submitted_at": "2026-01-04T00:00:00Z", "commit_id": "ddd", "user": {"login": "github-actions[bot]"}, "body": "r2\n\n<!-- the-judge -->"}]
JSON
}

# round_filter: the jq filter SKILL.md Step 0 passes to `gh api --paginate ... --jq`.
round_filter() { sed -n "s/^gh api --paginate .* --jq '\(.*\)'$/\1/p" "$SKILL/SKILL.md"; }

skill_round_from_marked_reviews() {
  local f=$SKILL/SKILL.md flt
  flt=$(round_filter)
  [ -n "$flt" ]
  grep -qF "gh api --paginate 'repos/<owner>/<repo>/pulls/<number>/reviews?per_page=100'" "$f"
  [ "$(reviews_fixture | env -u JUDGE_BOT_LOGIN jq -c "$flt" | jq -r .commit_id | tr '\n' ' ')" = "aaa ddd " ]
  [ "$(reviews_fixture | JUDGE_BOT_LOGIN= jq -c "$flt" | jq -r .commit_id | tr '\n' ' ')" = "aaa ddd " ]
  [ "$(reviews_fixture | JUDGE_BOT_LOGIN=alice jq -c "$flt" | jq -r .commit_id)" = ccc ]
  [ "$(reviews_fixture | env -u JUDGE_BOT_LOGIN jq -c "$flt" | head -1 | jq -r 'keys | join(",")')" = "body,commit_id,id,submitted_at" ]
  grep -qF 'The round is the number of such reviews plus one.' "$f"
  grep -qF 'the last reviewed commit is the `commit_id` of the latest one' "$f"
}

skill_round_1_when_none() {
  local flt
  flt=$(round_filter)
  [ -n "$flt" ]
  [ -z "$(reviews_fixture | jq '[.[] | select(.id == 2)]' | env -u JUDGE_BOT_LOGIN jq -c "$flt")" ]
  grep -qF 'No such review: this is round 1, run the full workflow.' "$SKILL/SKILL.md"
}

skill_scripts_absolute() {
  local f=$SKILL/SKILL.md
  ! grep -q 'python3 scripts/' "$f"
  grep -qF '| python3 ~/.claude/skills/the-judge/scripts/scan_bypasses.py' "$f"
  grep -qF 'python3 ~/.claude/skills/the-judge/scripts/review_gate.py findings.json' "$f"
}

skill_post_targets_pr_and_repo() {
  grep -qF 'python3 ~/.claude/skills/the-judge/scripts/post_review.py findings.json --pr <number> --repo <owner>/<repo>' "$SKILL/SKILL.md"
  [ "$(grep -c '^gh pr ' "$SKILL/SKILL.md")" -eq "$(grep -c '^gh pr .*--repo <owner>/<repo>' "$SKILL/SKILL.md")" ]
}

# gate_round4 <severity>: runs review_gate.py on a round-4 findings file with one finding of <severity>.
gate_round4() {
  local verdict=REQUEST_CHANGES emoji="🔴"
  if [ "$1" = should-fix ]; then verdict=COMMENT emoji="🟠"; fi
  cat >"$WORK/round4.json" <<EOF2
{"round": 4, "carryover": {"blocker": 0, "should-fix": 0}, "verdict": "$verdict",
 "summary": "## TL;DR\n$verdict.\n## Resolution\n| F1 | resolved |\n## Promote to lint rule\nnone",
 "findings": [{"id": "F9", "path": "a.py", "line": 3, "severity": "$1",
   "body": "$emoji \`x\` is never read (a.py:3).", "evidence": [{"type": "internal", "ref": "a.py:3"}]}]}
EOF2
  python3 "$SKILL/scripts/review_gate.py" "$WORK/round4.json"
}

skill_round_4_resolution_only() {
  grep -qF "$FOURTH_ROUND_NEW" "$SKILL/SKILL.md"
  ! grep -q 'never runs a fourth round' "$SKILL/SKILL.md"
  gate_round4 blocker
  ! gate_round4 should-fix
}

skill_unchanged_sections() {
  local a=$AIPP_JUDGE/SKILL.md b=$SKILL/SKILL.md
  [ -n "$(section "$a" '## Non-Negotiables' '## Severity and Verdict')" ]
  diff <(section "$a" '## Non-Negotiables' '## Severity and Verdict') <(section "$b" '## Non-Negotiables' '## Severity and Verdict')
  diff <(section "$a" '## Severity and Verdict' '## Workflow') <(section "$b" '## Severity and Verdict' '## Workflow')
  [ -n "$(section "$a" '### Step 2' '### Step 6')" ]
  diff <(section "$a" '### Step 2' '### Step 6') <(section "$b" '### Step 2' '### Step 6')
  diff <(section "$a" '## Convergence Contract' '## Examples' | sed "s/$FOURTH_ROUND_OLD/$FOURTH_ROUND_NEW/") \
    <(section "$b" '## Convergence Contract' '## Examples')
  diff <(section "$a" '### Step 6' '### Step 7' | sed 's|python3 scripts/|python3 ~/.claude/skills/the-judge/scripts/|') \
    <(section "$b" '### Step 6' '### Step 7')
  diff <(section "$a" '## Summary Body Template' '## Convergence Contract') <(section "$b" '## Summary Body Template' '## Convergence Contract')
  diff <(section "$a" '## Examples' '## Troubleshooting') <(section "$b" '## Examples' '## Troubleshooting')
  skill_verbatim_files
}

t "skill: no gh api user" skill_no_gh_api_user
t "skill: no human ask in skill" skill_no_human_ask
t "skill: round from marked bot reviews" skill_round_from_marked_reviews
t "skill: round 1 when no marked review" skill_round_1_when_none
t "skill: scripts called by absolute path" skill_scripts_absolute
t "skill: post command targets pr and repo" skill_post_targets_pr_and_repo
t "skill: round 4 and later resolution only" skill_round_4_resolution_only
t "skill: unchanged sections equal aipp" skill_unchanged_sections
