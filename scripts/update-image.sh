#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ] || { [ "$1" != dev ] && [ "$1" != staging ]; }; then
  echo "usage: bash scripts/update-image.sh <dev|staging> <sha256:digest> <40-character-commit-sha>" >&2
  exit 2
fi
if ! [[ "$2" =~ ^sha256:[a-f0-9]{64}$ ]] || ! [[ "$3" =~ ^[a-f0-9]{40}$ ]]; then
  echo "A full image digest and source commit SHA are required." >&2
  exit 2
fi
TF_IMAGE_DIGEST="$2" TF_IMAGE_TAG="$3" yq -i \
  '.image.digest = strenv(TF_IMAGE_DIGEST) | .image.tag = strenv(TF_IMAGE_TAG)' \
  "deploy/chart/taskflow/values-$1.yaml"
