# Content tests for README.md (CCR-26..28). Sourced by tests/run.sh.
R=$ROOT/README.md

has() { grep -qiF -- "$1" "$R"; }

readme_setup() {
  has '## One-time setup'
  has 'claude setup-token'
  has 'CLAUDE_TOKENS'
  has 'tok1;tok2;tok3'
  has 'contents: read'
  has 'pull-requests: write'
  has 'read-only'
  has 'Allow GitHub Actions to create and approve pull requests'
  has 'git tag v1'
}

readme_resync_and_divergences() {
  has '## Re-sync the skill from aipp'
  has 'cp -r ../aipp/skills/tech-leads-club/the-judge skills/'
  has 'git tag -f v1'
  has 'git push -f origin v1'
  has '## Divergences from aipp the-judge'
  has 'gh api user'
  has 'JUDGE_BOT_LOGIN'
  has '<!-- the-judge -->'
  has '--pr <number> --repo <owner>/<repo>'
  has '~/.claude/skills/the-judge/scripts/'
  has 'round 4 and later'
  has 'retried once as COMMENT'
  has 'stop and report'
}

readme_caveats() {
  has '## Caveats'
  has 'expire after one year'
  has 'Terms of use'
  has 'Bash is unrestricted'
  has 'No dependencies installed'
  has 'far more of the plan limits than a one-shot prompt'
}

t "readme: one-time setup" readme_setup
t "readme: re-sync and divergences" readme_resync_and_divergences
t "readme: caveats" readme_caveats
