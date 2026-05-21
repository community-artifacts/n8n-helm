# Helm Chart for n8n

A Helm chart for [n8n](https://n8n.io), the fair-code workflow automation platform.

This is a production-oriented Helm chart for n8n. it is a standalone distribution that ships additive operational knobs (extra task-runner controls, queue mode, multi-main, dedicated webhook processors, HPA, PDB, S3 binary storage, Postgres TLS, ServiceMonitor & PodMonitor) that are commonly requested but missing or limited in other available charts.

## Why this chart?

n8n's task-runner sidecar can be swapped for the dedicated `n8nio/runners` image (for example to enable the Python runner). This chart exposes the full image, args and env knobs as additive opt-in fields under `taskRunners.external`:

```yaml
taskRunners:
  mode: external
  external:
    image:
      repository: n8nio/runners
      tag: latest
    args:
      - javascript
      - python
    extraEnvVars:
      N8N_RUNNERS_STDLIB_ALLOW: "*"
      N8N_RUNNERS_EXTERNAL_ALLOW: "*"
```

When the new fields are left empty the chart falls back to the in-process task runner, so the default behaviour is unchanged.

## Install

```bash
helm repo add community-artifacts https://community-artifacts.github.io/n8n-helm
helm repo update
helm install n8n community-artifacts/n8n-helm
```

## Features

Already shipped in the current chart version:

- **Queue mode** — `worker.mode=queue` + `webhook.mode=queue` with optional bundled Redis (`redis.enabled`) or external Redis (`externalRedis.*`).
- **Multi-main / leader-follower** — `main.count` for enterprise license holders.
- **Webhook processors** — dedicated webhook deployment (`webhook.mode=queue`, `webhook.count`, `webhook.allNodes`) plus a separate MCP webhook (`webhook.mcp.enabled`).
- **External task-runner sidecar** — full override of image / args / env / resources under `taskRunners.external` (e.g. to enable the Python runner via `n8nio/runners`).
- **Horizontal Pod Autoscaler** — `worker.autoscaling.*` and `main.autoscaling.*` with custom metrics and behavior.
- **PodDisruptionBudget** — independently togglable for main, worker and webhook (`main.pdb`, `worker.pdb`, `webhook.pdb`).
- **S3 binary storage** — `binaryData.mode=s3` with `binaryData.s3.*` (host, bucket, region, credentials, existingSecret).
- **ServiceMonitor & PodMonitor** — Prometheus Operator scraping for the main pod and (in queue mode + Postgres) the workers.
- **Bundled Postgres / Redis / MinIO subcharts** — opt-in via the respective `.enabled` flags; production setups should point at managed services via `externalPostgresql` / `externalRedis`.
- **Postgres TLS** — `db.postgresdb.ssl` with inline base64-encoded certs or existing-secret references.
- **Persistence** — main and worker persistence with custom storage class, access mode and existing-claim support.
- **Wait-for-main probe** — workers can block startup until the leader is healthy (`worker.waitMainNodeReady`).
- **Values schema** — `values.schema.json` shipped alongside the chart so `helm install --set ...` is validated client-side.

Planned:

- **KEDA** — `ScaledObject` for worker scaling driven by Redis queue depth (currently only CPU/memory HPA is wired up).
- **OpenTelemetry integration** — first-class env wiring for the OTel collector endpoint.
- **Externalized config** — option to back the whole `*-configmap` set with a single user-provided ConfigMap / Secret reference.

## Status

This chart is **beta**. It is in active use by the community-artifacts maintainers but the wider adoption surface is small (single-digit forks/stars as of this writing), and chart-side breaking changes still occasionally land in MINOR bumps within the same n8n MAJOR (see `charts/n8n/RELEASE-NOTES.md`). The chart MAJOR version tracks the n8n binary MAJOR — see [CONTRIBUTING.md](CONTRIBUTING.md) for the versioning rule.

What this means for adopters:

- **Production deployments work** — every release renders cleanly against `helm lint`, passes ~770 unit-test assertions, and ships a `values.schema.json` that validates `--set` flags client-side. We use this chart ourselves.
- **Pin versions explicitly** — `helm install n8n community-artifacts/n8n --version <X.Y.Z>` rather than tracking `latest`. The chart sees iterative MINOR / PATCH bumps when n8n ships hosting-relevant changes or when chart-side defaults need to shift.
- **Read `RELEASE-NOTES.md` before upgrading** — every chart version has a corresponding entry calling out Added / Changed / Fixed / Removed items, including any rendered-output deltas.
- **GitOps users should pin `encryptionKey` or `existingEncryptionKeySecret` and set `requireExplicitEncryptionKey: true`** — the chart will fail-loud rather than silently regenerate the key on every reconcile.
- **Issues and PRs welcome.** Real-world adoption signals (issues / questions / feature requests) feed the prioritisation that drives version bumps.

## Contributing

PRs target the **`develop`** branch — `main` is reserved for releases and direct pushes are blocked. Work on a topic branch (`dev/<topic>` / `feat/<topic>` / `fix/<topic>` / `hotfix/<topic>`); **opening the PR into `develop`** kicks off the **Validate Chart** CI workflow (`helm lint`, schema cross-check, ~770 unit-test assertions, scenario matrix, kubeconform, minikube smoke install), which re-runs on every subsequent push that updates the PR. Pre-PR commits don't burn runner minutes — iterate locally with `helm lint` + `helm unittest` + `./scripts/run_scenarios.sh`. Releases ship by opening a PR `develop` → `main`; merging triggers the chart-releaser pipeline.

- [TESTING.md](TESTING.md) — testing layers, the `tests/scenarios/` matrix, local minikube setup, what CI enforces.
- [CONTRIBUTING.md](CONTRIBUTING.md) — branch strategy, PR checklist, release process, commit-message conventions.

## License

Apache-2.0.
