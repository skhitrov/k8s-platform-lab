#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "usage: bash scripts/test-tempo-memory.sh [colima-k3s-lab|colima-kind-lab]" >&2; exit 2
fi
docker_command=(docker)
if [ "$#" = 1 ]; then
  case "$1" in colima-k3s-lab|colima-kind-lab) ;; *) exit 2 ;; esac
  docker_command+=(--context "$1")
fi
"${docker_command[@]}" info >/dev/null
mkdir -p .cache/reports/tempo-memory
probe_directory="$(mktemp -d "$(pwd)/.cache/tempo-probe.XXXXXX")"
probe_name="taskflow-tempo-probe-$(date -u +%Y%m%dT%H%M%SZ)-$$"
probe_id=""
# Both ShellCheck versions used by the workstation and hosted CI miss this trap.
# shellcheck disable=SC2317,SC2329
cleanup() {
  if [ -n "${probe_id}" ]; then
    "${docker_command[@]}" logs "${probe_id}" >.cache/reports/tempo-memory/container.log 2>&1 || true
    "${docker_command[@]}" inspect --format '{{json .State}}' "${probe_id}" \
      >.cache/reports/tempo-memory/state.json || true
    # Only this invocation's disposable container; its synthetic trace data is discarded.
    "${docker_command[@]}" rm --force "${probe_id}" >/dev/null || true
  fi
  rm -rf "${probe_directory}"
}
trap 'cleanup' EXIT

archive="$(bash scripts/fetch-chart.sh tempo)"
helm template tempo "${archive}" --namespace observability \
  --values platform/addons/values/tempo.yaml >"${probe_directory}/rendered.yaml"
yq -er 'select(.kind == "ConfigMap" and .metadata.name == "tempo") | .data."tempo.yaml"' \
  "${probe_directory}/rendered.yaml" >"${probe_directory}/tempo.yaml"
yq -er 'select(.kind == "ConfigMap" and .metadata.name == "tempo") | .data."overrides.yaml"' \
  "${probe_directory}/rendered.yaml" >"${probe_directory}/overrides.yaml"
# Only test isolation paths differ; the actual buffer/concurrency settings remain unchanged.
# The writable container layer survives restart and never mounts a lab PVC.
yq -i '.storage.trace.local.path = "/tmp/tempo/traces" | .storage.trace.wal.path = "/tmp/tempo/wal"' \
  "${probe_directory}/tempo.yaml"
image_reference="$(yq -er 'select(.kind == "StatefulSet") | .spec.template.spec.containers[0].image' \
  "${probe_directory}/rendered.yaml")"
memory_mib="$(yq -er '.tempo.resources.limits.memory | sub("Mi$", "")' platform/addons/values/tempo.yaml)"
memory_target="$(yq -er '.tempo.extraEnv[] | select(.name == "GOMEMLIMIT") | .value' platform/addons/values/tempo.yaml)"
[[ "${memory_mib}" =~ ^[0-9]+$ ]]
probe_id="$("${docker_command[@]}" create --name "${probe_name}" \
  --memory "${memory_mib}m" --memory-swap "${memory_mib}m" --cpus 0.5 \
  --user 10001:10001 --cap-drop ALL --security-opt no-new-privileges \
  --env "GOMEMLIMIT=${memory_target}" \
  --mount "type=bind,src=${probe_directory}/tempo.yaml,dst=/etc/tempo.yaml,readonly" \
  --mount "type=bind,src=${probe_directory}/overrides.yaml,dst=/conf/overrides.yaml,readonly" \
  --publish 127.0.0.1:19418:4318 --publish 127.0.0.1:19420:3200 \
  "${image_reference}" -config.file=/etc/tempo.yaml -mem-ballast-size-mbs=0)"
"${docker_command[@]}" start "${probe_id}" >/dev/null
wait_ready() {
  for _attempt in $(seq 1 60); do
    if curl -fsS --max-time 3 http://127.0.0.1:19420/ready >/dev/null 2>&1; then return 0; fi
    if [ "$("${docker_command[@]}" inspect --format '{{.State.Running}}' "${probe_id}")" != true ]; then
      echo "Tempo exited before readiness; inspect .cache/reports/tempo-memory/." >&2; return 1
    fi
    sleep 1
  done
  echo "Tempo did not become ready within 60 attempts." >&2; return 1
}
wait_ready

for batch in 1 2; do
  timestamp_seconds="$(date +%s)"
  jq -n --arg timestamp "${timestamp_seconds}000000000" --argjson batch "${batch}" '
    {resourceSpans: [{resource: {attributes: [{key: "service.name", value: {stringValue: "tempo-memory-probe"}}]},
      scopeSpans: [{scope: {name: "taskflow-probe"}, spans: [range(0; 5000) as $i |
        {traceId: (("00000000000000000000000000000000" + (($batch * 10000 + $i) | tostring))[-32:]),
         spanId: "0000000000000001", name: "block-completion-probe", kind: 2,
         startTimeUnixNano: $timestamp, endTimeUnixNano: $timestamp,
         attributes: [{key: "probe.payload", value: {stringValue: ("x" * 1024)}}]}
      ]}]}]}' \
    >"${probe_directory}/batch.json"
  curl -fsS --max-time 30 --header 'Content-Type: application/json' \
    --data-binary "@${probe_directory}/batch.json" http://127.0.0.1:19418/v1/traces \
    >"${probe_directory}/ingest-response.json"
  jq -e '(.partialSuccess.rejectedSpans // "0" | tonumber) == 0' \
    "${probe_directory}/ingest-response.json" >/dev/null
  curl -fsS --max-time 30 --request POST http://127.0.0.1:19420/flush >/dev/null
  completed=false
  for _attempt in $(seq 1 90); do
    curl -fsS --max-time 5 http://127.0.0.1:19420/metrics >"${probe_directory}/metrics.txt"
    if awk -v expected="${batch}" '$1 == "tempo_ingester_blocks_flushed_total" && $2 >= expected {ok=1} END {exit !ok}' \
      "${probe_directory}/metrics.txt"; then completed=true; break; fi
    sleep 1
  done
  if [ "${completed}" != true ]; then echo "Tempo did not flush batch ${batch}." >&2; exit 1; fi
  "${docker_command[@]}" exec "${probe_id}" cat /sys/fs/cgroup/memory.events /sys/fs/cgroup/memory.peak \
    | tee ".cache/reports/tempo-memory/batch-${batch}-memory.txt"
  echo "Tempo completed and flushed batch ${batch}: 5,000 synthetic traces."
done

# A restart must recover/query persisted blocks, not merely pass a readiness probe.
"${docker_command[@]}" restart --time 30 "${probe_id}" >/dev/null
wait_ready
curl -fsS --max-time 30 --header 'Accept: application/json' \
  http://127.0.0.1:19420/api/traces/00000000000000000000000000010000 \
  >"${probe_directory}/trace.json"
jq -e 'any(.. | objects; .name? == "block-completion-probe")' "${probe_directory}/trace.json" >/dev/null
"${docker_command[@]}" exec "${probe_id}" cat /sys/fs/cgroup/memory.events /sys/fs/cgroup/memory.peak \
  | tee .cache/reports/tempo-memory/restart-memory.txt
echo "Tempo memory probe passed: two block flushes and a persisted trace query after restart; limit ${memory_mib}Mi."
