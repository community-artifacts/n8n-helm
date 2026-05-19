# Contributing

Thanks for taking the time to improve the `community-artifacts/n8n` Helm chart. This document is the short version of [AGENTS.md](AGENTS.md) — read that file too if you plan to make non-trivial changes.

## Ground rules

- This chart is **independent**, not a fork. Do not introduce references to other n8n Helm charts in code, docs, or commit messages.
- Changes must be **additive**. Deprecate before removing; do not rename existing values keys.
- Defaults stay **safe**. Anything that pulls in a dependency (queue mode, KEDA, S3, ingress, autoscaling) must default to off, and the chart must render with zero `--set` flags.
- Every templated resource has matching unit tests and snapshots. Untested template changes will be rejected.

## Local setup

You need:

- Helm `>= 3.14`
- The [`helm-unittest`](https://github.com/helm-unittest/helm-unittest) plugin
- Network access to pull the `bitnami` and `minio` subcharts on the first `helm dependency update`

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
```

If your change is intentionally a rendered-output change, regenerate snapshots and inspect the diff:

```bash
helm unittest --strict -u --file 'unittests/**/*.yaml' charts/n8n
git diff charts/n8n/unittests/__snapshot__/
```

For non-trivial changes also render the realistic configurations listed in `AGENTS.md` (queue mode, external task runner, ingress + HPA + PDB + ServiceMonitor) to make sure you didn't break anything outside the defaults.

## Pull requests

- One PR per logical change. A `taskRunners` tweak and an ingress refactor do not belong in the same PR.
- Bump `charts/n8n/Chart.yaml#version` in the same PR. The suffix scheme is `<base>-ca.<n>` (e.g. `1.16.40-ca.2`). Bump `appVersion` only when changing the default n8n image tag.
- Add a `RELEASE-NOTES.md` entry that matches the new version. Use the same bullet style as the existing entries (`**Added** / **Changed** / **Fixed** / **Removed**`).
- If your change adds or modifies values keys: update `values.yaml` (with a `# --` comment, which is the source of the values table in `charts/n8n/README.md`), update `values.schema.json`, and update or add unit tests.
- Squash before merging; PR title becomes the merge commit message.

### Commit message style

- Imperative mood, short subject line (≤ 72 chars).
- No AI co-author trailers (`Co-Authored-By: Claude …` or similar). The commit author is the human running the change.
- Reference issues with `Refs #N` / `Fixes #N` in the body when applicable.

## Releasing

Releases are automated. On every push to `main`, `.github/workflows/release.yml` runs [chart-releaser-action](https://github.com/helm/chart-releaser-action):

- Packages `charts/n8n` if `Chart.yaml#version` is new.
- Publishes the `.tgz` and updated `index.yaml` to the `gh-pages` branch.
- Creates a GitHub Release for the new chart version.

You do not run `helm package` or push to `gh-pages` manually. If GitHub Pages is not yet enabled on the repo, enable it under **Settings → Pages → Source: `gh-pages`** before the first release.

## Filing issues

Useful issue reports include:

- Chart version (`Chart.yaml#version`).
- `helm version --short`.
- Kubernetes server version.
- The `values.yaml` (or `--set` flags) that reproduce the problem, with secrets redacted.
- Either the `helm template` output that's wrong or the live cluster behaviour you observed.

## License

By contributing you agree that your contributions will be licensed under the [Apache License 2.0](charts/n8n/LICENSE).
