#!/usr/bin/env bash
set -euo pipefail

dir="$RUNNER_TEMP/ci-report"
eof="EOF_$RANDOM$RANDOM"

# A check with a command but no recorded row didn't run, because an earlier step failed.
skipped() {
  local c
  while IFS= read -r c; do
    grep -q "^| $c |" "$dir/rows.md" 2>/dev/null || echo "| $c | ⏭ skipped |"
  done < <(jq -r --arg checks "$CHECKS" '. as $in | $checks | split(" ")[] | select(($in[.] // "") != "")' <<< "$COMMANDS")
}

{
  echo "rows<<$eof"
  [[ "$SETUP" != failure ]] || echo "| setup | ❌ failed (see the run log) |"
  cat "$dir/rows.md" 2>/dev/null || true
  skipped
  echo "$eof"
  echo "details<<$eof"
  cat "$dir/details.md" 2>/dev/null || true
  echo "$eof"
} >> "$GITHUB_OUTPUT"
