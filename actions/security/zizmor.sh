#!/usr/bin/env bash
# GitHub Actions workflow security. Full findings go to the log; a table goes to the PR report.
set -uo pipefail

zizmor --format plain .
rc=$?
if (( rc != 0 )); then
  json="$RUNNER_TEMP/zizmor.json"
  zizmor --format json . > "$json" 2>/dev/null
  # shellcheck disable=SC2016 # jq program, not shell
  jq -r '
    "| Severity | Finding | Location |", "|---|---|---|",
    (map(select(.ignored | not))
      | sort_by({"High": 0, "Medium": 1, "Low": 2}[.determinations.severity] // 3)
      | .[] | . as $f | .locations[] | select(.symbolic.kind == "Primary")
      | "| \($f.determinations.severity) | [\($f.ident)](\($f.url)): \(.symbolic.annotation) | `\(.symbolic.key.Local.given_path // .symbolic.key.Local.verbatim_path // "?" | ltrimstr("./")):\(.concrete.location.start_point.row + 1)` |")
  ' "$json" > "$CI_REPORT_MD" || rm -f "$CI_REPORT_MD"
fi
exit "$rc"
