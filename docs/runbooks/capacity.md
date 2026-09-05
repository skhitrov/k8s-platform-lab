# Capacity and performance

Measure one environment at a time on the 4-vCPU/8-GiB VM. Record Mac architecture, Colima/Kubernetes/node topology, image digest, all resource settings, replicas, pool sizes, work units and concurrent background load. Close unrelated heavy workloads. Use identical settings for before/after comparisons.

The k6 script offers `smoke` (5/s, 30s), `ramp` (5→100/s), `spike` (up to 150/s), `soak` (25/s, 30m), and `acceptance` (50/s, 10m). These are arrival rates, not “virtual users equals RPS.” A run fails if valid acceptance falls below 99.5%, p95 submission duration reaches 300ms, transport/HTTP errors reach 0.5%, or the generator drops iterations.

For a stable endpoint on a port-forward:

```bash
kubectl --context kind-sre-lab --namespace taskflow-dev port-forward service/taskflow-taskflow 18080:80
k6 run --env BASE_URL=http://127.0.0.1:18080 --env PROFILE=smoke --summary-export /private/tmp/taskflow-smoke-summary.json tests/load/taskflow.js
k6 run --env BASE_URL=http://127.0.0.1:18080 --env PROFILE=ramp --summary-export /private/tmp/taskflow-ramp-summary.json tests/load/taskflow.js
kubectl --context kind-sre-lab --namespace taskflow-dev get hpa --watch
kubectl --context kind-sre-lab top pods --all-namespaces
```

Run the endpoint, load and watches in separate terminals. Use ingress for final end-user/canary measurements; port-forward measurements exclude ingress overhead and routing behavior. `WORK_UNITS` controls synthetic CPU cost and must remain fixed for comparisons.

Collect offered/completed RPS, HTTP failure and acceptance rates, p50/p95/p99, generator dropped iterations, CPU usage/throttling, memory/RSS/OOMs, worker throughput/duration, queue depth/oldest age, pool acquisition pressure and DB connections. A fast 202 is not proof that queued jobs are completing: after stopping load, record drain time and terminal job counts. More queued work than completed work is accumulating debt.

Find the first sustained saturation point. Change one factor: worker replicas, CPU requests/limits, API replicas or DB pools. HPA uses CPU requests as its denominator and reacts with stabilization delay. Raising a pool can exhaust PostgreSQL when replicas surge; compute total possible connections first. Increasing limits without VM headroom can move the failure into the host.

Complete the [capacity report template](../evidence/capacity-template.md). Never extrapolate this Mac's measurements to a production SLA or claim the 50/s target before a complete 10-minute run and queue-drain check.
