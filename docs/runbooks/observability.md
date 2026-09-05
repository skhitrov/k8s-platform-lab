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
