#!/usr/bin/env bash
set -euo pipefail

temporary_directory="$(mktemp -d)"
trap 'rm -rf "${temporary_directory}"' EXIT
mkdir -p .cache/reports

expect_rejection() {
  local fixture="$1"
  shift
  if "$@" > ".cache/reports/negative-${fixture}.txt" 2>&1; then
    echo "Validator unexpectedly accepted ${fixture}." >&2
    exit 1
  fi
  echo "Rejected ${fixture} as expected."
}

# Generated outside Git, avoiding allowlists in normal policy/secret scans.
printf '%s\n' 'apiVersion: v1' 'kind: Pod' 'metadata: {name: malformed}' \
  'spec: {containers: wrong-type}' > "${temporary_directory}/malformed.yaml"
expect_rejection malformed kubeconform -strict -kubernetes-version 1.36.3 \
  -cache .cache/kubeconform "${temporary_directory}/malformed.yaml"
rg -q 'Invalid|invalid' .cache/reports/negative-malformed.txt

printf '%s\n' 'apiVersion: v1' 'kind: Pod' 'metadata: {name: insecure}' \
  'spec:' '  containers:' '    - name: insecure' '      image: nginx:latest' \
  '      securityContext: {privileged: true, runAsUser: 0}' \
  > "${temporary_directory}/insecure.yaml"
expect_rejection privileged-pod trivy config --exit-code 1 --severity HIGH,CRITICAL \
  "${temporary_directory}/insecure.yaml"
rg -q 'AVD-KSV-0001|Privileged|privileged' .cache/reports/negative-privileged-pod.txt

# A nonfunctional secret-shaped fixture, assembled only in the temp tree.
fixture_suffix="$(openssl rand -hex 18)"
printf 'github_token = "%s%s"\n' 'ghp_' "${fixture_suffix}" \
  > "${temporary_directory}/fake-secret.txt"
expect_rejection fake-secret gitleaks dir "${temporary_directory}" --no-banner --redact
rg -q 'leaks found|leaks detected' .cache/reports/negative-fake-secret.txt

# Statically inspect a known-vulnerable call path; never execute the fixture.
mkdir -p "${temporary_directory}/vulnerable"
printf '%s\n' 'module example.invalid/negative-fixture' '' 'go 1.20' '' \
  'require golang.org/x/text v0.3.6' \
  > "${temporary_directory}/vulnerable/go.mod"
printf '%s\n' 'package fixture' 'import "golang.org/x/text/language"' \
  'func Parse(value string) { _, _ = language.Parse(value) }' > "${temporary_directory}/vulnerable/fixture.go"
go -C "${temporary_directory}/vulnerable" mod tidy
expect_rejection vulnerable-dependency govulncheck -C "${temporary_directory}/vulnerable" ./...
rg -q 'GO-[0-9]{4}-[0-9]+' .cache/reports/negative-vulnerable-dependency.txt
mkdir -p "${temporary_directory}/failing-test"
printf '%s\n' 'module example.invalid/failing-test' 'go 1.20' > "${temporary_directory}/failing-test/go.mod"
printf '%s\n' 'package fixture' 'import "testing"' \
  'func TestDeliberateFailure(t *testing.T) { t.Fatal("negative gate fixture") }' \
  > "${temporary_directory}/failing-test/fixture_test.go"
expect_rejection failing-test go -C "${temporary_directory}/failing-test" test ./...
rg -q 'FAIL.*TestDeliberateFailure' .cache/reports/negative-failing-test.txt
echo "Negative fixtures proved schema, policy, secret, and vulnerability gates are active."
