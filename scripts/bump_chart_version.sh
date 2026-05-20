#!/usr/bin/env bash
# Compute and apply the chart version bump for a develop → main release PR.
#
# Reads the last released tag (e.g. `n8n-2.4.0`), walks the conventional
# commits since that tag that touched `charts/n8n/`, picks the bump level,
# and writes the result into:
#   - charts/n8n/Chart.yaml#version
#   - charts/n8n/RELEASE-NOTES.md   (insert a `## <new-version>` stub)
#   - charts/n8n/Chart.yaml#annotations.artifacthub.io/changes (one entry
#     per conventional commit, mapped: feat→added, fix→fixed, breaking →
#     changed, anything else → changed)
#
# Idempotent: running twice with no new commits is a no-op. Running again
# after more commits land recomputes the target version from the same
# baseline (the last released tag, not the last bumped Chart.yaml).
#
# The chart MAJOR is pinned to the n8n binary MAJOR (see CONTRIBUTING.md)
# so BREAKING CHANGE / `feat!:` commits cap at MINOR, never MAJOR.
#
# Outputs (stdout):
#   BUMP_LEVEL=<none|patch|minor>
#   PREVIOUS_VERSION=<x.y.z>
#   NEW_VERSION=<x.y.z>
#   CHANGED=<true|false>
#
# Usage (local):  ./scripts/bump_chart_version.sh
# Usage (CI):     ./scripts/bump_chart_version.sh   (then commit + push)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
CHART_FILE="$REPO/charts/n8n/Chart.yaml"
RELEASE_NOTES="$REPO/charts/n8n/RELEASE-NOTES.md"

command -v git    >/dev/null || { echo "git not installed"    >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 not installed" >&2; exit 1; }

cd "$REPO"

# ---- 1. Baseline — last released tag, fall back to current Chart.yaml -----
last_tag=$(git tag --list 'n8n-*' --sort=-v:refname 2>/dev/null | head -1 || true)
if [[ -z "$last_tag" ]]; then
  # No release tags yet. Use the current Chart.yaml#version as baseline so
  # this becomes a no-op on first run, leaving the maintainer in charge.
  last_ver=$(awk '/^version:/{print $2; exit}' "$CHART_FILE")
  echo "No release tag found; using current Chart.yaml version $last_ver as baseline." >&2
else
  last_ver=${last_tag#n8n-}
fi

if ! [[ "$last_ver" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "Cannot parse SemVer from $last_ver (tag=$last_tag)" >&2; exit 1
fi
last_major=${BASH_REMATCH[1]}
last_minor=${BASH_REMATCH[2]}
last_patch=${BASH_REMATCH[3]}

# ---- 2. Walk conventional commits since the baseline ----------------------
# Only consider commits that actually touched the chart directory; pure
# docs / CI / scripts churn shouldn't force a bump.
range="${last_tag:-HEAD}..HEAD"
[[ -z "$last_tag" ]] && range="HEAD"

mapfile -t commit_subjects < <(
  git log --no-merges --pretty=format:'%H%x09%s%x09%b' "$range" -- charts/n8n/ 2>/dev/null \
    | awk -F'\t' '{print $1"\t"$2}'
)

bump_level="none"
declare -a changelog_added=() changelog_fixed=() changelog_changed=()

# Map a conventional-commit subject onto a (kind, description) pair.
classify() {
  local subj="$1"
  # Strip Conventional-Commit type/scope prefix → leave description.
  local desc
  desc=$(echo "$subj" | sed -E 's/^[a-zA-Z]+(\([^)]+\))?!?:[[:space:]]*//')

  case "$subj" in
    *"BREAKING CHANGE"*|feat!:*|feat\(*\)!:*|fix!:*|fix\(*\)!:*|refactor!:*|chore!:*)
      [[ "$bump_level" == "none" || "$bump_level" == "patch" ]] && bump_level="minor"
      changelog_changed+=("$desc")
      ;;
    feat:*|feat\(*\):*)
      [[ "$bump_level" == "none" || "$bump_level" == "patch" ]] && bump_level="minor"
      changelog_added+=("$desc")
      ;;
    fix:*|fix\(*\):*)
      [[ "$bump_level" == "none" ]] && bump_level="patch"
      changelog_fixed+=("$desc")
      ;;
    refactor:*|refactor\(*\):*|perf:*|perf\(*\):*|chore:*|chore\(*\):*|ci:*|ci\(*\):*|docs:*|docs\(*\):*|test:*|test\(*\):*|style:*|style\(*\):*)
      [[ "$bump_level" == "none" ]] && bump_level="patch"
      changelog_changed+=("$desc")
      ;;
    *)
      # Non-conventional subject — still counts as a chart change, classify as `changed`.
      [[ "$bump_level" == "none" ]] && bump_level="patch"
      changelog_changed+=("$desc")
      ;;
  esac
}

for line in "${commit_subjects[@]}"; do
  [[ -z "$line" ]] && continue
  IFS=$'\t' read -r _sha subject <<<"$line"
  [[ -z "$subject" ]] && continue
  # Skip the auto-bump commits the bot wrote on a previous PR sync —
  # otherwise every re-run inflates the changelog with its own commits.
  [[ "$subject" == chore\(release\):* ]] && continue
  classify "$subject"
done

# Filter empties out of the per-kind buckets (commits whose subject was
# pure prefix, e.g. `chore:`). bash arrays don't have a clean filter
# primitive, so do it manually.
filter_empty() {
  local -n arr=$1
  local -a kept=()
  for x in "${arr[@]}"; do
    [[ -n "$x" ]] && kept+=("$x")
  done
  arr=("${kept[@]}")
}
filter_empty changelog_added
filter_empty changelog_fixed
filter_empty changelog_changed

# Cap at 20 entries per kind to keep the annotation block readable.
# Artifact Hub renders this verbatim; an unbounded list buries the
# substantive entries under churn.
cap_entries() {
  local -n arr=$1
  if (( ${#arr[@]} > 20 )); then
    arr=("${arr[@]:0:20}")
  fi
}
cap_entries changelog_added
cap_entries changelog_fixed
cap_entries changelog_changed

# ---- 3. Compute target version --------------------------------------------
case "$bump_level" in
  minor) new_ver="${last_major}.$((last_minor + 1)).0" ;;
  patch) new_ver="${last_major}.${last_minor}.$((last_patch + 1))" ;;
  none)
    echo "BUMP_LEVEL=none"
    echo "PREVIOUS_VERSION=$last_ver"
    echo "NEW_VERSION=$last_ver"
    echo "CHANGED=false"
    echo "No chart-touching commits since ${last_tag:-baseline}; nothing to bump." >&2
    exit 0
    ;;
esac

current_ver=$(awk '/^version:/{print $2; exit}' "$CHART_FILE")

# Never downgrade. If Chart.yaml is ahead of the computed bump (e.g. a
# previous PR manually pinned a version higher than the conventional-
# commit log alone would suggest), keep the higher version.
ver_cmp() {
  # Print 0 if equal, -1 if $1 < $2, +1 if $1 > $2.
  local a b
  IFS=. read -ra a <<<"$1"; IFS=. read -ra b <<<"$2"
  for i in 0 1 2; do
    if (( ${a[i]:-0} < ${b[i]:-0} )); then echo -1; return; fi
    if (( ${a[i]:-0} > ${b[i]:-0} )); then echo 1; return; fi
  done
  echo 0
}

if [[ "$(ver_cmp "$new_ver" "$current_ver")" -lt 0 ]]; then
  echo "Computed bump ($new_ver) would downgrade current Chart.yaml ($current_ver); keeping current." >&2
  new_ver="$current_ver"
fi

if [[ "$current_ver" == "$new_ver" ]]; then
  # Already at the target — still regenerate the changelog stubs in case
  # new commits landed since the previous run on the same PR.
  echo "Chart.yaml already at $new_ver; refreshing changelog stubs only." >&2
fi

echo "BUMP_LEVEL=$bump_level"
echo "PREVIOUS_VERSION=$last_ver"
echo "NEW_VERSION=$new_ver"

# ---- 4. Apply the version bump --------------------------------------------
# Chart.yaml#version (sed in place — line format is exact).
sed -i "s/^version: .*/version: $new_ver/" "$CHART_FILE"

# RELEASE-NOTES.md — insert a stub `## <new-version> (unreleased)` heading
# above the most recent existing `## ` block, only if it isn't already there.
if ! grep -qE "^## ${new_ver}(\b| )" "$RELEASE_NOTES"; then
  python3 - "$RELEASE_NOTES" "$new_ver" <<'PYEOF'
import sys, pathlib, re
path, new_ver = pathlib.Path(sys.argv[1]), sys.argv[2]
text = path.read_text()
heading = f"## {new_ver} (unreleased)\n\n<!-- TODO: replace this stub with the real changelog before merging the PR to main. Bullet style follows the existing entries (Added / Changed / Fixed / Removed). -->\n\n"
m = re.search(r"^## ", text, re.MULTILINE)
if m:
    text = text[:m.start()] + heading + text[m.start():]
else:
    text = text + "\n" + heading
path.write_text(text)
PYEOF
fi

# Chart.yaml#annotations.artifacthub.io/changes — replace the multi-line
# block in place. We do this in Python so YAML quoting / indent stays right.
python3 - "$CHART_FILE" "${changelog_added[@]:+--added}" "${changelog_added[@]}" \
                       "${changelog_fixed[@]:+--fixed}" "${changelog_fixed[@]}" \
                       "${changelog_changed[@]:+--changed}" "${changelog_changed[@]}" <<'PYEOF'
import sys, re, pathlib
args = sys.argv[2:]
buckets = {"added": [], "fixed": [], "changed": []}
current = None
for a in args:
    if a == "--added": current = "added"
    elif a == "--fixed": current = "fixed"
    elif a == "--changed": current = "changed"
    elif current is not None: buckets[current].append(a)

def yamlify(s):
    # Use double-quoted YAML so we don't have to think about indentation
    # or embedded special characters. Escape backslash and double-quote.
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

lines = ["  artifacthub.io/changes: |"]
for kind in ("added", "changed", "fixed"):
    for desc in buckets[kind]:
        lines.append(f"    - kind: {kind}")
        lines.append(f"      description: {yamlify(desc)}")
if len(lines) == 1:
    # Nothing to write — leave a single placeholder so YAML stays valid.
    lines.append('    - kind: changed')
    lines.append('      description: "Chart version bumped; see RELEASE-NOTES.md for details."')

new_block = "\n".join(lines) + "\n"

chart_path = pathlib.Path(sys.argv[1])
chart = chart_path.read_text()
# Replace the existing annotation block (the `artifacthub.io/changes: |`
# line through the last contiguous indented continuation).
pattern = re.compile(
    r"^  artifacthub\.io/changes:\s*\|[^\n]*\n(?:    [^\n]*\n)+",
    re.MULTILINE,
)
if pattern.search(chart):
    chart = pattern.sub(new_block, chart, count=1)
else:
    # Not present yet (shouldn't happen at this point in the project) —
    # append at end of `annotations:` block.
    chart = chart.rstrip() + "\n" + new_block
chart_path.write_text(chart)
PYEOF

# ---- 5. Report changed status ---------------------------------------------
changed=false
if ! git diff --quiet -- "$CHART_FILE" "$RELEASE_NOTES"; then
  changed=true
fi
echo "CHANGED=$changed"

# Print a short human-readable summary for CI logs / PR comments.
{
  echo
  echo "=================================================================="
  echo "Bump:               $bump_level"
  echo "Previous version:   $last_ver  ${last_tag:+(from tag $last_tag)}"
  echo "New version:        $new_ver"
  echo "Commits classified:"
  printf "  added:   %d\n" "${#changelog_added[@]}"
  printf "  fixed:   %d\n" "${#changelog_fixed[@]}"
  printf "  changed: %d\n" "${#changelog_changed[@]}"
  echo "=================================================================="
} >&2
