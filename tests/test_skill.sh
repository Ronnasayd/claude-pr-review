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
