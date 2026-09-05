SHELL := /bin/bash

IMAGE ?= taskflow:dev
VERSION ?= dev
COMMIT ?= local
BUILD_DATE ?= local
CONTEXT ?= colima-k3s-lab
PROFILE ?= ramp

.DEFAULT_GOAL := help

.PHONY: help doctor fmt fmt-check vet test test-integration build image compose-up compose-down \
	validate e2e smoke load bootstrap-k3s bootstrap-kind verify render test-validators deploy-local bootstrap-gitops

help: ## Show available targets.
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "%-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

doctor: ## Check the workstation without changing it.
	@bash scripts/doctor.sh

fmt: ## Format Go source files.
	@rg --files app -g '*.go' -0 | xargs -0 gofmt -w

fmt-check: ## Fail if Go source is not formatted.
	@unformatted="$$(rg --files app -g '*.go' -0 | xargs -0 gofmt -l)"; \
	if [ -n "$$unformatted" ]; then echo "Unformatted Go files:"; echo "$$unformatted"; exit 1; fi

vet: ## Run the Go static analyzer.
	@go vet ./app/...

test: ## Run unit tests with the race detector.
	@go test -race -coverprofile=coverage.out ./app/...

test-integration: ## Run PostgreSQL integration tests through Docker Compose.
	@bash scripts/test-integration.sh

build: ## Compile the local Taskflow binary.
	@mkdir -p bin
	@go build -trimpath -ldflags="-X main.version=$(VERSION) -X main.commit=$(COMMIT) -X main.date=$(BUILD_DATE)" -o bin/taskflow ./app/cmd/taskflow

image: ## Build the local Taskflow container image.
	@docker build --build-arg VERSION=$(VERSION) --build-arg COMMIT=$(COMMIT) --build-arg BUILD_DATE=$(BUILD_DATE) --tag $(IMAGE) .

compose-up: ## Start the local PostgreSQL, API, and worker stack.
	@docker compose up --build --detach --wait

compose-down: ## Stop the local stack without deleting its database volume.
	@docker compose down

render: ## Render all pinned releases and extract custom-resource schemas.
	@bash scripts/render.sh

validate: ## Validate schemas, workflows, shell, secrets, and vulnerabilities.
	@bash scripts/validate.sh

test-validators: ## Prove security and schema gates reject deliberately bad fixtures.
	@bash scripts/test-validators.sh

e2e: ## Build and test the chart in a disposable Kind cluster.
	@bash scripts/e2e-kind.sh

smoke: ## Smoke-test the local Compose endpoint.
	@bash scripts/smoke.sh http://127.0.0.1:8080

load: ## Run the stored k6 smoke and capacity profile against Compose.
	@k6 run --env BASE_URL=http://127.0.0.1:8080 --env PROFILE=$(PROFILE) tests/load/taskflow.js

bootstrap-k3s: ## Create and bootstrap the named Colima K3s lab.
	@bash scripts/bootstrap-k3s.sh

bootstrap-kind: ## Create and bootstrap the three-node Kind lab on Colima.
	@bash scripts/bootstrap-kind.sh

deploy-local: ## Build and deploy to CONTEXT before enabling GitOps.
	@bash scripts/deploy-local.sh $(CONTEXT)

bootstrap-gitops: ## Bootstrap GitOps after publication and the first digest PRs.
	@bash scripts/bootstrap-gitops.sh $(CONTEXT)

verify: fmt-check vet test validate ## Run the pre-commit quality gate.
