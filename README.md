# ci-workflows

Reusable GitHub Actions CI for Node (npm) and Rust repos. A repo calls one workflow and passes in its own commands. The workflow runs each check as its own step, scans for security problems, and keeps one PR comment up to date with the results.

```
node.yml  checks:  checkout → osv → zizmor → setup-node → install → lint → typecheck → test → build
rust.yml  checks:  checkout → osv → zizmor → toolchain → rust-cache → fmt → clippy → test
          report:  update the PR comment
```

- Every check runs even if an earlier one failed, so one run shows every failure. If setup or install fails, the checks after it show as skipped.
- The scanners run first, before any repo or dependency code runs on the machine.
- [OSV-Scanner](https://google.github.io/osv-scanner/) checks dependencies for known vulnerabilities.
- [zizmor](https://docs.zizmor.sh) checks the repo's GitHub Actions workflows for security problems.

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
    uses: mrcastle/ci-workflows/.github/workflows/node.yml@<sha>
    with:
      lint: npm run lint
      typecheck: npx tsc --noEmit
      test: npm test
      build: npm run build
```

For Rust, call `rust.yml` instead. Its checks have defaults, so `with:` is optional.

- **Commands** run from `working-directory` with `bash -euo pipefail`. Leave a check out, or set it to `""`, to skip it.
- **Pin by commit SHA.** zizmor requires it. Dependabot (`package-ecosystem: github-actions`) keeps the pin current.
- **Call each workflow once per workflow file.** The PR comment is keyed on the workflow's name, so two calls in one file would overwrite each other's comment. Use a separate file per project in a monorepo.
- **Don't use `pull_request_target` or `secrets: inherit`** in the caller.
- **Require the `checks` job** in branch protection or a ruleset. Its check name is `<caller job> / checks`, for example `node / checks`. Don't require `report`. It only posts the PR comment.

### Inputs

| Input | Workflow | Default | Purpose |
|---|---|---|---|
| `lint`, `typecheck`, `test`, `build` | node | empty (skipped) | Commands for each check |
| `install` | node | `npm ci --ignore-scripts --no-audit --no-fund` | Needs a `package-lock.json`; pnpm and yarn aren't set up. Drop `--ignore-scripts` if you need postinstall (e.g. Prisma) |
| `node-version` | node | `lts/*` | Ignored when `node-version-file` is set |
| `node-version-file` | node | none | Read the version from a file such as `.nvmrc` |
| `fmt` | rust | `cargo fmt --check` | |
| `clippy` | rust | `cargo clippy --all-targets --locked -- -D warnings` | |
| `test` | rust | `cargo test --locked` | |
| `toolchain` | rust | `stable` | Ignored when a `rust-toolchain.toml` pins one |
| `working-directory` | both | `.` | Project root, for monorepos. The security scans always cover the whole repo |
| `timeout-minutes` | both | 15 / 20 | Time limit for the checks job |

### The PR comment

- Posted the first time a run has a failure, then updated on every run, so it always reflects the latest commit.
- Failure details show the findings table for osv and zizmor, and the end of the output for other checks, each capped in size. A command can write markdown to `$CI_REPORT_MD` to replace its details.

### Security exceptions

- **OSV:** add the vulnerability to `osv-scanner.toml` with a reason and an expiry:

  ```toml
  [[IgnoredVulns]]
  id = "GHSA-xxxx-xxxx-xxxx"
  ignoreUntil = 2027-01-01
  reason = "Dev-only dependency, not reachable"
  ```

- **zizmor:** configure it in `.github/zizmor.yml`.

## Security

- Actions are pinned by commit SHA, and the scanner binaries by version and SHA256.
- Each job gets only the permissions it needs. Only `report` can write to the PR, and it never checks out or runs repo code.
- `persist-credentials: false` on every checkout.
- Inputs reach the shell only through `env`.

## Development

| Path | What it is |
|---|---|
| `.github/workflows/node.yml`, `rust.yml` | The reusable workflows |
| `actions/check` | Runs one check and records its result |
| `actions/security` | Runs OSV-Scanner and zizmor |
| `actions/results` | Hands the results to the report job |
| `actions/comment` | Updates the PR comment |
| `test-fixtures/` | Minimal projects for the self-tests |

The actions are referenced with GitHub's `$/` self-repository syntax, so they run from the same commit the caller pinned.

On every PR, `self-test.yml` runs actionlint, parse-checks the composite actions, and runs `node.yml` against `test-fixtures/node`. `self-test-rust.yml` runs `rust.yml` against `test-fixtures/rust`.

Dependabot can't update the scanner and actionlint binaries. Bump them by hand in `actions/security/action.yml` and `self-test.yml`, and record the SHA256 of each download.

## License

[MIT](LICENSE)
