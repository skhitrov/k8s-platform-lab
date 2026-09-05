#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ] || ! [[ "$2" =~ ^taskflow-[a-z0-9-]+$ ]]; then
  echo "usage: bash scripts/test-network-policy.sh <kube-context> <taskflow-namespace>" >&2; exit 2
fi
kube_context="$1"
namespace="$2"
if [ "${kube_context}" = kind-taskflow-e2e ]; then
  echo "The CI-only default Kind CNI does not enforce NetworkPolicy." >&2; exit 2
fi
kubectl --context "${kube_context}" --namespace "${namespace}" get networkpolicy taskflow-taskflow-default-deny >/dev/null
probe_image="$(kubectl --context "${kube_context}" --namespace "${namespace}" get statefulset taskflow-taskflow-postgresql \
  -o jsonpath='{.spec.template.spec.containers[0].image}')"
probe_suffix="${RANDOM}"
created_probes=()
cleanup() {
  local probe
  for probe in "${created_probes[@]}"; do
    kubectl --context "${kube_context}" --namespace "${probe%%:*}" delete pod "${probe#*:}" \
      --ignore-not-found --wait=false >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT
create_probe() {
  local probe_namespace="$1" probe_name="$2" component="$3" probe_spec
  probe_spec="$(jq -n --arg name "${probe_name}" --arg image "${probe_image}" '{spec: {
    automountServiceAccountToken: false,
    securityContext: {runAsNonRoot: true, runAsUser: 70, runAsGroup: 70, seccompProfile: {type: "RuntimeDefault"}},
    containers: [{name: $name, image: $image, command: ["sleep", "300"],
      securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}},
      resources: {requests: {cpu: "10m", memory: "16Mi"}, limits: {cpu: "100m", memory: "64Mi"}}}]
  }}')"
  kubectl --context "${kube_context}" --namespace "${probe_namespace}" run "${probe_name}" \
    --image="${probe_image}" --restart=Never --overrides="${probe_spec}" \
    --labels="app.kubernetes.io/name=taskflow,app.kubernetes.io/instance=taskflow,app.kubernetes.io/component=${component}"
  created_probes+=("${probe_namespace}:${probe_name}")
  kubectl --context "${kube_context}" --namespace "${probe_namespace}" wait --for=condition=Ready "pod/${probe_name}" --timeout=2m
}
create_probe "${namespace}" "taskflow-policy-allowed-${probe_suffix}" migration
create_probe "${namespace}" "taskflow-policy-denied-${probe_suffix}" unauthorized
create_probe ingress-nginx "taskflow-policy-ingress-${probe_suffix}" probe
for role in allowed denied; do
  kubectl --context "${kube_context}" --namespace "${namespace}" exec "taskflow-policy-${role}-${probe_suffix}" \
    -- nslookup -type=A "taskflow-taskflow-postgresql.${namespace}.svc.cluster.local."
done
kubectl --context "${kube_context}" --namespace "${namespace}" exec "taskflow-policy-allowed-${probe_suffix}" \
  -- pg_isready --host=taskflow-taskflow-postgresql --port=5432 --timeout=3
if kubectl --context "${kube_context}" --namespace "${namespace}" exec "taskflow-policy-denied-${probe_suffix}" \
  -- pg_isready --host=taskflow-taskflow-postgresql --port=5432 --timeout=3; then
  echo "Unauthorized Pod reached PostgreSQL: policy is not enforced." >&2; exit 1
fi
kubectl --context "${kube_context}" --namespace ingress-nginx exec "taskflow-policy-ingress-${probe_suffix}" \
  -- wget -q -T 5 -O - "http://taskflow-taskflow.${namespace}.svc.cluster.local/health/ready"
echo "DNS and authorized DB/ingress traffic passed; unauthorized DB traffic was blocked."
