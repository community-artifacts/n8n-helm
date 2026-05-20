# Contributing

Thanks for taking the time to improve the `community-artifacts/n8n-helm` Helm chart. This document is the short version of [AGENTS.md](AGENTS.md) — read that file too if you plan to make non-trivial changes.

## Ground rules

- This chart is **independent**, not a fork. Do not introduce references to other n8n Helm charts in code, docs, or commit messages.
- Changes must be **additive**. Deprecate before removing; do not rename existing values keys.
- Defaults stay **safe**. Anything that pulls in a dependency (queue mode, KEDA, S3, ingress, autoscaling) must default to off, and the chart must render with zero `--set` flags.
- Every templated resource has matching unit tests and snapshots. Untested template changes will be rejected.

## Branch strategy

```
   dev/<topic>  ──┐
                  ├──→  develop  ──PR──→  main  ──→  Release Charts CI
   dev/<topic>  ──┘                                  (publish to gh-pages)
        │                │                │
        ▼                ▼                ▼
   Validate Chart   Validate Chart   Release Charts
   (CI on push)     (CI on push)     (CI on push)
                    (CI on PR-to-main)
```

- **`main` is protected** and is the source of releases. Direct pushes are blocked; the only way `main` advances is a merged PR from `develop`. Every push to `main` triggers [`release.yml`](.github/workflows/release.yml), which packages the chart and publishes it to the `gh-pages` Helm repo.
- **`develop` is the integration branch.** It is also protected: every push and every PR must show a green **Validate Chart** run before merge. Push directly to `develop` only for small, low-risk maintenance changes; for anything user-visible, open a PR from a `dev/<topic>` branch.
- **`dev/<topic>`** branches are short-lived feature / fix branches. They trigger the same **Validate Chart** workflow on every push.
- **`gh-pages`** is managed by CI only — never `git push` to it manually.

Required GitHub branch-protection settings (set once by the maintainer):

| Branch | Required status checks (all from Validate Chart) | Other rules |
|--------|---------------------------------------------------|-------------|
| `main` | `helm lint`, `helm-unittest`, `Render scenario matrix`, `values.schema.json well-formed`, `kubeconform` | Require PR from `develop`; require linear history; require approval; no force push; no deletion |
| `develop` | `helm lint`, `helm-unittest`, `Render scenario matrix`, `values.schema.json well-formed` | Require PR for non-maintainer commits; no force push; no deletion |

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
- Maintainer-only: open a PR from `develop` → `main` once the desired set of changes have landed on `develop` and the latest Validate Chart run is green. The PR is also gated on Validate Chart against `main` (same jobs run once more). On merge, Release Charts on `main` packages and publishes the new chart version.
- One PR per logical change. A `taskRunners` tweak and an ingress refactor do not belong in the same PR.
- The chart version is independent SemVer (starting at `2.0.0`). The chart's MAJOR component tracks n8n's MAJOR. MINOR and PATCH bumps are at maintainer discretion when chart-side behavior changes. `Chart.yaml#version` and `Chart.yaml#appVersion` are independent; either can move without the other.
- **Whenever you bump `appVersion`,** read the n8n release notes for every version between the previous and the new `appVersion`, and apply any hosting-relevant changes (new env vars, deprecations, port or endpoint changes, default-value shifts) in the same PR. The full procedure and the grep recipe are in [AGENTS.md](AGENTS.md#reading-the-n8n-changelog-on-every-binary-bump).
- Add a `RELEASE-NOTES.md` entry under a new `## <version>` heading. Bullet style: `**Added** / **Changed** / **Fixed** / **Removed**`. Always note which `appVersion` ships with the bundle; if `appVersion` moved, summarize what the n8n-changelog audit surfaced.
- **Replace the `artifacthub.io/changes` annotation block in `charts/n8n/Chart.yaml`** with entries describing the changes since the previous version. Artifact Hub renders this as the per-version changelog on the chart's page; annotations are baked into the tgz at release time, so they cannot be backfilled. Valid `kind` values: `added`, `changed`, `deprecated`, `removed`, `fixed`, `security`. Keep the entries roughly parallel to the `RELEASE-NOTES.md` bullets but one line each — Artifact Hub shows the `description` inline. Spec: <https://artifacthub.io/docs/topics/annotations/helm/>.
- If your change adds or modifies values keys: update `values.yaml` (with a `# --` comment, which is the source of the values table in `charts/n8n/README.md`), update `values.schema.json`, and update or add unit tests.
- Squash before merging; PR title becomes the merge commit message.

### Commit message style

- Imperative mood, short subject line (≤ 72 chars).
- No AI co-author trailers (`Co-Authored-By: Claude …` or similar). The commit author is the human running the change.
- Reference issues with `Refs #N` / `Fixes #N` in the body when applicable.

## Release process

Releases are automated, but only `main` triggers them. The full path of a release:

1. **Work on `dev/<topic>`** — push commits, watch the Validate Chart run on each push.
2. **PR `dev/<topic>` → `develop`** — once Validate Chart is green and the PR is reviewed, merge with squash. Validate Chart runs once more against the merge commit on `develop`.
3. **PR `develop` → `main`** — when `develop` is in a release-shaped state (Chart.yaml version bumped, RELEASE-NOTES entry added, `artifacthub.io/changes` updated), open this PR. Validate Chart runs against the merge target (`main`); the PR can be merged only after green. Use a **merge commit** here (not squash) so `develop`'s history is preserved.
4. **Merge to `main`** — triggers [`release.yml`](.github/workflows/release.yml), which runs `chart-releaser-action`:
   - Packages `charts/n8n` if `Chart.yaml#version` is new.
   - Signs the `.tgz` with the maintainer's GPG key (RSA, see release.yml).
   - Publishes `.tgz` + `.tgz.prov` + updated `index.yaml` to `gh-pages`.
   - Creates a tagged GitHub Release.

You never run `helm package` or push to `gh-pages` manually. If GitHub Pages is not yet enabled on the repo, enable it under **Settings → Pages → Source: `gh-pages`** before the first release.

## Filing issues

Useful issue reports include:

- Chart version (`Chart.yaml#version`).
- `helm version --short`.
- Kubernetes server version.
- The `values.yaml` (or `--set` flags) that reproduce the problem, with secrets redacted.
- Either the `helm template` output that's wrong or the live cluster behaviour you observed.

## License

By contributing you agree that your contributions will be licensed under the [Apache License 2.0](charts/n8n/LICENSE).
