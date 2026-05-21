# Contributing

Thanks for taking the time to improve the `community-artifacts/n8n-helm` Helm chart. This document is the short version of [AGENTS.md](AGENTS.md) — read that file too if you plan to make non-trivial changes.

## Ground rules

- This chart is **independent**, not a fork. Do not introduce references to other n8n Helm charts in code, docs, or commit messages.
- Changes must be **additive**. Deprecate before removing; do not rename existing values keys.
- Defaults stay **safe**. Anything that pulls in a dependency (queue mode, KEDA, S3, ingress, autoscaling) must default to off, and the chart must render with zero `--set` flags.
- Every templated resource has matching unit tests and snapshots. Untested template changes will be rejected.

## Branch strategy

```
   dev/<topic>  ──PR──→  develop  ──PR──→  main  ──→  Release Charts CI
   dev/<topic>  ──PR──→                                (publish to gh-pages)
                            │                │
                            ▼                ▼
                       Validate Chart   Release Charts
                       (CI on push +    (CI on push)
                        PR-to-main)
```

- **`main` is protected** and is the source of releases. Direct pushes are blocked for everyone; the only way `main` advances is a merged PR from `develop`. Every push to `main` triggers [`release.yml`](.github/workflows/release.yml), which packages the chart and publishes it to the `gh-pages` Helm repo.
- **`develop` is protected and PR-only.** After the initial push that creates the branch, direct pushes are blocked for humans. The only allowed exception is the [`version-bump.yml`](.github/workflows/version-bump.yml) workflow, which uses `GITHUB_TOKEN` to push the auto-computed chart-version bump back onto `develop` while a release PR is open — see the bypass row in the branch-protection table below.
- **`dev/<topic>`** branches are short-lived feature / fix branches. All chart changes start here. Open a PR from `dev/<topic>` → `develop` once the work is ready; CI runs Validate Chart on every push to the branch and on the PR itself.
- **`gh-pages`** is managed by CI only — never `git push` to it manually.

Required GitHub branch-protection settings (set once by the maintainer, under **Settings → Branches → Add rule**):

| Branch | Required status checks (all from Validate Chart) | Other rules |
|--------|---------------------------------------------------|-------------|
| `main` | `helm lint`, `helm-unittest`, `Render scenario matrix`, `values.schema.json well-formed`, `kubeconform` | Require PR (no direct push); require approval; require linear history; no force push; no deletion |
| `develop` | `helm lint`, `helm-unittest`, `Render scenario matrix`, `values.schema.json well-formed` | Require PR (no direct push); **allow specified actors to bypass required PRs: `github-actions[bot]`** (so the `version-bump.yml` workflow can push the bump commit back onto the PR head); no force push; no deletion |

> **Why the bypass on `develop`?** The release flow opens a PR `develop` → `main`. The `version-bump.yml` workflow detects that PR, computes the next chart version from the conventional-commit log, and pushes a bump commit onto `develop` so the PR carries the right version. Branch protection without the `github-actions[bot]` bypass would block that automated push and require either a second PR (bot → develop) per release, or a manual bump. Listing the GitHub Actions bot in the bypass set keeps the release flow to a single PR while still blocking all human direct pushes.

See [TESTING.md](TESTING.md) for the full list of CI jobs and what each one verifies.

## Local setup

You need:

- Helm `>= 3.14`
- The [`helm-unittest`](https://github.com/helm-unittest/helm-unittest) plugin
- Network access to pull the `cloudpirates/postgres` (OCI), `valkey`, and `minio` subcharts on the first `helm dependency update`

```bash
helm plugin install https://github.com/helm-unittest/helm-unittest.git
helm dependency update charts/n8n
```

## The development loop

```bash
# 1. Static analysis
helm lint charts/n8n

# 2. Render defaults and skim the diff
helm template testn8n charts/n8n | less

# 3. Run the full unit-test suite
helm unittest --strict --file 'unittests/**/*.yaml' charts/n8n

# 4. Render every scenario in tests/scenarios/ (this is what CI runs)
./scripts/run_scenarios.sh

# 5. (Optional) install selected scenarios against minikube and watch them roll out
export KUBECONFIG=/path/to/minikube.yaml
INSTALL_SCENARIOS="01 02" ./scripts/run_scenarios.sh
```

If your change is intentionally a rendered-output change, regenerate snapshots and inspect the diff:

```bash
helm unittest --strict -u --file 'unittests/**/*.yaml' charts/n8n
git diff charts/n8n/unittests/__snapshot__/
```

For the complete checklist of what must pass before opening a PR — including the scenario matrix and the schema cross-check — see [TESTING.md](TESTING.md).

## Pull requests

- **Branch off `develop`, not `main`.** Use `dev/<short-topic>` as the branch name (e.g. `dev/runner-grace-period`). Push to your branch triggers Validate Chart; open the PR with `develop` as the base.
- Maintainer-only: open a PR from `develop` → `main` once the desired set of changes have landed on `develop` and the latest Validate Chart run is green. Opening (or syncing) that PR triggers the **Bump chart version** workflow, which:
  - Reads the conventional-commit log since the last released tag (`n8n-x.y.z`).
  - Picks the bump level (`feat` → MINOR, anything else → PATCH; `BREAKING CHANGE` is capped at MINOR per the chart-MAJOR-pinned-to-n8n-MAJOR rule).
  - Updates `charts/n8n/Chart.yaml#version`, regenerates the `artifacthub.io/changes` annotation, and inserts a `## <new-version> (unreleased)` stub heading at the top of `charts/n8n/RELEASE-NOTES.md`.
  - Pushes the result back onto the PR head (the `develop` branch) with `[skip ci]` so Validate Chart only re-runs once everything is in place.
  - Comments on the PR with the bump summary.
- The maintainer's job before merging the release PR is to replace the `<!-- TODO -->` block in `RELEASE-NOTES.md` with the real prose changelog and sanity-check the auto-generated `artifacthub.io/changes` descriptions. On merge of `develop` → `main`, Release Charts on `main` packages and publishes the new chart version.
- One PR per logical change. A `taskRunners` tweak and an ingress refactor do not belong in the same PR.
- The chart version is independent SemVer (starting at `2.0.0`). The chart's MAJOR component tracks n8n's MAJOR. MINOR and PATCH bumps are at maintainer discretion when chart-side behavior changes. `Chart.yaml#version` and `Chart.yaml#appVersion` are independent; either can move without the other.
- **Whenever you bump `appVersion`,** read the n8n release notes for every version between the previous and the new `appVersion`, and apply any hosting-relevant changes (new env vars, deprecations, port or endpoint changes, default-value shifts) in the same PR. The full procedure and the grep recipe are in [AGENTS.md](AGENTS.md#reading-the-n8n-changelog-on-every-binary-bump).
- Add a `RELEASE-NOTES.md` entry under a new `## <version>` heading. Bullet style: `**Added** / **Changed** / **Fixed** / **Removed**`. Always note which `appVersion` ships with the bundle; if `appVersion` moved, summarize what the n8n-changelog review surfaced.
- **Replace the `artifacthub.io/changes` annotation block in `charts/n8n/Chart.yaml`** with entries describing the changes since the previous version. Artifact Hub renders this as the per-version changelog on the chart's page; annotations are baked into the tgz at release time, so they cannot be backfilled. Valid `kind` values: `added`, `changed`, `deprecated`, `removed`, `fixed`, `security`. Keep the entries roughly parallel to the `RELEASE-NOTES.md` bullets but one line each — Artifact Hub shows the `description` inline. Spec: <https://artifacthub.io/docs/topics/annotations/helm/>.
- If your change adds or modifies values keys: update `values.yaml` (with a `# --` comment, which is the source of the values table in `charts/n8n/README.md`), update `values.schema.json`, and update or add unit tests.
- Squash before merging; PR title becomes the merge commit message.

### Commit message style

- Imperative mood, short subject line (≤ 72 chars).
- No AI co-author trailers (`Co-Authored-By: Claude …` or similar). The commit author is the human running the change.
- Reference issues with `Refs #N` / `Fixes #N` in the body when applicable.

## Release process

Releases are fully automated; the maintainer's only manual touchpoint is the changelog prose. Two paths reach `main`, both end at the Release Charts workflow:

### Automatic (nightly cron) — default path

[`.github/workflows/scheduled-release.yml`](.github/workflows/scheduled-release.yml) runs at `02:00 UTC` daily. It:

1. Skips if `develop` has no commits ahead of `main`.
2. Runs [`scripts/bumpy_decide.sh`](scripts/bumpy_decide.sh), which implements the **Bumpy** quantity-based SemVer strategy from [`improvements/bumpy.md`](improvements/bumpy.md). The script measures added / removed lines under `charts/n8n/` between the last `n8n-X.0.0` baseline and `HEAD`, computes net change% and churn%, and picks:
   - **PATCH** — net < 5%, or refactor case (churn > 10% AND net < 5%).
   - **MINOR** — net 5–15%, or a `BREAKING CHANGE:` marker is present (raised from a raw MAJOR), or net ≥ 15% (which would be MAJOR but is **capped at MINOR** here — chart MAJOR is pinned to n8n's MAJOR; see "Branch strategy" above).
   - Generated artifacts (`__snapshot__/`, `Chart.lock`, vendored `charts/`) are excluded from line counts.
3. Calls `./scripts/bump_chart_version.sh --level <patch|minor>` to bump `Chart.yaml`, regenerate `artifacthub.io/changes`, and insert the `RELEASE-NOTES.md` stub.
4. Commits the bump on `develop` with `[skip ci]`.
5. Opens (or re-uses) the PR `develop` → `main`, labels it `bot/release`, and enables auto-merge with the **merge commit** strategy (preserving `develop`'s history).
6. Validate Chart runs on the PR. When it goes green and any required reviews are in place, auto-merge lands the PR on `main`, which triggers Release Charts to package, sign, and publish to `gh-pages`.

You can replace the `<!-- TODO -->` marker in `RELEASE-NOTES.md` with prose changelog any time before auto-merge fires. The per-PR `version-bump.yml` workflow recognizes the `bot/release` label and stays out of the way (otherwise it would double-bump).

### Hotfix — immediate release on `hotfix:` commits

[`.github/workflows/hotfix-release.yml`](.github/workflows/hotfix-release.yml) triggers on every push to `develop`. If the tip commit subject matches a hotfix marker — `hotfix:`, `hotfix(<scope>):`, `fix!:` with `hotfix` in the body, or a literal `[HOTFIX]` tag — the same Bumpy + bump + PR + auto-merge plumbing runs immediately instead of waiting for 02:00 UTC. The opened PR is titled `Hotfix X.Y.Z` and carries both the `bot/release` and `hotfix` labels (the latter for human visibility — set up branch-protection required reviews on `main` if you want a human signoff on hotfixes).

Non-hotfix pushes to `develop` are ignored by this workflow (Bumpy still runs nightly via the cron path).

### Manual — for ad-hoc / urgent releases

The full path of a manual release:

1. **Work on `dev/<topic>`.** Push commits with [Conventional Commits](https://www.conventionalcommits.org/) prefixes (`feat:`, `fix:`, `chore:`, …) — the version-bump workflow uses these to pick the correct bump level. Validate Chart runs on every push.
2. **PR `dev/<topic>` → `develop`.** Once Validate Chart is green and the PR is reviewed, merge with squash. Validate Chart runs once more against the merge commit on `develop`.
3. **PR `develop` → `main`** when `develop` is release-ready.
   - Opening (or syncing) this PR triggers the **Bump chart version** workflow. It computes the next chart version, updates `Chart.yaml`, regenerates `artifacthub.io/changes`, inserts a `RELEASE-NOTES.md` stub heading, and pushes those changes onto `develop` with `[skip ci]`.
   - You then fill in the real RELEASE-NOTES prose under the new heading and review the auto-generated `artifacthub.io/changes` entries. Commit and push (this re-triggers Validate Chart).
   - Validate Chart runs against the merge target (`main`); the PR can be merged only after green. Use a **merge commit** here (not squash) so `develop`'s history is preserved.
4. **Merge to `main`** triggers [`release.yml`](.github/workflows/release.yml), which runs `chart-releaser-action`:
   - Packages `charts/n8n` if `Chart.yaml#version` is new.
   - Signs the `.tgz` with the maintainer's GPG key (RSA, see release.yml).
   - Publishes `.tgz` + `.tgz.prov` + updated `index.yaml` to `gh-pages`.
   - Creates a tagged GitHub Release.

You never run `helm package`, `helm template ... > release.yaml`, or push to `gh-pages` manually. If GitHub Pages is not yet enabled on the repo, enable it under **Settings → Pages → Source: `gh-pages`** before the first release.

### Bumping manually

If you need to bypass the automation (e.g., to test the bump script locally before opening the release PR), run:

```bash
./scripts/bump_chart_version.sh
```

The script is idempotent — running it twice without new commits is a no-op. It prints the resolved `BUMP_LEVEL`, `PREVIOUS_VERSION`, and `NEW_VERSION` to stdout.

## Filing issues

Useful issue reports include:

- Chart version (`Chart.yaml#version`).
- `helm version --short`.
- Kubernetes server version.
- The `values.yaml` (or `--set` flags) that reproduce the problem, with secrets redacted.
- Either the `helm template` output that's wrong or the live cluster behaviour you observed.

## License

By contributing you agree that your contributions will be licensed under the [Apache License 2.0](charts/n8n/LICENSE).
