# Cluster lifecycle and reconstruction

Preflight: save evidence/dumps outside the VM, check free disk and `make doctor`, stop Compose if it occupies port 8080, and verify the context on every command. Never delete a profile or cluster just to rerun bootstrap. Both scripts preserve existing clusters and secrets.

```bash
colima list
docker context ls
kubectl config get-contexts
make bootstrap-kind
kubectl --context kind-sre-lab get nodes -o wide
kubectl --context kind-sre-lab get pods --all-namespaces
kubectl --context kind-sre-lab get storageclass
kubectl --context kind-sre-lab top nodes
```

The expected Kind topology is one control-plane and two workers, Calico VXLAN with BGP disabled, and the default Kind local-path provisioner. Node readiness is checked **after** Calico installation. Waiting for node readiness before installing a deliberately external CNI deadlocks bootstrap.

Bootstrap also raises `fs.inotify.max_user_instances` to 1024 inside **only** `kind-lab`: the VM's default 128 instances are shared across node containers and can prevent an additional CI-test node from starting. No macOS/default-profile kernel setting is changed. If startup still fails, inspect retained node logs and real memory/disk pressure instead of assuming the same cause. See [Kind's known issues](https://kind.sigs.k8s.io/docs/user/known-issues/).

For K3s use `make bootstrap-k3s`; it stops `kind-lab`, starts only the named K3s profile, disables Traefik, and installs the pinned ingress chart. For the full published platform, follow GitOps prerequisites, then:

```bash
make bootstrap-gitops CONTEXT=kind-sre-lab
kubectl --context kind-sre-lab --namespace argocd get applications
```

Before GitOps, install individual Week 3/6/9 add-ons with `bash scripts/install-addon.sh kind-sre-lab cert-manager` (or `sealed-secrets`, `argo-rollouts`, `kube-prometheus-stack`, `loki`, `tempo`, `alloy`, `opentelemetry-collector`). The helper uses the same locked archives/values as Argo and refuses to overwrite an existing Argo-owned Application. Install controllers before their custom resources; install telemetry backends before collectors. After the required CRDs exist, apply `platform/config` to provision namespaces, TLS issuers, dashboard and alert rules. Do not run that manual path once GitOps owns it.

Timed rebuild: start a timer before bootstrap, restore external secrets/sealing material as needed, wait for all child Applications to be Healthy/Synced, test TLS, submit a job and verify completion, exercise a denied network request, and stop the timer. Record failures and timings in the weekly template; the target is under 45 minutes, not a claimed result.

To pause without removing disks or clusters:

```bash
colima stop kind-lab
```

Only delete `sre-lab` after explicitly deciding its PVC data can be discarded and verifying an off-VM backup. The destructive command is intentionally not part of bootstrap or the daily quick start.

## Scheduling exercise

```bash
kubectl --context kind-sre-lab --namespace taskflow-dev get pods -o wide
kubectl --context kind-sre-lab --namespace taskflow-dev get pdb
kubectl --context kind-sre-lab cordon sre-lab-worker2
kubectl --context kind-sre-lab drain sre-lab-worker2 --ignore-daemonsets --timeout=2m
kubectl --context kind-sre-lab uncordon sre-lab-worker2
```

Do not add `--force`, `--disable-eviction`, or `--delete-emptydir-data` to make a blocked drain pass. Inspect the PDB, local volumes, unmanaged Pods and available capacity; a blocked eviction is valid evidence. Local database storage can pin recovery to one node. Use the failure cards for a controlled container-stop experiment and restore the exact stopped node afterward.
