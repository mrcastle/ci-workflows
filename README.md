# ci-workflows

Reusable GitHub Actions workflows for PR checks: lint, tests by type, and security scanning. They're hardened by default and designed to fit the GitHub Free minutes budget.

| Workflow | Runs | Job time limit |
|---|---|---|
| `node.yml` | Installs once, then runs your checks | 10 min |
| `rust.yml` | Sets up the toolchain and build cache once, then runs your checks | 15 min |
| `security.yml` | [OSV-Scanner](https://google.github.io/osv-scanner/) for vulnerable dependencies, [zizmor](https://docs.zizmor.sh) for workflow security, [gitleaks](https://github.com/gitleaks/gitleaks) for leaked secrets | 5 min |

## Usage

Add `.github/workflows/pr-checks.yml` to a repo:

```yaml
name: pr-checks

on:
  pull_request:
  schedule:
    - cron: "0 7 * * 1" # weekly: catch new CVEs in unchanged lockfiles
  workflow_dispatch:

permissions: {}

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  node:
    if: github.event_name != 'schedule'
    permissions:
      contents: read
    uses: mrcastle/ci-workflows/.github/workflows/node.yml@<sha> # v1.0.0
    with:
      checks: |
        lint: npm run lint
        typecheck: npx tsc --noEmit
        test-unit: npm run test:unit
        test-integration: npm run test:integration
        build: npm run build

  security:
    permissions:
      contents: read
      actions: read
    uses: mrcastle/ci-workflows/.github/workflows/security.yml@<sha> # v1.0.0
```

For Rust, swap the `node` job for this:

```yaml
    uses: mrcastle/ci-workflows/.github/workflows/rust.yml@<sha> # v1.0.0
    with:
      checks: |
        fmt: cargo fmt --check
        clippy: cargo clippy --all-targets --locked -- -D warnings
        test-unit: cargo test --lib --locked
        test-integration: cargo test --test '*' --locked
```

Pin by commit SHA (zizmor's default policy requires it). Then add `.github/dependabot.yml`, and Dependabot will bump the SHA and the `# vX.Y.Z` comment together:

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule: { interval: weekly }
    cooldown: { default-days: 14 }
```

### How `checks` works

Each line is `name: command`. Blank lines and lines starting with `#` are skipped.

- Every check runs even if an earlier one fails, so a single run reports every failure.
- Each check gets its own collapsible log group and a row in the job summary.
- The job fails if any check failed.
- Commands run from `working-directory` with `bash -euo pipefail`, using the same commands you run locally.

### Inputs

| Input | Workflow | Default | Purpose |
|---|---|---|---|
| `checks` | node, rust | required | The checks to run, one `name: command` per line |
| `working-directory` | node, rust | `.` | Project root, for monorepos |
| `timeout-minutes` | node, rust | 10 / 15 | Job time limit |
| `node-version` | node | `lts/*` | Node version, ignored when `node-version-file` is set |
| `node-version-file` | node | none | Read the version from a file such as `.nvmrc` |
| `install-command` | node | `npm ci --ignore-scripts` | Dependency install. Remove `--ignore-scripts` if you need postinstall, e.g. Prisma |
| `toolchain` | rust | `stable` | A `rust-toolchain.toml` in the repo takes precedence |
| `scan-path` | security | `.` | Directory scanned for lockfiles |

### Security results and exceptions

- **OSV-Scanner:** fails on known vulnerabilities and puts a report in the job summary.
  - To accept a vulnerability, add it to `osv-scanner.toml` with a reason and an expiry:
    ```toml
    [[IgnoredVulns]]
    id = "GHSA-xxxx-xxxx-xxxx"
    ignoreUntil = 2027-01-01
    reason = "Dev-only dependency, not reachable"
    ```
  - Repos with no lockfiles pass with a notice.
- **zizmor:** findings appear as annotations on the PR. Configure it with `.github/zizmor.yml`.
- **gitleaks:** on a PR it scans only that PR's commits. On scheduled runs it scans the full history. Allowlist false positives in `.gitleaksignore`.

## Design

**The repo owns *what* runs, and the shared workflow owns *how*.** Each repo lists its own commands, so any CI failure can be reproduced locally. The shared workflows provide setup, hardening and reporting.

**Built for GitHub Free:**
- **One job per stack.** GitHub [bills each job rounded up to the minute](https://docs.github.com/en/billing/reference/actions-runner-pricing), and every job is a new runner that repeats checkout and install. Lint, typecheck and every test type share a single install.
- **PR-only checks.** There's no push-to-`main` run, because merged code was already tested on its PR. A weekly schedule re-runs only the security job.
- **No wasted runs.** `cancel-in-progress` stops superseded runs, and tight job time limits stop a hung job from using up the monthly minutes.
- **Typical cost:** about 2–3 billed minutes per PR run.

**Hardening:**
- **Pinned dependencies.** Every action is pinned to a commit SHA, and the tool binaries are pinned by version and SHA256.
- **Least-privilege token.** `permissions: {}` at the top, then minimal grants per job.
- **No credentials left behind.** `persist-credentials: false` on every checkout.
- **No inline inputs.** Inputs reach the shell only through `env`, never inlined into scripts, which avoids template injection.
- **No install scripts by default.** `npm ci --ignore-scripts` stops install-time code from dependencies.
- **Free reporting.** Results go to annotations and the job summary instead of SARIF, which needs paid Advanced Security on private repos.
- **Never use `pull_request_target` or `secrets: inherit` in callers.**

### Alternatives considered

| Alternative | Why not |
|---|---|
| One job per tool | 2–3× the billed minutes, because every job repeats checkout and install |
| Workflow templates or required workflows | These need an organization `.github` repo or org rulesets. Personal accounts don't have them |
| Copy-paste per repo plus Renovate | The copies drift, and every repo gets its own update PRs for each action |
| A fixed input per check type | More rigid and verbose than one `checks` list |
| Floating `@v1` tags | Tags can be moved, and zizmor's default policy rejects them |
| Shared composite action for the checks loop | See below |

**About the checks loop:** `node.yml` and `rust.yml` contain the same 15-line loop, and `self-test.yml` fails if the two copies differ.

- **Why not share it as a composite action?** A composite action can't be referenced from inside a reusable workflow at the same commit unless you use GitHub's `$/` syntax ([July 2026](https://github.blog/changelog/2026-07-30-reference-same-repository-actions-with-self-repository-syntax/)).
- **Why not use `$/` now?** actionlint can't parse `$/` yet ([rhysd/actionlint#711](https://github.com/rhysd/actionlint/issues/711)).

## Development

`self-test.yml` runs on every PR. It doesn't count against the minutes quota because the repo is public. It does three things:
- Runs actionlint.
- Runs `node.yml` and `rust.yml` against the projects in `fixtures/`.
- Runs `security.yml` on this repo.

Dependabot keeps action SHAs up to date, with a 14-day cooldown before adopting new releases. It can't update the tool binaries, so bump those by hand. They're pinned in:

| Tool | Where |
|---|---|
| osv-scanner | `env` in `security.yml` |
| gitleaks | `env` in `security.yml` |
| actionlint | `env` in `self-test.yml` |
| zizmor | the `version:` input in `security.yml` |

When bumping, use releases at least 14 days old and copy the SHA256 from the release's checksums file.

**Releases** use immutable `vX.Y.Z` tags, recorded in [CHANGELOG.md](CHANGELOG.md). Callers pin to the release's commit SHA.

## License

[MIT](LICENSE)
