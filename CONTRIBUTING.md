# Contributing

Thanks for taking the time to improve the `community-artifacts/n8n-helm` Helm chart. This document is the short version of [AGENTS.md](AGENTS.md) — read that file too if you plan to make non-trivial changes.

## Ground rules

- This chart is **independent**, not a fork. Do not introduce references to other n8n Helm charts in code, docs, or commit messages.
- Changes must be **additive**. Deprecate before removing; do not rename existing values keys.
- Defaults stay **safe**. Anything that pulls in a dependency (queue mode, KEDA, S3, ingress, autoscaling) must default to off, and the chart must render with zero `--set` flags.
- Every templated resource has matching unit tests and snapshots. Untested template changes will be rejected.

## Branch strategy

```
   dev/<topic>     ──PR──→
   feat/<topic>    ──PR──→
   fix/<topic>     ──PR──→  develop  ──PR──→  main  ──→  Release Charts CI
   hotfix/<topic>  ──PR──→     │                │      (publish to gh-pages)
                               ▼                ▼
                         Validate Chart    Release Charts
                          (CI on push +    (CI on push)
                           PR-to-main)
```

- **`main` is protected** and is the source of releases. Direct pushes are blocked for everyone; the only way `main` advances is a merged PR from `develop`. Every push to `main` triggers [`release.yml`](.github/workflows/release.yml), which packages the chart and publishes it to the `gh-pages` Helm repo.
- **`develop` is soft-protected.** Required Validate Chart status checks must be green before a PR merges into `develop`; force-push and deletion are blocked. PR-required is intentionally **OFF** so the [`version-bump.yml`](.github/workflows/version-bump.yml) / [`scheduled-release.yml`](.github/workflows/scheduled-release.yml) / [`hotfix-release.yml`](.github/workflows/hotfix-release.yml) workflows can push their bump commits — GitHub silently drops every "let github-actions[bot] bypass PR-required" mechanism on Free org plans (both legacy `restrictions.apps` and Rulesets `bypass_actors`). "All human work goes through a PR from a topic branch" is therefore a **social convention**, not a technical block. The real release gate sits on `main`, which IS hard-protected.
- **Topic branches feeding `develop`** — chart work starts on a short-lived branch named after its kind. Validate Chart runs **the moment you open a PR from the branch into `develop`** (and re-runs on every subsequent push while the PR is open, via the `synchronize` event). Pre-PR commits do not trigger CI on their own — run the same checks locally via `helm lint` + `helm unittest` + `./scripts/run_scenarios.sh` while you iterate. Pick the prefix that matches the change:
  - **`dev/<topic>`** — general / refactor / docs / chore work (the default).
  - **`feat/<topic>`** — new functionality (Conventional `feat:` commits → MINOR bump under the manual path).
  - **`fix/<topic>`** — regular non-urgent bug fixes. Ships in the next nightly cron release alongside whatever else is on `develop`.
  - **`hotfix/<topic>`** — urgent bug fixes. When the squashed merge into `develop` lands with a `hotfix:` (or `[HOTFIX]`) commit subject, `hotfix-release.yml` opens the release PR immediately instead of waiting for the cron; see [Release process](#release-process) below.
- **`gh-pages`** is managed by CI only — never `git push` to it manually.

Required GitHub branch-protection settings (set once by the maintainer, under **Settings → Branches → Add rule**):

| Branch | Required status checks (all from Validate Chart) | Other rules |
|--------|---------------------------------------------------|-------------|
| `main` | `helm lint`, `helm-unittest (773 assertions, 219 snapshots)`, `Render scenario matrix (helm template)`, `values.schema.json well-formed`, `kubeconform (validate rendered manifests vs Kubernetes API)` | Require PR (no direct push); 1 required approving review; require linear history; no force push; no deletion |
| `develop` | same as main | **No** PR-required (soft protection — see note below); no force push; no deletion |

> **Why no PR-required on `develop`?** The bump workflows (`version-bump.yml`, `scheduled-release.yml`, `hotfix-release.yml`) push commits onto `develop` using `GITHUB_TOKEN`. On paid GitHub plans you'd add `github-actions[bot]` to "Allow specified actors to bypass required PRs" and keep PR-required ON. On Free org plans GitHub silently drops every available bypass mechanism (legacy `restrictions.apps`, modern Rulesets `bypass_actors` of type `Integration`), so the choice is binary: either humans get blocked along with the bot, or humans can push along with the bot. The script picks the second so the release flow keeps working. The release gate that matters — `main` — is fully PR-required + reviewed + status-checked, so a bad direct-push to `develop` can't reach `main` without going through the gate.

The whole config is reproducible: [`scripts/configure_github.sh`](scripts/configure_github.sh) (maintainer-local, not tracked) applies all of this via `gh api`. Run it on a fresh clone or after a settings drift.

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

- **Branch off `develop`, not `main`.** Pick a prefix based on the change: `dev/<short-topic>` for general / refactor / chore work, `feat/<short-topic>` for new functionality, `fix/<short-topic>` for regular bug fixes, `hotfix/<short-topic>` for urgent bug fixes that should ship immediately. Examples: `dev/runner-grace-period`, `feat/keda-scaler`, `fix/probe-timeout-default`, `hotfix/runner-image-tag-typo`. CI engages **when you open the PR** with `develop` as the base (and re-runs on every push that updates the PR head); pre-PR commits don't burn runner minutes — iterate locally with `helm lint` / `helm unittest` / `./scripts/run_scenarios.sh`.
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

1. **Work on `dev/<topic>` / `feat/<topic>` / `fix/<topic>` / `hotfix/<topic>`.** Push commits with [Conventional Commits](https://www.conventionalcommits.org/) prefixes (`feat:`, `fix:`, `hotfix:`, `chore:`, …) — the version-bump workflow uses these to pick the correct bump level. Validate Chart fires when you open the PR (not on bare topic-branch pushes).
2. **PR `<branch>` → `develop`.** Once Validate Chart is green and the PR is reviewed, merge with squash. Validate Chart runs once more against the merge commit on `develop`. If the squashed commit subject starts with `hotfix:` (or contains `[HOTFIX]`), the **hotfix release** path fires automatically — skip step 3.
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
