#!/usr/bin/env bash
# Decide the next chart bump level from the *quantity* of change since the
# last major-version baseline, following the "Bumpy" SemVer strategy
# documented in improvements/bumpy.md.
#
# Algorithm (in order):
#   1. Find the baseline = last `n8n-<MAJOR>.0.0` tag (i.e., the most
#      recent major). If none, fall back to the chart's first commit.
#   2. Measure baseline_size = lines of code in `charts/n8n/` at the
#      baseline (excluding generated artifacts: __snapshot__, Chart.lock,
#      lockfiles, vendored subcharts/).
#   3. Diff `<baseline>..HEAD` over the same path filter; collect
#      added / removed line counts.
#   4. Compute net% = (added - removed) / baseline_size * 100
#               churn% = (added + removed) / baseline_size * 100.
#   5. Apply the bumpy thresholds:
#        - High churn (> 10%) AND low net (< 5%) → PATCH (refactor).
#        - Net ≥ 15%  → MAJOR  (will be capped — see below).
#        - Net ≥ 5%   → MINOR.
#        - else       → PATCH.
#   6. **Cap MAJOR at MINOR.** The chart MAJOR is pinned to the n8n
#      binary MAJOR (see CONTRIBUTING.md "Branch strategy"); chart-side
#      changes never raise the chart's MAJOR component on their own.
#   7. A `BREAKING CHANGE:` marker in any commit message since the
#      baseline raises the floor to MINOR (still capped — never MAJOR).
#
# Output (stdout, machine-parseable):
#   LEVEL=<patch|minor>
#   NET_PCT=<x.xx>
#   CHURN_PCT=<x.xx>
#   ADDED=<n>
#   REMOVED=<n>
#   BASELINE=<tag-or-sha>
#   BASELINE_SIZE=<lines>
#
# Flags:
#   --range <REV>..<REV>   Override the diff range (default:
#                          baseline..HEAD). Useful for hotfix mode where
#                          we want the bump computed from a single
#                          commit instead of "everything since baseline".
#   --json                 Emit the result as a single-line JSON object
#                          (handy for `gh api` / step outputs).
#
# Usage:
#     scripts/bumpy_decide.sh
#     scripts/bumpy_decide.sh --range HEAD~1..HEAD          # hotfix
#     scripts/bumpy_decide.sh --json

set -euo pipefail

# Force C locale so awk uses '.' (not ',') as the decimal separator and
# numeric comparisons stay portable across French / German / etc. dev hosts.
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO"

range_override=""
emit_json=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --range) range_override="$2"; shift 2 ;;
    --json)  emit_json=true; shift ;;
    -h|--help)
      sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 64 ;;
  esac
done

# --- 1. Baseline -------------------------------------------------------------
# The chart's last MAJOR (n8n-X.0.0). If absent, use the first commit
# that introduced any file under charts/n8n/.
baseline=$(git tag --list 'n8n-*.0.0' --sort=-v:refname | head -1 || true)
if [[ -z "$baseline" ]]; then
  baseline=$(git rev-list --reverse HEAD -- charts/n8n/ | head -1 || git rev-list --reverse HEAD | head -1)
fi
if [[ -z "$baseline" ]]; then
  echo "Cannot determine baseline (no n8n-*.0.0 tag and no chart history)." >&2
  exit 1
fi

# --- 2. Baseline size --------------------------------------------------------
# Count non-blank lines under charts/n8n/ at the baseline, excluding
# generated artifacts that should not count toward bumpy's "project size".
# `git ls-tree` does NOT honour `:!` pathspec excludes — use a grep filter
# instead. The diff step further down DOES use the pathspec exclude form,
# which `git diff` supports natively.
EXCLUDE_REGEX='(charts/n8n/unittests/__snapshot__/|charts/n8n/Chart\.lock$|charts/n8n/charts/)'

count_lines_at() {
  local ref="$1"
  local files
  files=$(git ls-tree -r --name-only "$ref" -- charts/n8n/ 2>/dev/null \
            | grep -vE "$EXCLUDE_REGEX" || true)
  [[ -z "$files" ]] && { echo 0; return; }
  local total=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    n=$(git show "$ref:$f" 2>/dev/null | grep -cE '^[[:space:]]*[^[:space:]]' || true)
    total=$((total + n))
  done <<< "$files"
  echo "$total"
}
baseline_size=$(count_lines_at "$baseline")
if (( baseline_size == 0 )); then
  # Shouldn't happen, but guard against divide-by-zero.
  baseline_size=1
fi

# --- 3. Diff range -----------------------------------------------------------
range="${range_override:-${baseline}..HEAD}"

# Pathspec excludes (the `:!` form) work fine with `git diff`.
DIFF_EXCLUDES=(
  ':!charts/n8n/unittests/__snapshot__'
  ':!charts/n8n/Chart.lock'
  ':!charts/n8n/charts'
)

# `--shortstat` gives "N files changed, X insertions(+), Y deletions(-)"
# OR a subset if either count is 0. Parse defensively.
diff_stat=$(git diff --shortstat "$range" -- charts/n8n/ "${DIFF_EXCLUDES[@]}" 2>/dev/null || true)
added=$(  printf '%s\n' "$diff_stat" | grep -oE '[0-9]+ insertions?' | grep -oE '[0-9]+' || echo 0)
removed=$(printf '%s\n' "$diff_stat" | grep -oE '[0-9]+ deletions?'  | grep -oE '[0-9]+' || echo 0)
added=${added:-0}
removed=${removed:-0}

# --- 4. Percentages ----------------------------------------------------------
# bc returns a string; default to 0 on empty input.
net_pct=$(awk -v a="$added" -v r="$removed" -v b="$baseline_size" 'BEGIN{ printf "%.2f", (a - r) / b * 100 }')
churn_pct=$(awk -v a="$added" -v r="$removed" -v b="$baseline_size" 'BEGIN{ printf "%.2f", (a + r) / b * 100 }')

# Build the float-comparison helpers in awk for portability.
ge() { awk -v x="$1" -v y="$2" 'BEGIN{ exit (x+0 >= y+0) ? 0 : 1 }'; }
lt() { awk -v x="$1" -v y="$2" 'BEGIN{ exit (x+0 <  y+0) ? 0 : 1 }'; }

# --- 5. Detect breaking-change marker ---------------------------------------
breaking="false"
if git log --format=%B "$range" -- charts/n8n/ 2>/dev/null | grep -qE '^BREAKING CHANGE:'; then
  breaking="true"
fi

# --- 6. Decide ---------------------------------------------------------------
level="patch"
# Refactor: lots of churn but little net growth → patch (overrides MAJOR).
if ge "$churn_pct" 10 && lt "$net_pct" 5; then
  level="patch"
elif [[ "$breaking" == "true" ]]; then
  level="minor"   # would be MAJOR; capped (see #7).
elif ge "$net_pct" 15; then
  level="minor"   # would be MAJOR; capped.
elif ge "$net_pct" 5; then
  level="minor"
fi

# --- 7. Emit -----------------------------------------------------------------
if $emit_json; then
  printf '{"level":"%s","net_pct":%s,"churn_pct":%s,"added":%d,"removed":%d,"baseline":"%s","baseline_size":%d,"breaking":%s}\n' \
    "$level" "$net_pct" "$churn_pct" "$added" "$removed" "$baseline" "$baseline_size" "$breaking"
else
  cat <<EOF
LEVEL=$level
NET_PCT=$net_pct
CHURN_PCT=$churn_pct
ADDED=$added
REMOVED=$removed
BASELINE=$baseline
BASELINE_SIZE=$baseline_size
BREAKING=$breaking
EOF
fi

# Human-readable summary to stderr.
breaking_note=""
[[ "$breaking" == "true" ]] && breaking_note="  (BREAKING CHANGE marker present — capped at MINOR per chart-MAJOR rule)"
{
  echo "=================================================================="
  echo "Bumpy decision:        ${level}${breaking_note}"
  echo "Baseline:              $baseline ($baseline_size lines under charts/n8n/)"
  echo "Range:                 $range"
  echo "Added / removed lines: $added / $removed"
  printf "Net change %%:          %s%%\n"   "$net_pct"
  printf "Churn %%:               %s%%\n"   "$churn_pct"
  echo "Thresholds:            patch < 5%% ≤ minor < 15%% ≤ major (capped);"
  echo "                       refactor override: churn > 10%% AND net < 5%% → patch."
  echo "=================================================================="
} >&2
