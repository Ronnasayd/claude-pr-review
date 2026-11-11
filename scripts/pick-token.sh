#!/usr/bin/env bash
# Picks one random token from TOKENS (";"-separated) and writes it to the step output "token".
# invariant: the token reaches only $GITHUB_OUTPUT, never $GITHUB_ENV, and is masked before any use.
set -euo pipefail

tokens=()
IFS=';' read -ra parts <<<"${TOKENS:-}"
for p in "${parts[@]}"; do
  p="${p#"${p%%[![:space:]]*}"}"
  p="${p%"${p##*[![:space:]]}"}"
  if [ -n "$p" ]; then tokens+=("$p"); fi
done

n=${#tokens[@]}
if [ "$n" -eq 0 ]; then
  echo "::error::CLAUDE_TOKENS is empty or has no token"
  exit 1
fi

i=$((RANDOM % n))
token=${tokens[$i]}
echo "::add-mask::$token"
echo "Using token $((i + 1)) of $n"
echo "token=$token" >>"$GITHUB_OUTPUT"
