#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: bash scripts/deploy-local.sh <colima-k3s-lab|kind-sre-lab>" >&2; exit 2
fi
kube_context="$1"
case "${kube_context}" in
  colima-k3s-lab) docker_context=colima-k3s-lab ;;
  kind-sre-lab) docker_context=colima-kind-lab ;;
  *) echo "Use one of the two named lab contexts." >&2; exit 2 ;;
esac
image_tag="local-$(date -u +%Y%m%d%H%M%S)"
image="taskflow:${image_tag}"
docker --context "${docker_context}" build --tag "${image}" --build-arg "VERSION=${image_tag}" .
if [ "${kube_context}" = kind-sre-lab ]; then
  DOCKER_CONTEXT="${docker_context}" kind load docker-image "${image}" --name sre-lab
else
  runtime="$(kubectl --context "${kube_context}" get nodes -o jsonpath='{.items[0].status.nodeInfo.containerRuntimeVersion}')"
  if [[ "${runtime}" == containerd:* ]]; then
    docker --context "${docker_context}" save "${image}" \
      | colima --profile k3s-lab ssh -- sudo k3s ctr images import -
  fi
fi
bash scripts/create-lab-secrets.sh "${kube_context}" taskflow-dev
helm upgrade --install taskflow deploy/chart/taskflow \
  --kube-context "${kube_context}" --namespace taskflow-dev \
  --values deploy/chart/taskflow/values-local.yaml --set-string "image.tag=${image_tag}" \
  --wait --wait-for-jobs --timeout 6m
