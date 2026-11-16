#!/usr/bin/env bash
# Run one check ($NAME: $RUN) and record its result for the PR report.
# Optional TOOL_URL/TOOL_SHA256/TOOL_BIN: download a checksum-verified binary onto PATH first.
# A command can write markdown to $CI_REPORT_MD (e.g. a findings table) to replace the default
# failure details, which are the tail of its output.
set -uo pipefail

dir="$RUNNER_TEMP/ci-report"
mkdir -p "$dir"
export CI_REPORT_MD="$dir/$NAME.table.md"

# Replace this check's row (the workflow lists each check as skipped up front), or add one.
rows="$dir/rows.md"
touch "$rows"
result() {
  awk -v key="| $NAME |" -v row="| $NAME | $1 |" \
    'index($0, key) == 1 { print row; found = 1; next } { print } END { if (!found) print row }' \
    "$rows" > "$rows.tmp" && mv "$rows.tmp" "$rows"
}
# Marked now and replaced at the end, so a check killed mid-run (e.g. a timeout) still shows up.
result "❌ didn't finish"

install_tool() {
  [[ -n "${TOOL_URL:-}" ]] || return 0
  mkdir -p "$RUNNER_TEMP/bin"
  curl -fsSLo "$RUNNER_TEMP/download" "$TOOL_URL" || return
  echo "$TOOL_SHA256  $RUNNER_TEMP/download" | sha256sum -c - || return
  if [[ "$TOOL_URL" == *.tar.gz ]]; then tar -xzf "$RUNNER_TEMP/download" -C "$RUNNER_TEMP/bin" "$TOOL_BIN" || return
  else mv "$RUNNER_TEMP/download" "$RUNNER_TEMP/bin/$TOOL_BIN"; fi
  chmod +x "$RUNNER_TEMP/bin/$TOOL_BIN"
  export PATH="$RUNNER_TEMP/bin:$PATH"
}

echo "\$ $RUN"
{ install_tool && bash -euo pipefail -c "$RUN"; } < /dev/null 2>&1 | tee "$dir/$NAME.log"
rc=${PIPESTATUS[0]}
[[ -s "$CI_REPORT_MD" ]] && cat "$CI_REPORT_MD" >> "$GITHUB_STEP_SUMMARY"

if (( rc == 0 )); then
  result "✅ passed"
  exit 0
fi

result "❌ failed (exit $rc)"
{
  echo "<details><summary>❌ <b>$NAME</b> (exit $rc)</summary>"
  echo
  # Size caps keep one huge output from pushing every check's details out of the comment.
  if [[ -s "$CI_REPORT_MD" ]] && (( $(wc -c < "$CI_REPORT_MD") > 15000 )); then
    head -c 15000 "$CI_REPORT_MD" | sed '$d'
    echo; echo "Truncated; the full table is in the job summary."
  elif [[ -s "$CI_REPORT_MD" ]]; then
    cat "$CI_REPORT_MD"
  else
    # Escaped inside <pre>, so the output can't close the block or inject markdown/HTML.
    echo '<pre>'
    { echo "\$ $RUN"; tail -n 60 "$dir/$NAME.log" | tail -c 4000; } \
      | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g; s/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
    echo '</pre>'
  fi
  echo
  echo "</details>"
} >> "$dir/details.md"
echo "::error title=$NAME failed::exit $rc"
exit "$rc"
