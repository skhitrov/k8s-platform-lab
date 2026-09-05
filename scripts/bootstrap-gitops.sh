#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: bash scripts/bootstrap-gitops.sh <colima-k3s-lab|kind-sre-lab>" >&2
  exit 2
fi
kube_context="$1"
case "${kube_context}" in
  colima-k3s-lab|kind-sre-lab) ;;
  *) echo "This bootstrap is scoped to the two named lab clusters." >&2; exit 2 ;;
esac
# First complete the dev release PR. The first tested promotion enrolls staging.
while IFS= read -r environment; do
  image_digest="$(yq -r '.image.digest' "deploy/chart/taskflow/values-${environment}.yaml")"
  if ! [[ "${image_digest}" =~ ^sha256:[a-f0-9]{64}$ ]]; then
    echo "${environment} has no published digest. Follow docs/runbooks/gitops.md first." >&2
    exit 1
  fi
done < <(yq -r '.spec.generators[0].list.elements[].environment' platform/gitops/taskflow-applicationset.yaml)
git ls-remote --exit-code https://github.com/skhitrov/k8s-platform-lab.git refs/heads/main >/dev/null
bash scripts/create-lab-secrets.sh "${kube_context}" taskflow-dev
bash scripts/create-lab-secrets.sh "${kube_context}" taskflow-staging
bash scripts/create-platform-secrets.sh "${kube_context}"

bash scripts/render.sh
kubectl --context "${kube_context}" apply --server-side -f .cache/rendered/upstream/argocd.yaml
kubectl --context "${kube_context}" --namespace argocd rollout status deployment/argocd-server --timeout=5m
kubectl --context "${kube_context}" --namespace argocd rollout status statefulset/argocd-application-controller --timeout=5m
kubectl --context "${kube_context}" apply -f platform/gitops/projects.yaml
kubectl --context "${kube_context}" apply -f platform/bootstrap/root-application.yaml
echo "Argo CD is reconciling platform dependencies from Git. Inspect Applications in the argocd namespace."
