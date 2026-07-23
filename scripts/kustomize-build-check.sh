#!/usr/bin/env bash
#
# kustomize-build-check.sh - Build every kustomize component against its tier so a patch
# whose target does not exist fails here instead of in-cluster.
#
# Usage:
#   scripts/kustomize-build-check.sh            # every add-on under kustomize/
#   scripts/kustomize-build-check.sh <add-on>   # one add-on directory
#
# `windsor test` asserts what a facet composes, never what kustomize renders, so a broken
# JSON patch passes the facet suite untouched. A component nested inside another
# (install/registry/pvc) patches what its parent contributes, so it is built with every
# ancestor component that exists rather than against the bare tier.

set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

CHECK_DIR=.buildcheck
failures=0

cleanup() {
  find kustomize -type d -name "$CHECK_DIR" -prune -exec rm -rf {} + 2>/dev/null || true
}
trap cleanup EXIT

# True when $1 holds a kustomize Component rather than a plain overlay.
is_component() {
  [ -f "$1/kustomization.yaml" ] && grep -q '^kind: Component' "$1/kustomization.yaml"
}

# Build $tier of $addon with the components given as remaining arguments, each a path
# relative to the add-on directory.
build() {
  local addon=$1 tier=$2
  shift 2
  local label overlay out
  label=$(printf '%s' "$*" | tr ' /' '__')
  overlay="$addon/$CHECK_DIR/${tier}${label:+__$label}"
  mkdir -p "$overlay"
  {
    echo "apiVersion: kustomize.config.k8s.io/v1beta1"
    echo "kind: Kustomization"
    echo "resources:"
    echo "  - ../../$tier"
    if [ "$#" -gt 0 ]; then
      echo "components:"
      local c
      for c in "$@"; do echo "  - ../../$c"; done
    fi
  } >"$overlay/kustomization.yaml"

  if out=$(kustomize build --load-restrictor LoadRestrictionsNone "$overlay" 2>&1); then
    echo "ok: $addon $tier [${*:-base}]"
  else
    echo "FAIL: $addon $tier [${*:-base}]" >&2
    printf '%s\n' "$out" >&2
    failures=$((failures + 1))
  fi
}

check_addon() {
  local addon=$1 tier tier_path comp rel ancestors parent
  for tier in install resources; do
    tier_path="$addon/$tier"
    [ -d "$tier_path" ] || continue
    build "$addon" "$tier"

    # Every component under this tier, deepest last so ancestors are known to exist.
    while IFS= read -r comp; do
      is_component "$comp" || continue
      rel=${comp#"$addon"/}
      ancestors=()
      parent=$(dirname "$rel")
      while [ "$parent" != "." ]; do
        if is_component "$addon/$parent"; then
          ancestors=("$parent" "${ancestors[@]+"${ancestors[@]}"}")
        fi
        parent=$(dirname "$parent")
      done
      build "$addon" "$tier" ${ancestors[@]+"${ancestors[@]}"} "$rel"
    done < <(find "$tier_path" -mindepth 1 -type d -not -path "*/$CHECK_DIR/*" | sort)
  done
}

main() {
  if ! command -v kustomize >/dev/null 2>&1; then
    echo "error: kustomize is not installed" >&2
    exit 1
  fi
  cleanup

  if [ "$#" -gt 0 ]; then
    check_addon "${1%/}"
  else
    local addon
    for addon in kustomize/*/; do
      addon=${addon%/}
      [ -d "$addon/install" ] || [ -d "$addon/resources" ] || continue
      check_addon "$addon"
    done
  fi

  if [ "$failures" -gt 0 ]; then
    echo "error: $failures kustomize build(s) failed" >&2
    exit 1
  fi
  echo "all kustomize builds ok"
}

main "$@"
