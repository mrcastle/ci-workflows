# Changelog

## v1.0.0 (unreleased)

- **`node.yml` and `rust.yml`:** turn the caller's `checks` into one job per check, each with its own setup.
- **`security.yml`:** one job per scanner, with binaries pinned by SHA256:
  - OSV-Scanner 2.7.0
  - zizmor 1.31.1
  - gitleaks 8.30.1
- **`report.yml`:** a single PR comment with a results table and failure details, kept up to date on every run.
- **Composite actions:** `plan`, `node-setup`, `rust-setup`, `run-check` and `scanners`, referenced with `$/`.
- **`self-test.yml`:**
  - actionlint
  - a parse check of the composite actions
  - the workflows run against fixtures
  - the report comment
