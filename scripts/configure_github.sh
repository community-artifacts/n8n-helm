#!/usr/bin/env bash
# Apply the GitHub repo settings + branch protection rules the release
# flow assumes. Idempotent: running twice is a no-op except for tweaks
# you've made in between.
#
# What it does:
#   1. Repo flags
#        - Allow auto-merge (so scheduled-release / hotfix-release can
#          call `gh pr merge --auto`)
#        - Automatically delete head branches on merge (topic-branch
#          cleanup)
#        - Keep merge-commit AND squash-merge enabled (the docs flow
#          uses both)
#   2. Labels
#        - Create `bot/release` and `hotfix` if they don't exist
#   3. Branch protection on `main`
#        - Require PR (no direct push)
#        - Required status checks = the Validate Chart job names
#          (kept in REQUIRED_CHECKS_MAIN below — edit if you rename a
#          job or want to relax the gate)
#        - Require linear history
#        - 1 approving review (set REQUIRED_REVIEWS_MAIN=0 to skip)
#        - No force push, no deletion
#   4. Branch protection on `develop`
#        - Require PR (no direct push)
#        - Allow `github-actions[bot]` to bypass required PRs — needed
#          for the bump workflows to push back onto develop while a
#          release PR is open
#        - Required status checks = the Validate Chart job names
#        - No required reviews on develop by default (low-friction
#          topic-branch integration)
#        - No force push, no deletion
#
# Requires:
#   - `gh` CLI authenticated with admin scope on the repo (the same
#     account that owns the repo, or org admin).
#
# Override knobs via env:
#   REPO=community-artifacts/n8n-helm   target repo (default: this one)
#   REQUIRED_REVIEWS_MAIN=1              approvals required on main
#   INCLUDE_MINIKUBE_CHECK=false         gate main on the minikube job too
#   DRY_RUN=false                        only print the API calls
#
# Usage:
#     gh auth login --scopes 'repo,admin:repo_hook'   (one-time)
#     ./scripts/configure_github.sh
#     INCLUDE_MINIKUBE_CHECK=true ./scripts/configure_github.sh
#     DRY_RUN=true ./scripts/configure_github.sh

set -euo pipefail

# ---- config -----------------------------------------------------------------
REPO="${REPO:-community-artifacts/n8n-helm}"
REQUIRED_REVIEWS_MAIN="${REQUIRED_REVIEWS_MAIN:-1}"
INCLUDE_MINIKUBE_CHECK="${INCLUDE_MINIKUBE_CHECK:-false}"
DRY_RUN="${DRY_RUN:-false}"

# Exact job names emitted by .github/workflows/validate.yml. GitHub's
# required-status-check matching is literal string equality, so any
# rename in validate.yml has to be mirrored here.
REQUIRED_CHECKS=(
  "helm lint"
  "helm-unittest (773 assertions, 219 snapshots)"
  "Render scenario matrix (helm template)"
  "values.schema.json well-formed"
  "kubeconform (validate rendered manifests vs Kubernetes API)"
)
if [[ "$INCLUDE_MINIKUBE_CHECK" == "true" ]]; then
  REQUIRED_CHECKS+=("minikube install (representative scenarios)")
fi

# ---- helpers ----------------------------------------------------------------
command -v gh   >/dev/null || { echo "gh CLI not installed"   >&2; exit 1; }
command -v jq   >/dev/null || { echo "jq not installed"       >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh not authenticated; run 'gh auth login'" >&2; exit 1; }

run() {
  echo "  $ $*"
  if [[ "$DRY_RUN" != "true" ]]; then
    "$@"
  fi
}

# Build the JSON `contexts` array literal from REQUIRED_CHECKS.
contexts_json() {
  printf '%s\n' "${REQUIRED_CHECKS[@]}" | jq -R . | jq -s .
}

echo "============================================================"
echo "Target repo:        $REPO"
echo "Required reviews on main: $REQUIRED_REVIEWS_MAIN"
echo "Gate main on minikube:    $INCLUDE_MINIKUBE_CHECK"
echo "Dry run:                  $DRY_RUN"
echo "============================================================"

# ---- 1. Repo flags ----------------------------------------------------------
echo
echo "==> Repo flags"
run gh api -X PATCH "repos/$REPO" \
  -F allow_auto_merge=true \
  -F delete_branch_on_merge=true \
  -F allow_merge_commit=true \
  -F allow_squash_merge=true \
  -F allow_rebase_merge=true

# ---- 2. Labels --------------------------------------------------------------
echo
echo "==> Labels"
ensure_label() {
  local name="$1" color="$2" desc="$3"
  if gh api "repos/$REPO/labels/${name//\//%2F}" >/dev/null 2>&1; then
    echo "  · $name exists; leaving as-is."
  else
    run gh api -X POST "repos/$REPO/labels" \
      -f name="$name" -f color="$color" -f description="$desc"
  fi
}
ensure_label "bot/release" "fbca04" "Release PR opened by an automated workflow; version-bump.yml no-ops on it."
ensure_label "hotfix"      "b60205" "Hotfix release — fast-tracked by hotfix-release.yml."

# ---- 3. Branch protection on main ------------------------------------------
echo
echo "==> Branch protection: main"
contexts=$(contexts_json)
main_payload=$(jq -n \
  --argjson contexts "$contexts" \
  --argjson reviews "$REQUIRED_REVIEWS_MAIN" \
  '{
    required_status_checks: {
      strict: true,
      contexts: $contexts
    },
    enforce_admins: false,
    required_pull_request_reviews: (
      if $reviews > 0 then {
        required_approving_review_count: $reviews,
        dismiss_stale_reviews: true,
        require_code_owner_reviews: false
      } else {
        required_approving_review_count: 0,
        dismiss_stale_reviews: false,
        require_code_owner_reviews: false
      } end
    ),
    restrictions: null,
    required_linear_history: true,
    allow_force_pushes: false,
    allow_deletions: false,
    required_conversation_resolution: true,
    block_creations: false
  }'
)
if [[ "$DRY_RUN" == "true" ]]; then
  echo "  $ gh api -X PUT repos/$REPO/branches/main/protection (payload below)"
  echo "$main_payload" | jq .
else
  echo "$main_payload" | gh api -X PUT "repos/$REPO/branches/main/protection" \
    -H "Accept: application/vnd.github+json" --input - >/dev/null
  echo "  · main protection applied."
fi

# ---- 4. Branch protection on develop ---------------------------------------
echo
echo "==> Branch protection: develop"
develop_payload=$(jq -n \
  --argjson contexts "$contexts" \
  '{
    required_status_checks: {
      strict: false,
      contexts: $contexts
    },
    enforce_admins: false,
    required_pull_request_reviews: {
      required_approving_review_count: 0,
      dismiss_stale_reviews: false,
      require_code_owner_reviews: false,
      bypass_pull_request_allowances: {
        users: [],
        teams: [],
        apps:  ["github-actions"]
      }
    },
    restrictions: null,
    required_linear_history: false,
    allow_force_pushes: false,
    allow_deletions: false,
    required_conversation_resolution: false,
    block_creations: false
  }'
)
if [[ "$DRY_RUN" == "true" ]]; then
  echo "  $ gh api -X PUT repos/$REPO/branches/develop/protection (payload below)"
  echo "$develop_payload" | jq .
else
  # If `develop` doesn't exist yet, skip with a clear message.
  if ! gh api "repos/$REPO/branches/develop" >/dev/null 2>&1; then
    echo "  · develop branch doesn't exist yet on the remote — skipping. Push it first."
  else
    echo "$develop_payload" | gh api -X PUT "repos/$REPO/branches/develop/protection" \
      -H "Accept: application/vnd.github+json" --input - >/dev/null
    echo "  · develop protection applied (github-actions[bot] in bypass list)."
  fi
fi

# ---- 5. Verify --------------------------------------------------------------
if [[ "$DRY_RUN" != "true" ]]; then
  echo
  echo "==> Verification"
  for br in main develop; do
    state=$(gh api "repos/$REPO/branches/$br/protection" 2>/dev/null \
              | jq -r '"PR required: \(.required_pull_request_reviews != null) | linear history: \(.required_linear_history.enabled // false) | force push: \(.allow_force_pushes.enabled // false) | bypass apps: \([.required_pull_request_reviews.bypass_pull_request_allowances.apps[]?.slug] | join(","))"' \
              || echo "(not protected)")
    printf "  · %-7s → %s\n" "$br" "$state"
  done
fi

cat <<EOF

============================================================
Done. Remaining manual steps that aren't safe to script blindly:
  - If you want to change the default branch from main → develop
    so PRs default-target develop, do it in Settings → General →
    Default branch. (Not done here because changing it can confuse
    in-flight PRs.)
  - GPG signing secrets (CR_GPG_KEY / CR_GPG_PASSPHRASE /
    CR_GPG_KEY_NAME) must be present in repo Secrets for the
    Release Charts workflow to sign tgzs. If you've never set them,
    run scripts/gen_chart_signing_key.sh and follow the prompts.
============================================================
EOF
