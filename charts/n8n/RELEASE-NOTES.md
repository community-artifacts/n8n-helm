# Changelog

Chart versions follow [Semantic Versioning](https://semver.org/) independently of the n8n binary. The chart's MAJOR component tracks n8n's MAJOR component (the chart's `2.x` line ships n8n `2.x`); MINOR and PATCH are bumped at chart maintainer discretion when chart-side behavior or templates change.

For every n8n binary bump (`appVersion`), the maintainer reads the n8n release notes between the previous and new `appVersion` and applies any hosting-relevant changes to the chart (new env vars, deprecations, port or endpoint changes, default-value adjustments). The corresponding entry below summarizes what was carried over.

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
