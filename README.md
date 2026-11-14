# ci-workflows

Reusable GitHub Actions CI for Node and Rust repos. One job installs dependencies once and runs every check as its own step: lint, typecheck, test, build, then security scanning. A second job keeps one PR comment up to date with the results.

```
checks:  checkout → setup → install → lint → typecheck → test → build → osv → zizmor → gitleaks
report:  update the PR comment
```

- **Each check is its own step.** It has its own pass/fail and its own log section in the job view.
- **Every check runs even if an earlier one failed,** so one run shows every failure. The only exception: when install fails, the checks that need dependencies are skipped.

| Workflow | Steps |
|---|---|
| `node.yml` | install, lint, typecheck, test, build, security |
| `rust.yml` | fmt, clippy, test, security |

**Security scanning** runs these three tools:
- [OSV-Scanner](https://google.github.io/osv-scanner/) checks dependencies for known vulnerabilities.
- [zizmor](https://docs.zizmor.sh) checks the GitHub Actions workflows for security problems.
- [gitleaks](https://github.com/gitleaks/gitleaks) looks for leaked secrets.

## Usage

Add `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  pull_request:
  schedule:
    - cron: "0 7 * * 1" # weekly, to catch new CVEs in unchanged lockfiles
  workflow_dispatch:

permissions: {}

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  node:
    permissions:
      contents: read
      actions: read # zizmor online audits
      pull-requests: write # report comment
    uses: mrcastle/ci-workflows/.github/workflows/node.yml@<sha> # v1.0.0
    with:
      lint: npm run lint
      typecheck: npx tsc --noEmit
      test: npm test
      build: npm run build
```

**Checks:** leave any check out to skip it. Each command runs from `working-directory` with `bash -euo pipefail`, the same way you'd run it locally.

**Rust:** call `rust.yml` instead. Its fmt, clippy and test checks default to:

| Check | Default command |
|---|---|
| fmt | `cargo fmt --check` |
| clippy | `cargo clippy --all-targets --locked -- -D warnings` |
| test | `cargo test --locked` |

Override any of them, or set one to `""` to skip it.

**Permissions:** each job narrows the caller's grant:
- `checks` gets `contents: read` and `actions: read`.
- Only `report` can write to the PR, and it never checks out or runs repo code.

**Pinning and updates.** Pin by commit SHA, since zizmor's default policy requires it. Then add `.github/dependabot.yml`, and Dependabot will bump the SHA and the `# vX.Y.Z` comment together:

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule: { interval: weekly }
    cooldown: { default-days: 14 }
```

### Inputs

| Input | Workflow | Default | Purpose |
|---|---|---|---|
| `lint`, `typecheck`, `test`, `build` | node | empty (skipped) | Commands for each check |
| `fmt`, `clippy`, `test` | rust | see above | Commands for each check |
| `install` | node | `npm ci --ignore-scripts --no-audit --no-fund` | Drop `--ignore-scripts` if you need postinstall (e.g. Prisma) |
| `node-version` | node | `lts/*` | Ignored when `node-version-file` is set |
| `node-version-file` | node | none | Read the version from a file such as `.nvmrc` |
| `toolchain` | rust | `stable` | A `rust-toolchain.toml` in the repo takes precedence |
| `working-directory` | both | `.` | Project root, for monorepos. Security always scans the whole repo |
| `timeout-minutes` | both | 15 / 20 | Time limit for the checks job |

### The PR comment

- **When it's posted:** the first time a run has a failure.
- **After that:** it's updated on every run, including passing ones, which turns it into "✅ all N checks passed". So it's never stale.
- **One comment per caller workflow.** A repo with both stacks can have one caller workflow per stack.
- **Failure details:**

| Check | Shows |
|---|---|
| osv | Vulnerability table |
| zizmor | Findings by severity, with doc links and `file:line` |
| gitleaks | Rule, file, line and commit. Secrets are never shown |
| Your own checks | The end of the output |

A command can write markdown to `$CI_REPORT_MD` to replace its default details.

### Security exceptions

**OSV.** Add the vulnerability to `osv-scanner.toml` with a reason and an expiry:

```toml
[[IgnoredVulns]]
id = "GHSA-xxxx-xxxx-xxxx"
ignoreUntil = 2027-01-01
reason = "Dev-only dependency, not reachable"
```

Repos with no lockfiles pass.

**zizmor.** Configure it in `.github/zizmor.yml`.

**gitleaks.** Allowlist false positives in `.gitleaksignore`. On a PR it scans only the PR's commits. Scheduled runs scan the full history.

## Design

**One job, one install.** This is GitHub's starter-workflow shape: install, then run the checks as steps on the same machine. Nothing is uploaded or cached between jobs. The one exception is Rust, where `rust-cache` keeps compiled dependencies between runs.

**Cost:** a run bills about 2 minutes plus the time the checks actually take. GitHub Free includes 2,000 private minutes a month.

**The repo owns *what* runs, and the shared workflows own *how*.** Callers write the same commands they run locally. The shared workflows handle setup, hardening and reporting.

**Hardening:**

| Measure | What it means |
|---|---|
| Pinned dependencies | Every action is pinned to a commit SHA. Every scanner binary is pinned by version and SHA256 |
| Least-privilege tokens | `permissions: {}` at the top, then per-job grants |
| Isolated write access | Only the report job can write to the PR, and it never checks out or runs repo code |
| No credentials left behind | `persist-credentials: false` on every checkout |
| No template injection | Inputs reach the shell only through `env`, never inlined into scripts |
| No environment-file writes | Nothing writes to `GITHUB_ENV` or `GITHUB_PATH` |
| No install scripts by default | `npm ci --ignore-scripts` stops install-time code from dependencies |
| Free reporting | Results go to the job logs, the summary and the PR comment instead of SARIF, which needs paid Advanced Security on private repos |
| Caller rule | Never use `pull_request_target` or `secrets: inherit` in callers |

**Shared steps** are composite actions in `actions/`, referenced with GitHub's `$/` self-repository syntax ([July 2026](https://github.blog/changelog/2026-07-30-reference-same-repository-actions-with-self-repository-syntax/)). That syntax resolves to this repo at the exact commit the caller pinned.

| Action | What it does |
|---|---|
| `check` | Runs one check and records its result |
| `security` | Runs the three scanners |
| `results` | Hands the results to the report job |
| `comment` | Updates the PR comment |

## Development

Two workflows run on every PR, wired exactly like callers. They don't count against the minutes quota because the repo is public.
- **`self-test.yml`:**
  - Runs actionlint, ignoring only its two errors about `$/` ([rhysd/actionlint#711](https://github.com/rhysd/actionlint/issues/711)).
  - Parse-checks the composite actions, which actionlint doesn't read.
  - Runs `node.yml` against `fixtures/node`.
- **`self-test-rust.yml`:** runs `rust.yml` against `fixtures/rust`.

Dependabot keeps the action SHAs up to date, with a 14-day cooldown before adopting new releases. It can't update the scanner binaries:

| Tool | Where it's pinned |
|---|---|
| osv-scanner, zizmor, gitleaks | `actions/security/action.yml` |
| actionlint | `env` in `self-test.yml` |

When bumping them by hand, use releases at least 14 days old and record the SHA256 of the downloaded file.

**Releases** use immutable `vX.Y.Z` tags, recorded in [CHANGELOG.md](CHANGELOG.md). Callers pin to the release's commit SHA.

## License

[MIT](LICENSE)
