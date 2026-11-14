# Changelog

## v1.0.0 (unreleased)

- **`node.yml`:** one `checks` job (install once, then lint, typecheck, test, build and security as steps), plus a `report` job.
- **`rust.yml`:** the same shape, with fmt, clippy and test.
- **Security scanning:** binaries pinned by SHA256:
  - OSV-Scanner 2.7.0
  - zizmor 1.31.1
  - gitleaks 8.30.1
- **PR comment:** one comment per caller workflow, with a results table and failure details, kept up to date on every run.
- **Composite actions:** `check`, `security`, `results` and `comment`, referenced with `$/`.
- **`self-test.yml` and `self-test-rust.yml`:** actionlint, a parse check of the composite actions, and both workflows run against fixtures.
