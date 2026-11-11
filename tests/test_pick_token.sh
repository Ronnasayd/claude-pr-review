# Tests for scripts/pick-token.sh (CCR-06..09). Sourced by tests/run.sh.

# pick <tokens>: runs the picker once; stdout to $WORK/pick.out, step output to $WORK/pick.gh.
pick() {
  : >"$WORK/pick.gh"
  TOKENS="$1" GITHUB_OUTPUT="$WORK/pick.gh" bash "$ROOT/scripts/pick-token.sh" >"$WORK/pick.out"
}

picked() { sed -n 's/^token=//p' "$WORK/pick.gh"; }

# draws <tokens> <n>: prints the token picked in each of n runs.
draws() {
  local i
  for i in $(seq "$2"); do
    pick "$1"
    picked
  done
}

pick_single() {
  pick "tok1"
  [ "$(picked)" = "tok1" ]
}

pick_trims_and_skips() {
  local got
  got=$(draws " tok1 ; tok2 " 50 | sort -u | tr '\n' ' ')
  [ "$got" = "tok1 tok2 " ]
}

pick_double_and_trailing_separators() {
  local got
  got=$(draws "tok1;;tok2;" 50 | sort -u | tr '\n' ' ')
  [ "$got" = "tok1 tok2 " ]
}

pick_every_token_reachable() {
  local got
  got=$(draws "tok1;tok2;tok3" 200 | sort -u | tr '\n' ' ')
  [ "$got" = "tok1 tok2 tok3 " ]
}

pick_masks_and_logs_index() {
  pick "tok1;tok2;tok3"
  local tok i
  tok=$(picked)
  [ "$(sed -n 1p "$WORK/pick.out")" = "::add-mask::$tok" ]
  i=$(sed -n 2p "$WORK/pick.out" | sed -n 's/^Using token \([1-3]\) of 3$/\1/p')
  [ -n "$i" ]
  [ "$tok" = "tok$i" ]
  [ "$(wc -l <"$WORK/pick.out")" -eq 2 ]
  [ "$(cat "$WORK/pick.gh")" = "token=$tok" ]
}

pick_fails_on() {
  local rc=0
  pick "$1" || rc=$?
  [ "$rc" -eq 1 ]
  grep -qx '::error::CLAUDE_TOKENS is empty or has no token' "$WORK/pick.out"
  [ ! -s "$WORK/pick.gh" ]
}

t "pick_token: single token returned" pick_single
t "pick_token: trims whitespace and skips empty entries" pick_trims_and_skips
t "pick_token: double and trailing separators yield no empty token" pick_double_and_trailing_separators
t "pick_token: every token reachable" pick_every_token_reachable
t "pick_token: masks token and logs index only" pick_masks_and_logs_index
t "pick_token: empty input fails with message" pick_fails_on ""
t "pick_token: separator-only input fails with message" pick_fails_on ";;"
