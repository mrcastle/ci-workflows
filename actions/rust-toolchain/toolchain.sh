#!/usr/bin/env bash
set -euo pipefail

d=$PWD
until [[ -f $d/rust-toolchain.toml || -f $d/rust-toolchain || $d == / ]]; do d=$(dirname "$d"); done

if [[ -f $d/rust-toolchain.toml || -f $d/rust-toolchain ]]; then
  echo "Using the toolchain pinned in $d"
  rustup toolchain install
  rustup component add rustfmt clippy
else
  rustup toolchain install "$TOOLCHAIN" --profile minimal --component rustfmt,clippy
  rustup default "$TOOLCHAIN"
fi
