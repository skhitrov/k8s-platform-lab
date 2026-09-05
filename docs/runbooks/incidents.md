# Incident triage

Begin with scope, impact, UTC start time, recent Git change and exact cluster/namespace. Preserve events/logs before restarting anything. Investigate one hypothesis at a time; record the command, result and next hypothesis. Protect the source database and backups throughout.

```bash
kubectl --context kind-sre-lab --namespace taskflow-dev get pods,deployments,statefulsets,jobs,pvc,services,ingress,hpa,pdb -o wide
kubectl --context kind-sre-lab --namespace taskflow-dev get events --sort-by=.lastTimestamp
kubectl --context kind-sre-lab --namespace taskflow-dev logs deployment/taskflow-taskflow-api --tail=100
kubectl --context kind-sre-lab --namespace taskflow-dev logs deployment/taskflow-taskflow-worker --tail=100
kubectl --context kind-sre-lab --namespace taskflow-dev get endpointslices
```

Never paste Secret contents, a connection URL or a dump into a ticket. Distroless has no shell; failure of `kubectl exec ... sh` is expected, not proof of a broken image.

| Symptom | Distinguish these causes | Recovery and proof |
| --- | --- | --- |
| Pending Pod | Requests vs allocatable, taints, PVC affinity, quota, unbound claim | Restore capacity or placement; inspect scheduled node and Ready condition |
| ImagePullBackOff / ErrImageNeverPull | Wrong digest, private GHCR, unloaded local image, architecture | Restore reviewed image/pull access; verify `/version` and job completion |
| CrashLoopBackOff | Bad config, migration failure, OOM, permission/UID mismatch | Inspect previous logs/events; fix source config, verify restart count stabilizes |
| Ready=false but live=true | DB reachability, credentials, missing schema or pool exhaustion | Restore dependency; do not weaken readiness to hide it |
| Service has no endpoints | Label selector, target port, readiness, namespace | Compare selector→Pod labels→container port; retry through Service and ingress |
| Ingress 502/503 | No ready endpoints, wrong host, backend port or ingress node | Test each hop; preserve TLS verification in final client check |
| DNS timeout / DB timeout | DNS egress denied vs destination egress/ingress denied | Contrast nslookup and TCP readiness; restore precise policy, rerun policy test |
| Queue age increasing | Worker crash, insufficient CPU, DB pool/lease contention | Compare submission vs completion rate; restore workers, drain backlog, check terminal states |
| Canary stuck/aborted | No candidate traffic, missing hash labels, regression, Prometheus error | Inspect AnalysisRun query/results; Git revert, never force-promote a regression |
| Backup failure/stale | Full PVC, bad credentials, unreachable DB, unscheduled job | Export a verified archive; restore into a new namespace and check a known job |
| Node drain blocked | PDB, node-local storage, no spare capacity | Restore capacity or end exercise; do not override protections blindly |

Escalation boundary: a single-instance database/node-local volume outage cannot be fixed by rescheduling an API. Bring back the data node or execute a reviewed fresh-namespace restore; report the downtime honestly. Stopping one Kind worker does not simulate independent-host HA, and losing the ingress-mapped worker can remove the public lab endpoint.

Finish only after client validation, a new completed job, queue recovery, restored desired state and stable observations. Use the [postmortem template](../evidence/postmortem-template.md) for impact, timeline, causal chain, what helped/hurt, and a tested prevention action.
