#!/usr/bin/env bash
set -euo pipefail

digest="$(yq -er '.image.digest' deploy/chart/taskflow/values-dev.yaml)"
commit="$(yq -er '.image.tag' deploy/chart/taskflow/values-dev.yaml)"
bash scripts/update-image.sh staging "${digest}" "${commit}"
yq -i '.spec.generators[0].list.elements |= ((. + [{"environment": "staging"}]) | unique_by(.environment))' \
  platform/gitops/taskflow-applicationset.yaml
echo "Staging now references the exact dev digest. Submit and review this change as a PR."
