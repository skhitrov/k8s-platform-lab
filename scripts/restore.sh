#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "usage: bash scripts/restore.sh <kube-context> <source-namespace> <backup.dump> <new-taskflow-restore-namespace>" >&2
  exit 2
fi
kube_context="$1"
source_namespace="$2"
backup_file="$3"
restore_namespace="$4"
if ! [[ "${restore_namespace}" =~ ^taskflow-restore-[a-z0-9-]+$ ]]; then
  echo "Restore targets must start with taskflow-restore-." >&2; exit 2
fi
if [ ! -s "${backup_file}" ] || [ "$(head -c 5 "${backup_file}")" != PGDMP ]; then
  echo "A nonempty PostgreSQL custom archive is required." >&2; exit 2
fi
if [ -f "${backup_file}.sha256" ]; then
  shasum -a 256 -c "${backup_file}.sha256"
fi
existing_namespace="$(kubectl --context "${kube_context}" get namespace "${restore_namespace}" --ignore-not-found -o name)"
if [ -n "${existing_namespace}" ]; then
  echo "Refusing to overwrite existing namespace ${restore_namespace}. Choose a new restore name." >&2
  exit 1
fi
image_ref="$(kubectl --context "${kube_context}" --namespace "${source_namespace}" get pods \
  -l app.kubernetes.io/instance=taskflow,app.kubernetes.io/component=api \
  -o jsonpath='{.items[0].spec.containers[0].image}')"
if [ -z "${image_ref}" ]; then
  echo "No source API image was found." >&2; exit 1
fi
image_settings=()
if [[ "${image_ref}" == *@sha256:* ]]; then
  image_settings=(--set-string "image.repository=${image_ref%@*}" --set-string "image.digest=${image_ref#*@}")
else
  image_settings=(--set-string "image.repository=${image_ref%:*}" --set-string "image.tag=${image_ref##*:}")
fi
bash scripts/create-lab-secrets.sh "${kube_context}" "${restore_namespace}"
helm upgrade --install taskflow deploy/chart/taskflow \
  --kube-context "${kube_context}" --namespace "${restore_namespace}" \
  "${image_settings[@]}" --set image.pullPolicy=IfNotPresent \
  --set api.replicas=0 --set worker.replicas=0 \
  --set api.autoscaling.enabled=false --set worker.autoscaling.enabled=false \
  --set api.disruptionBudget.enabled=false --set worker.disruptionBudget.enabled=false \
  --set migration.enabled=false --set ingress.enabled=false \
  --set serviceMonitor.enabled=false --set backup.enabled=false \
  --wait --timeout 5m
kubectl --context "${kube_context}" --namespace "${restore_namespace}" exec -i \
  statefulset/taskflow-taskflow-postgresql -- \
  pg_restore --username=taskflow --dbname=taskflow --exit-on-error --no-owner --no-privileges \
  < "${backup_file}"
kubectl --context "${kube_context}" --namespace "${restore_namespace}" exec \
  statefulset/taskflow-taskflow-postgresql -- \
  psql --username=taskflow --dbname=taskflow --set=ON_ERROR_STOP=1 \
  --command='SELECT status, count(*) FROM jobs GROUP BY status ORDER BY status;'
helm upgrade taskflow deploy/chart/taskflow --reuse-values \
  --kube-context "${kube_context}" --namespace "${restore_namespace}" \
  --set api.replicas=1 --set worker.replicas=1 --wait --timeout 5m
echo "Restored into ${restore_namespace}. The namespace is retained for verifying known job IDs."
