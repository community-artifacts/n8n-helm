<div align="center" markdown="1">

<img src="https://avatars1.githubusercontent.com/u/45487711?s=200&v=4" width="96" height="96" alt="n8n" />

# n8n-helm

**Production-oriented Helm chart for [n8n](https://n8n.io) — the fair-code workflow automation platform.**

[![License](https://img.shields.io/github/license/community-artifacts/n8n-helm?color=blue)](https://github.com/community-artifacts/n8n-helm/blob/main/LICENSE)
[![Latest release](https://img.shields.io/github/v/release/community-artifacts/n8n-helm?label=chart&color=brightgreen)](https://github.com/community-artifacts/n8n-helm/releases)
[![App version](https://img.shields.io/badge/n8n-2.21.4-ff6d5a)](https://github.com/n8n-io/n8n/releases)
[![Kubernetes](https://img.shields.io/badge/kubernetes-%E2%89%A51.23-326ce5)](https://kubernetes.io)

</div>

---

## Quick start

```bash
helm repo add community-artifacts https://community-artifacts.github.io/n8n-helm
helm repo update
helm install n8n community-artifacts/n8n
```

Need a `values.yaml`? See the [**full values reference**](https://github.com/community-artifacts/n8n-helm/blob/main/charts/n8n/README.md) and the [example overlays](https://github.com/community-artifacts/n8n-helm/blob/main/charts/n8n/README.md#deployment-with-the-bundled-postgresql-subchart) in the chart README.

## What's inside

Operational knobs that the upstream n8n image alone doesn't give you — all opt-in:

- **Queue mode** with dedicated `worker`, `webhook`, and MCP-webhook deployments
- **External task runners** (`n8nio/runners`) with full image/args/env/resources overrides
- **Multi-main HA** (`main.count > 1`) for enterprise license holders
- **Autoscaling** — HPA for `main` and `worker`, KEDA-aware
- **PodDisruptionBudgets** per role (`main.pdb`, `worker.pdb`, `webhook.pdb`)
- **S3 binary storage** (`binaryData.mode=s3`) with optional bundled MinIO
- **Postgres TLS** with inline base64 certs or `existingSecret` references
- **Observability** — `ServiceMonitor` for `main`, `PodMonitor` for workers in queue + Postgres mode
- **Bundled subcharts** — opt-in [`cloudpirates/postgres`](https://artifacthub.io/packages/helm/cloudpirates-postgres/postgres) (PostgreSQL 18) and [`valkey/valkey`](https://github.com/valkey-io/valkey-helm) (Redis-wire-compatible 9.x), with the option to bring your own via `externalPostgresql` / `externalRedis`
- **`values.schema.json`** shipped with the chart, so `helm install --set foo=bar` is validated client-side

## Versions

The chart's MAJOR component tracks the n8n binary's MAJOR (`2.x` ships n8n `2.x`); chart-side MINOR / PATCH bumps live independently. Full changelog in [`RELEASE-NOTES.md`](https://github.com/community-artifacts/n8n-helm/blob/main/charts/n8n/RELEASE-NOTES.md).

| Chart | n8n (`appVersion`) | Highlights |
|-------|---------------------|------------|
| `2.2.0` | `2.21.4` | Per-sidecar `securityContext` on the external task-runner |
| `2.1.1` | `2.21.4` | Task-runner container port renamed `task-runner` (was `http`) |
| `2.1.0` | `2.21.4` | Replaced Bitnami subcharts with CloudPirates Postgres + Valkey |
| `2.0.0` | `2.21.4` | First release of the community-artifacts distribution |

```bash
# pin a specific version
helm install n8n community-artifacts/n8n --version 2.2.0
```

## Source, issues, contributing

- **Chart source**: <https://github.com/community-artifacts/n8n-helm>
- **Issue tracker**: <https://github.com/community-artifacts/n8n-helm/issues>
- **Contributing guide**: [`CONTRIBUTING.md`](https://github.com/community-artifacts/n8n-helm/blob/main/CONTRIBUTING.md)
- **n8n project**: <https://github.com/n8n-io/n8n>

---
