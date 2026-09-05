# Security, secrets, TLS and network isolation

App Pods run as non-root with a read-only root filesystem, dropped capabilities, no privilege escalation, `RuntimeDefault` seccomp and no Kubernetes API token. PostgreSQL's Alpine image uses UID/GID 70, not 999; writable data and temporary paths are explicit volumes. Restricted Pod Security applies only to app namespaces; privileged infrastructure such as Calico is a reviewed platform exception.

`create-lab-secrets.sh` generates a random password only when the named Secret is absent. Rerunning bootstrap must **not** change it while the existing PostgreSQL PVC retains its original password. Neither password nor connection URL is printed. Grafana uses a separately generated existing Secret. Compose's `taskflow` password is local-only public fixture data, not a cluster credential.

## Sealing and rotation

Install Sealed Secrets first. Seal only the database Secret, strictly bound to its existing name and namespace:

```bash
bash scripts/seal-db-secret.sh kind-sre-lab dev
```

The script marks only the existing database Secret for managed/patch adoption, seals it in memory, and writes only ciphertext into `sealedSecret.encryptedPassword` in dev values. Review the rendered name/namespace and merge. Do not insert `tee` before `kubeseal`. Never commit a sealing private key; export/backup it directly to an encrypted external store under a separately reviewed procedure.

Database password rotation is coordinated maintenance, **not** deleting the Secret and rerunning bootstrap: take a backup; securely generate/store a new password; change the PostgreSQL role password and matching Secret/sealed ciphertext; restart API and workers; verify readiness and a completed job; retain rollback material until verified. The cluster Secret, database role and Git ciphertext must agree. Avoid command-line password arguments, shell history and logged SQL literals.

## Lab TLS

The platform creates a self-signed root CA and `taskflow-lab-ca` ClusterIssuer. In dev/staging values enable `ingress.tls.enabled` and set `ingress.annotations.cert-manager.io/cluster-issuer: taskflow-lab-ca`. Commit via PR when GitOps owns the release. Inspect the Certificate's Ready condition. Export the **public CA certificate only** for client validation:

```bash
kubectl --context kind-sre-lab --namespace cert-manager get secret taskflow-lab-ca -o jsonpath='{.data.ca\.crt}' | base64 --decode > /private/tmp/taskflow-lab-ca.crt
curl --fail --cacert /private/tmp/taskflow-lab-ca.crt --resolve taskflow.localhost:8443:127.0.0.1 https://taskflow.localhost:8443/health/ready
```

Trust this CA only for the disposable lab. Do not globally install it without understanding the trust expansion. Do not export `tls.key` or use `curl -k` as TLS acceptance evidence.

## Policy verification

Check that Calico is healthy, then run the policy test:

```bash
bash scripts/test-network-policy.sh kind-sre-lab taskflow-dev
kubectl --context kind-sre-lab --namespace taskflow-dev auth can-i get secrets --as=system:serviceaccount:taskflow-dev:taskflow-taskflow
```

The expected RBAC answer is `no`. The policy test contrasts an allowed app-labelled Pod with an unauthorized Pod in the same namespace; both resolve DNS, only the allowed Pod reaches PostgreSQL. It also checks the API's ready endpoint from an ingress-namespace probe. Passing YAML validation or using the CI-only default Kind CNI is not proof of enforcement.

Security gate failures: investigate; update to a fixed dependency/image; rerun tests and scans. Do not globally ignore a rule to pass CI. Negative fixtures are generated outside Git, redacted, and discarded after proving rejection.
