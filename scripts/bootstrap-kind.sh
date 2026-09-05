#!/usr/bin/env bash
set -euo pipefail

if colima status k3s-lab >/dev/null 2>&1; then
  colima stop k3s-lab
fi
colima start kind-lab --cpu 4 --memory 8 --disk 60 --runtime docker --activate=false
# These limits are shared by containers in this VM, not namespaced per Kind node.
colima --profile kind-lab ssh -- sudo sysctl -w fs.inotify.max_user_instances=1024
export DOCKER_CONTEXT=colima-kind-lab

if ! kind get clusters | rg -qx sre-lab; then
  kind create cluster \
    --name sre-lab \
    --config platform/kind/cluster.yaml \
    --image "$(yq -r '.kind.nodeImage' platform/versions.yaml)"
fi
kubectl --context kind-sre-lab apply --server-side -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/operator-crds.yaml
kubectl --context kind-sre-lab apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/tigera-operator.yaml
kubectl --context kind-sre-lab apply -f platform/kind/calico-installation.yaml
kubectl --context kind-sre-lab wait --for=condition=Ready nodes --all --timeout=8m
# Kind already provides its own default local-path StorageClass.
helm upgrade --install ingress-nginx "$(bash scripts/fetch-chart.sh ingress-nginx)" \
  --kube-context kind-sre-lab \
  --namespace ingress-nginx \
  --create-namespace \
  --values platform/kind/ingress-values.yaml \
  --wait --timeout 5m
helm upgrade --install metrics-server "$(bash scripts/fetch-chart.sh metrics-server)" \
  --kube-context kind-sre-lab --namespace kube-system \
  --values platform/kind/metrics-server-values.yaml --wait --timeout 5m

bash scripts/create-lab-secrets.sh kind-sre-lab taskflow-dev
bash scripts/create-lab-secrets.sh kind-sre-lab taskflow-staging

echo "Kind cluster is ready. Next: make deploy-local CONTEXT=kind-sre-lab"
echo "GitOps bootstrap is a separate Week 8 step: make bootstrap-gitops CONTEXT=kind-sre-lab"
