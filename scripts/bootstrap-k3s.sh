#!/usr/bin/env bash
set -euo pipefail

if colima status kind-lab >/dev/null 2>&1; then
  colima stop kind-lab
fi
colima start k3s-lab \
  --cpu 4 \
  --memory 8 \
  --disk 60 \
  --runtime docker \
  --activate=false \
  --kubernetes \
  --k3s-arg=--disable=traefik \
  --kubernetes-version "$(yq -r '.k3s.version' platform/versions.yaml)"

kubectl --context colima-k3s-lab wait --for=condition=Ready node --all --timeout=180s

helm upgrade --install ingress-nginx "$(bash scripts/fetch-chart.sh ingress-nginx)" \
  --kube-context colima-k3s-lab \
  --namespace ingress-nginx \
  --create-namespace \
  --values platform/k3s/ingress-values.yaml \
  --wait --timeout 5m

bash scripts/create-lab-secrets.sh colima-k3s-lab taskflow-dev
bash scripts/create-lab-secrets.sh colima-k3s-lab taskflow-staging

echo "K3s cluster is ready. Next: make deploy-local CONTEXT=colima-k3s-lab"
echo "GitOps bootstrap is a separate Week 8 step: make bootstrap-gitops CONTEXT=colima-k3s-lab"
