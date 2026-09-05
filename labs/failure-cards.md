# Controlled failure cards

Use a disposable learning/restore namespace unless a card explicitly needs the named lab cluster. The mentor chooses a card; hide the cause during blind diagnosis. Before injection record exact targets, healthy behavior, current Git digest/config, recovery action and stop condition. Never delete a source PVC or rotate a real credential merely to create a fault. Stop after one fault; verify recovery before the next.

| Card | Controlled injection | Expected discriminating evidence | Recovery / pass condition |
| --- | --- | --- | --- |
| F01 Selector | Change a learning Service selector to an unused value | Ready Pods but empty EndpointSlices | Restore selector; request through Service succeeds |
| F02 Port | Point learning Service to an unused container port | Endpoints exist; TCP/HTTP hop fails | Restore targetPort; both Service and ingress work |
| F03 Probe | Set a learning readiness path to a missing endpoint | Process live, readiness failing, endpoint removed | Restore path; observe Ready and traffic return |
| F04 Image | Use a nonexistent local image with PullNever | ErrImageNeverPull, new ReplicaSet unavailable | Restore exact known image; rollout and smoke pass |
| F05 Configuration | Change a required non-secret field/key in a clone | CreateContainerConfigError or bounded startup error | Restore config; verify stable restart count |
| F06 Quota | Request more than the learning namespace quota | Admission event identifies quota, not scheduler | Correct/delete only test Pod; valid request accepted |
| F07 CPU/OOM | Restrict one isolated CPU workload or memory limit | Throttling vs OOMKilled are distinguished | Restore measured limits; no repeated OOM/backlog growth |
| F08 DNS | Temporarily remove DNS allowance in an isolated copy | nslookup fails before DB connection is attempted | Restore precise DNS rule; policy test passes |
| F09 DB policy | Deny app→DB while leaving DNS | DNS succeeds; DB TCP readiness fails | Restore only required flow; API ready and job completes |
| F10 RBAC | Remove learning observer RoleBinding | Forbidden with correct identity/namespace | Restore binding; Pod reads allowed, Secret reads denied |
| F11 PVC | Use incompatible node affinity for a disposable claim | Pending with volume binding/affinity event | Restore compatible placement; marker persists |
| F12 Worker kill | Terminate one selected worker with known queued work | Lease expiry/new attempt, no stale completion commit | New worker drains queue; known IDs terminal |
| F13 Database restart | Restart the single lab DB after a verified backup | API live but not ready; worker DB errors | DB returns on data node; readiness and jobs recover |
| F14 Bad secret | Mismatch a password only in a disposable restored clone | Authentication failure rather than DNS/TCP timeout | Restore matching credentials without touching source |
| F15 Worker node | Stop a selected Kind worker after recording ingress/DB placement | Node/endpoint/Pod transitions and client error timeline | Start same container; restore placement; prove client and queue recovery |
| F16 Canary latency | Reviewed staging fault latency of 500ms with active ingress load | Candidate-hash p95 fails; stable metrics do not hide it | Automatic abort then Git revert; stable traffic and desired state healthy |
| F17 Canary errors | Reviewed staging 20% error fault | Candidate success analysis fails before 100% | Abort plus revert; verify sample counts and recovery |
| F18 No telemetry | Wrong ServiceMonitor selector or OTLP destination in a clone | Missing target/export failure, not a healthy-zero signal | Restore config; new metric/trace appears |
| F19 Bad archive | Truncate a copy of a dump, never the original | Header/checksum/restore validation rejects it | Use original verified archive in a new namespace |
| F20 GitOps drift | Change a harmless live application label | Argo detects and self-heals drift | Label returns to Git state; no manual overwrite loop |

For F15, inspect `kubectl --context kind-sre-lab --namespace taskflow-dev get pods -o wide` first. The explicitly scoped pair `docker --context colima-kind-lab stop sre-lab-worker2` / `docker --context colima-kind-lab start sre-lab-worker2` affects only that named node but may interrupt its database PVC. Do not use it without the inventory, backup and recovery plan. End-to-end unavailability is a valid finding in this single-VM/single-database design.

Each card ends with a sanitized postmortem/prevention assertion, not merely a successful restart command.
