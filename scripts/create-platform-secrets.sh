#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: bash scripts/create-platform-secrets.sh <kube-context>" >&2
  exit 2
fi
kube_context="$1"
kubectl --context "${kube_context}" create namespace observability --dry-run=client -o yaml \
  | kubectl --context "${kube_context}" apply -f -
existing_secret="$(kubectl --context "${kube_context}" --namespace observability \
  get secret taskflow-grafana-admin --ignore-not-found -o name)"
if [ -z "${existing_secret}" ]; then
  password="$(openssl rand -base64 36 | tr -d '\n')"
  kubectl --context "${kube_context}" --namespace observability create secret generic taskflow-grafana-admin \
    --from-literal=admin-user=admin --from-literal="admin-password=${password}" \
    --dry-run=client -o yaml | kubectl --context "${kube_context}" create -f -
fi
