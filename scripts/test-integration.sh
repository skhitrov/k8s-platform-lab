#!/usr/bin/env bash
set -euo pipefail

if [ -n "$(docker compose --file compose.test.yaml ps --all --quiet)" ]; then
  echo "The taskflow-integration project already exists; finish that test run first." >&2
  exit 1
fi
cleanup() {
  docker compose --file compose.test.yaml down --volumes >/dev/null
}
trap cleanup EXIT
docker compose --file compose.test.yaml up --detach --wait postgres

TEST_DATABASE_URL='postgres://taskflow:integration-only@127.0.0.1:15432/taskflow_test?sslmode=disable' \
  go test -race -count=1 ./app/internal/database/...
