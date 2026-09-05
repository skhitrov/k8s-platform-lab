import http from 'k6/http';
import { check } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

const baseURL = __ENV.BASE_URL || 'http://127.0.0.1:8080';
const submitted = new Counter('taskflow_jobs_submitted');
const submitDuration = new Trend('taskflow_submit_duration', true);
const accepted = new Rate('taskflow_acceptance');
const profile = __ENV.PROFILE || 'ramp';
const profiles = {
  smoke: { executor: 'constant-arrival-rate', rate: 5, timeUnit: '1s', duration: '30s', preAllocatedVUs: 5, maxVUs: 20 },
  acceptance: { executor: 'constant-arrival-rate', rate: 50, timeUnit: '1s', duration: '10m', preAllocatedVUs: 50, maxVUs: 150 },
  soak: { executor: 'constant-arrival-rate', rate: 25, timeUnit: '1s', duration: '30m', preAllocatedVUs: 25, maxVUs: 150 },
  spike: { executor: 'ramping-arrival-rate', startRate: 5, timeUnit: '1s', preAllocatedVUs: 50, maxVUs: 200,
    stages: [{ target: 5, duration: '30s' }, { target: 150, duration: '10s' }, { target: 150, duration: '1m' }, { target: 5, duration: '10s' }, { target: 5, duration: '1m' }] },
  ramp: { executor: 'ramping-arrival-rate', startRate: 5, timeUnit: '1s', preAllocatedVUs: 30, maxVUs: 150,
    stages: [{ target: 10, duration: '30s' }, { target: 25, duration: '30s' }, { target: 50, duration: '1m' }, { target: 100, duration: '1m' }, { target: 0, duration: '15s' }] },
};
if (!profiles[profile]) throw new Error(`Unknown profile: ${profile}`);

export const options = {
  scenarios: { [profile]: profiles[profile] },
  thresholds: {
    http_req_failed: ['rate<0.005'],
    taskflow_acceptance: ['rate>=0.995'],
    taskflow_submit_duration: ['p(95)<300'],
    dropped_iterations: ['count==0'],
  },
};

export default function () {
  const response = http.post(
    `${baseURL}/v1/jobs`,
    JSON.stringify({ work_units: Number(__ENV.WORK_UNITS || 25000) }),
    { headers: { 'Content-Type': 'application/json' }, timeout: '5s', tags: { name: 'POST /v1/jobs' } },
  );
  submitDuration.add(response.timings.duration);
  const ok = check(response, { 'job accepted': (result) => result.status === 202 });
  accepted.add(ok);
  if (ok) {
    submitted.add(1);
  }
}
