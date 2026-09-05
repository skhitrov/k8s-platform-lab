# Implementation status — resumed 2026-09-05

The previously missing platform, delivery workflows, backup/restore, strict validation and documentation have now been implemented. The reference project includes an 84-day workbook, architecture/ADRs, runbooks, fault cards and evidence/acceptance templates.

Current checks: Go race tests and isolated PostgreSQL integration pass; 408 rendered resources validate with no skipped schemas; workflow/shell/secret/config/Go vulnerability checks pass; tested image has no HIGH/CRITICAL Trivy findings. Both K3s and three-node Kind bootstrap/application/policy paths pass. Disposable Kubernetes backup/restore and unhealthy-image rejection/recovery pass. The ten-minute 50/s ingress baseline accepted and completed 30,001 jobs. K3s live telemetry correlation, CA-validated HTTPS and disposable Sealed Secret recreation also pass.

The [public repository](https://github.com/skhitrov/k8s-platform-lab) is pushed; hosted CI and the verified multi-architecture GHCR release succeeded. After explicit user approval, [dev PR #1](https://github.com/skhitrov/k8s-platform-lab/pull/1) was squash-merged and main CI passed. Dev now runs the verified GHCR digest under Argo CD; the database Secret/data were preserved and a harmless-label drift/self-heal check passed. Staging is not enrolled or promoted. Live main-branch protection still requires CI/review with no admin bypass.

The longer GitOps bring-up exposed two memory limits that startup checks missed: repo-server OOM during concurrent chart rendering, and Tempo OOM during block completion. The local bootstrap repo-server correction passed a hard-refresh retest. A separate Tempo container passed two 5,000-trace block flushes and a persisted trace query after restart with the proposed smaller buffers/768Mi limit. The follow-up changes require review; **live Git-managed Tempo remains unhealthy until the reviewed fix is applied and rechecked**. Do not treat the earlier correlation success as current full-stack health. See the [GitOps adoption evidence](docs/evidence/2026-09-05-gitops.md).

No cloud provider or paid resource is involved. `k3s-lab` is running; Kind is stopped with data preserved; the default profile remains untouched. Exact dependency pins are in `platform/versions.yaml`, not the older list below.

See [implementation evidence](docs/evidence/implementation.md) for observed results and [acceptance](docs/acceptance.md) for unproven capstone exercises. Configuration existing is not evidence that a capacity, canary, recovery or learning gate was completed.

## Historical checkpoint from the earlier pause

The following sections describe the **2026-09-04 state only**, before this continuation; they are retained as the original handoff history, not current status.

## Completed

- Installed the local practice toolchain with Homebrew:
  - Go 1.27.1
  - kubectl 1.37.0
  - Helm 4.2.4
  - Kind 0.33.0
  - Kustomize 5.8.1
  - yq 4.53.6
  - k6 2.2.0
  - kubeconform 0.8.0
  - Trivy 0.74.0
  - actionlint 1.7.12
  - gitleaks 8.30.1
- Implemented the Taskflow Go application:
  - `api`, `worker`, `migrate`, and `version` subcommands
  - PostgreSQL-backed jobs with atomic `FOR UPDATE SKIP LOCKED` claims
  - leases, bounded retries, and idempotent synthetic CPU work
  - health, readiness, version, job, and Prometheus endpoints
  - structured JSON logging and optional OTLP tracing
  - deterministic latency/error fault injection for rollout labs
- Added unit tests and a PostgreSQL integration test.
- Added the hardened multi-stage/distroless Docker build and Compose development stack.
- Implemented most of the canonical Taskflow Helm chart:
  - API Deployment or optional Argo Rollout
  - worker Deployment
  - PostgreSQL StatefulSet and PVC
  - migration Job
  - Services, Ingress, HPA, PDB, NetworkPolicies, and ServiceMonitor
  - restricted security contexts and external Secret references
  - dev and staging values plus JSON schema
- Added the Makefile and scripts for diagnostics, validation, integration tests,
  smoke tests, k6 load tests, disposable Kind end-to-end tests, and K3s/Kind
  bootstrap.
- Added the stored k6 capacity profile.
- Generated `go.sum` with `go mod tidy`.

## Verified

- `gofmt` completed.
- All Go packages compile.
- All Go unit tests pass with the race detector.
- Helm 4 lints the chart successfully.
- Helm renders the dev chart successfully.
- Kubeconform reached all 21 rendered resources; validation was interrupted only
  because its schema download was blocked by sandboxed DNS, not because a schema
  error was reported.

## Current official chart versions discovered

- ingress-nginx: `4.15.1`
- argo-rollouts: `2.43.0`
- kube-prometheus-stack: `89.2.1`
- Loki: `7.3.0`
- Grafana Alloy: `1.12.1`
- Tempo: `1.24.4`
- OpenTelemetry Collector: `0.172.0`
- Sealed Secrets: lookup was interrupted before completion.

## Constraints and untouched state

- Colima remains stopped; no cluster was created.
- Nothing was published to GitHub or GHCR.
- No external repository, credential, or cloud resource was created.
- `git init -b main` failed because the managed workspace blocks creating `.git`.
  Project contents are present, but this directory is not yet a Git repository.

## Resume from here

1. Resolve and pin the current Sealed Secrets chart version.
2. Add Kind/Calico/ingress cluster configuration.
3. Add Argo CD bootstrap, AppProject, ApplicationSet, and pinned add-on Applications.
4. Add laptop-sized Prometheus/Grafana, Loki/Alloy, Tempo/OTel, dashboards, alerts,
   and backup/restore resources.
5. Add GitHub Actions for CI, ephemeral Kind, multi-architecture release/attestation,
   digest-update PRs, and staging promotion.
6. Add the README, 12-week daily workbook, runbooks, ADRs, fault cards, and portfolio
   acceptance checklist.
7. Run actionlint, gitleaks, Trivy, Helm staging render, kubeconform with network,
   Compose integration/smoke tests, image build, and the disposable Kind end-to-end
   test.
8. Fix any validation or runtime defects found, then report the final handoff.
