# ci-workflows

Reusable GitHub Actions CI. A repo calls one workflow with its own commands. Dependencies are installed once, every command then runs as its own job (a separate check on the PR, with its own node in the workflow graph and its own log), security scanning runs alongside, and one PR comment summarizes the results.

```
install ──┬─▶ lint ──────┐
          ├─▶ typecheck ─┤
          └─▶ build ─────┤
security ─┬─▶ osv ───────┼──▶ report
          ├─▶ zizmor ────┤
          └─▶ gitleaks ──┘
```

| Workflow | What it does |
|---|---|
| `node.yml` | `install` runs `npm ci` once and passes `node_modules` to the check jobs as a run artifact (tarred, kept 1 day). Then one job per check, plus `security` and `report` |
| `rust.yml` | Same shape. Rust has no install step, so a small `plan` job builds the check list, and each check job builds with its own `rust-cache` |
| `security.yml` | Called by both. One job per scanner: [OSV-Scanner](https://google.github.io/osv-scanner/) for vulnerable dependencies, [zizmor](https://docs.zizmor.sh) for workflow security, [gitleaks](https://github.com/gitleaks/gitleaks) for leaked secrets. It never installs or runs repo code |
| `report.yml` | Called by both. Keeps one PR comment in sync with the run: a results table that links to each job, plus details for each failure |

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
      actions: read # Jobs API (report), zizmor online audits
      pull-requests: write # report comment
    uses: mrcastle/ci-workflows/.github/workflows/node.yml@<sha> # v1.0.0
    with:
      checks: |
        lint: npm run lint
        typecheck: npx tsc --noEmit
        test-unit: npm run test:unit
        build: npm run build
```

The PR shows `CI / node / install`, `CI / node / lint`, …, `CI / node / security / osv`, and so on. Each job narrows the caller's grant to what it needs: install and the checks get `contents: read` only.

For Rust, call `rust.yml` instead:

```yaml
    uses: mrcastle/ci-workflows/.github/workflows/rust.yml@<sha> # v1.0.0
    with:
      checks: |
        fmt: cargo fmt --check
        clippy: cargo clippy --all-targets --locked -- -D warnings
        test-unit: cargo test --lib --locked
        test-integration: cargo test --test '*' --locked
```

A repo with both stacks uses one caller workflow per stack. Each gets its own PR comment.

**Pinning and updates.** Pin by commit SHA, since zizmor's default policy requires it. Then add `.github/dependabot.yml`, and Dependabot will bump the SHA and the `# vX.Y.Z` comment together:

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule: { interval: weekly }
    cooldown: { default-days: 14 }
```

### `checks`

**Format.** One `name: command` per line. Blank lines and `#` comments are skipped.

**Names.** Each name becomes a job (`ci / <name>`), so names must be unique and can't be `osv`, `zizmor` or `gitleaks`.

**How commands run.** Each command runs from `working-directory` with `bash -euo pipefail`, using the same command you'd run locally.

**Custom failure details.** By default a failing check's PR comment section shows the end of its output. A command can write markdown to `$CI_REPORT_MD` (a findings table, say) to show that instead. The security scanners do this.

### Inputs

| Input | Workflow | Default | Purpose |
|---|---|---|---|
| `checks` | node, rust | required | The checks to run |
| `working-directory` | node, rust | `.` | Project root, for monorepos |
| `timeout-minutes` | node, rust | 10 / 15 | Time limit for each check job |
| `node-version` | node | `lts/*` | Ignored when `node-version-file` is set |
| `node-version-file` | node | none | Read the version from a file such as `.nvmrc` |
| `install-command` | node | `npm ci --ignore-scripts --no-audit --no-fund` | Drop `--ignore-scripts` if you need postinstall (e.g. Prisma) |
| `toolchain` | rust | `stable` | A `rust-toolchain.toml` in the repo takes precedence |

### The PR comment

- **When it's posted:** the first time a run has a failure.
- **After that:** it's updated on every run, including passing ones, which turns it into "✅ all N checks passed". So it's never stale.
- **The results table** comes from the Jobs API, so setup failures and cancellations show too.
- **Failure details:**

| Check | Shows |
|---|---|
| osv | Vulnerability table |
| zizmor | Findings by severity, with doc links and `file:line` |
| gitleaks | Rule, file, line and commit. Secrets are never shown |
| Your own checks | The end of the output, or the markdown they wrote to `$CI_REPORT_MD` |

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

**Install once, then one job per check.**
- Every check is a native PR check with its own log, and the checks run in parallel.
- Jobs run on separate machines, so `install` hands `node_modules` to them as a run artifact. It's tarred first because artifact uploads don't keep file permissions, which the executables in `node_modules/.bin` need. Only the root `node_modules` is passed, so npm workspaces with nested `node_modules` aren't supported yet.
- GitHub bills each job rounded up to a whole minute, so a run costs about one minute per job: about 8 for a typical Node repo, well inside GitHub Free's 2,000 private minutes a month. Keeping the Actions spending limit at $0 means going over pauses runs instead of charging.

**The repo owns *what* runs, and the shared workflows own *how*.** Callers list the same commands they run locally. The shared workflows handle setup, hardening and reporting.

**Hardening:**

| Measure | What it means |
|---|---|
| Pinned dependencies | Every action is pinned to a commit SHA. Every scanner binary is pinned by version and SHA256 |
| Least-privilege tokens | `permissions: {}` at the top, then per-job grants. Jobs that run repo code get `contents: read` only |
| Isolated write access | Only the report job can write to the PR, and it never checks out or runs repo code |
| No credentials left behind | `persist-credentials: false` on every checkout |
| No template injection | Inputs reach the shell only through `env` or action inputs, never inlined into scripts |
| No environment-file writes | Nothing writes to `GITHUB_ENV` or `GITHUB_PATH`. The scanner action passes its command as an output |
| No install scripts by default | `npm ci --ignore-scripts` stops install-time code from dependencies |
| Free reporting | Results go to the job logs, the summary and the PR comment instead of SARIF, which needs paid Advanced Security on private repos |
| Caller rule | Never use `pull_request_target` or `secrets: inherit` in callers |

**No duplicated logic.** Shared steps are composite actions in `actions/`: `plan`, `node-setup` (install and upload, or download), `rust-setup`, `run-check` and `scanners`. Workflows reference them, and each other, with GitHub's `$/` self-repository syntax ([July 2026](https://github.blog/changelog/2026-07-30-reference-same-repository-actions-with-self-repository-syntax/)), which resolves to this repo at the exact commit the caller pinned.

### Alternatives considered

| Alternative | Why not |
|---|---|
| All checks in one job | Cheaper in minutes, but one PR check and no graph. Reporting each check separately would need workarounds like the commit-status API |
| Workflow templates or required workflows | These need an organization `.github` repo or org rulesets. Personal accounts don't have them |
| Copy-paste per repo | The copies drift, and every repo gets its own update PRs for each action |
| Third-party comment and scanner actions | More supply-chain surface. `gh` and pinned binaries do the same job |
| Floating `@v1` tags | Tags can be moved, and zizmor's default policy rejects them |

## Development

Two workflows run on every PR, wired exactly like callers. They don't count against the minutes quota because the repo is public.
- `self-test.yml` runs actionlint, with only actionlint's two errors about `$/` ignored ([rhysd/actionlint#711](https://github.com/rhysd/actionlint/issues/711)), and parse-checks the composite actions, which actionlint doesn't read. Then it runs `node.yml` against `fixtures/node`.
- `self-test-rust.yml` runs `rust.yml` against `fixtures/rust`.
- Each runs security on this repo and posts its own report comment.

Dependabot keeps the action SHAs up to date, with a 14-day cooldown before adopting new releases. It can't update the scanner binaries:

| Tool | Where it's pinned |
|---|---|
| osv-scanner, zizmor, gitleaks | The `matrix` in `security.yml` |
| actionlint | `env` in `self-test.yml` |

When bumping them by hand, use releases at least 14 days old and record the SHA256 of the downloaded file.

**Releases** use immutable `vX.Y.Z` tags, recorded in [CHANGELOG.md](CHANGELOG.md). Callers pin to the release's commit SHA.

## License

[MIT](LICENSE)
