# Metrics, logs, traces and SLOs

The GitOps stack installs Prometheus/Alertmanager/Grafana, monolithic Loki, Alloy, Tempo and a traces-only OpenTelemetry collector. Grafana provisions the Taskflow dashboard and data sources; Prometheus discovers both API and worker ServiceMonitors. App metrics add namespace, component and rollout-hash labels through scrape relabeling. High-cardinality IDs belong in logs/traces, not metric labels.

```bash
kubectl --context kind-sre-lab --namespace observability get pods,pvc
kubectl --context kind-sre-lab --namespace observability port-forward service/kube-prometheus-stack-grafana 13000:80
kubectl --context kind-sre-lab --namespace observability port-forward service/kube-prometheus-stack-prometheus 19090:9090
```

Run each port-forward in its own terminal. Retrieve the generated Grafana admin password privately from `taskflow-grafana-admin`; do not include it in evidence. Grafana configuration is provisioned from Git; UI edits are experiments, not the durable source.

Once telemetry is enabled, close those port-forwards and run the automated correlation probe:

```bash
bash scripts/test-observability.sh colima-k3s-lab taskflow-dev
```

It submits one job, verifies API and worker scrape targets, finds both components' same-trace logs in Loki, and checks the API → database enqueue → worker parent chain in Tempo. It owns and cleans up its loopback port-forwards. This proves the data path, not every dashboard link or alert condition.

Grafana's two Python sidecars have 192Mi limits after 64Mi caused observed startup OOM kills. Grafana itself has a 512Mi limit and 400MiB Go memory target after its measured working set reached 255Mi. Suggested plugin preinstallation and update checks are disabled to avoid unpinned background downloads; see [Grafana configuration](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/#preinstall_disabled). Alertmanager's inherited child routes are explicitly cleared when defining the lab receiver.

Tempo's original 384Mi limit passed readiness and a small trace query, then OOM-killed it during the first delayed block completion. The hardened values use a 768Mi limit/500MiB Go target, one flush worker, 8Mi blocks, 4Mi Parquet row groups and limited query/read concurrency. These are lab settings, not production sizing. Their field names and original defaults were checked against the pinned [Tempo 2.9 ingester](https://github.com/grafana/tempo/blob/v2.9.0/modules/ingester/config.go), [block configuration](https://github.com/grafana/tempo/blob/v2.9.0/tempodb/encoding/common/config.go) and [configuration reference](https://github.com/grafana/tempo/blob/v2.9.0/docs/sources/tempo/configuration/_index.md).

```bash
bash scripts/test-tempo-memory.sh colima-k3s-lab
```

This regression test runs the chart's image/configuration in a disposable container capped at 0.5 CPU and the configured memory limit. Two 5,000-trace batches are flushed and queried after a graceful restart. A third batch is left in the WAL: the test verifies its populated metadata and absence of a completed block, sends SIGKILL, checks that the stopped container retained the WAL, and then requires that same block to replay/complete. The first and last traces of the replayed batch must be queryable under the memory cap, with zero OOM events. Diagnostics are in `.cache/reports/tempo-memory/`; hosted CI runs it too. Ports 19418 and 19420 must be free. Its synthetic container data is removed on exit; no lab PVC is mounted. This tests process-crash recovery of a valid non-empty WAL, not host power loss, prolonged capacity or recovery of arbitrary damaged live data.

For a live OOM, retain previous-container logs, restart counts and the PVC. Do not erase the trace volume to make readiness green. Under GitOps, propose memory/configuration changes through a reviewed PR and then recheck block completion, trace lookup and end-to-end correlation after Argo applies them.

## Recover a stalled Tempo StatefulSet

An `OrderedReady`/`RollingUpdate` StatefulSet can wait for its old unready Pod before replacing it with the corrected template. Updating Git is necessary but may not finish recovery on its own; see [Kubernetes forced-rollback behavior](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#forced-rollback). A ConfigMap refresh may let the old process recover automatically, so do not delete a Pod just because a PR was merged.

After the fix has been reviewed and merged, inspect the actual cluster state. The commands below target the K3s lab only:

```bash
git switch main
git pull --ff-only origin main
kubectl --context colima-k3s-lab --namespace argocd get application tempo -o json | jq '{sync: .status.sync, operation: .status.operationState.phase, health: .status.health}'
kubectl --context colima-k3s-lab --namespace observability get statefulset tempo -o json | jq '{generation: .metadata.generation, observedGeneration: .status.observedGeneration, desiredRevision: .status.updateRevision, currentRevision: .status.currentRevision, template: .spec.template}'
kubectl --context colima-k3s-lab --namespace observability get configmap tempo -o jsonpath='{.data.tempo\.yaml}'
kubectl --context colima-k3s-lab --namespace observability get pod tempo-0 -o json | jq '{uid: .metadata.uid, revision: .metadata.labels["controller-revision-hash"], status: .status.containerStatuses}'
kubectl --context colima-k3s-lab --namespace observability get pvc storage-tempo-0 -o json | jq '{uid: .metadata.uid, volume: .spec.volumeName, phase: .status.phase}'
```

Record the PVC UID/volume and old Pod UID. Verify Argo's values-source revision matches the reviewed commit; the StatefulSet controller has observed its current generation; and its template/config contain the reviewed limit, Go memory target and buffer settings. For this fix those are 768Mi/500MiB, one flush worker, 8Mi blocks and 4Mi row groups. Also confirm the existing Pod is still unready **and has a different revision from `status.updateRevision`**. If the template/config are stale, wait for or diagnose Argo. If the Pod already uses the desired revision, diagnose that Pod's WAL/storage/probe errors instead of repeatedly deleting it.

Only if the corrected template is observed but the old-revision Pod remains stuck, recheck those conditions and perform one normal Pod deletion:

```bash
kubectl --context colima-k3s-lab --namespace observability delete pod tempo-0 --wait=true --timeout=90s
kubectl --context colima-k3s-lab --namespace observability rollout status statefulset/tempo --timeout=3m
kubectl --context colima-k3s-lab --namespace observability get pod tempo-0 -o json | jq '{uid: .metadata.uid, revision: .metadata.labels["controller-revision-hash"], status: .status.containerStatuses}'
kubectl --context colima-k3s-lab --namespace observability get pvc storage-tempo-0 -o json | jq '{uid: .metadata.uid, volume: .spec.volumeName, phase: .status.phase}'
kubectl --context colima-k3s-lab --namespace observability logs tempo-0 --since=10m
bash scripts/test-observability.sh colima-k3s-lab taskflow-dev
```

The replacement must have a new Pod UID and the desired revision, become Ready without new OOMs, retain the original PVC UID/volume, replay any existing WAL successfully, and pass trace correlation/block completion. Do not use `--force`, delete the StatefulSet/PVC, uninstall the release, erase WAL files, or patch live values around Git. Stop and retain diagnostics if the replacement still fails; repeated deletion is not a repair. Restarting the stale Pod after the reviewed template is applied does not change Git's desired state.

The controller/PVC transition has its own disposable regression:

```bash
bash scripts/test-tempo-statefulset.sh colima-k3s-lab
```

It installs the pinned Tempo chart in a newly created test namespace, seeds a public file on its PVC, demonstrates an `OrderedReady` stall with an intentionally bad readiness path, corrects the template, and recreates only the stale Pod. It requires a new healthy Pod, the same PVC UID and unchanged file contents. Cleanup removes only that test namespace and its synthetic storage. The Kubernetes E2E job runs this test too; diagnostics are in `.cache/reports/tempo-statefulset.*`.

## Request-to-root-cause exercise

1. Send a valid job request with a unique `X-Request-ID`, save the response headers/job ID and wait for completion.
2. Find its JSON API log in Loki by namespace and request ID; follow `trace_id` to Tempo. Confirm the worker span is in the same trace, not a new unrelated trace.
3. Check RED panels, queue age/depth, worker duration and acquired/max DB connections. Use a Prometheus exemplar to find the sampled trace where available.
4. Inject a bounded error/latency fault only in a lab environment. Find the alert, inspect the scoped panels/logs/trace, then revert the fault and verify recovery.

Useful PromQL:

```promql
sum by (namespace) (rate(taskflow_http_requests_total{route="/v1/jobs",method="POST"}[5m]))
taskflow:http_errors:ratio5m
taskflow:http_latency:p95
max by (namespace) (taskflow_queue_oldest_age_seconds)
taskflow_db_pool_acquired_connections / taskflow_db_pool_max_connections
```

Loki example: `{namespace="taskflow-dev",component="api"} | json | request_id="<REQUEST_ID>"`. Events use job `kubernetes/events`. Alloy reads namespace-scoped Kubernetes APIs instead of privileged host log mounts; absence of logs can be RBAC/discovery/config errors as well as Loki failures. Check collector exports and Tempo readiness for missing traces. The Tempo chart retains loopback-only legacy Jaeger listeners because its service templates expect those receiver keys; app traffic uses OTLP.

## SLO definition and caveats

Availability target: 99.5% of measured `/v1/jobs` API responses are not 5xx; valid synthetic load additionally requires 202. Latency objective: p95 below 300 ms. The error budget fraction is 0.005. Fast burn requires 14.4× burn in both 5m and 1h windows; slow burn requires 6× in both 30m and 6h windows. The rules are namespace-scoped. Short 6h retention supports the lab windows, not a real 30-day compliance report.

An in-process request counter cannot see DNS failures, connection refusal, ingress outages or a dead API that emits no metrics. Include external k6/client failure evidence when reporting user-visible availability; do not equate zero exported 5xx with health. Low/missing traffic also makes percentile estimates meaningless. Canary gates require a minimum sample count and do not pass missing candidate data.

Alerts are visible in local Alertmanager, but its default receiver does not page anyone. Configure and test an external receiver only when explicitly choosing a destination; never commit its credential. Validate alert firing **and resolution** with timestamps. For a five-minute learning exercise, make a temporary shorter-window rule in an isolated namespace, clearly label it experimental, then remove it; do not claim the real six-hour window was tested in five minutes.
