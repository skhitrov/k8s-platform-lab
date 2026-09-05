#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ] || ! [[ "$1" =~ ^[a-z][a-z0-9-]+$ ]]; then
  echo "usage: bash scripts/fetch-chart.sh <chart-key-from-platform/versions.yaml>" >&2
  exit 2
fi
chart_key="$1"
chart_version="$(yq -er ".charts.\"${chart_key}\".version" platform/versions.yaml)"
archive_url="$(yq -er ".charts.\"${chart_key}\".archive" platform/versions.yaml)"
expected_sha="$(yq -er ".charts.\"${chart_key}\".sha256" platform/versions.yaml)"
archive_path=".cache/charts/${chart_key}-${chart_version}.tgz"
mkdir -p .cache/charts
if [ ! -f "${archive_path}" ]; then
  curl --fail --location --silent --show-error --retry 3 \
    "${archive_url}" --output "${archive_path}.partial"
  mv "${archive_path}.partial" "${archive_path}"
fi
actual_sha="$(shasum -a 256 "${archive_path}" | awk '{print $1}')"
if [ "${actual_sha}" != "${expected_sha}" ]; then
  echo "SHA256 mismatch for ${archive_path}; refusing to use this archive." >&2
  exit 1
fi
printf '%s\n' "${archive_path}"
