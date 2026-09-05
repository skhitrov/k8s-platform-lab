#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: bash scripts/test-tempo-statefulset.sh <colima-k3s-lab|kind-sre-lab|kind-taskflow-e2e>" >&2; exit 2
fi
kube_context="$1"
case "${kube_context}" in colima-k3s-lab|kind-sre-lab|kind-taskflow-e2e) ;; *) exit 2 ;; esac
namespace="taskflow-tempo-recovery-$(date -u +%Y%m%d%H%M%S)-$$"
mkdir -p .cache/reports
report_directory="$(mktemp -d .cache/reports/tempo-statefulset.XXXXXX)"
created_namespace_uid=""
# ShellCheck 0.9/0.11 do not recognize the EXIT-trap call.
# shellcheck disable=SC2317,SC2329
cleanup() {
  local exit_status="$?" current_uid
  trap - EXIT
  if [ -n "${created_namespace_uid}" ]; then
    current_uid="$(kubectl --context "${kube_context}" get namespace "${namespace}" \
      --ignore-not-found -o jsonpath='{.metadata.uid}')" || current_uid=""
    if [ "${current_uid}" = "${created_namespace_uid}" ]; then
      kubectl --context "${kube_context}" --namespace "${namespace}" get pods,statefulsets,pvc -o yaml \
        >"${report_directory}/resources.yaml" 2>&1 || true
      kubectl --context "${kube_context}" --namespace "${namespace}" get events --sort-by=.lastTimestamp \
        >"${report_directory}/events.txt" 2>&1 || true
      kubectl --context "${kube_context}" --namespace "${namespace}" logs tempo-0 --tail=100 \
        >"${report_directory}/tempo.log" 2>&1 || true
      # Only this invocation's namespace/PVC and public synthetic marker are removed.
      kubectl --context "${kube_context}" delete namespace "${namespace}" --wait=false >/dev/null || true
    fi
  fi
  echo "StatefulSet recovery diagnostics: ${report_directory}"
  exit "${exit_status}"
}
trap 'cleanup' EXIT
created_namespace_uid="$(kubectl --context "${kube_context}" create namespace "${namespace}" -o jsonpath='{.metadata.uid}')"
kubectl --context "${kube_context}" label namespace "${namespace}" \
  pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=v1.36 >/dev/null
archive="$(bash scripts/fetch-chart.sh tempo)"
helm_arguments=(tempo "${archive}" --kube-context "${kube_context}" --namespace "${namespace}"
  --values platform/addons/values/tempo.yaml
  --set serviceAccount.automountServiceAccountToken=false
  --set securityContext.seccompProfile.type=RuntimeDefault
  --set tempo.securityContext.allowPrivilegeEscalation=false
  --set 'tempo.securityContext.capabilities.drop[0]=ALL')

# Wrong probe path keeps this otherwise healthy test container permanently unready.
helm upgrade --install "${helm_arguments[@]}" \
  --set tempo.readinessProbe.httpGet.path=/deliberately-unready-recovery-fixture >/dev/null
kubectl --context "${kube_context}" --namespace "${namespace}" wait \
  --for=create pod/tempo-0 --timeout=3m
kubectl --context "${kube_context}" --namespace "${namespace}" wait \
  --for=jsonpath='{.status.phase}'=Running pod/tempo-0 --timeout=3m
kubectl --context "${kube_context}" --namespace "${namespace}" get pod tempo-0 -o json >"${report_directory}/old-pod.json"
jq -e '.status.containerStatuses[0].ready == false and .status.containerStatuses[0].state.running != null' \
  "${report_directory}/old-pod.json" >/dev/null
old_pod_uid="$(jq -er '.metadata.uid' "${report_directory}/old-pod.json")"
kubectl --context "${kube_context}" --namespace "${namespace}" get pvc storage-tempo-0 -o json \
  >"${report_directory}/original-pvc.json"
original_pvc_uid="$(jq -er '.metadata.uid' "${report_directory}/original-pvc.json")"
kubectl --context "${kube_context}" --namespace "${namespace}" exec tempo-0 -- \
  sh -ec 'printf "%s\n" "public-statefulset-recovery-marker" > /var/tempo/recovery-marker'

# Correct the desired template first. Do not change the existing Pod or PVC yet.
helm upgrade "${helm_arguments[@]}" --reset-values >/dev/null
for _attempt in $(seq 1 30); do
  kubectl --context "${kube_context}" --namespace "${namespace}" get statefulset tempo -o json \
    >"${report_directory}/corrected-statefulset.json"
  if jq -e '.status.observedGeneration == .metadata.generation
    and .status.updateRevision != .status.currentRevision' "${report_directory}/corrected-statefulset.json" >/dev/null; then break; fi
  sleep 1
done
jq -e '.spec.podManagementPolicy == "OrderedReady" and .spec.updateStrategy.type == "RollingUpdate"
  and .status.observedGeneration == .metadata.generation
  and .status.updateRevision != .status.currentRevision
  and .spec.template.spec.containers[0].readinessProbe.httpGet.path == "/ready"' \
  "${report_directory}/corrected-statefulset.json" >/dev/null
desired_revision="$(jq -er '.status.updateRevision' "${report_directory}/corrected-statefulset.json")"
if kubectl --context "${kube_context}" --namespace "${namespace}" rollout status statefulset/tempo \
  --timeout=15s >"${report_directory}/expected-stall.txt" 2>&1; then
  echo "The negative fixture did not reproduce an OrderedReady stall." >&2; exit 1
fi
kubectl --context "${kube_context}" --namespace "${namespace}" get pod tempo-0 -o json >"${report_directory}/stalled-pod.json"
jq -e --arg uid "${old_pod_uid}" --arg desired "${desired_revision}" \
  '.metadata.uid == $uid and .status.containerStatuses[0].ready == false
    and .metadata.labels."controller-revision-hash" != $desired' "${report_directory}/stalled-pod.json" >/dev/null

# This is the conditional runbook action: only the stale Pod is recreated.
kubectl --context "${kube_context}" --namespace "${namespace}" delete pod tempo-0 --wait=true --timeout=90s
kubectl --context "${kube_context}" --namespace "${namespace}" rollout status statefulset/tempo --timeout=3m
kubectl --context "${kube_context}" --namespace "${namespace}" get pod tempo-0 -o json >"${report_directory}/recovered-pod.json"
jq -e --arg old_uid "${old_pod_uid}" --arg desired "${desired_revision}" \
  '.metadata.uid != $old_uid and .status.containerStatuses[0].ready == true
    and .metadata.labels."controller-revision-hash" == $desired' "${report_directory}/recovered-pod.json" >/dev/null
[ "$(kubectl --context "${kube_context}" --namespace "${namespace}" get pvc storage-tempo-0 -o jsonpath='{.metadata.uid}')" = "${original_pvc_uid}" ]
[ "$(kubectl --context "${kube_context}" --namespace "${namespace}" exec tempo-0 -- cat /var/tempo/recovery-marker)" = public-statefulset-recovery-marker ]
echo "OrderedReady recovery passed: corrected template, new healthy Pod, same PVC UID and preserved marker."
