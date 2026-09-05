# 84-day practical workbook

12 weeks × 7 days × 3 hours = 252 hours. Work from the repository root. Week 1 starts on K3s; Week 10 moves to Kind. The supplied implementation is a reference solution, not evidence that the learner completed a lab. Keep raw-manifest experiments in `taskflow-learning`, never in GitOps-owned namespaces.

Every day uses the same clock: 15 minutes define/inspect the result; 90 minutes build; 45 minutes break/diagnose/recover; 20 minutes automate/test; 10 minutes commit sanitized evidence and one operational lesson. Use the named runbook only while solving that day's concrete problem. If the failure is not recovered in its slot, document the current state and continue recovery the next day; do not invent a pass.

Every weekly gate requires a clean commit/PR, passing `make verify`, one independently diagnosed fault, a runbook/postmortem, a timed rebuild or repair, and a [weekly review](evidence/weekly-template.md) with repository link, command output, symptoms, cause, fix and open questions. Fail a gate if its proof is missing.

## Week 1 — Workstation, Go, container and first Pod

| Day | Build / observable outcome | Break, recover, and commit proof |
| --- | --- | --- |
| 01 | Authenticate `gh`, create/inspect the public repository, run `make doctor`, provision only `k3s-lab`. Record exact tools and profile resources. | Select a wrong context without applying resources; identify it from context/cluster output. Add a preflight checklist. |
| 02 | Trace health/version endpoints, structured logs and signal handling through the Go source; add one endpoint test, run `make test`. Use local PostgreSQL as a supporting fixture. | Make the new test fail, explain its assertion, then repair it. Save test output, not only coverage percentage. |
| 03 | Build the multi-stage image and inspect user, architecture, layers and OCI labels. Run the `version` subcommand. | Use a missing image tag, diagnose pull vs architecture errors, load the correct image. Record image ID and size. |
| 04 | Run API/worker with read-only root, dropped capabilities and CPU/memory limits; observe SIGTERM shutdown. | Interrupt a process and compare exit/log timing to its grace period. Automate non-root/read-only checks. |
| 05 | Inspect K3s nodes, system Pods, events, API resources and StorageClasses. Explain requests vs node allocatable. | Query an absent namespace/resource kind and distinguish client/context/API errors. Commit a context-safe command sheet. |
| 06 | Run `labs/raw/first-pod.yaml` after loading the image; inspect logs/status, recreate it, then exercise an API port-forward. | Use a nonexistent image and inspect events; restore the file. Record Completed versus Ready semantics. |
| 07 | Rebuild the learning namespace and first image/Pod without shell history, using only committed instructions. | Time recovery from the week's unknown image/config fault. Commit the Week 1 review and troubleshooting notes. |

Gate: tested Go image executes as non-root in Docker and K3s; a fresh operator can repeat the first-Pod path.

## Week 2 — Core workload objects

| Day | Build / observable outcome | Break, recover, and commit proof |
| --- | --- | --- |
| 08 | Write a Pod lifecycle exercise in `labs/raw`; observe restartPolicy, termination state and conditions. | Force a nonzero exit and distinguish RestartCount from a replacement Pod. Add a status assertion. |
| 09 | Replace the API Pod with a Deployment in the learning namespace; scale and perform an update. | Deploy a bad tag, inspect ReplicaSets and undo; save rollout timing and ready replica counts. |
| 10 | Write a ClusterIP Service; inspect EndpointSlices and resolve it from a disposable debug Pod. | Break the selector, then targetPort separately; diagnose each hop before fixing. Save a selector→endpoint checklist. |
| 11 | Add ConfigMap settings and Secret references as environment/volume examples, without committing plaintext credentials. | Rename a required key; distinguish configuration failure from database authentication. Test the repaired template. |
| 12 | Implement startup/readiness/liveness probes and verify graceful SIGTERM. | Make DB access fail while the process stays live; prove readiness, not liveness, removes it from endpoints. |
| 13 | Record Guaranteed/Burstable/BestEffort examples in isolated Pods; measure CPU throttling and a controlled OOM. | Repair one resource-starved Pod without removing limits entirely. Commit events and chosen settings. |
| 14 | Recreate the stateless objects declaratively. | Under 45 minutes repair selector, port, probe, image and configuration cards; commit the diagnostic order and Week 2 review. |

Gate: updates preserve a working endpoint and an operator can diagnose core workload faults from evidence.

## Week 3 — Networking, storage, access and isolation

| Day | Build / observable outcome | Break, recover, and commit proof |
| --- | --- | --- |
| 15 | Add labels, annotations, ResourceQuota and LimitRange to the learning namespace; inspect admission defaults. | Exceed one quota intentionally, recover by resizing/removing only the test Pod, and assert the rejection reason. |
| 16 | Install ingress and cert-manager using the locked charts; enable the lab CA/TLS and validate with `--cacert`. | Use the wrong Host header and wrong CA separately; show routing vs trust failures. Never count `-k` as success. |
| 17 | Write a Job/CronJob with bounded retries, deadline, history and cleanup. | Force one failed run; inspect Job conditions and retry behavior before correcting the command. |
| 18 | Bind a PVC and persist a marker across Pod replacement; inspect StorageClass and reclaim policy. | Schedule against incompatible node affinity; diagnose Pending storage without deleting real data. |
| 19 | Apply a namespaced read-only Role/ServiceAccount; test allowed Pod reads and denied Secret reads with `auth can-i`. | Remove the RoleBinding, observe denial, restore it. Prove the app does not mount a token. |
| 20 | Apply default-deny and explicit DNS/ingress/database/monitoring policy. | Prove an unauthorized Pod cannot reach DB while required traffic succeeds; add the policy test output. |
| 21 | Rebuild the namespace with networking, storage and RBAC from Git. | Solve five independent faults with a timer, preserve the PVC where required, and submit Week 3 review. |

Gate: ingress/TLS works, unauthorized flows are blocked by an enforcing CNI, and state survives Pod replacement.

## Week 4 — Stateful Taskflow behavior

| Day | Build / observable outcome | Break, recover, and commit proof |
| --- | --- | --- |
| 22 | Trace schema and migration ledger; run isolated PostgreSQL integration setup and repeat migrations safely. | Alter an already-applied migration in a temporary copy; prove checksum rejection, then discard the copy. |
| 23 | Add API validation tests for work bounds, malformed/trailing JSON, UUIDs and timeouts. | Send invalid requests and show bounded route labels; make and repair an assertion failure. |
| 24 | Explain SKIP LOCKED claims, leases, attempts and fenced completion from code and database state. | Simulate an expired lease and stale worker completion; prove it cannot overwrite the newer claim. |
| 25 | Run concurrent claim, bounded retry, final-crash lease and database-pool reconnect tests with race detection. | Introduce a temporary duplicate-claim bug; ensure the integration test fails before restoring code. |
| 26 | Add/inspect request IDs, trace IDs, RED/queue/pool metrics and bounded DB pools. | Exhaust a small pool under controlled concurrency, distinguish acquisition delay from query delay, then restore it. |
| 27 | Run API, worker and migrate from the same immutable image in Compose. | Stop/restart a worker with pending work; verify terminal states and explain at-least-once limits. |
| 28 | Run the first k6 ramp and record percentiles, offered/accepted rate, queue drain, CPU/memory and DB pressure. | Find one saturation symptom and test one hypothesis. Commit an honest baseline and Week 4 review. |

Gate: concurrency/lease tests pass, known jobs are neither lost nor multiply committed, and a measured baseline exists.

## Week 5 — Reliable Kubernetes workload

| Day | Build / observable outcome | Break, recover, and commit proof |
| --- | --- | --- |
| 29 | Deploy the PostgreSQL StatefulSet, existing Secret, Service, PVC and explicit resource limits. | Replace the Pod, confirm known data persists, and verify the Alpine UID 70 volume permissions. |
| 30 | Run the migration Job before API/workers; inspect hooks, conditions and schema ledger. | Make a migration fail in an isolated release; prove app rollout does not proceed as healthy. |
| 31 | Tune startup/readiness, shutdown timing and RollingUpdate settings with active requests. | Kill an API Pod during requests; measure endpoint removal and recovery, then improve one setting. |
| 32 | Enable HPA/PDB and topology spreading; document what a single K3s node cannot guarantee. | Attempt a blocked eviction and explain the PDB/capacity constraint without forcing it. |
| 33 | Drive CPU load and observe HPA replicas, stabilization delay, throttling and DB-pool totals. | Set an overly small CPU limit briefly; distinguish scale-out from throttling and restore the baseline. |
| 34 | Enable the backup CronJob; export an archive and restore it into a fresh `taskflow-restore-*` namespace. | Try an existing restore target and a corrupt archive; both must be rejected without changing source data. |
| 35 | Queue work, kill workers, restart PostgreSQL and inject bad configuration one incident at a time. | Verify lease recovery and new job completion after repair; submit backup evidence and Week 5 review. |

Gate: worker replacement preserves queued work; restore proves a known job; resource choices cite observations.

## Week 6 — Packaging, validation and security

| Day | Build / observable outcome | Break, recover, and commit proof |
| --- | --- | --- |
| 36 | Reconstruct the canonical Helm chart from the raw exercise; compare rendered resources and ownership labels. | Break a helper/selector, catch it before applying, then add a rendering assertion. |
| 37 | Add local/dev/staging values and JSON-schema constraints; render every environment. | Supply wrong types/bounds, prove Helm rejects them, then restore valid settings. |
| 38 | Exercise install, upgrade, failed upgrade and rollback in an isolated namespace; inspect retained PVCs. | Recover a failed image update without deleting state; document uninstall and retention behavior. |
| 39 | Build platform Kustomize output and explain why it is separate from application Helm packaging. | Break a resource path, diagnose the build failure, and restore it. Inspect pinned upstream content hashes. |
| 40 | Verify non-root, read-only root, seccomp, dropped capabilities, resource limits and immutable image references. | Submit a privileged Pod to a Restricted namespace and confirm admission denial. |
| 41 | Seal the existing database password and commit only namespace-bound ciphertext; test RBAC and policy again. | Try ciphertext in another namespace, observe decryption failure, and restore the valid binding. |
| 42 | Run `make validate` and `make test-validators`; inspect positive and negative reports. | Prove malformed, privileged, fake-secret, vulnerable and failing-test fixtures are rejected for the expected reason, not a network error. |

Gate: validation rejects unsafe changes without globally ignoring schemas or security rules; weekly review includes actual outputs.

## Week 7 — CI and supply chain

| Day | Build / observable outcome | Break, recover, and commit proof |
| --- | --- | --- |
| 43 | Configure protected `main`, required `verify`, PR review, CODEOWNERS and Dependabot. | Open a failing PR and prove merge is blocked; document solo-author review limitations. |
| 44 | Run formatting, vet, race tests, coverage and govulncheck on hosted CI. | Introduce a failing unit test on a branch; confirm useful logs, then repair it. |
| 45 | Run actionlint, Helm/schema checks, shellcheck, gitleaks and Trivy in CI. | Break one manifest/action pin; verify the correct stage rejects it and the report is retained. |
| 46 | Publish commit-SHA-tagged amd64/arm64 images to GHCR from a successful main CI run. | Confirm an untrusted PR cannot invoke the privileged release path; inspect both manifest platforms. |
| 47 | Verify registry SBOM and signed provenance against the exact image digest/source repository. | Try an incorrect digest/identity and record verification failure, then verify the genuine release. |
| 48 | Run ephemeral hosted Kind E2E with smoke, backup/restore and deliberately unhealthy-image rejection. | Inspect the negative rollout report and confirm cleanup removes only the CI-owned cluster. |
| 49 | Review durations and duplicated work across workflow jobs; optimize without dropping gates. | Exercise one failed stage blindly, repair it, and submit pipeline links and Week 7 review. |

Gate: tests, security, manifests and Kubernetes deployment checks block unverified changes; published artifacts are traceable by digest.

## Week 8 — Pull-based GitOps

| Day | Build / observable outcome | Break, recover, and commit proof |
| --- | --- | --- |
| 50 | Merge the first dev digest PR and bootstrap pinned Argo CD from Kustomize. | Block repository access temporarily in an isolated exercise; distinguish fetch failure from workload failure. |
| 51 | Inspect scoped AppProjects and the ApplicationSet; dev is first, staging is enrolled by its first promotion. | Attempt an out-of-project destination in a temporary Application and prove it is denied. |
| 52 | Observe dev auto-sync, pruning and self-heal. | Edit a harmless live label, record drift detection/correction time, and verify no Git change was needed. |
| 53 | Send a small Go change through CI/release/dev digest PR and merge after review. | Verify docs-only/digest-only merges do not rebuild endlessly; trace source SHA to deployed digest. |
| 54 | Collect dev evidence, trigger promotion and review the exact-digest staging PR. | Try a missing/malformed dev digest locally; promotion must fail rather than rebuild or use a tag. |
| 55 | Practice coordinated database password rotation/resealing with a recoverable backup. | Diagnose a mismatched password in an isolated clone, repair database/Secret/ciphertext agreement, scan history. |
| 56 | Deploy a bounded broken configuration and recover by a reviewed Git revert. | No direct cluster image fix: record Git→Argo→workload reconciliation and submit Week 8 review. |

Gate: merged changes reach dev by pull GitOps, and staging receives a reviewed, runtime-tested immutable digest.

## Week 9 — Metrics, logs, traces and SLOs

| Day | Build / observable outcome | Break, recover, and commit proof |
| --- | --- | --- |
| 57 | Inspect RED, queue depth/age, worker duration, pool saturation and trace propagation under requests. | Add a bad metric label in a temporary branch; detect cardinality risk and restore bounded labels. |
| 58 | Install/check the small Prometheus, Alertmanager and Grafana stack with resource/retention bounds. | Break a ServiceMonitor selector, diagnose an absent target, then restore scraping. |
| 59 | Add a useful dashboard panel and recording rule from a concrete diagnostic question. | Break the query label/namespace, catch the empty series and fix it; commit the dashboard JSON. |
| 60 | Define 99.5% availability, p95 <300ms and multi-window burn alerts; state measurement blind spots. | Inject errors long enough for the chosen real window or label a shortened test rule honestly; prove firing and resolution. |
| 61 | Check Loki logs and Alloy namespace-scoped API/event access. | Break an Alloy RBAC binding in a clone, diagnose forbidden errors and recover without granting Secret access. |
| 62 | Follow one API request through queue persistence to the worker span in Tempo and correlated Loki logs. | Break the OTLP endpoint, observe export failures, restore it, and prove a new full trace. |
| 63 | Diagnose an unknown fault starting with alerts/panels, then logs/traces, before inspecting manifests. | Submit the evidence chain, recovery timeline and Week 9 review; distinguish missing telemetry from healthy service. |

Gate: a user-visible failure has a defensible alert→dashboard→log/trace→cause path, with external-client evidence for blind spots.

## Week 10 — Multi-node scheduling

| Day | Build / observable outcome | Break, recover, and commit proof |
| --- | --- | --- |
| 64 | Stop K3s; bootstrap Kind with one control-plane/two workers, Calico, ingress mappings and local storage. | Prove only one named Colima profile is running and all three nodes become Ready after CNI installation. |
| 65 | Exercise labels, node affinity, taints/tolerations and a DaemonSet in the learning namespace. | Create an unschedulable Pod, explain the scheduler event and repair only the intended constraint. |
| 66 | Prove API replica spreading with placement output, then tighten one constraint experimentally. | Remove capacity and compare ScheduleAnyway with hard scheduling behavior; restore the baseline. |
| 67 | Cordon, drain and uncordon a worker while observing PDBs and volume affinity. | Diagnose a blocked drain without disabling eviction checks or deleting data; record the limitation. |
| 68 | Stop one selected Kind worker container after inventorying ingress/database placement; measure clients and rescheduling. | Start that exact container, uncordon if needed and verify recovery. Separate API process availability from end-to-end availability. |
| 69 | Bootstrap the GitOps platform on Kind and rerun policy, TLS, smoke and telemetry checks. | Use an unauthorized Pod to prove Calico enforcement; compare with the intentionally non-enforcing CI topology. |
| 70 | Perform a timed rebuild from Git plus external secret/backup material. | Document K3s/Kind differences, node-local limitations and Week 10 review. |

Gate: portability and policy enforcement are proven; worker-loss availability claims identify ingress/database dependencies honestly.

## Week 11 — Progressive delivery, performance and incidents

| Day | Build / observable outcome | Break, recover, and commit proof |
| --- | --- | --- |
| 71 | Inspect Argo Rollouts and initialize a stable staging revision. | Distinguish first initialization from a real canary update; record the stable digest and candidate mechanism. |
| 72 | Run traffic through staging ingress while a new version takes 10/25/50/100% steps. | Remove candidate traffic and verify analysis does not falsely pass; restore traffic and inspect sample counts. |
| 73 | Promote a bounded latency/error regression and prove automatic abort before 100%. | Verify stable traffic recovery, then Git-revert the candidate config; save namespace/hash-scoped AnalysisRun results. |
| 74 | Run ramp, spike and soak profiles with a fixed workload; find the sustained saturation knee. | Distinguish generator dropped iterations from service saturation; repeat a misleading run with adequate generator capacity. |
| 75 | Tune one factor at a time: worker/API replicas, CPU settings or pool sizes; compare to Week 4. | Revert one unhelpful change; commit before/after measurements including backlog drain, not only API latency. |
| 76 | Run pod-kill, worker-loss, DNS-denial, DB-restart, bad-secret and bad-image cards one at a time. | Recover and verify client+queue behavior after each; never overlap faults unintentionally. |
| 77 | Write a capacity report, SLO/error-budget report and postmortem with measured MTTR. | Reproduce the prevention test from the postmortem and submit Week 11 review. |

Gate: regression is rejected by candidate-scoped analysis, and tuning/recovery claims have dated measurements.

## Week 12 — Capstone and portfolio

| Day | Build / observable outcome | Break, recover, and commit proof |
| --- | --- | --- |
| 78 | Rebuild a fresh three-node platform from Git and external recovery material; target <45 minutes. | Record every manual intervention and fix the runbook; rerun the failing step from a clean state. |
| 79 | Deliver a Go change through PR checks, GHCR, dev digest review and Argo deployment. | Trace one wrong-SHA hypothesis and prove the actually deployed digest using registry and Kubernetes evidence. |
| 80 | Promote the tested digest to staging and demonstrate both good canary progression and a failed candidate abort. | Recover the failed configuration with Git only; preserve analysis and routing evidence. |
| 81 | Sustain 50 accepted submissions/s for 10 minutes, ≥99.5% acceptance, p95 <300ms and no generator drops. | Inspect/drain the backlog; if the target fails, report the measured boundary and test one improvement rather than inventing success. |
| 82 | Restore PostgreSQL into a new namespace, verify known IDs/results and create new successful work. | Confirm an existing namespace/corrupt archive cannot be used destructively; record RPO/RTO and archive checksum. |
| 83 | Have a mentor select a blind fault; capture impact, timeline, hypotheses, recovery and prevention. | Run the prevention test and measure MTTR from first symptom to verified service recovery. |
| 84 | Finish README, architecture/ADRs, dashboards, runbooks, reports and a five-minute demo. | Ask another engineer to follow the instructions unaided; fix their first ambiguity and submit the final acceptance review. |

Gate: another engineer can reproduce the platform, verify it, deliver a change and operate an incident. Use [acceptance.md](acceptance.md); leave unproven items unchecked.
