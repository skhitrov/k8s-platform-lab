#!/usr/bin/env bash
set -euo pipefail

bash scripts/render.sh
python3 scripts/check-repository.py
mkdir -p .cache/reports .cache/kubeconform
kubeconform -strict -summary -kubernetes-version 1.36.3 -cache .cache/kubeconform \
  -schema-location default \
  -schema-location '.cache/schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  .cache/rendered/first-party .cache/rendered/upstream \
  | tee .cache/reports/kubeconform.txt

actionlint
shellcheck scripts/*.sh
for script in scripts/*.sh; do bash -n "${script}"; done

# Scan Git-visible source, including unstaged/untracked work, without generated
# credentials or reports. History is independently scanned when a commit exists.
source_directory="$(mktemp -d)"
trap 'rm -rf "${source_directory}"' EXIT
git ls-files --cached --others --exclude-standard -z | tar --null -T - -cf - \
  | tar -xf - -C "${source_directory}"
gitleaks dir "${source_directory}" --no-banner --redact --report-format json \
  --report-path .cache/reports/gitleaks-source.json
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  gitleaks git . --no-banner --redact --report-format json --report-path .cache/reports/gitleaks-history.json
fi
trivy config --exit-code 1 --severity HIGH,CRITICAL \
  --format table --output .cache/reports/trivy-config.txt \
  .cache/rendered/first-party || { cat .cache/reports/trivy-config.txt; exit 1; }
trivy config --exit-code 1 --severity HIGH,CRITICAL Dockerfile
govulncheck ./app/...
echo "Validation passed, including custom-resource schemas and vulnerability checks."
