# Final acceptance — evidence required

This is a learner/capstone checklist, not a promise that the implementation session performed every exercise. Link dated evidence and exact source/image versions before checking an item.

- [ ] `make verify` passes locally and in hosted GitHub CI for the reviewed commit.
- [ ] CI rejects malformed manifests, privileged Pods, fake leaked credentials, a known vulnerable call path, failing Go tests and an unhealthy Kubernetes deployment.
- [ ] GHCR contains amd64/arm64 images, SBOM and verified provenance; dev/staging use immutable digests.
- [ ] Branch protection and required reviews/checks are configured and tested; no self-hosted runner or cluster credential is used by CI.
- [ ] App containers run non-root/read-only, without capabilities or unnecessary API tokens; no plaintext credentials or private sealing material appear in Git history.
- [ ] Default-deny networking blocks an unauthorized Pod while DNS, ingress, PostgreSQL, monitoring and OTLP work on an enforcing CNI.
- [ ] GitOps deploys only Git-approved state, corrects drift, and recovers a broken release via Git revert.
- [ ] Staging promotion copies an actually tested dev digest and requires review.
- [ ] API/worker scaling is observed; queued work survives worker replacement and drains afterward.
- [ ] Worker-node failure behavior is measured with ingress/database placement documented; single-instance PostgreSQL is not called HA.
- [ ] Logs, metrics and a propagated API→worker trace can diagnose a real injected failure; SLO alerts fire and resolve.
- [ ] A candidate regression aborts before full promotion using namespace/hash-scoped evidence; missing traffic cannot falsely pass.
- [ ] 50 requests/s for 10 minutes meets ≥99.5% acceptance and p95 <300ms with zero generator drops, plus job completion/drain verification.
- [ ] A backup restores a known job into a fresh namespace; archive checksum, RPO/RTO and external copy are recorded.
- [ ] A fresh three-node platform is reconstructed from Git and external recovery material; actual elapsed time is recorded against the 45-minute objective.
- [ ] Another engineer follows the README without hidden state; portfolio contains ADRs, runbooks, dashboards, measurements, postmortem and demo.
