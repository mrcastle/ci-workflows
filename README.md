# ci-workflows

Reusable GitHub Actions workflows for PR checks. Each repo lists its own commands, and every command runs as its own job, so each one is a separate check on the PR with its own node in the workflow graph and its own log. Security scanning is built in, and one PR comment summarizes the results.

```
          ┌─▶ ci / lint ───────┐
ci / plan ┼─▶ ci / typecheck ──┤
          └─▶ ci / build ──────┤
security ───▶ osv ─────────────┼──▶ report / comment
         ───▶ zizmor ──────────┤
         ───▶ gitleaks ────────┘
```

| Workflow | What it does |
|---|---|
| `node.yml` / `rust.yml` | Turns the caller's `checks` list into one job per check. Each job sets up the toolchain, installs dependencies and runs one command |
| `security.yml` | One job per scanner: [OSV-Scanner](https://google.github.io/osv-scanner/) for vulnerable dependencies, [zizmor](https://docs.zizmor.sh) for workflow security, [gitleaks](https://github.com/gitleaks/gitleaks) for leaked secrets. It never installs or runs repo code |
| `report.yml` | Keeps one PR comment in sync with the run: a results table that links to each job, plus details for each failure |

## Usage

Add `.github/workflows/pr-checks.yml`:

```yaml
name: pr-checks

on:
  pull_request:
  schedule:
    - cron: "0 7 * * 1" # weekly: security only, to catch new CVEs in unchanged lockfiles
  workflow_dispatch:

permissions: {}

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  ci:
    if: github.event_name != 'schedule'
    permissions:
      contents: read
    uses: mrcastle/ci-workflows/.github/workflows/node.yml@<sha> # v1.0.0
    with:
      checks: |
        lint: npm run lint
        typecheck: npx tsc --noEmit
        test-unit: npm run test:unit
        build: npm run build

  security:
    permissions:
      contents: read
      actions: read
    uses: mrcastle/ci-workflows/.github/workflows/security.yml@<sha> # v1.0.0

  report:
    needs: [ci, security]
    if: ${{ always() && github.event_name == 'pull_request' }}
    permissions:
      actions: read
      pull-requests: write
    uses: mrcastle/ci-workflows/.github/workflows/report.yml@<sha> # v1.0.0
```

For Rust, swap the `ci` job's workflow:

```yaml
    uses: mrcastle/ci-workflows/.github/workflows/rust.yml@<sha> # v1.0.0
    with:
      checks: |
        fmt: cargo fmt --check
        clippy: cargo clippy --all-targets --locked -- -D warnings
        test-unit: cargo test --lib --locked
        test-integration: cargo test --test '*' --locked
```

A repo with both stacks can call `node.yml` and `rust.yml` as two jobs, and list both in `report`'s `needs`.

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

**One job per check.**
- Every check is a native PR check with its own log, and the checks run in parallel.
- Each job repeats checkout and install, so a run bills roughly one minute per check. That's about 8 minutes for a typical Node repo, comfortably inside GitHub Free's 2,000 private minutes a month.
- Keeping the Actions spending limit at $0 means going over pauses runs instead of charging.

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

**No duplicated logic.** Shared steps are composite actions in `actions/`: `plan`, `node-setup`, `rust-setup`, `run-check` and `scanners`. Workflows reference them, and each other, with GitHub's `$/` self-repository syntax ([July 2026](https://github.blog/changelog/2026-07-30-reference-same-repository-actions-with-self-repository-syntax/)), which resolves to this repo at the exact commit the caller pinned.

### Alternatives considered

| Alternative | Why not |
|---|---|
| All checks in one job | Cheaper in minutes, but one PR check and no graph. Reporting each check separately would need workarounds like the commit-status API |
| Workflow templates or required workflows | These need an organization `.github` repo or org rulesets. Personal accounts don't have them |
| Copy-paste per repo | The copies drift, and every repo gets its own update PRs for each action |
| Third-party comment and scanner actions | More supply-chain surface. `gh` and pinned binaries do the same job |
| Floating `@v1` tags | Tags can be moved, and zizmor's default policy rejects them |

## Development

`self-test.yml` runs on every PR, wired exactly like a caller. It doesn't count against the minutes quota because the repo is public. It does four things:
- Runs actionlint, with only actionlint's two errors about `$/` ignored ([rhysd/actionlint#711](https://github.com/rhysd/actionlint/issues/711)). It also parse-checks the composite actions, which actionlint doesn't read.
- Runs `node.yml` and `rust.yml` against the projects in `fixtures/`.
- Runs `security.yml` on this repo.
- Posts the report comment on the PR.

Dependabot keeps the action SHAs up to date, with a 14-day cooldown before adopting new releases. It can't update the scanner binaries:

| Tool | Where it's pinned |
|---|---|
| osv-scanner, zizmor, gitleaks | The `matrix` in `security.yml` |
| actionlint | `env` in `self-test.yml` |

When bumping them by hand, use releases at least 14 days old and record the SHA256 of the downloaded file.

**Releases** use immutable `vX.Y.Z` tags, recorded in [CHANGELOG.md](CHANGELOG.md). Callers pin to the release's commit SHA.

## License

[MIT](LICENSE)
