# Changelog

Chart versions follow [Semantic Versioning](https://semver.org/) independently of the n8n binary. The chart's MAJOR component tracks n8n's MAJOR component (the chart's `2.x` line ships n8n `2.x`); MINOR and PATCH are bumped at chart maintainer discretion when chart-side behavior or templates change.

For every n8n binary bump (`appVersion`), the maintainer reads the n8n release notes between the previous and new `appVersion` and applies any hosting-relevant changes to the chart (new env vars, deprecations, port or endpoint changes, default-value adjustments). The corresponding entry below summarizes what was carried over.

## 2.2.0

- **Added**: `taskRunners.external.securityContext` lets you set a dedicated container `securityContext` on the external task-runner sidecar. When left empty (the default), the sidecar inherits `.Values.securityContext` — so existing deployments now apply the chart-level non-root posture to the runner container instead of leaving it unset. Useful on clusters enforcing Pod Security Standards `restricted`, where a non-numeric image `USER` cannot be proven non-root and an explicit `runAsUser` must be provided.

## 2.1.1

- **Fixed**: The external task-runner sidecar's container port is now named `task-runner` instead of `http`, with the liveness and readiness probes updated to match. The previous `http` name collided with the main n8n container's port in the same pod, which could lead a Service's `targetPort: http` to resolve to the wrong container and to confusing kubectl/describe output. Behaviour-only fix — no values changed.

## 2.1.0

- **Breaking** (within 2.x, since the chart's MAJOR is pinned to the n8n binary's MAJOR): Replaced the Bitnami PostgreSQL and Redis subcharts. The chart now ships [`cloudpirates/postgres`](https://artifacthub.io/packages/helm/cloudpirates-postgres/postgres) `0.19.4` (PostgreSQL 18.3, StatefulSet, official `postgres` image) and [`valkey/valkey`](https://github.com/valkey-io/valkey-helm) `0.9.4` (Valkey 9.0.2, Redis-wire-compatible).
- **Breaking**: Restructured `postgresql.*` values:
  - `postgresql.primary.service.ports.postgresql` → `postgresql.service.port`
  - `postgresql.primary.persistence.{enabled,existingClaim}` → `postgresql.persistence.{enabled,existingClaim}`
  - Dropped `postgresql.architecture` and `postgresql.image.repository` Bitnami workaround.
- **Breaking**: Restructured `redis.*` values:
  - `redis.master.service.ports.redis` → `redis.service.port`
  - In-cluster redis Service host loses the `-master` suffix (now `{release}-redis` instead of `{release}-redis-master`).
  - `redis.auth.enabled` now defaults to `false`. Valkey uses ACL rather than single-password auth; to enable, set `redis.auth.aclUsers.default.password` (or `redis.auth.usersExistingSecret`) and mirror the value in `externalRedis.password`.
  - Dropped `redis.architecture`, `redis.master.persistence`, and the `bitnamilegacy/redis` workaround.
- **Fixed**: `n8n.postgresql.fullname` / `n8n.redis.fullname` helpers now match the subchart's actual rendered Service/Secret name in releases whose name does not contain `n8n` (previously the configmap referenced `{release}-n8n-postgresql` while the subchart created `{release}-postgresql`).
- **Dependencies**: postgres `0.19.4` (alias `postgresql`), valkey `0.9.4` (alias `redis`), minio `5.4.0`.

## 2.0.0

First release of the community-artifacts `n8n` Helm chart.

- **Added**: Independent SemVer line starting at `2.0.0`. The chart's MAJOR component tracks the n8n binary's MAJOR component (currently `2.x`).
- **Added**: `appVersion: 2.21.4` (latest stable n8n release).
- **Added**: External task-runner sidecar with full image / args / env / resources overrides under `taskRunners.external` (enables the `n8nio/runners` image, including the Python runner).
- **Added**: Queue mode (`worker.mode=queue`, `webhook.mode=queue`) with bundled or external Redis.
- **Added**: Multi-main support (`main.count`) for enterprise license holders.
- **Added**: Dedicated webhook processor and MCP webhook deployments in queue mode.
- **Added**: HPA for worker (`worker.autoscaling.*`) and main (`main.autoscaling.*`).
- **Added**: PodDisruptionBudget per role (`main.pdb`, `worker.pdb`, `webhook.pdb`).
- **Added**: S3 binary storage (`binaryData.mode=s3`, `binaryData.s3.*`).
- **Added**: Postgres TLS (`db.postgresdb.ssl.*`) with inline base64-encoded certs or existing-secret references.
- **Added**: ServiceMonitor for main; PodMonitor for workers in queue + Postgres mode.
- **Added**: Bundled Postgres / Redis / MinIO subcharts, all opt-in via `.enabled` flags.
- **Added**: `values.schema.json` shipped with the chart for client-side validation of `--set` / `-f`.
- **Dependencies**: redis `25.5.3`, postgresql `18.6.4`, minio `5.4.0` (bitnami + min.io subcharts).
