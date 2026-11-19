#!/usr/bin/env bash
set -euo pipefail

tgz="actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"
curl -fsSL --retry 3 --retry-all-errors -o "$RUNNER_TEMP/$tgz" \
  "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/$tgz"
echo "$ACTIONLINT_SHA256  $RUNNER_TEMP/$tgz" | sha256sum -c -
tar -xzf "$RUNNER_TEMP/$tgz" -C "$RUNNER_TEMP" actionlint

# actionlint 1.7.12 can't parse GitHub's `$/` self-repository syntax yet
# (rhysd/actionlint#711); ignore only those two errors.
"$RUNNER_TEMP/actionlint" -color \
  -ignore 'specifying action "\$/' \
  -ignore 'reusable workflow call "\$/'
