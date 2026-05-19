# AGENTS.md

Operating notes for AI agents (and humans skimming this file like one) working in this repo. Read this before touching anything; the README is for end users, this file is for contributors.

## What this repo is

A single, independent Helm chart for [n8n](https://n8n.io) published to GitHub Pages. **It is not a fork.** When describing the chart in commits, PRs, READMEs or comments, never refer to "upstream" or to any other n8n Helm chart by name. The chart was *inspired by* the broader n8n hosting ecosystem; that's the strongest claim you should make.

If you spot any reference to other n8n Helm charts that slipped in (repo names, install commands, doc links, ArtifactHub upstream links, prior maintainer attributions), strip it and reframe as independent.

## Repository layout

```
.
├── README.md                 # User-facing readme (install, features, roadmap)
├── CONTRIBUTING.md           # Contributor workflow
├── AGENTS.md                 # This file
├── .github/workflows/
│   └── release.yml           # chart-releaser-action → gh-pages
└── charts/
    └── n8n/
        ├── Chart.yaml        # Version, appVersion, deps
        ├── Chart.lock
        ├── values.yaml       # Source of truth for user-facing config
        ├── values.schema.json# Validates --set / -f at install time
        ├── README.md         # Auto-generatable values reference
        ├── RELEASE-NOTES.md  # One section per chart version bump
        ├── templates/        # Helm templates (see below)
        ├── unittests/        # helm-unittest suites + __snapshot__/
        └── charts/           # Vendored subchart tarballs (postgres/redis/minio)
```

### Template responsibilities

| File | Purpose |
| --- | --- |
| `deployment.yaml` | Main n8n pod (UI / leader) |
| `deployment-worker.yaml` / `statefulset-worker.yaml` | Queue-mode workers (deployment unless `worker.forceToUseStatefulset` or `worker.persistence.enabled`) |
| `deployment-webhook.yaml` | Dedicated webhook processor in queue mode |
| `deployment-mcp-webhook.yaml` | MCP webhook processor (queue mode + Postgres only) |
| `statefulset.yaml` | Main as StatefulSet when persistence requires it |
| `configmap.yaml` | All env-var ConfigMaps (database, logging, diagnostics, …) — split into many keys |
| `secret.yaml` | Encryption key + external service credentials |
| `service.yaml` | ClusterIP services for main / worker / webhook / mcp |
| `ingress.yaml` | Optional Ingress for the main service |
| `hpa.yaml` | HPA for worker (+ main if enabled) |
| `pdb.yaml` | PDB per role (main / worker / webhook) |
| `pvc.yaml` | Standalone PVC when `*.persistence.existingClaim` is not set |
| `servicemonitor.yaml` | ServiceMonitor for main + PodMonitor for workers (queue + Postgres) |
| `serviceaccount.yaml` | SA + optional imagePullSecrets wiring |
| `NOTES.txt` | Post-install help text |
| `_helpers.tpl` | Naming, label, selector helpers — read this before adding labels anywhere |

## Conventions to follow

- **Additive only.** Never remove a values key without a deprecation cycle. If something is going away, keep the key, mark it `DEPRECATED:` in the comment, and drop it in a later major version. The current `affinity` top-level key is the model.
- **Keep defaults safe.** Default to off for anything that introduces a dependency (queue mode, KEDA, S3, ingress, autoscaling, telemetry). The chart must template cleanly with zero `--set` flags.
- **No external repo names in code or docs.** See the top section.
- **Schema discipline.** Any new top-level or nested values key must be reflected in `values.schema.json` *and* in `values.yaml` with a `# --` comment (these comments are the source for the values table in `charts/n8n/README.md`).
- **Tests are required.** Every templated resource has a `unittests/<name>_test.yaml` and a matching `__snapshot__/`. When you change rendered output intentionally, regenerate snapshots with `helm unittest -u …` and review the diff in the same PR.
- **One feature, one PR.** Releases are driven by `Chart.yaml#version` bumps; mixing unrelated changes makes `RELEASE-NOTES.md` lie.
- **No comments that restate the code.** This applies to template comments too. Helm templates already have plenty of noise; add a comment only when the *why* is non-obvious (e.g. "PodMonitor only renders for queue + Postgres because the metrics port is wired by the worker statefulset").

## How to test locally

Prereqs: `helm >= 3.14`, the `helm-unittest` plugin.

```bash
# Install the unittest plugin once
helm plugin install https://github.com/helm-unittest/helm-unittest.git

# Resolve subchart tarballs (writes Chart.lock + charts/*.tgz)
helm dependency update charts/n8n

# Static analysis
helm lint charts/n8n

# Render with defaults (sqlite, no queue, no ingress)
helm template testn8n charts/n8n

# Render queue mode with external services
helm template testn8n charts/n8n \
  --set redis.enabled=true \
  --set worker.mode=queue --set worker.count=2 \
  --set webhook.mode=queue \
  --set db.type=postgresdb \
  --set externalPostgresql.host=pg.local \
  --set externalPostgresql.username=u \
  --set externalPostgresql.password=p \
  --set externalPostgresql.database=d

# Render with external task-runner sidecar
helm template testn8n charts/n8n \
  --set taskRunners.mode=external \
  --set taskRunners.external.image.repository=n8nio/runners \
  --set taskRunners.external.image.tag=latest

# Full unit-test suite (771 tests, 219 snapshots at time of writing)
helm unittest --strict --file 'unittests/**/*.yaml' charts/n8n
```

A change is considered green when `helm lint`, `helm template`, and `helm unittest` all pass. If you've added a template, you have also added the matching `_test.yaml` and snapshot.

## Versioning & releases

- `Chart.yaml#version` follows SemVer with a `-ca.N` suffix (e.g. `1.16.40-ca.1`). The base part tracks the broad n8n feature line; the `-ca.N` part bumps on every chart change.
- `Chart.yaml#appVersion` is the n8n container tag the chart was last validated against. Bump it when bumping the default image tag.
- `RELEASE-NOTES.md` gets a new entry on every version bump. Format is the existing bullet style.
- Pushing to `main` triggers `.github/workflows/release.yml`, which uses `helm/chart-releaser-action` to package `charts/n8n` and publish to the `gh-pages` branch. GitHub Pages must be enabled with `gh-pages` as the source.

## Work in progress

Tracked in the README "Planned" list. As of this writing:

- **KEDA worker scaling.** HPA is already wired; a KEDA `ScaledObject` driven by Redis list depth is the natural next step for queue mode.
- **NetworkPolicy defaults.** One NetworkPolicy is rendered today (worker → redis in queue mode). A broader, opinionated set would help locked-down clusters.
- **OpenTelemetry env wiring.** n8n supports `OTEL_*` env vars; surface them as a first-class block instead of forcing users into `extraEnvVars`.
- **External config refs.** Allow a user-provided ConfigMap/Secret to back the env split-up, for environments where chart-rendered ConfigMaps are restricted.

Before starting on any of these: open an issue, link it in the PR, and update `RELEASE-NOTES.md` in the same PR that bumps `Chart.yaml#version`.

## Things not to do

- Do **not** add a `Co-Authored-By: Claude …` trailer (or any other AI co-author trailer) to commits in this repo. Commit author is the human running the change.
- Do **not** commit rendered manifests, `.tgz` outputs of `helm package`, or anything under `gh-pages` — the release workflow owns that branch.
- Do **not** introduce a hard dependency on a CRD (KEDA, Prometheus Operator, cert-manager) without an `enabled: false` guard in `values.yaml` and a schema-allowed toggle.
- Do **not** rename existing values keys. Add new ones; deprecate the old.
