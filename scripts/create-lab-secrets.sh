#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: scripts/create-lab-secrets.sh <kube-context> <namespace>" >&2
  exit 2
fi

kube_context="$1"
namespace="$2"
if ! [[ "${namespace}" =~ ^taskflow-[a-z0-9-]+$ ]]; then
  echo "Use a taskflow- namespace for this lab." >&2
  exit 2
fi

kubectl --context "${kube_context}" create namespace "${namespace}" --dry-run=client -o yaml \
  | kubectl --context "${kube_context}" apply -f -
kubectl --context "${kube_context}" label namespace "${namespace}" \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/enforce-version=v1.36 \
  --overwrite
existing_secret="$(kubectl --context "${kube_context}" --namespace "${namespace}" \
  get secret taskflow-postgres --ignore-not-found -o name)"
if [ -n "${existing_secret}" ]; then
  echo "Preserved the existing taskflow-postgres Secret in ${namespace}."
  exit 0
fi
password="$(openssl rand -base64 36 | tr -d '\n')"
kubectl --context "${kube_context}" --namespace "${namespace}" create secret generic taskflow-postgres \
  --from-literal="password=${password}" \
  --dry-run=client -o yaml \
  | kubectl --context "${kube_context}" create -f -

echo "Created taskflow-postgres in ${namespace}; the generated password was not printed or written to disk."
