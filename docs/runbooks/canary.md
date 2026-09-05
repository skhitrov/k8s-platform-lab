# Canary delivery and automatic abort

Preconditions: staging enrolled by a reviewed promotion, one healthy stable revision, ingress-nginx/Argo Rollouts/Prometheus healthy, ServiceMonitor targets scraped, enough surge capacity, and sustained valid requests through the **staging ingress**. Port-forwarding the stable service bypasses weighted ingress and does not test canary traffic routing.

```bash
k6 run --env BASE_URL=http://staging.taskflow.localhost:8080 --env PROFILE=acceptance tests/load/taskflow.js
kubectl --context kind-sre-lab --namespace taskflow-staging get rollouts,analysisruns,replicasets,pods --watch
```

Ensure `staging.taskflow.localhost` resolves to 127.0.0.1 first; use your resolver or an explicitly reviewed hosts entry. The hostname is part of ingress routing, so substituting a bare IP changes the test. The configured steps are 10%, 25%, 50%, then 100%, with pauses and inline analysis at the first three weights.

Each analysis selects this namespace and the **Latest candidate Pod template hash**, excludes health probes, and checks at least 20 POST samples in two minutes, success ≥99.5%, and p95 <300ms. Stable traffic cannot dilute candidate errors. Too little traffic, absent metrics, NaN latency, or failed queries must prevent a pass. The configured `failureLimit: 1` permits one failed measurement before final failure; inspect the actual AnalysisRun rather than expecting instantaneous abort.

## Success, failure and recovery

1. Promote a known-good new digest. Record the old/new digest, traffic weights, candidate hash, AnalysisRuns and final stable revision. The first-ever Rollout initializes stable; use a subsequent change for a genuine canary comparison.
2. In a controlled staging PR, set `config.faultErrorPercent: 20` or `config.faultLatencyMs: 500`. The config checksum creates a new candidate template. Keep load active; verify analysis fails and nginx traffic returns to stable before full promotion.
3. Open a revert PR restoring the last good configuration/digest. Check the reverted desired state, ready endpoints, new job completion and cleared alert. An abort protects traffic but does not automatically rewrite Git or repair the candidate.

Do not manually promote a failed candidate to make the exercise finish. Capture lack of traffic, missing CRDs, wrong metric labels or insufficient capacity as a failed exercise with root cause. Keep before/after evidence in the [capacity report](../evidence/capacity-template.md) and [postmortem](../evidence/postmortem-template.md).
