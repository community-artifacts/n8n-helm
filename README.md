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
- **NetworkPolicy presets** — opinionated defaults beyond the existing one rendered in queue mode.
- **OpenTelemetry integration** — first-class env wiring for the OTel collector endpoint.
- **Externalized config** — option to back the whole `*-configmap` set with a single user-provided ConfigMap / Secret reference.

## License

Apache-2.0.
