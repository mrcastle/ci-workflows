#!/usr/bin/env bash
# Known-vulnerable dependencies in any lockfile. Ignore one with a reason in osv-scanner.toml.
set -uo pipefail

osv-scanner scan source --recursive --format markdown --output-file "$CI_REPORT_MD" .
rc=$?
cat "$CI_REPORT_MD" 2>/dev/null
case $rc in
  0)   exit 0 ;;
  128) echo "No lockfiles found; nothing to scan."; exit 0 ;;
  *)   exit "$rc" ;;
esac
