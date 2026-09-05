#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ] || { [ "$2" != dev ] && [ "$2" != staging ]; }; then
  echo "usage: bash scripts/seal-db-secret.sh <kube-context> <dev|staging>" >&2; exit 2
fi
kube_context="$1"
environment="$2"
namespace="taskflow-${environment}"
# Mark this existing Secret for adoption; do not change its password/data.
kubectl --context "${kube_context}" --namespace "${namespace}" annotate secret taskflow-postgres \
  sealedsecrets.bitnami.com/managed=true sealedsecrets.bitnami.com/patch=true --overwrite
ciphertext="$(kubectl --context "${kube_context}" --namespace "${namespace}" get secret taskflow-postgres -o json \
  | kubeseal --context "${kube_context}" --controller-name sealed-secrets-controller --controller-namespace kube-system --format json \
  | jq -er '.spec.encryptedData.password')"
TF_SEALED_PASSWORD="${ciphertext}" yq -i '.sealedSecret.encryptedPassword = strenv(TF_SEALED_PASSWORD)' \
  "deploy/chart/taskflow/values-${environment}.yaml"
echo "Only encrypted password data was written to ${environment} values. Review and submit a PR."
