# Raw-manifest exercises

These files are learning material, not an alternative deployment source. The canonical workload is `deploy/chart/taskflow`; GitOps never applies this directory. Use only `taskflow-learning` for raw experiments and preserve dev/staging.

The first Pod runs the image's `version` command to learn termination/status without requiring a database. First build/load the local image into the selected cluster. On Kind:

```bash
docker --context colima-kind-lab build --tag taskflow:dev .
env DOCKER_CONTEXT=colima-kind-lab kind load docker-image taskflow:dev --name sre-lab
kubectl --context kind-sre-lab apply -f labs/raw/namespace.yaml
kubectl --context kind-sre-lab apply -f labs/raw/first-pod.yaml
kubectl --context kind-sre-lab --namespace taskflow-learning logs taskflow-version
kubectl --context kind-sre-lab --namespace taskflow-learning get pod taskflow-version -o wide
```

For K3s, use its named Docker context and the image-import behavior documented in `scripts/deploy-local.sh` when its node runtime is containerd; do not assume a Docker build is automatically visible to Kubernetes.

For the Week 2 API exercises, provision an isolated Taskflow learning release with local values, then derive one raw API Deployment/Service/ConfigMap at a time from `helm template`. Use a distinct release name and inspect selectors before applying. Keep a supporting PostgreSQL fixture; the real API deliberately requires a database for readiness. Stop managing a resource through Helm before making a raw exercise its owner. Do not copy plaintext Secrets into raw YAML.

The RBAC example grants only Pod reads to a dedicated observer; apply it, then prove Secret reads and Pod writes are denied. Network and workload faults are listed in [failure-cards.md](failure-cards.md). Save your own superseded manifests and sanitized evidence as you progress, rather than copying a completed gate claim.
