#!/usr/bin/env bash
# Known-vulnerable dependencies in any lockfile. Ignore one with a reason in osv-scanner.toml.
set -uo pipefail

json="$RUNNER_TEMP/osv.json"
osv-scanner scan source --recursive --format json --output-file "$json" .
rc=$?
case $rc in
  0)   echo "No known vulnerabilities."; exit 0 ;;
  128) echo "No lockfiles found; nothing to scan."; exit 0 ;;
  1)   ;;
  *)   exit "$rc" ;;
esac

# One row per vulnerability: its CVE (or advisory ID when there's no CVE), linked to osv.dev,
# and the first fixed version above the installed one. Most severe first.
# shellcheck disable=SC2016 # jq program, not shell
jq -r '
  def ver: split("-")[0] | split(".") | map(tonumber? // 0);
  def rank: {critical: 0, high: 1, moderate: 2, medium: 2, low: 3}[.] // 4;
  [ .results[].packages[] | .package as $p | (.dependency_groups // []) as $groups
    | .vulnerabilities[]
    | { id: ((.aliases // []) | map(select(startswith("CVE-"))) | first) // .id,
        severity: (.database_specific.severity // "unknown" | ascii_downcase),
        package: ($p.name + (if $groups | index("dev") then " (dev)" else "" end)),
        version: $p.version,
        fixed: ([ .affected[] | select(.package.name == $p.name) | .ranges[]?.events[] | .fixed // empty
                  | select(ver > ($p.version | ver)) ] | min_by(ver) // "none") } ]
  | unique_by([.id, .package, .version]) | sort_by((.severity | rank), .package) as $rows
  | "\($rows | length) vulnerabilities in \($rows | map([.package, .version]) | unique | length) packages",
    "",
    "| CVE | Severity | Package | Version | Fixed in |",
    "|---|---|---|---|---|",
    ($rows[] | "| [\(.id)](https://osv.dev/vulnerability/\(.id)) | \(.severity) | \(.package) | \(.version) | \(.fixed) |")
' "$json" > "$CI_REPORT_MD" || rm -f "$CI_REPORT_MD"
cat "$CI_REPORT_MD" 2>/dev/null
exit "$rc"
