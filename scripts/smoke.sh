#!/usr/bin/env bash
set -euo pipefail

base_url="${1:-http://127.0.0.1:8080}"

curl --fail --silent --show-error "${base_url}/health/live" | jq -e '.status == "alive"' >/dev/null
curl --fail --silent --show-error "${base_url}/health/ready" | jq -e '.status == "ready"' >/dev/null

job_id="$(curl --fail --silent --show-error \
  --request POST \
  --header 'Content-Type: application/json' \
  --data '{"work_units":10000}' \
  "${base_url}/v1/jobs" | jq -er '.id')"

for _attempt in $(seq 1 60); do
  job_status="$(curl --fail --silent --show-error "${base_url}/v1/jobs/${job_id}" | jq -er '.status')"
  case "${job_status}" in
    succeeded)
      echo "Smoke test passed: job ${job_id} succeeded."
      printf 'SMOKE_JOB_ID=%s\n' "${job_id}"
      exit 0
      ;;
    failed)
      echo "Smoke test failed: job ${job_id} entered failed state."
      exit 1
      ;;
  esac
  sleep 1
done

echo "Smoke test timed out waiting for job ${job_id}."
exit 1
