# Tests for skills/the-judge/scripts/post_review.py (CCR-11, 12, 15, 16, 17, 18). Sourced by tests/run.sh.

# post_setup <verdict>: fresh fake-gh dir and a gate-passing findings.json with one finding for <verdict>.
post_setup() {
  local sev emoji
  FG=$WORK/fg
  rm -rf "$FG"
  mkdir -p "$FG/bin"
  ln -s "$ROOT/tests/fake-gh" "$FG/bin/gh"
  : >"$FG/log"
  case $1 in
    APPROVE) sev=nit emoji="🟡" ;;
    COMMENT) sev=should-fix emoji="🟠" ;;
    REQUEST_CHANGES) sev=blocker emoji="🔴" ;;
  esac
  cat >"$FG/findings.json" <<EOF
{"round": 1, "carryover": {"blocker": 0, "should-fix": 0}, "verdict": "$1",
 "summary": "## TL;DR\n$1 with one finding.\n## Promote to lint rule\nnone",
 "findings": [{"id": "F1", "path": "a.py", "line": 3, "severity": "$sev",
   "body": "$emoji \`x\` is never read (a.py:3).", "evidence": [{"type": "internal", "ref": "a.py:3"}]}]}
EOF
}

# post <args...>: runs post_review.py against fake gh; JUDGE_BOT_LOGIN is unset unless LOGIN is given.
post() {
  local login=()
  if [ -n "${LOGIN:-}" ]; then login=(JUDGE_BOT_LOGIN="$LOGIN"); fi
  env -u JUDGE_BOT_LOGIN "${login[@]}" PATH="$FG/bin:$PATH" FAKE_GH_LOG="$FG/log" FAKE_GH_DIR="$FG" \
    python3 "$ROOT/skills/the-judge/scripts/post_review.py" "$FG/findings.json" "$@" >"$FG/out" 2>"$FG/err"
}

payload() { jq -r "$1" "$FG/payload-${2:-1}.json"; }
posts() { find "$FG" -maxdepth 1 -name 'payload-*.json' | wc -l; }

post_no_api_user_default_login() {
  post_setup APPROVE
  FAKE_GH_AUTHOR=alice post --pr 7 --repo o/r
  [ "$(payload .event)" = APPROVE ]
  ! grep -q '^api user' "$FG/log"
  post_setup APPROVE
  FAKE_GH_AUTHOR='github-actions[bot]' post --pr 7 --repo o/r
  [ "$(payload .event)" = COMMENT ]
  ! grep -q '^api user' "$FG/log"
}

post_login_from_env() {
  post_setup APPROVE
  LOGIN=mybot FAKE_GH_AUTHOR=mybot post --pr 7 --repo o/r
  [ "$(payload .event)" = COMMENT ]
  post_setup APPROVE
  LOGIN=mybot FAKE_GH_AUTHOR='github-actions[bot]' post --pr 7 --repo o/r
  [ "$(payload .event)" = APPROVE ]
}

post_requires_and_uses_pr_and_repo() {
  local rc
  post_setup APPROVE
  rc=0
  post --pr 7 || rc=$?
  [ "$rc" -eq 1 ]
  grep -q 'usage: post_review.py findings.json --pr N --repo owner/repo' "$FG/err"
  rc=0
  post --repo o/r || rc=$?
  [ "$rc" -eq 1 ]
  grep -q 'usage:' "$FG/err"
  [ ! -s "$FG/log" ]
  post --pr 7 --repo o/r
  grep -qx 'pr view 7 --repo o/r --json number,author' "$FG/log"
  [ "$(grep -c '^pr ' "$FG/log")" -eq "$(grep -c '^pr .*--repo o/r' "$FG/log")" ]
  grep -q '^api repos/o/r/pulls/7/reviews --method POST' "$FG/log"
  ! grep -q '^repo ' "$FG/log"
}

post_own_pr_comment() {
  post_setup REQUEST_CHANGES
  FAKE_GH_AUTHOR='github-actions[bot]' post --pr 7 --repo o/r
  [ "$(posts)" -eq 1 ]
  [ "$(payload .event)" = COMMENT ]
  payload .body | grep -qF "_Intended verdict: **REQUEST_CHANGES**. Posted as a comment because GitHub does not allow REQUEST_CHANGES on the author's own PR._"
  [ "$(payload '.comments[0].path'):$(payload '.comments[0].line')" = "a.py:3" ]
}

t "post_review: no gh api user and default bot login" post_no_api_user_default_login
t "post_review: bot login taken from JUDGE_BOT_LOGIN" post_login_from_env
t "post_review: requires and uses pr and repo" post_requires_and_uses_pr_and_repo
t "post_review: own pr posts as comment" post_own_pr_comment

# ends_with_marker: payload 1 body ends with a blank line and the hidden marker.
ends_with_marker() {
  python3 -c 'import json,sys; b=json.load(open(sys.argv[1]))["body"]; sys.exit(not b.endswith("\n\n<!-- the-judge -->"))' "$FG/payload-1.json"
}

post_body_ends_with_marker() {
  post_setup APPROVE
  FAKE_GH_AUTHOR=alice post --pr 7 --repo o/r
  ends_with_marker
  payload .body | grep -q '^## TL;DR$'
}

post_marker_after_own_pr_footer() {
  post_setup APPROVE
  FAKE_GH_AUTHOR='github-actions[bot]' post --pr 7 --repo o/r
  ends_with_marker
  python3 -c 'import json,sys; b=json.load(open(sys.argv[1]))["body"]; sys.exit(not b.endswith("own PR._\n\n<!-- the-judge -->"))' "$FG/payload-1.json"
}

t "post_review: body ends with marker" post_body_ends_with_marker
t "post_review: marker follows own pr footer" post_marker_after_own_pr_footer
