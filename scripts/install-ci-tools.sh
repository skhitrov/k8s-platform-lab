#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname -s)-$(uname -m)" != Linux-x86_64 ]; then
  echo "This installer is for GitHub-hosted Linux AMD64 runners. On macOS use the README Homebrew commands." >&2
  exit 2
fi
binary_directory="$(pwd)/.cache/bin"
download_directory="$(mktemp -d)"
trap 'rm -rf "${download_directory}"' EXIT
mkdir -p "${binary_directory}"
while IFS= read -r tool; do
  tool_name="$(jq -r '.name' <<<"${tool}")"
  if [ "$#" -gt 0 ] && [ "$1" != "${tool_name}" ]; then
    continue
  fi
  tool_url="$(jq -r '.url' <<<"${tool}")"
  tool_sha="$(jq -r '.sha256' <<<"${tool}")"
  tool_format="$(jq -r '.format' <<<"${tool}")"
  archive_path="${download_directory}/${tool_name}.download"
  curl --fail --silent --show-error --location --retry 3 "${tool_url}" --output "${archive_path}"
  printf '%s  %s\n' "${tool_sha}" "${archive_path}" | sha256sum --check --status
  if [ "${tool_format}" = binary ]; then
    install -m 0755 "${archive_path}" "${binary_directory}/${tool_name}"
  else
    mkdir -p "${download_directory}/${tool_name}"
    tar -xzf "${archive_path}" -C "${download_directory}/${tool_name}"
    tool_binary="$(jq -r '.binary' <<<"${tool}")"
    install -m 0755 "${download_directory}/${tool_name}/${tool_binary}" "${binary_directory}/${tool_name}"
  fi
done < <(jq -c '.[]' platform/ci-tools.json)
if [ "$#" -eq 0 ]; then
  GOBIN="${binary_directory}" go install golang.org/x/vuln/cmd/govulncheck@v1.7.0
elif [ ! -x "${binary_directory}/$1" ]; then
  echo "Unknown tool: $1" >&2
  exit 2
fi
if [ -n "${GITHUB_PATH:-}" ]; then
  printf '%s\n' "${binary_directory}" >> "${GITHUB_PATH}"
fi
echo "Installed checksum-verified CI tools in ${binary_directory}."
