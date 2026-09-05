#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then echo "usage: bash scripts/test-sealed-secret.sh <lab-context>" >&2; exit 2; fi
kube_context="$1"
case "${kube_context}" in colima-k3s-lab|kind-sre-lab) ;; *) exit 2 ;; esac
namespace="taskflow-seal-check-$(date -u +%Y%m%d%H%M%S)-$$"
# Only this successfully created disposable namespace is eligible for cleanup.
kubectl --context "${kube_context}" create namespace "${namespace}"
trap 'kubectl --context "${kube_context}" delete namespace "${namespace}" --wait=false >/dev/null' EXIT
kubectl --context "${kube_context}" --namespace "${namespace}" create secret generic seal-probe \
  --from-literal=probe=public-disposable-test-value
kubectl --context "${kube_context}" --namespace "${namespace}" annotate secret seal-probe \
  sealedsecrets.bitnami.com/managed=true
original_uid="$(kubectl --context "${kube_context}" --namespace "${namespace}" get secret seal-probe -o jsonpath='{.metadata.uid}')"
original_data="$(kubectl --context "${kube_context}" --namespace "${namespace}" get secret seal-probe -o jsonpath='{.data.probe}')"
kubectl --context "${kube_context}" --namespace "${namespace}" get secret seal-probe -o json \
  | kubeseal --context "${kube_context}" --controller-name sealed-secrets-controller --controller-namespace kube-system --format json \
  | kubectl --context "${kube_context}" --namespace "${namespace}" apply -f -
kubectl --context "${kube_context}" --namespace "${namespace}" wait --for=condition=Synced sealedsecret/seal-probe --timeout=60s
kubectl --context "${kube_context}" --namespace "${namespace}" delete secret seal-probe
for _attempt in $(seq 1 30); do
  recovered="$(kubectl --context "${kube_context}" --namespace "${namespace}" get secret seal-probe --ignore-not-found -o json)"
  if [ -n "${recovered}" ] \
    && [ "$(jq -r '.metadata.uid' <<<"${recovered}")" != "${original_uid}" ] \
    && [ "$(jq -r '.data.probe' <<<"${recovered}")" = "${original_data}" ]; then
    echo "Sealing passed: the controller recreated the disposable Secret with identical data."
    exit 0
  fi
  sleep 1
done
echo "The disposable Secret was not recreated correctly." >&2
exit 1
