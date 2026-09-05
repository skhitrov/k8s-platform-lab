#!/usr/bin/env bash
set -euo pipefail

cluster_name="taskflow-e2e"
kube_context="kind-taskflow-e2e"
namespace="taskflow-e2e"
image="${E2E_IMAGE:-taskflow:dev}"
port_forward_pid=""
created_cluster=false
temporary_directory="$(mktemp -d)"
export KUBECONFIG="${temporary_directory}/kubeconfig"

cleanup() {
  exit_status="$?"
  trap - EXIT
  if [ -n "${port_forward_pid}" ]; then
    kill "${port_forward_pid}" >/dev/null 2>&1 || true
  fi
  if [ "${created_cluster}" = true ]; then
    if [ "${exit_status}" -ne 0 ]; then
      mkdir -p .cache/reports/e2e
      # Full node dumps stay private; only scoped resource/event/app logs upload.
      mkdir -p .cache/private
      kind export logs .cache/private/e2e-node-logs --name "${cluster_name}" >/dev/null 2>&1 || true
      kubectl --context "${kube_context}" --namespace "${namespace}" get pods,jobs,pvc -o wide \
        > .cache/reports/e2e/resources.txt 2>&1 || true
      kubectl --context "${kube_context}" --namespace "${namespace}" get events --sort-by=.lastTimestamp \
        > .cache/reports/e2e/events.txt 2>&1 || true
      kubectl --context "${kube_context}" --namespace "${namespace}" logs \
        -l app.kubernetes.io/instance=taskflow --all-containers --prefix --tail=100 \
        > .cache/reports/e2e/logs.txt 2>&1 || true
    fi
    if [ "${E2E_KEEP:-0}" != 1 ]; then
      kind delete cluster --name "${cluster_name}" >/dev/null 2>&1 || true
    else
      echo "Retained ${cluster_name}; kubeconfig: ${KUBECONFIG}"
    fi
  fi
  if [ "${E2E_KEEP:-0}" != 1 ]; then
    rm -rf "${temporary_directory}"
  fi
  exit "${exit_status}"
}
trap cleanup EXIT

if kind get clusters | rg -qx "${cluster_name}"; then
  echo "Cluster ${cluster_name} already exists; refusing to delete it." >&2
  exit 1
fi

if [ "${E2E_SKIP_BUILD:-0}" != 1 ]; then
  docker build --tag "${image}" .
fi
created_cluster=true
kind create cluster --retain --name "${cluster_name}" --config platform/kind/e2e.yaml \
  --image "$(yq -r '.kind.nodeImage' platform/versions.yaml)" --wait 180s
kind load docker-image "${image}" --name "${cluster_name}"

bash scripts/create-lab-secrets.sh "${kube_context}" "${namespace}"
helm upgrade --install taskflow deploy/chart/taskflow \
  --kube-context "${kube_context}" \
  --namespace "${namespace}" \
  --set-string "image.repository=${image%:*}" \
  --set-string "image.tag=${image##*:}" \
  --set image.pullPolicy=Never \
  --set ingress.enabled=false \
  --set networkPolicy.enabled=false \
  --set serviceMonitor.enabled=false \
  --set api.rollout.enabled=false \
  --set api.autoscaling.enabled=false \
  --set worker.autoscaling.enabled=false \
  --set backup.enabled=true \
  --wait --wait-for-jobs --timeout 6m

kubectl --context "${kube_context}" --namespace "${namespace}" port-forward service/taskflow-taskflow 18080:80 \
  > "${temporary_directory}/port-forward.log" 2>&1 &
port_forward_pid="$!"

for _attempt in $(seq 1 30); do
  if curl --fail --silent http://127.0.0.1:18080/health/live >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

bash scripts/smoke.sh http://127.0.0.1:18080 | tee "${temporary_directory}/smoke.log"
smoke_job="$(sed -n 's/^SMOKE_JOB_ID=//p' "${temporary_directory}/smoke.log")"
if ! [[ "${smoke_job}" =~ ^[a-f0-9-]{36}$ ]]; then
  echo "Smoke test did not return a job UUID." >&2; exit 1
fi
bash scripts/backup.sh "${kube_context}" "${namespace}" | tee "${temporary_directory}/backup.log"
backup_file="$(sed -n 's/^BACKUP_PATH=//p' "${temporary_directory}/backup.log")"
bash scripts/restore.sh "${kube_context}" "${namespace}" "${backup_file}" taskflow-restore-e2e
restored_status="$(kubectl --context "${kube_context}" --namespace taskflow-restore-e2e exec \
  statefulset/taskflow-taskflow-postgresql -- psql -U taskflow -d taskflow -tAc \
  "SELECT status FROM jobs WHERE id = '${smoke_job}'")"
if [ "${restored_status}" != succeeded ]; then
  echo "The known smoke-test job was not restored." >&2; exit 1
fi
echo "Kubernetes smoke, CronJob export, and restoration of the known job passed."

# Prove rollout checking rejects an unhealthy image, then restore the tested one.
kubectl --context "${kube_context}" --namespace "${namespace}" set image deployment/taskflow-taskflow-api \
  api=taskflow:deliberately-missing-negative-fixture
mkdir -p .cache/reports
if kubectl --context "${kube_context}" --namespace "${namespace}" rollout status deployment/taskflow-taskflow-api \
  --timeout=20s > .cache/reports/negative-unhealthy-deployment.txt 2>&1; then
  echo "An unavailable image unexpectedly passed the rollout gate." >&2; exit 1
fi
kubectl --context "${kube_context}" --namespace "${namespace}" get pods -o json \
  | jq -e '[.items[].status.containerStatuses[]?.state.waiting.reason] | any(. == "ErrImageNeverPull")' >/dev/null
kubectl --context "${kube_context}" --namespace "${namespace}" set image deployment/taskflow-taskflow-api "api=${image}"
kubectl --context "${kube_context}" --namespace "${namespace}" rollout status deployment/taskflow-taskflow-api --timeout=2m
echo "The unhealthy deployment was rejected and the tested image recovered."

# Reproduce and recover an unready OrderedReady StatefulSet without deleting data.
bash scripts/test-tempo-statefulset.sh "${kube_context}"
