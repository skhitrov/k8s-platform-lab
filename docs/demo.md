# Five-minute portfolio demo

Preflight outside the five minutes: healthy platform, a real recent CI/release/promotion, known completed job, saved restore/canary evidence, working port-forwards, and sanitized tabs. Do not imply a ten-minute load run or full rebuild happened inside this demo.

1. **0:00–0:45 — Boundary and architecture.** Show one VM/three nodes, API/queue/workers, ingress and observability. State PostgreSQL/local-path/ingress-node limitations immediately.
2. **0:45–1:45 — Delivery identity.** Show a reviewed PR, passing hosted `verify`, both GHCR platforms, SBOM/provenance and the same digest in dev and its approved staging promotion. Show Argo Synced/Healthy, with no CI cluster credential.
3. **1:45–2:45 — One job across signals.** Submit a job, show success, the request ID, correlated log/trace and relevant latency/queue panel. Explain 202 latency versus completion latency.
4. **2:45–3:45 — Failed candidate.** Show the captured candidate hash, weighted step, failed AnalysisRun and stable recovery. Show the Git revert that repaired desired state; do not fake a new live abort if its measurements are not ready.
5. **3:45–4:30 — Recovery proof.** Show a checksum-identified archive and the same known job in a fresh restored namespace. State measured RPO/RTO and where the off-VM copy is protected, without exposing it.
6. **4:30–5:00 — Evidence and limits.** Show capacity/MTTR/rebuild reports, one rejected optimization and a prevention test. End with one concrete remaining limitation and next experiment.

If a prerequisite is unproven, say so and show the implemented test/runbook as pending, not a successful demonstration.
