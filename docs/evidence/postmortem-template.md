# Incident <ID> — <DATE UTC>

Status: EXERCISE TEMPLATE, NOT AN OBSERVED INCIDENT.

Impact: affected users/environment/endpoints/jobs, availability/latency, data loss or none proven. State the exact measurement boundary.

Detection: first client symptom, alert/log/trace, missing signals. Recovery: first verified successful client request and completed job, stable observations, remaining degraded dependencies. MTTR uses those timestamps, not when a restart command was entered.

| UTC time | Evidence / action | Result / next hypothesis |
| --- | --- | --- |
| Not recorded | | |

Root cause: causal chain from change/failure to user impact; contributing conditions; why safeguards did/did not work. Distinguish triggers from causes.

Recovery steps and risks; proof source data/known jobs remain intact; desired-state restoration; what helped/hurt diagnosis; one owned prevention action with a repeatable test and due date. Link the fixing PR and rerun evidence. Avoid blame and unsupported HA/SLO claims.
