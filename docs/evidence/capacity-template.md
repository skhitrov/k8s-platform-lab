# Capacity report — <DATE UTC>

Status: NOT YET MEASURED.

## Reproduction

Commit/digest; machine/architecture; Colima CPU/RAM; node topology; environment; ingress vs port-forward; replicas/HPA; requests/limits; DB pools; PostgreSQL settings; k6 profile/work units; background load; exact command; run start/end UTC; raw sanitized result path.

| Measurement | Baseline | Single change | Observation |
| --- | --- | --- | --- |
| Offered / accepted RPS | Not measured | Not measured | |
| 202 acceptance / HTTP failure rate | Not measured | Not measured | |
| Submission p50 / p95 / p99 | Not measured | Not measured | |
| Dropped generator iterations | Not measured | Not measured | |
| Worker completion rate / duration | Not measured | Not measured | |
| Queue peak depth / oldest age / drain time | Not measured | Not measured | |
| CPU usage / throttling / memory / OOM | Not measured | Not measured | |
| DB connections / pool acquisition delay | Not measured | Not measured | |

Saturation knee and evidence; limiting component; rejected alternative hypotheses; why the chosen change helped/hurt; repeatability/variance; remaining capacity/headroom; limits of extrapolation.

Acceptance result: 50 submissions/s for 10 minutes, ≥99.5% valid acceptance, p95 <300ms, no dropped iterations, followed by queue-drain/terminal-state verification. Mark PASS only with the actual run and backlog evidence. A failed target is a useful result, not a reason to omit the report.
