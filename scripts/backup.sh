#!/usr/bin/env bash
set -euo pipefail
umask 077

if [ "$#" -ne 2 ]; then
  echo "usage: bash scripts/backup.sh <kube-context> <taskflow-namespace>" >&2
  exit 2
fi
kube_context="$1"
namespace="$2"
if ! [[ "${namespace}" =~ ^taskflow-[a-z0-9-]+$ ]]; then
  echo "Use a taskflow- namespace." >&2; exit 2
fi
backup_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_job="taskflow-backup-$(printf '%s' "${backup_stamp}" | tr '[:upper:]' '[:lower:]')"
reader_pod="taskflow-backup-reader-${RANDOM}"
destination="backups/${namespace}-${backup_stamp}.dump"
mkdir -p backups
cleanup() {
  kubectl --context "${kube_context}" --namespace "${namespace}" delete pod "${reader_pod}" \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl --context "${kube_context}" --namespace "${namespace}" create job "${backup_job}" \
  --from=cronjob/taskflow-taskflow-backup
kubectl --context "${kube_context}" --namespace "${namespace}" wait --for=condition=Complete \
  "job/${backup_job}" --timeout=10m
kubectl --context "${kube_context}" --namespace "${namespace}" logs "job/${backup_job}" \
  > "${destination}.log"
remote_file="$(sed -n 's/^BACKUP_FILE=//p' "${destination}.log" | tail -n 1)"
if ! [[ "${remote_file}" =~ ^taskflow-[A-Za-z0-9-]+\.dump$ ]]; then
  echo "Backup job did not report a valid archive name. Inspect ${destination}.log." >&2
  exit 1
fi
postgres_image="$(kubectl --context "${kube_context}" --namespace "${namespace}" \
  get cronjob taskflow-taskflow-backup -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}')"
reader_spec="$(jq -n --arg name "${reader_pod}" --arg image "${postgres_image}" '{
  spec: {
    automountServiceAccountToken: false,
    securityContext: {runAsNonRoot: true, runAsUser: 70, runAsGroup: 70, fsGroup: 70, seccompProfile: {type: "RuntimeDefault"}},
    containers: [{name: $name, image: $image, command: ["sleep", "600"],
      securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}},
      resources: {requests: {cpu: "10m", memory: "16Mi"}, limits: {cpu: "100m", memory: "64Mi"}},
      volumeMounts: [{name: "backups", mountPath: "/backups", readOnly: true}]}],
    volumes: [{name: "backups", persistentVolumeClaim: {claimName: "taskflow-taskflow-backups", readOnly: true}}]
  }}')"
kubectl --context "${kube_context}" --namespace "${namespace}" run "${reader_pod}" \
  --image="${postgres_image}" --restart=Never --overrides="${reader_spec}"
kubectl --context "${kube_context}" --namespace "${namespace}" wait --for=condition=Ready \
  "pod/${reader_pod}" --timeout=3m
kubectl --context "${kube_context}" --namespace "${namespace}" exec "${reader_pod}" \
  -- cat "/backups/${remote_file}" > "${destination}.partial"
if [ "$(head -c 5 "${destination}.partial")" != PGDMP ]; then
  echo "Export is not a PostgreSQL custom archive." >&2; exit 1
fi
mv "${destination}.partial" "${destination}"
shasum -a 256 "${destination}" > "${destination}.sha256"
echo "Exported ${destination}; checksum and backup-job log are alongside it."
printf 'BACKUP_PATH=%s\n' "${destination}"
