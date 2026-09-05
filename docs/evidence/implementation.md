# Implementation verification — 2026-09-05

This records observed implementation checks, **not completion of the 84-day course**. Runtime and hosted-delivery evidence are updated as checks finish; unfinished acceptance items remain in `docs/acceptance.md`.

Observed locally on macOS ARM64, named Colima `kind-lab` (4 vCPU, 8 GiB), Kubernetes 1.36.1 node image pinned in the repository:

- Go unit tests with race detection passed.
- Six isolated PostgreSQL integration cases passed: exclusive concurrent claims, stale-lease fencing, bounded retries, recovery of a final crashed lease, pool reconnect, and repeated migrations.
- Docker runtime image uses user `65532:65532`, ARM64. Trivy found no HIGH/CRITICAL vulnerabilities in the tested image's Debian packages or Go binary; govulncheck found no reachable Go vulnerabilities at check time.
- Helm rendered local/dev/staging plus ten pinned upstream charts, Argo CD and raw exercise manifests; kubeconform validated **408 resources, zero invalid/errors/skipped**, including custom resources and CRD definitions. Later additions can change that count; rerun the command for the current tree.
- actionlint, shellcheck, source gitleaks and Trivy first-party configuration checks passed at that checkpoint. Git history had no commits yet at that check; history scanning is repeated after committing.
- Negative schema, privileged-Pod, generated fake-secret, known-vulnerable call-path and failing-Go-test fixtures were rejected for their intended reasons. The Kubernetes E2E rerun also rejected an unavailable image with `ErrImageNeverPull`, then successfully rolled back to the tested image.
- A disposable Kind cluster passed API/worker smoke, backup CronJob export, and fresh-namespace restore, including a full rerun after adding the negative rollout gate. Known completed job `f100ddf2-b177-43cd-a395-34215be8f0f2` was present as `succeeded` after restoration. The disposable cluster was removed by its own cleanup. Archives stayed in ignored `backups/`.
- The persistent three-node `sre-lab` cluster was created; all three nodes and Calico became Ready. Pinned ingress-nginx and metrics-server installed successfully. The existing default Colima profile was preserved and remained stopped.
- Taskflow deployed to that three-node lab and returned ready through localhost ingress. Its Calico policy test passed: both probe Pods resolved the DB name; the migration-labelled probe reached PostgreSQL; the unauthorized probe timed out; the ingress-namespace probe reached API readiness. Only the temporary probe Pods were removed.

Defects caught during implementation: unsafe secret rotation on bootstrap, destructive cluster recreation, PostgreSQL Alpine UID mismatch, backup PVC binding order, restore schema rejecting zero app replicas, candidate metrics mixing revisions, ignored CRD schemas, two upstream chart-value incompatibilities, and pre-CNI node-readiness waiting. These were corrected and relevant checks rerun as recorded above.

The public repository `https://github.com/skhitrov/k8s-platform-lab` was created under the authenticated user account. Commit authorship uses the GitHub no-reply address; no private email is needed. Hosted CI/publication results are recorded after their runs, not inferred from local success.

Still requires runtime evidence: full GitOps reconciliation and promotion, complete telemetry correlation, TLS/sealing recovery, real canary abort, 50/s ten-minute capacity acceptance, worker-failure availability boundaries and timed clean-cluster recovery. Do not infer any of these from rendered YAML alone.
