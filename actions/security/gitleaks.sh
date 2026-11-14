#!/usr/bin/env bash
# Leaked secrets: only the PR's commits on pull_request (BASE/HEAD set), full history otherwise.
# Secrets are redacted everywhere. Allowlist false positives in .gitleaksignore.
set -uo pipefail

range=()
[[ -n "${BASE:-}" ]] && range=(--log-opts="$BASE..$HEAD")
json="$RUNNER_TEMP/gitleaks.json"

gitleaks git --redact --no-banner --report-format json --report-path "$json" "${range[@]}" .
rc=$?
if (( rc != 0 )) && [[ -s "$json" ]]; then
  # shellcheck disable=SC2016 # jq program, not shell
  jq -r '"| Rule | File | Line | Commit |", "|---|---|---|---|",
    (.[] | "| \(.RuleID) | `\(.File)` | \(.StartLine) | `\(.Commit[0:7])` |")' "$json" > "$CI_REPORT_MD"
fi
exit "$rc"
