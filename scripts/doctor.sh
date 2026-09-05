#!/usr/bin/env bash
set -euo pipefail

required_tools="colima docker go kubectl helm kustomize kind jq yq k6 kubeconform trivy actionlint gitleaks gh shellcheck govulncheck kubeseal rg python3"
missing=0

printf '%-18s %s\n' TOOL STATUS
for tool in ${required_tools}; do
  if command -v "${tool}" >/dev/null 2>&1; then
    printf '%-18s %s\n' "${tool}" "$(command -v "${tool}")"
  else
    printf '%-18s %s\n' "${tool}" MISSING
    missing=1
  fi
done

if command -v kubectl >/dev/null 2>&1; then
  kubectl_minor="$(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.minor' | tr -cd '0-9')"
  if [ -n "${kubectl_minor}" ] && { [ "${kubectl_minor}" -lt 35 ] || [ "${kubectl_minor}" -gt 37 ]; }; then
    echo "WARNING: kubectl minor ${kubectl_minor} is outside the intended 1.36 lab range."
    missing=1
  fi
fi

if command -v kind >/dev/null 2>&1; then
  kind version
  echo "The reproducible CI lock uses Kind 0.32.0; node images are digest-pinned independently."
fi
if command -v docker >/dev/null 2>&1; then
  docker compose version || missing=1
  docker buildx version || missing=1
fi

echo
colima list 2>/dev/null || true
echo
docker context show 2>/dev/null || true
kubectl config get-contexts 2>/dev/null || true

if [ "${missing}" -ne 0 ]; then
  echo
  echo "Install the missing tools listed above, then rerun make doctor."
  exit 1
fi
