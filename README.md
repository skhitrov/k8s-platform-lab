# Taskflow — Kubernetes Platform / SRE Lab

A 12-week, 252-hour practical curriculum for a Linux/KVM engineer moving into Kubernetes and SRE. The workload is a Go job API, concurrent workers, and a PostgreSQL-backed queue. One repository carries the application, platform, delivery pipeline, and operational evidence.

This is a laptop lab, not a highly available production platform. Three Kind nodes still share one Colima VM; PostgreSQL and local-path volumes are single-node dependencies. Performance objectives are targets until a dated report proves them.

## Start here

Follow the [84-day workbook](docs/workbook.md). Use the implementation as a reference: reproduce the increments, break them deliberately, and submit the [weekly evidence template](docs/evidence/weekly-template.md). Do not mark an exercise complete just because its configuration exists.

Prerequisites: an Apple Silicon or Intel Mac with 16 GB RAM, approximately 30 GB free initially, Homebrew, Docker CLI, and GitHub access. A Colima profile is configured with a 60 GB maximum disk. Only one of `k3s-lab` and `kind-lab` may run at a time; the existing default profile is preserved.

```bash
brew install colima docker docker-compose docker-buildx go kubectl helm kustomize kind jq yq k6 kubeconform trivy gitleaks actionlint gh shellcheck govulncheck kubeseal ripgrep
git clone https://github.com/skhitrov/k8s-platform-lab.git /Users/skhitrov/study/k8s-platform-lab
cd /Users/skhitrov/study/k8s-platform-lab
make doctor
```

The current implementation workspace may instead be `/Users/skhitrov/study/devops`; run all remaining commands from the repository root. If Docker cannot find the Homebrew CLI plugins, follow `brew info docker-compose` and `brew info docker-buildx`; do not replace unrelated existing plugin files.

`platform/versions.yaml` locks cluster and chart dependencies; `platform/ci-tools.json` locks Linux CI binaries and SHA256 checksums. CI uses Kubernetes 1.36.3 tooling and Kind 0.32.0 with the published 1.36.1 multi-platform node digest. The Mac's `kubectl` may be one minor older/newer than the 1.36 API server. Local tool patch versions can differ; record `make doctor` output. Update locks deliberately and rerun validation.

## First local run

```bash
colima stop k3s-lab
colima start kind-lab --cpu 4 --memory 8 --disk 60 --runtime docker --activate=false
docker --context colima-kind-lab compose up --build --detach --wait
make test
bash scripts/smoke.sh http://127.0.0.1:8080
docker --context colima-kind-lab compose down
```

If `k3s-lab` does not exist, the first command is unnecessary. Compose binds only to loopback and uses an intentionally public local-only database password. Never reuse it elsewhere. `compose down` retains its named database volume. Integration tests use a separate ephemeral `taskflow_test` database on port 15432 and refuse to truncate another database.

```bash
make verify
make test-validators
env DOCKER_CONTEXT=colima-kind-lab make test-integration
env DOCKER_CONTEXT=colima-kind-lab make e2e
```

Validation downloads checksum-verified charts and public schemas/security databases. `make e2e` creates and removes only its own disposable `taskflow-e2e` cluster, checks a completed job, exports a CronJob backup, and verifies that same job after restoring into a new namespace. It refuses to reuse an existing cluster with that name. Its default Kind CNI does **not** prove NetworkPolicy enforcement.

## Kubernetes paths

Use K3s in Weeks 1–9, then Kind in Week 10. Bootstrap scripts stop the other named lab profile, never the default profile, and preserve existing clusters and database secrets.

```bash
make bootstrap-k3s
make deploy-local CONTEXT=colima-k3s-lab
```

Or, for the three-node platform:

```bash
make bootstrap-kind
make deploy-local CONTEXT=kind-sre-lab
curl --fail --resolve taskflow.localhost:8080:127.0.0.1 http://taskflow.localhost:8080/health/ready
```

Kind exposes ingress on localhost ports 8080 and 8443. For either cluster, an explicit port-forward also works:

```bash
kubectl --context kind-sre-lab --namespace taskflow-dev port-forward service/taskflow-taskflow 18080:80
bash scripts/smoke.sh http://127.0.0.1:18080
```

Run the smoke command in another terminal. Use `colima-k3s-lab` instead of `kind-sre-lab` for K3s. The non-root distroless application has no shell: inspect logs, metrics, events, or use a narrowly scoped debug Pod.

## Delivery and operation

```text
PR → hosted CI → main → immutable amd64/arm64 GHCR image + SBOM/provenance
                            ↓
                      dev digest PR → review/merge → Argo CD pulls dev
                                                          ↓
                               manual promotion PR → review/merge → staging canary

Ingress → API → PostgreSQL job queue ← workers
            └──── metrics / JSON logs / OTLP traces → observability stack
```

No cluster credential is stored in GitHub Actions. Follow [GitOps setup](docs/runbooks/gitops.md) before `make bootstrap-gitops`: initial environment digests are deliberately empty, so a placeholder image cannot be bootstrapped. The first dev digest PR is a prerequisite; the first tested promotion enrolls staging.

Operational guides: [cluster lifecycle](docs/runbooks/cluster.md), [troubleshooting](docs/runbooks/incidents.md), [backup and restore](docs/runbooks/backup-restore.md), [security and TLS](docs/runbooks/security.md), [observability/SLOs](docs/runbooks/observability.md), [canary delivery](docs/runbooks/canary.md), [capacity testing](docs/runbooks/capacity.md).

Architecture and limits: [design](docs/architecture.md), [ADRs](docs/adr/README.md). Review [implementation evidence](docs/evidence/implementation.md) and the [acceptance checklist](docs/acceptance.md) for the distinction between implemented, tested, and still to demonstrate.

## Repository map

| Path | Role |
| --- | --- |
| `app/`, `Dockerfile` | Go API, worker, migrations, immutable runtime image |
| `deploy/chart/taskflow/` | Canonical application Helm chart; local/dev/staging values |
| `platform/` | Version locks, cluster bootstrap, GitOps and add-on configuration |
| `.github/workflows/` | Hosted CI, image publication, digest and promotion PRs |
| `scripts/`, `tests/` | Repeatable verification, backup/restore, load profiles |
| `labs/` | Isolated raw-manifest learning exercises, superseded by the chart |
| `docs/` | Workbook, decisions, runbooks, evidence and portfolio |

Generated dumps, kubeconfigs, private keys, plaintext credentials, and security-scanner reports must remain outside Git. If a credential is ever committed, revoke it first; deleting the working file does not remove it from history.
