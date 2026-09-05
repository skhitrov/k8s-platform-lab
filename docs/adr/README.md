# Architecture decision records

Accepted for the local training platform; revisit only with measured evidence or a changed requirement.

## ADR-001 — One Go image, PostgreSQL queue

Decision: one distroless non-root image provides `api`, `worker`, and `migrate`. PostgreSQL supplies persistence and leased queue claims. Reason: learn deployment, concurrency, and failure handling without introducing another broker. Consequence: database capacity and availability bound the entire service; fenced writes do not guarantee exactly-once external effects. Alternative: Redis/RabbitMQ and a separate database, deferred until the existing bottleneck is demonstrated.

## ADR-002 — Named Colima profiles and staged topologies

Decision: begin with K3s, then one-control-plane/two-worker Kind with Calico, one 8-GiB profile running at a time. Reason: fit the 16-GB workstation and separate basic Kubernetes learning from scheduling/policy experiments. Consequence: VM/node-local failure limits must be explicit; default Colima state remains untouched. Alternative: cloud multi-host clusters, outside the budget/scope.

## ADR-003 — Helm application, Kustomize platform

Decision: the Helm chart is the only canonical Taskflow deployment package; Kustomize assembles bootstrap and static platform configuration. Raw exercises stay in `labs/` and are not applied to GitOps namespaces. Reason: eliminate competing desired states while learning both tools. Consequence: environment differences belong in values; changes must be tested across local/dev/staging renders.

## ADR-004 — Pull GitOps, digest promotion

Decision: hosted CI publishes commit-tagged multi-architecture images, SBOM/provenance and reviewed digest PRs. Argo CD pulls approved Git state. Staging promotion copies the tested dev digest. Reason: avoid exposing a laptop cluster or giving CI its credentials; make rollback reviewable. Consequence: GitHub permissions, branch checks, package visibility, and public clone access are explicit prerequisites. Tags alone are insufficient provenance; verify the registry digest and attestation.

## ADR-005 — Small observability stack

Decision: Prometheus/Grafana/Alertmanager, monolithic filesystem Loki plus namespace-scoped API-log Alloy, single-binary Tempo, and traces-only OTLP collector. Reason: retain metrics/log/trace learning on one small VM without caches, distributed backends, or object storage. Consequence: short retention, single-replica failure modes and no durable paging receiver by default. Local alerts are visible but are not delivered to an external on-call channel until configured.

## ADR-006 — Explicit security and recovery boundaries

Decision: Restricted app namespaces, non-root/read-only containers, no app API token, deny-by-default networking, externally generated database credentials, and strict-namespace Sealed Secrets. Backup uses custom-format PostgreSQL archives restored only into a fresh namespace. Reason: make privileges and destructive operations observable and narrow. Consequence: sealing-key backup is essential; restoring data without the key is possible with a new database password, but resealing existing encrypted secrets requires the original key or plaintext source from a secure store.

## ADR-007 — Candidate-scoped canary analysis

Decision: nginx traffic weights 10/25/50/100, with namespace and `rollouts-pod-template-hash` scoped sample, success and latency queries. Reason: aggregate stable traffic must not hide a broken candidate. Consequence: load must remain active; missing/insufficient data does not pass. The first rollout initializes stable without an existing comparison revision; demonstrate abort on a subsequent change.
