# Changelog

Chart versions follow [Semantic Versioning](https://semver.org/) independently of the n8n binary. The chart's MAJOR component tracks n8n's MAJOR component (the chart's `2.x` line ships n8n `2.x`); MINOR and PATCH are bumped at chart maintainer discretion when chart-side behavior or templates change.

For every n8n binary bump (`appVersion`), the maintainer reads the n8n release notes between the previous and new `appVersion` and applies any hosting-relevant changes to the chart (new env vars, deprecations, port or endpoint changes, default-value adjustments). The corresponding entry below summarizes what was carried over.

## 2.4.1

Single-fix hotfix on top of 2.4.0. No values keys touched, no rendered-output change, no `appVersion` bump — only the chart's Artifact Hub metadata.

### Fixed

- **Artifact Hub rejected the 2.4.0 `artifacthub.io/changes` annotation** with `invalid changes annotation. Please use quotes on strings that include any of the following characters: {}:[],&*#?|-<>=!%@`. The 2.4.0 block listed 11 `description:` values containing unquoted YAML-special characters (`{`, `[`, `:`, `|`, `-`, `!`, `=`, `<`, `>`), which artifact-hub-tooling's parser refused. Each `description:` value is now a double-quoted scalar; the three entries with internal `"` (the `["javascript"]`, `["ps aux | grep '[n]8n'"]`, and `"I set ..."` cases) have those escaped as `\"`. Pure metadata fix — chart templates and rendered output are byte-identical to 2.4.0. **Note**: this fixes the annotation rendered for 2.4.1 onward; the 2.4.0 entry in `gh-pages/index.yaml` was snapshotted at release time and will continue to error on Artifact Hub's per-version enrichment for that one version.

## 2.4.0

Chart hardening sweep + influence-chart review. All changes are additive — no values keys removed, no rendered-output regressions for existing installs, no `appVersion` bump (still n8n `2.21.4`). Existing release upgrades pick up bugfixes + new opt-in features without further config.

### Fixed

- **Runner-sidecar drift between Deployment and StatefulSet renders.** The external task-runner sidecar in `templates/statefulset.yaml`, `templates/statefulset-worker.yaml`, and `templates/deployment-worker.yaml` was hardcoded to `.Values.image.repository:tag` and `args: ["javascript"]`. The `taskRunners.external.{image,args,extraEnvVars}` knobs documented in the chart applied only to the main `templates/deployment.yaml` render — and the kind auto-flips to StatefulSet exactly when `main.count > 1` with RWO persistence, the use case "production-oriented" implies. The sidecar block is now a `_helpers.tpl` partial (`n8n.taskRunnerSidecar`) included from all four parent templates, eliminating the drift permanently.
- **Top-level `/LICENSE` reset to Apache-2.0.** The repo root carried GPL-3.0 while `charts/n8n/LICENSE`, `Chart.yaml#artifacthub.io/license`, and the chart README all said Apache-2.0 — the inconsistency was a blocker for enterprise legal review.

### Added

- **Per-role pod `terminationGracePeriodSeconds`** — `main.terminationGracePeriodSeconds` (default 60s), `worker.terminationGracePeriodSeconds` (90s; workers can be mid-execution at scale-down time), `webhook.terminationGracePeriodSeconds` (60s), `webhook.mcp.terminationGracePeriodSeconds` (60s). The chart previously relied on the kubelet's default 30s grace period, which silently truncated any value of `gracefulShutdownTimeout` above 30 — n8n would ask for more time, the kubelet wouldn't grant it.
- **`requireExplicitEncryptionKey`** (default `false`) — when set true and neither `encryptionKey` nor `existingEncryptionKeySecret` is configured, the template fails loudly under `helm template` / Argo CD / Flux renders that can't reach the cluster, instead of silently re-generating a fresh `N8N_ENCRYPTION_KEY` on every reconcile (which would re-encrypt every stored credential in n8n). **Strongly recommended for any GitOps deployment.** Default is `false` so the chart's own unit-test fixtures (which render without a live cluster) keep passing; production deployments should set this to `true`.
- **`helm.sh/resource-policy: keep`** on the encryption-key Secret — survives `helm uninstall` so an accidental teardown doesn't brick access to every credential stored in the n8n database. Operators who deliberately want to rotate the key must delete the Secret out-of-band first.
- **`extraManifests` / `extraTemplateManifests`** — top-level escape hatch for arbitrary additional Kubernetes resources (NetworkPolicies more specific than `networkPolicy.*` covers, CronJobs, ExternalSecret resources, supplementary ConfigMaps). `extraManifests` items are full YAML mappings emitted as-is; `extraTemplateManifests` items are multi-line YAML strings passed through `tpl` so chart includes and value references resolve.
- **`networkPolicy.enabled`** (default `false`) — opt-in NetworkPolicy per active role (main; worker / webhook when `mode: queue`). Default posture: ingress from same-namespace pods + optional ingress-controller selector; egress to DNS, in-cluster Postgres / Redis / S3 derived from `db.type`, `*.mode`, `binaryData.availableModes`. Extend with `networkPolicy.{additionalIngressRules,additionalEgressRules}` for outbound webhook targets and similar.
- **HPA / PDB precondition warnings in NOTES.** Configurations where `worker.autoscaling.enabled: true` or `webhook.autoscaling.enabled: true` or the corresponding PDB `enabled: true` would silently produce no resource (because of `worker.mode != queue`, RWO persistence forcing StatefulSet, `allNodes: true`, etc.) now print a `!!!`-prefixed message naming the missing prerequisites at `helm install` time.

### Changed

- **Worker / webhook / MCP-webhook default `startupProbe`** is now `httpGet /healthz` with `failureThreshold: 30` instead of `exec ["/bin/sh", "-c", "ps aux | grep '[n]8n'"]`. The previous `ps aux` match passed before n8n was actually serving requests, then liveness immediately failed and crash-looped — exactly the opposite of what a startup probe is meant to do.
- **`main.startupProbe` is now configured by default.** Live minikube testing of 2.4.0 surfaced a real regression on slow clusters: the main pod has a tight `livenessProbe` (timeout 1s, failure threshold 3) and no startup probe, so a cold-starting n8n (image pull + Postgres schema check + listener bind) silently exceeds the 30s window and the kubelet sends SIGTERM before n8n binds its HTTP port. Default `startupProbe.failureThreshold: 30` with 5s period gives 150 s of cold-start budget. Was present on worker/webhook/MCP-webhook but missing on main — fixed in this release.
- **Chart README has a new `Bundled subchart details` section** naming the actual upstreams behind the `redis` / `postgresql` / `minio` value aliases (Valkey 9.x, CloudPirates Postgres 18.x, MinIO) with repo URLs. Operators with policies on supply chain or specific Postgres / Redis distributions can now evaluate fit before deploying.
- **`externalPostgresql.password` carries a prominent in-line warning** against the inline-secret pattern (the cleartext password ends up in the rendered manifest, the Helm release history, and the Argo CD application diff). Recommends `existingSecret` for production.
- **README `Status` section** documents the chart's `beta` maturity, the chart-MAJOR-tracks-n8n-MAJOR versioning rule, and the GitOps `requireExplicitEncryptionKey` recommendation so adopters can calibrate expectations before deploying.
- **Deprecated root `livenessProbe` / `readinessProbe` deprecation notes** updated to spell out the precedence (per-role wins) and the shallow-merge gotcha (setting any key in a per-role probe replaces the whole map for that role).

### Tested

- `helm lint`, `helm template`, and `helm-unittest` all clean — 771/771 unit-test assertions pass, 219/219 snapshots match.
- 14 deployment scenarios in `tests/scenarios/` cover defaults, bundled Postgres, external Postgres via existingSecret, queue mode with bundled subcharts, the external task-runner with full overrides (image / args / extraEnvVars / securityContext), multi-main HA via StatefulSet, full external surface (Ingress + HPA + PDB + ServiceMonitor), S3 binary storage with MinIO, the GitOps encryption-key safety guard (positive + negative cases), NetworkPolicy, `extraManifests`, per-role `terminationGracePeriodSeconds`, and the HPA precondition warning. All 14 pass `helm template`; a representative subset (defaults / bundled Postgres / queue mode / external task runner / multi-main StatefulSet) passes `helm install --wait` on a local 3-node minikube cluster.

## 2.2.3

- **Fixed**: Stop setting the deprecated `N8N_RUNNERS_ENABLED` environment variable. n8n logs `N8N_RUNNERS_ENABLED -> Remove this environment variable; it is no longer needed.` on startup when it is set — task runners are always enabled on supported n8n versions, and the env var is now a no-op. Removed from `templates/configmap.yaml` (the task-broker ConfigMap consumed via `envFrom` by main / worker / statefulset workloads), `templates/deployment-webhook.yaml`, and `templates/deployment-mcp-webhook.yaml`. Matching unit-test assertions inverted to `notExists` / `notContains` guards so a regression that re-introduces the var would fail CI; snapshots regenerated. Behavior-only fix — no values changed.

## 2.2.2

- **Added**: GPG provenance signing for chart releases. `chart-releaser-action` now imports the maintainer's private key from the `CR_GPG_KEY` / `CR_GPG_PASSPHRASE` / `CR_GPG_KEY_NAME` secrets and publishes a `.tgz.prov` file alongside every chart `.tgz`. Artifact Hub auto-detects the provenance file and displays the "Signed" badge on the chart's page.
- **Added**: Public key committed at the repo root as [`pubkey.gpg`](https://github.com/community-artifacts/n8n-helm/blob/main/pubkey.gpg) so consumers can `helm install --verify` against signed releases.
- **Added**: New `Verifying the Chart` section in the chart README walking through key import and `helm install --verify`.
- **Note**: `chart-releaser` is built on Go's deprecated `golang.org/x/crypto/openpgp`, which only supports RSA and DSA keys. Ed25519 / Curve25519 keys (OpenPGP public-key algorithm `22`) will fail packaging with `openpgp: unsupported feature: public key type: 22`. Generate the signing key with `Key-Type: RSA` / `Key-Length: 4096`.

## 2.2.1

- **Added**: Per-version changelog surfaced on the chart's [Artifact Hub](https://artifacthub.io/) page via the `artifacthub.io/changes` annotation in `Chart.yaml`. Every version bump from this release onwards must populate the annotation with structured `kind` + `description` entries describing the changes since the previous version. Past tgz files (2.2.0, 2.1.1, 2.1.0) cannot be retro-annotated — their Artifact Hub changelog will appear empty.

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
