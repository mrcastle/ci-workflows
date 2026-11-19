#!/usr/bin/env bash
set -euo pipefail

dir="$RUNNER_TEMP/ci-report"
mkdir -p "$dir"
touch "$dir/rows.md"
read -ra checks <<< "$CHECKS"

declare -A recorded
order=()
while IFS= read -r line; do
  name=${line#| }
  name=${name%% |*}
  recorded[$name]=$line
  order+=("$name")
done < "$dir/rows.md"

listed() {
  local c
  for c in "${checks[@]}"; do [[ $c == "$1" ]] && return 0; done
  return 1
}

rows() {
  local name command
  for name in "${order[@]}"; do
    listed "$name" || echo "${recorded[$name]}"
  done
  [[ "$SETUP" != failure ]] || echo "| setup | ❌ failed (see the run log) |"
  for name in "${checks[@]}"; do
    if [[ -n ${recorded[$name]+x} ]]; then
      echo "${recorded[$name]}"
    else
      command=$(jq -r --arg c "$name" '.[$c] // ""' <<< "$COMMANDS")
      [[ -z $command ]] || echo "| $name | ⏭ skipped |"
    fi
  done
}

eof="EOF_$RANDOM$RANDOM"
{
  echo "rows<<$eof"
  rows
  echo "$eof"
  echo "details<<$eof"
  cat "$dir/details.md" 2>/dev/null || true
  echo "$eof"
} >> "$GITHUB_OUTPUT"
