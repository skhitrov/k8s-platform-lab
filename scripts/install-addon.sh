#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: bash scripts/install-addon.sh <colima-k3s-lab|kind-sre-lab> <addon-chart>" >&2; exit 2
fi
kube_context="$1"
chart="$2"
case "${kube_context}" in
  colima-k3s-lab|kind-sre-lab) ;;
  *) echo "Use a named lab context." >&2; exit 2 ;;
esac
case "${chart}" in
  sealed-secrets) namespace=kube-system ;;
  cert-manager) namespace=cert-manager ;;
  argo-rollouts) namespace=argo-rollouts ;;
  kube-prometheus-stack|loki|tempo|alloy|opentelemetry-collector) namespace=observability ;;
  *) echo "Unknown platform add-on: ${chart}" >&2; exit 2 ;;
esac
if [ -n "$(kubectl --context "${kube_context}" get crd applications.argoproj.io --ignore-not-found -o name)" ]; then
  existing_application="$(kubectl --context "${kube_context}" --namespace argocd get applications.argoproj.io \
    "${chart}" --ignore-not-found -o name)"
  if [ -n "${existing_application}" ]; then
    echo "Argo CD owns ${chart}; update Git instead of running a Helm upgrade." >&2; exit 1
  fi
fi
if [ "${namespace}" = observability ]; then
  bash scripts/create-platform-secrets.sh "${kube_context}"
fi
if [ "${chart}" = alloy ]; then
  # Namespace-scoped event Roles also cover Argo before Week 8 installs it.
  kubectl --context "${kube_context}" create namespace argocd --dry-run=client -o yaml \
    | kubectl --context "${kube_context}" apply -f -
fi
archive="$(bash scripts/fetch-chart.sh "${chart}")"
helm upgrade --install "${chart}" "${archive}" --kube-context "${kube_context}" \
  --namespace "${namespace}" --create-namespace \
  --values "platform/addons/values/${chart}.yaml" --wait --wait-for-jobs --timeout 8m
if [ "${chart}" = kube-prometheus-stack ]; then
  # Helm cannot infer health of the workloads reconciled from these CRs.
  kubectl --context "${kube_context}" --namespace observability wait --for=condition=Available \
    prometheus/kube-prometheus-stack-prometheus alertmanager/kube-prometheus-stack-alertmanager --timeout=3m
fi
echo "Installed ${chart} for pre-GitOps practice. Once Argo owns it, change Git only."
