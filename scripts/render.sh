#!/usr/bin/env bash
set -euo pipefail

mkdir -p .cache/rendered/first-party .cache/rendered/upstream .cache/upstream .cache/schemas
temporary_directory="$(mktemp -d)"
trap 'rm -rf "${temporary_directory}"' EXIT

for environment in dev staging local; do
  helm lint deploy/chart/taskflow --values "deploy/chart/taskflow/values-${environment}.yaml"
  helm template taskflow deploy/chart/taskflow --kube-version 1.36.3 \
    --namespace "taskflow-${environment}" \
    --values "deploy/chart/taskflow/values-${environment}.yaml" \
    > ".cache/rendered/first-party/taskflow-${environment}.yaml"
done
kustomize build platform/gitops > .cache/rendered/first-party/gitops.yaml
kustomize build platform/config > .cache/rendered/first-party/platform-config.yaml
cp platform/bootstrap/root-application.yaml .cache/rendered/first-party/root-application.yaml
for manifest in labs/raw/*.yaml; do
  cp "${manifest}" ".cache/rendered/first-party/lab-$(basename "${manifest}")"
done

# Render exactly the Helm releases Argo CD will use, not just our values files.
while IFS= read -r application; do
  chart="$(jq -r '.spec.sources[0].chart' <<<"${application}")"
  release="$(jq -r '.spec.sources[0].helm.releaseName' <<<"${application}")"
  namespace="$(jq -r '.spec.destination.namespace' <<<"${application}")"
  archive="$(bash scripts/fetch-chart.sh "${chart}")"
  helm template "${release}" "${archive}" --kube-version 1.36.3 --include-crds \
    --namespace "${namespace}" --values "platform/addons/values/${chart}.yaml" \
    > ".cache/rendered/upstream/${chart}.yaml"
done < <(yq -o=json -I=0 'select(.kind == "Application")' platform/gitops/addons.yaml)
for chart in ingress-nginx metrics-server; do
  archive="$(bash scripts/fetch-chart.sh "${chart}")"
  values="platform/kind/ingress-values.yaml"
  if [ "${chart}" = metrics-server ]; then values="platform/kind/metrics-server-values.yaml"; fi
  helm template "${chart}" "${archive}" --kube-version 1.36.3 --namespace "${chart}" \
    --include-crds --values "${values}" > ".cache/rendered/upstream/${chart}.yaml"
done

# Checksum the raw Argo CD release before applying our Kustomize patches.
argocd_version="$(yq -r '.argocd.version' platform/versions.yaml)"
argocd_file=".cache/upstream/argocd-${argocd_version}.yaml"
if [ ! -f "${argocd_file}" ]; then
  curl --fail --silent --show-error --location --retry 3 \
    "https://raw.githubusercontent.com/argoproj/argo-cd/${argocd_version}/manifests/install.yaml" \
    --output "${argocd_file}"
fi
expected_sha="$(yq -r '.argocd.manifestSHA256' platform/versions.yaml)"
actual_sha="$(shasum -a 256 "${argocd_file}" | awk '{print $1}')"
if [ "${actual_sha}" != "${expected_sha}" ]; then
  echo "Argo CD manifest checksum mismatch." >&2
  exit 1
fi
cp "${argocd_file}" "${temporary_directory}/install.yaml"
cp platform/bootstrap/argocd/namespace.yaml platform/bootstrap/argocd/config.yaml "${temporary_directory}/"
yq '.resources = ["namespace.yaml", "install.yaml"]' platform/bootstrap/argocd/kustomization.yaml \
  > "${temporary_directory}/kustomization.yaml"
kustomize build "${temporary_directory}" > .cache/rendered/upstream/argocd.yaml
yq -o=json eval-all '[select(.kind == "CustomResourceDefinition")]' .cache/rendered/upstream/*.yaml \
  | python3 scripts/extract-crd-schemas.py .cache/schemas
# The default registry omits the standalone CRD kind schema. Derive it from
# Kubernetes' own versioned API-extension OpenAPI document, without skipping it.
schema_version="$(yq -r '.apiextensionsSchema.version' platform/versions.yaml)"
schema_file=".cache/upstream/apiextensions-v${schema_version}.json"
if [ ! -f "${schema_file}" ]; then
  curl --fail --silent --show-error --location --retry 3 \
    "https://raw.githubusercontent.com/kubernetes/kubernetes/v${schema_version}/api/openapi-spec/v3/apis__apiextensions.k8s.io__v1_openapi.json" \
    --output "${schema_file}"
fi
if [ "$(shasum -a 256 "${schema_file}" | awk '{print $1}')" != "$(yq -r '.apiextensionsSchema.sha256' platform/versions.yaml)" ]; then
  echo "API-extension schema checksum mismatch." >&2; exit 1
fi
python3 scripts/extract-api-schema.py "${schema_file}" .cache/schemas
echo "Rendered application, platform, and pinned upstream releases in .cache/rendered."
