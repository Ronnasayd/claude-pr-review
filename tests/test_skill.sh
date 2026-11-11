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

skill_round_from_marked_reviews() {
  local f=$SKILL/SKILL.md
  grep -qF 'select(.user.login == (env.JUDGE_BOT_LOGIN // "github-actions[bot]") and (.body | contains("<!-- the-judge -->")))' "$f"
  grep -qF '{id, submitted_at, commit_id, body}' "$f"
  grep -qF 'The round is the number of such reviews plus one.' "$f"
  grep -qF 'the last reviewed commit is the `commit_id` of the latest one' "$f"
}

skill_round_1_when_none() {
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

skill_round_4_resolution_only() {
  grep -qF "$FOURTH_ROUND_NEW" "$SKILL/SKILL.md"
  ! grep -q 'never runs a fourth round' "$SKILL/SKILL.md"
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
}

t "skill: no gh api user" skill_no_gh_api_user
t "skill: no human ask in skill" skill_no_human_ask
t "skill: round from marked bot reviews" skill_round_from_marked_reviews
t "skill: round 1 when no marked review" skill_round_1_when_none
t "skill: scripts called by absolute path" skill_scripts_absolute
t "skill: post command targets pr and repo" skill_post_targets_pr_and_repo
t "skill: round 4 and later resolution only" skill_round_4_resolution_only
t "skill: unchanged sections equal aipp" skill_unchanged_sections
