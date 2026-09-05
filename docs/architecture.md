# Architecture and operating boundaries

## Workload

`POST /v1/jobs` accepts bounded CPU work and returns 202 plus a UUID. `GET /v1/jobs/{id}` returns queued/running/succeeded/failed state. `/health/live` checks the process; `/health/ready` checks database access. `/metrics` exposes bounded-label Prometheus metrics, and `/version` identifies the source build. Clients may send `X-Request-ID`; responses and JSON logs correlate requests with trace IDs.

The API persists both a job and its W3C trace parent. Workers claim rows with `FOR UPDATE SKIP LOCKED`, bounded attempts, and expiring leases. Completion/failure updates are fenced by the claim attempt and unexpired lease. A crashed final attempt becomes failed after expiry, not permanently running. This is at-least-once processing with fenced state changes, **not** exactly-once execution of arbitrary external side effects. A future side-effecting handler needs an idempotency key/outbox design.

Migration files are ordered, checksummed, transactionally applied, and protected by an advisory lock. Do not edit an applied migration; add a new one. API/worker pools default to five maximum connections each; size their combined maximum, rollout surge, migrations, and backups against PostgreSQL's connection capacity.

## Deployment ownership

| Owner | Managed resources | Boundary |
| --- | --- | --- |
| Colima/Kind scripts | Named VM, nodes, Calico, ingress, metrics-server | Preserve default profile and existing clusters |
| Kustomize bootstrap | Argo CD, root Application, AppProjects | Trusted platform administration |
| Platform GitOps Applications | Pinned Helm add-ons and platform configuration | Cluster-scoped CRDs/RBAC require reviewed platform changes |
| Taskflow ApplicationSet | Dev and staging Helm releases | Restricted AppProject destinations and namespaced resources |
| Secret bootstrap / Sealed Secrets | Database and Grafana credentials | Never plaintext in Git; private sealing key stays external |
| Hosted CI | Tests, scans, images, attestations, Git PRs | No local kubeconfig, cluster token, or self-hosted runner |

Sync waves establish controllers/CRDs, observability backends, collectors, platform configuration, then workload Applications. Application health propagation makes the parent wait for child health. Inside the workload chart, ServiceAccount/config/policies precede PostgreSQL, then the migration Sync hook, then API/worker resources. The backup PVC and database share a binding wave so local-path `WaitForFirstConsumer` does not deadlock.

GitOps owns application state after adoption. Helm CLI changes are for the early local path or isolated exercises; do not use them to fight an active Argo Application. Stage promotions copy the **exact** dev manifest digest and source SHA, without rebuilding.

## Network and resource model

App namespaces enforce Restricted Pod Security, quotas and limits. Default-deny ingress/egress is opened only for DNS, ingress-to-API, app/backup-to-PostgreSQL, monitoring scrapes, and OTLP to the collector. Calico supplies enforcement in Kind; the CI-only Kind topology intentionally uses its default CNI and skips that claim.

The full lab uses one 4-vCPU/8-GiB VM. Initial requests, not guaranteed actual usage: API 50m/64Mi each, worker 100m/64Mi each, PostgreSQL 100m/256Mi per environment; Prometheus 200m/512Mi; Loki 100m/256Mi; Tempo 75m/128Mi; collector 25m/64Mi, plus Grafana, controllers, Kubernetes and storage overhead. Limits can overcommit the host. Measure actual totals before increasing replicas; HPA maxima are ceilings, not a recommendation to run both environments at their ceilings together.

Metrics retain 6 hours, Loki logs 24 hours and Tempo traces 6 hours. Data uses local filesystem/PVC storage, with no object-store dependency. This is a cost/footprint choice, not a durable observability service. Only application traces are exported; the collector is not also scraping Prometheus or duplicating Alloy's logs.

## Deliberate limitations

- PostgreSQL is a single instance and PVCs are node-local. Losing its node interrupts both readiness and queue processing. A database backup PVC on the same node protects against logical mistakes, not node/disk loss; export and copy archives outside the VM.
- Kind worker loss exercises scheduling inside one host, not an availability zone. Replica spreading can preserve API processes while the database dependency still makes the service unavailable.
- Ingress is bound to one worker for the local port mapping. Losing that ingress worker can interrupt the external endpoint even when API replicas survive. Measure endpoint and dependency failures separately; do not claim complete HA.
- The synthetic CPU workload is an operability vehicle, not an internet-scale benchmark. API acceptance latency and job completion latency are different measurements.
- The lab CA is not publicly trusted. Never disable TLS verification in a real client to emulate this lab.
- No cloud billing, kubeadm, true multi-host HA, service mesh, or custom operator is part of the core curriculum.
