# Testing the n8n Helm chart

How contributors validate chart changes locally, and what the CI pipeline
enforces on every push / PR.

> **Branch strategy in one paragraph.** All work happens on topic
> branches named `dev/<topic>` (general), `feat/<topic>` (new
> functionality), `fix/<topic>` (regular bug fixes), or
> `hotfix/<topic>` (urgent bug fixes — fast-tracked release path). PR
> `<topic-branch>` → `develop` to integrate. PR
> `develop` → `main` to release — opening that PR triggers the
> [version-bump workflow](.github/workflows/version-bump.yml) which
> computes the next chart version from the conventional-commit log,
> updates `Chart.yaml`, regenerates `artifacthub.io/changes`, and inserts
> a `RELEASE-NOTES.md` stub on `develop`. Both `develop` and `main` are
> branch-protected: **direct pushes are blocked for humans**. The only
> automated exception is the version-bump bot's push back to `develop`,
> allowed via the `github-actions[bot]` bypass in develop's protection
> rule. See [CONTRIBUTING.md](CONTRIBUTING.md#branch-strategy) for the
> full picture and the exact branch-protection settings.

---

## Test layers

Every change must pass all five layers before the chart is released.
Layer-N depends on layer-(N-1) succeeding; CI runs them in this order.

| # | Layer | Tool | Where it runs | Time |
|---|-------|------|---------------|------|
| 1 | Lint | `helm lint` | local + CI | ~2 s |
| 2 | Schema | `jq` + `values.yaml` cross-check | local + CI | ~1 s |
| 3 | Unit tests | [`helm-unittest`](https://github.com/helm-unittest/helm-unittest) | local + CI | ~15 s |
| 4 | Scenario matrix | `helm template` over `tests/scenarios/*.values.yaml` | local + CI | ~10 s |
| 5 | Kubernetes validation | `kubeconform` + minikube install | CI (push / merged PR) | ~5 min |

If layer 1–4 fails on `develop`, the next merge to `main` is blocked by
GitHub branch protection. Layer 5 runs on every push but is permitted to
flake on slow runners — see [Minikube notes](#minikube-notes) below.

---

## Local setup (one-time)

```bash
# Helm 3.14+
helm version

# Plugins
helm plugin install https://github.com/helm-unittest/helm-unittest.git

# Subcharts (downloads cloudpirates/postgres, valkey/valkey, minio/minio)
helm repo add valkey https://valkey.io/valkey-helm
helm repo add minio  https://charts.min.io/
helm repo update
helm dependency update charts/n8n
```

For the cluster layer:

```bash
# 3-node minikube with multi-node storage provisioner
minikube start --nodes 3 --memory 6g --cpus 2
minikube addons enable storage-provisioner-rancher
minikube addons enable default-storageclass

# This repo's local-only kubeconfig
export KUBECONFIG=/path/to/minikube.yaml
```

---

## Running each layer locally

### 1. Lint
```bash
helm lint charts/n8n
```

### 2. Schema sanity check
```bash
jq empty charts/n8n/values.schema.json
```

For a deeper check (every top-level key in `values.yaml` is declared in the
schema), copy the `schema` job's script block from
[`.github/workflows/validate.yml`](.github/workflows/validate.yml) and run
it locally; CI will catch it anyway.

### 3. Unit tests
```bash
helm unittest --strict -f 'unittests/*.yaml' charts/n8n
```

If your change is an intentional rendered-output change, regenerate
snapshots with `-u`:

```bash
helm unittest --strict -u -f 'unittests/*.yaml' charts/n8n
git diff charts/n8n/unittests/__snapshot__/
```

Inspect every snapshot diff before committing. Snapshot churn is a
first-class chart change; reviewers read the diff.

### 4. Scenario matrix

```bash
# Phase 1 — render every scenario with helm template (fast, no cluster).
./scripts/run_scenarios.sh

# Restrict to specific scenarios when iterating:
SCENARIOS="05 06" ./scripts/run_scenarios.sh
```

The scenarios live in [`tests/scenarios/`](tests/scenarios/); each file has
a header comment explaining what it exercises. When adding a new value
key or a new template, add a scenario alongside.

### 5. Cluster installation (optional, slow)

```bash
export KUBECONFIG=/path/to/minikube.yaml

# Subset of scenarios you want to actually deploy:
INSTALL_SCENARIOS="01 02 04" ./scripts/run_scenarios.sh

# Everything (heavy — n8n image is ~500MB and queue mode brings up many pods):
INSTALL_SCENARIOS="all" ./scripts/run_scenarios.sh
```

The script creates a unique namespace per scenario, pre-seeds dummy
secrets for `existingSecret`-based scenarios, runs `helm install --wait
--timeout 8m`, prints any non-Running pods, then `helm uninstall`s.

---

## Required tests for every change

Before opening a PR (from `dev/<topic>` / `feat/<topic>` /
`fix/<topic>` / `hotfix/<topic>` → `develop`, or `develop` → `main`):

1. **Lint clean.** `helm lint charts/n8n` must report `0 chart(s) failed`.
2. **All unit tests pass.** No flaky / silenced tests; if a test fails,
   either the change is wrong or the test needs to be updated to match
   the new expected behaviour (and the reason for the update goes in
   the commit message).
3. **Snapshots reflect intent.** If `helm unittest` reports snapshot
   diffs, `-u` and read every line of the diff. Surprises here are
   bugs.
4. **Affected scenarios re-rendered.** Add or update entries in
   `tests/scenarios/` for any new value key or any value combination
   whose render path changed. Run `./scripts/run_scenarios.sh` and
   confirm all entries pass.
5. **`values.schema.json` matches `values.yaml`.** Every new top-level
   key in `values.yaml` must have a matching schema entry. The `schema`
   CI job will fail otherwise.
6. **RELEASE-NOTES.md and `artifacthub.io/changes`.** Every chart
   version bump must add a `## <version>` section to
   `charts/n8n/RELEASE-NOTES.md` AND refresh the
   `artifacthub.io/changes` annotation block in
   `charts/n8n/Chart.yaml`. See [CONTRIBUTING.md](CONTRIBUTING.md#release-process) for
   format.
7. **Cluster smoke test (PRs to main).** Manually run scenarios 01 +
   02 against a real cluster at least once. The CI minikube job covers
   this on merged PRs to `main`, but `develop`-to-`main` PRs should
   show a green CI run before the maintainer approves.

---

## Adding a new scenario

A scenario is a single `*.values.yaml` file under `tests/scenarios/`.
Naming pattern: `NN-short-name.values.yaml`, where `NN` is a zero-padded
sequence number (sorts the matrix output).

Required:

- A leading comment block explaining *what behaviour the scenario
  exercises* and which fix / value key it covers. Reviewers should be
  able to tell from the comment alone why the scenario exists.
- Self-contained: any `existingSecret` referenced must be a name that
  `scripts/run_scenarios.sh` already pre-seeds (or extend the script).

Negative scenarios (those where `helm template` is expected to *fail*)
must be added to the `is_negative()` function in
`scripts/run_scenarios.sh`.

---

## Adding a new unit test

```yaml
# charts/n8n/unittests/<area>_test.yaml
suite: <descriptive name>
templates:
  - <template-name>.yaml
release:
  name: n8n
  namespace: n8n
tests:
  - it: should <describe expected behaviour in one line>
    set:
      # minimal values to trigger the behaviour
    asserts:
      - equal:
          path: spec...
          value: ...
      # add a notExists / notContains assertion for any "must not appear"
      # behaviour — these are regression guards.
```

Prefer `notExists` / `notContains` assertions for "must not be present"
behaviour over relying on full-template snapshots; snapshots are
expensive to maintain and the focused negative assertion documents
intent.

---

## Minikube notes

Running the full scenario matrix on minikube is slow (the n8n image is
~500 MB; queue mode + bundled subcharts brings up 6–8 pods per scenario).
Practical guidance:

- **Smallest reliable subset**: `01-defaults` and `02-postgres-bundled`
  — both install in ~3 min combined and exercise the main install path
  + the bundled Postgres subchart wiring.
- **For runner-sidecar work**: also run `05-external-task-runner` and
  `06-multi-main-statefulset`. The second is heavy (StatefulSet kind,
  many pods); allow ~8 min.
- **For schema-only work**: skip the cluster layer entirely. `helm
  lint` + unit tests + scenario matrix cover schema changes.

Multi-node minikube requires the rancher local-path provisioner (or
similar); the default `storage-provisioner` only works on single-node
minikube and leaves PVCs Pending on a multi-node cluster.

---

## CI workflows

| Workflow | Triggered by | Purpose |
|---------|--------------|---------|
| `.github/workflows/validate.yml`         | push to `develop`; PR opened/synced/reopened targeting `develop` / `main`                                                | Lint, schema check, unit tests, scenario render, kubeconform, minikube install. Topic branches (`dev/**` / `feat/**` / `fix/**` / `hotfix/**`) only trigger CI **once a PR into `develop` is open** — pre-PR commits run locally only. |
| `.github/workflows/version-bump.yml`     | PR `opened`/`synchronize`/`reopened` targeting `main` from `develop` / `dev/**` / `feat/**` / `fix/**` / `hotfix/**`, **unless** the PR has the `bot/release` label | Auto-bump `Chart.yaml#version`, regenerate `artifacthub.io/changes`, insert RELEASE-NOTES stub on the PR head |
| `.github/workflows/scheduled-release.yml`| `cron: '0 2 * * *'` (02:00 UTC daily) + `workflow_dispatch`           | If `develop` ahead of `main`: run [Bumpy](improvements/bumpy.md) via `scripts/bumpy_decide.sh`, bump accordingly (MAJOR capped at MINOR), open release PR labelled `bot/release`, enable auto-merge |
| `.github/workflows/hotfix-release.yml`   | push to `develop` whose tip commit subject matches a hotfix marker     | Same as scheduled-release but fired immediately; opens PR titled `Hotfix X.Y.Z` with `bot/release` + `hotfix` labels |
| `.github/workflows/release.yml`          | push to `main` (i.e., merged PR from `develop`); `workflow_dispatch`  | Package chart, sign, publish to `gh-pages`, create GitHub Release |

Releasing is fully automatic from `main` — no manual `helm package` or
`gh-pages` push. See [release.yml](.github/workflows/release.yml) for
the chart-releaser-action invocation and the GPG signing setup.
