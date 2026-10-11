#!/usr/bin/env bash
# helm-render-diff.sh — render a HelmRelease's chart at two git revisions and
# diff the results. Fills the gap left by the absent `flux diff helmrelease`
# (chart rendering in diff is fluxcd/flux2#2434): approximates a pre-merge
# render diff on a machine that holds the SOPS age key.
#
# Usage:
#   bash scripts/helm-render-diff.sh <path/to/app/helm-release.yaml>
#
#   BASE_REF=main   bash scripts/helm-render-diff.sh <file>   # default: origin/main
#   ENV_FILE=clusters/main/clusterenv.yaml                    # substitution source (default)
#
# <file> is a repo-relative path, and the working tree is compared against
# BASE_REF: the base revision is rendered with ITS pinned chart version and
# values, the working tree with its own — so chart-version bumps show up in
# the diff too. If the file does not exist in BASE_REF (new app), the base
# side is empty and the diff is all-additions.
#
# Requires: git, sops, flux, helm, yq. The SOPS age key is resolved like
# this: SOPS_AGE_KEY_FILE if set (.envrc/direnv does this), else age.agekey
# in the repo root (gitignored), else failure with instructions. No direnv
# dependency.
#
# Both yq dialects are supported: mikefarah Go yq and the kislyuk python
# yq/jq wrapper. The python dialect emits JSON (quoted strings), so scalar
# extraction goes through yq_scalar which strips the surrounding quotes.
#
# Exit code follows diff(1): 0 = renders identical, 1 = differences (review
# them), 2 = error.
#
# SECURITY: substitution turns SOPS-encrypted values into plaintext secrets.
# All intermediate files live in a chmod-700 temp dir and are shredded on
# exit. The diff itself is printed to your terminal — do not redirect it
# into a file you keep.
set -euo pipefail

BASE_REF="${BASE_REF:-origin/main}"
ENV_FILE="${ENV_FILE:-clusters/main/clusterenv.yaml}"
HR_FILE="${1:-}"

fail() { echo "error: $*" >&2; exit 2; }

[ -n "$HR_FILE" ] && [ -f "$HR_FILE" ] || fail "usage: bash $0 <path/to/helm-release.yaml> (repo-relative)"
[ -f "$ENV_FILE" ] || fail "env file not found: $ENV_FILE (set ENV_FILE)"
for tool in git sops flux helm yq diff; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing required tool: $tool"
done

# --- age key preflight (before any decryption) ------------------------------
# .envrc wires SOPS_AGE_KEY_FILE via direnv; do not depend on direnv being
# active — fall back to the repo-root keyfile like .envrc does.
if [ -z "${SOPS_AGE_KEY_FILE:-}" ]; then
  if [ -f "$PWD/age.agekey" ]; then
    export SOPS_AGE_KEY_FILE="$PWD/age.agekey"
  else
    fail "SOPS_AGE_KEY_FILE is not set and no age.agekey found in the repo root. export SOPS_AGE_KEY_FILE=<path to the age private key>"
  fi
fi
[ -f "$SOPS_AGE_KEY_FILE" ] || fail "SOPS_AGE_KEY_FILE points to a missing file: $SOPS_AGE_KEY_FILE"
if ! sops -d "$ENV_FILE" > /dev/null 2>&1; then
  fail "cannot decrypt $ENV_FILE with the key at $SOPS_AGE_KEY_FILE — wrong key? The file's sops metadata lists the expected age recipient; compare with the 'public key' line of the key file"
fi

# Scalar extraction that tolerates both yq dialects: the python yq wrapper
# emits JSON, so strings come back double-quoted; mikefarah yq emits them raw.
# Strips one pair of surrounding double quotes if present.
yq_scalar() {  # $1: expression, $2: file
  yq "$1" "$2" | sed -e 's/^"\(.*\)"$/\1/'
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hrdiff.XXXXXXXX")"
chmod 700 "$WORK"
cleanup() {
  if command -v shred >/dev/null 2>&1; then
    find "$WORK" -type f -exec shred -u {} + 2>/dev/null || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

# Substitute ${VAR} placeholders from the SOPS-encrypted clusterenv the same
# way Flux postBuild does at reconcile time (flux envsubst), then extract
# spec.values into a plain helm values file. (python-yq emits JSON here,
# which helm accepts as a values file — JSON is a YAML subset.)
subst_values() {  # $1: helm-release.yaml (raw) -> $WORK/.values
  if ! sops exec-env "$ENV_FILE" "flux envsubst --strict < '$1' > '$WORK/.subst'"; then
    fail "substitution failed for $1 — sops decryption or envsubst failure (check SOPS_AGE_KEY_FILE and for undefined variables)"
  fi
  local vals
  vals="$(yq '.spec.values' "$WORK/.subst")"
  if [ "$vals" = "null" ]; then
    printf '{}\n' > "$WORK/.values"
  else
    printf '%s\n' "$vals" > "$WORK/.values"
  fi
}

# Render one HelmRelease (any revision) into $2.
render_from_file() {  # $1: helm-release.yaml (raw), $2: output file
  local f="$1" out="$2" name ns chart ver src repo_file type url ref
  name="$(yq_scalar '.metadata.name' "$f")"
  ns="$(yq_scalar '.metadata.namespace' "$f")"
  chart="$(yq_scalar '.spec.chart.spec.chart' "$f")"
  ver="$(yq_scalar '.spec.chart.spec.version' "$f")"
  src="$(yq_scalar '.spec.chart.spec.sourceRef.name' "$f")"

  repo_file="repositories/helm/${src}.yaml"
  [ -f "$repo_file" ] || fail "HelmRepository manifest not found: $repo_file"
  type="$(yq_scalar '.spec.type // ""' "$repo_file")"
  url="$(yq_scalar '.spec.url' "$repo_file")"

  case "$type" in
    oci) ref="${url}/${chart}" ;;
    http|https|"")
      helm repo add "$src" "$url" >/dev/null 2>&1 || true
      helm repo update >/dev/null 2>&1 || true
      ref="${src}/${chart}" ;;
    *) fail "unsupported repository type '$type' in $repo_file" ;;
  esac

  subst_values "$f"
  if [ -n "$ver" ] && [ "$ver" != "null" ]; then
    helm template "$name" "$ref" --version "$ver" -n "$ns" -f "$WORK/.values" > "$out"
  else
    helm template "$name" "$ref" -n "$ns" -f "$WORK/.values" > "$out"
  fi
  echo "rendered: $name ($ref@${ver:-latest}) from $f" >&2
}

BASE_OUT="$WORK/render-base.yaml"
HEAD_OUT="$WORK/render-head.yaml"

if git show "${BASE_REF}:${HR_FILE}" > "$WORK/base-hr.yaml" 2>/dev/null; then
  render_from_file "$WORK/base-hr.yaml" "$BASE_OUT" || exit 2
else
  echo "note: $HR_FILE does not exist in $BASE_REF — rendering head only; diff is all-additions" >&2
  : > "$BASE_OUT"
fi

render_from_file "$HR_FILE" "$HEAD_OUT" || exit 2

rc=0
diff -u "$BASE_OUT" "$HEAD_OUT" || rc=$?
if [ "$rc" -eq 0 ]; then
  echo "renders identical" >&2
else
  echo "renders differ (exit 1) — review the diff above" >&2
fi
exit "$rc"
