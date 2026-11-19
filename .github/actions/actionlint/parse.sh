#!/usr/bin/env bash
set -euo pipefail

# actionlint doesn't read composite actions, so at least make sure they parse.
for f in actions/*/action.yml .github/actions/*/action.yml; do
  yq e . "$f" > /dev/null
done
