# Implementation verification — 2026-09-05

This records observed implementation checks, **not completion of the 84-day course**. Runtime and hosted-delivery evidence are updated as checks finish; unfinished acceptance items remain in `docs/acceptance.md`.

Observed locally on macOS ARM64, named Colima `kind-lab` (4 vCPU, 8 GiB), Kubernetes 1.36.1 node image pinned in the repository:

- Go unit tests with race detection passed.
- Six isolated PostgreSQL integration cases passed: exclusive concurrent claims, stale-lease fencing, bounded retries, recovery of a final crashed lease, pool reconnect, and repeated migrations.
- Docker runtime image uses user `65532:65532`, ARM64. Trivy found no HIGH/CRITICAL vulnerabilities in the tested image's Debian packages or Go binary; govulncheck found no reachable Go vulnerabilities at check time.
- Helm rendered local/dev/staging plus ten pinned upstream charts, Argo CD and raw exercise manifests; kubeconform validated **408 resources, zero invalid/errors/skipped**, including custom resources and CRD definitions. Later additions can change that count; rerun the command for the current tree.
- actionlint, shellcheck, source gitleaks and Trivy first-party configuration checks passed. The subsequent verification also scanned both initial Git commits with no leaks.
- Negative schema, privileged-Pod, generated fake-secret, known-vulnerable call-path and failing-Go-test fixtures were rejected for their intended reasons. The Kubernetes E2E rerun also rejected an unavailable image with `ErrImageNeverPull`, then successfully rolled back to the tested image.
- A disposable Kind cluster passed API/worker smoke, backup CronJob export, and fresh-namespace restore, including a full rerun after adding the negative rollout gate. Known completed job `f100ddf2-b177-43cd-a395-34215be8f0f2` was present as `succeeded` after restoration. The disposable cluster was removed by its own cleanup. Archives stayed in ignored `backups/`.
- The persistent three-node `sre-lab` cluster was created; all three nodes and Calico became Ready. Pinned ingress-nginx and metrics-server installed successfully. The existing default Colima profile was preserved and remained stopped.
- Taskflow deployed to that three-node lab and returned ready through localhost ingress. Its Calico policy test passed: both probe Pods resolved the DB name; the migration-labelled probe reached PostgreSQL; the unauthorized probe timed out; the ingress-namespace probe reached API readiness. Only the temporary probe Pods were removed.

Defects caught during implementation: unsafe secret rotation on bootstrap, destructive cluster recreation, PostgreSQL Alpine UID mismatch, backup PVC binding order, restore schema rejecting zero app replicas, candidate metrics mixing revisions, ignored CRD schemas, two upstream chart-value incompatibilities, and pre-CNI node-readiness waiting. These were corrected and relevant checks rerun as recorded above.

The public repository `https://github.com/skhitrov/k8s-platform-lab` was created under the authenticated user account. Commit authorship uses the GitHub no-reply address; no private email is needed. Hosted CI/publication results are recorded after their runs, not inferred from local success.

[Initial hosted CI](https://github.com/skhitrov/k8s-platform-lab/actions/runs/33982739433) passed all gates for `e00fa001d6b0d323a2df90514321aa822d549b1d`, including Linux image build/scan, negative fixtures and Kubernetes backup/restore. The first Release workflow skipped publication because `rg` was absent from its separate runner; its green overall status was **not** treated as artifact success. Release change detection was corrected to use Git/Bash only, compare against the deployed source SHA, and fail on command errors; registry publication is verified separately.

Still requires capstone evidence: full GitOps reconciliation and reviewed promotion, alert firing/resolution and dashboard-assisted fault diagnosis, private sealing-key recovery on a clean cluster, real canary abort, full-platform capacity, worker-failure availability boundaries and timed clean-cluster recovery. Do not infer any of these from rendered YAML alone.

The [local ingress capacity baseline](2026-09-05-capacity.md) subsequently passed 50/s for ten minutes: 30,001 accepted and completed jobs, zero HTTP failures/dropped iterations, 1.758ms submission p95. This is the local-values baseline without the full telemetry stack; full-platform capacity and the other capstone claims remain separate exercises.

## Hosted artifact and review gate

[CI for source commit `178876c`](https://github.com/skhitrov/k8s-platform-lab/actions/runs/33983147019) and its [Release](https://github.com/skhitrov/k8s-platform-lab/actions/runs/33983331956) both passed. Release actually executed its build, signed-provenance verification, architecture checks and per-platform SBOM/provenance checks. The published image is `ghcr.io/skhitrov/k8s-platform-lab/taskflow@sha256:f13a105f7ae4cfcda977df0483c5d3fe41864d72b00ca8c876da756f28f2ecc2`. A separate anonymous registry-token/manifest request confirmed access and the `linux/amd64` and `linux/arm64` index entries; no user credential was used for that check.

The workflow opened [dev digest PR #1](https://github.com/skhitrov/k8s-platform-lab/pull/1). It was deliberately not approved or merged during implementation. A later release can update that PR's digest; compare its current source identity against its own successful Release. GitOps adoption and staging promotion remain gated by actual human review, not inferred authorization.

## K3s and live add-ons

K3s `v1.36.3+k3s1` was bootstrapped in its own 4-vCPU/8-GiB profile after stopping Kind. Taskflow built and deployed using the local helper. K3s policy probes passed the same DNS/allowed-DB/denied-DB/ingress checks as Kind. A lab Certificate became Ready and HTTPS readiness returned `{"status":"ready"}` through `https://taskflow.localhost`, with the public lab CA explicitly validated, not `curl -k`.

All eight add-ons installed on K3s. Prometheus and Alertmanager reported Available; Grafana, Loki, Tempo, Alloy, the OTLP collector and security controllers were Ready. Runtime checks found/fixed Grafana sidecar OOM limits, insufficient Grafana headroom, an inherited Alertmanager route to a removed receiver, the pre-GitOps Alloy namespace prerequisite and the sealing helper's controller name. The OTLP exporter uses its current `otlp_grpc/tempo` name without the chart's deprecated-name rewrite.

`bash scripts/test-observability.sh colima-k3s-lab taskflow-dev` passed for job `3583d835-6409-4f31-b825-13dc9e87c913`, request `telemetry-20260905T182539Z-21229`, trace `f184cb27b65172b10040565c16ca2836`. Prometheus scraped API/worker targets, Loki contained both components' logs with that trace, and Tempo linked server → `jobs.insert` → `jobs.process` spans. This proves propagation through the database queue, not merely independent traces.

`bash scripts/test-sealed-secret.sh colima-k3s-lab` passed: the controller decrypted an isolated test SealedSecret, then recreated its deleted Secret with a new UID and identical data. Only the disposable test namespace was removed; no database credential was rotated and no sealing private key was exported.

At handoff the K3s profile is running; Kind is stopped with its data retained; the pre-existing default profile is still stopped and unchanged. The active K3s app uses its local test image with telemetry and TLS overrides, not the unmerged GHCR digest. No Argo CD application reconciliation is claimed yet.
