#!/usr/bin/env bash
set -euo pipefail

[[ -n "$PR" ]] || { echo "Not a pull_request run; nothing to report."; exit 0; }
marker="<!-- ci-workflows:report:$WORKFLOW -->"
body="$RUNNER_TEMP/comment.md"

# A job that failed outside any check step (e.g. checkout) still shows up.
[[ "$RESULT" == success || "$ROWS" == *❌* ]] || ROWS+=$'\n'"| job | ❌ $RESULT (see the run log) |"
total=$(grep -c '^|' <<< "$ROWS" || true)
failed=$(grep -c '❌' <<< "$ROWS" || true)
skipped=$(grep -c '⏭' <<< "$ROWS" || true)
(( ${#DETAILS} < 60000 )) || DETAILS="Failure details are too long for a comment; see the [run log]($RUN_URL)."

{
  echo "$marker"
  if (( failed > 0 && skipped > 0 )); then echo "### ❌ CI: $failed of $total checks failed, $skipped skipped"
  elif (( failed > 0 )); then echo "### ❌ CI: $failed of $total checks failed"
  else echo "### ✅ CI: all $total checks passed"; fi
  echo "Commit \`${SHA:0:7}\` · [workflow run]($RUN_URL)"
  echo
  echo "| Check | Result |"
  echo "|---|---|"
  grep -v '^$' <<< "$ROWS" || true
  echo
  echo "$DETAILS"
} > "$body"
cat "$body" >> "$GITHUB_STEP_SUMMARY"

# The filter reads the marker from env, so any workflow name is safe in it.
if ! id=$(MARKER="$marker" gh api "repos/$GH_REPO/issues/$PR/comments" --paginate \
  --jq '.[] | select(.user.login == "github-actions[bot]" and (.body | startswith(env.MARKER))) | .id' | sed -n 1p); then
  echo "::warning::Couldn't read the PR's comments, so the report wasn't posted. Results are in the job summary."
  exit 0
fi
if [[ -n "$id" ]]; then
  gh api -X PATCH "repos/$GH_REPO/issues/comments/$id" -F body=@"$body" > /dev/null && echo "Updated comment $id"
elif (( failed > 0 )); then
  gh api "repos/$GH_REPO/issues/$PR/comments" -F body=@"$body" > /dev/null && echo "Created comment"
else
  echo "All passing and no earlier comment; nothing to post."
fi || echo "::warning::Couldn't post the PR comment (read-only token, e.g. a fork PR). Results are in the job summary."
