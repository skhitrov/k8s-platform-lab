#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: bash scripts/test-observability.sh <lab-context> <taskflow-namespace>" >&2; exit 2
fi
kube_context="$1"
namespace="$2"
case "${kube_context}" in colima-k3s-lab|kind-sre-lab) ;; *) exit 2 ;; esac
case "${namespace}" in taskflow-dev|taskflow-staging) ;; *) exit 2 ;; esac
report_directory="$(mktemp -d)"
forward_pids=()
# Invoked by the EXIT trap, including successful early exit after convergence.
# shellcheck disable=SC2329
cleanup() {
  for pid in "${forward_pids[@]}"; do kill "${pid}" 2>/dev/null || true; done
  for pid in "${forward_pids[@]}"; do wait "${pid}" 2>/dev/null || true; done
  rm -rf "${report_directory}"
}
trap 'cleanup' EXIT
forward() {
  kubectl --context "${kube_context}" --namespace "$1" port-forward --address 127.0.0.1 \
    "service/$2" "$3" >"${report_directory}/$2-forward.log" 2>&1 &
  forward_pids+=("$!")
}
forward "${namespace}" taskflow-taskflow 18080:http
forward observability kube-prometheus-stack-prometheus 19090:9090
forward observability loki 13100:3100
forward observability tempo 13200:3200
for _attempt in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:18080/health/ready >/dev/null 2>&1 \
    && curl -fsS http://127.0.0.1:19090/-/ready >/dev/null 2>&1 \
    && curl -fsS http://127.0.0.1:13100/ready >/dev/null 2>&1 \
    && curl -fsS http://127.0.0.1:13200/ready >/dev/null 2>&1; then break; fi
  sleep 1
done
for pid in "${forward_pids[@]}"; do
  if ! kill -0 "${pid}" 2>/dev/null; then
    echo "A port-forward failed; ensure ports 18080, 19090, 13100 and 13200 are free." >&2
    exit 1
  fi
done
request_id="telemetry-$(date -u +%Y%m%dT%H%M%SZ)-$$"
status="$(curl -fsS --dump-header "${report_directory}/headers" --output "${report_directory}/job.json" \
  --write-out '%{http_code}' --header 'Content-Type: application/json' \
  --header "X-Request-ID: ${request_id}" --data '{"work_units":10000}' http://127.0.0.1:18080/v1/jobs)"
[ "${status}" = 202 ]
job_id="$(jq -er '.id' "${report_directory}/job.json")"
trace_id="$(awk 'tolower($1) == "x-trace-id:" {gsub("\r", "", $2); print $2}' "${report_directory}/headers")"
if ! [[ "${trace_id}" =~ ^[a-f0-9]{32}$ ]]; then
  echo "No valid trace header: enable the application's OTLP endpoint first." >&2; exit 1
fi

for _attempt in $(seq 1 60); do
  curl -fsS "http://127.0.0.1:18080/v1/jobs/${job_id}" --output "${report_directory}/job.json"
  curl -fsS -H 'Accept: application/json' "http://127.0.0.1:13200/api/traces/${trace_id}" \
    --output "${report_directory}/trace.json" 2>/dev/null || true
  curl -fsS --get http://127.0.0.1:13100/loki/api/v1/query_range \
    --data-urlencode "query={namespace=\"${namespace}\"} |= \"${trace_id}\"" \
    --data-urlencode 'since=10m' --data-urlencode 'limit=100' --output "${report_directory}/logs.json"
  curl -fsS --get http://127.0.0.1:19090/api/v1/query \
    --data-urlencode "query=up{namespace=\"${namespace}\",component=~\"api|worker\"}" \
    --output "${report_directory}/metrics.json"
  if jq -e '.status == "succeeded"' "${report_directory}/job.json" >/dev/null \
    && jq -e '[.. | objects | select(has("spanId"))] as $spans
      | [$spans[] | select(.kind == "SPAN_KIND_SERVER" and .name == "POST /v1/jobs") | .spanId] as $servers
      | [$spans[] | select(.name == "jobs.insert" and (.parentSpanId as $id | $servers | index($id) != null)) | .spanId] as $enqueues
      | any($spans[]; .name == "jobs.process" and (.parentSpanId as $id | $enqueues | index($id) != null))' \
      "${report_directory}/trace.json" >/dev/null 2>&1 \
    && jq -e '[.data.result[].stream.component] | index("api") != null and index("worker") != null' \
      "${report_directory}/logs.json" >/dev/null \
    && jq -e '[.data.result[] | select(.value[1] == "1") | .metric.component]
      | index("api") != null and index("worker") != null' "${report_directory}/metrics.json" >/dev/null; then
    echo "Telemetry passed: job ${job_id}; request ${request_id}; trace ${trace_id}."
    echo "Prometheus scraped API/worker; Loki received their same-trace logs; Tempo linked API -> enqueue -> worker."
    exit 0
  fi
  sleep 2
done
echo "Telemetry correlation did not converge within two minutes. Check ServiceMonitors, Alloy and OTLP export." >&2
exit 1
