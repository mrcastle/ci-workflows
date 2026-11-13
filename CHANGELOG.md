# Changelog

## v1.0.0 (2026-11-13)

- `node.yml`: installs once, then runs the caller's `checks` list.
- `rust.yml`: sets up the toolchain and rust-cache, then runs the caller's `checks` list.
- `security.yml`: OSV-Scanner 2.7.0, zizmor 1.31.1 and gitleaks 8.30.1.
- `self-test.yml`: actionlint, plus the reusable workflows run against fixtures.
