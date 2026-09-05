# GitHub publication, GitOps, promotion and rollback

## Repository prerequisites

Use the public `skhitrov/k8s-platform-lab` repository and public GHCR package `ghcr.io/skhitrov/k8s-platform-lab/taskflow`. Authenticate interactively with `gh auth login --hostname github.com`; never paste tokens into a command, file or chat. Initial publication must precede branch protection because there is no base branch for the first PR.

After initial CI succeeds, `bash scripts/configure-github.sh` enables Actions/PR creation, enforces action SHA pins, and protects `main` with required `verify` checks, up-to-date branches, resolved conversations and one approving review. Admin bypass, deletion and force pushes are disabled. Workflow permissions remain explicitly scoped in YAML. CODEOWNERS assigns platform and delivery changes to `skhitrov` but a code-owner-only approval is not required: a solo author cannot approve their own PR, so use a mentor/reviewer instead of silently weakening the rule. Dependabot changes to action SHAs must also update `.github/action-pins.json`.

Never attach a self-hosted runner to this public repository. The CI job uses only GitHub-hosted `ubuntu-24.04`, and release accepts only a successful **push-to-main** CI run from this repository. It checks out the exact tested SHA. Release skips docs/values-only commits to prevent an image-update loop.

## First release and adoption

1. Merge the application implementation after CI passes. Watch `CI`, then `Release` with `gh run list --repo skhitrov/k8s-platform-lab`.
2. Make the new GHCR package public in package settings; anonymous cluster pulls must work. Release verifies both architectures, SBOM and signed provenance from the registry.
3. Review and merge `automation/dev-image`. Verify its digest and source SHA match the successful Release run. CI is explicitly dispatched on automation branches; review any GitHub approval-required run instead of assuming a bot PR has passed.
4. Pull `main` locally and bootstrap. Initially the ApplicationSet enrolls **only dev**; no empty staging digest is deployed.

```bash
git pull --ff-only origin main
make bootstrap-gitops CONTEXT=kind-sre-lab
kubectl --context kind-sre-lab --namespace argocd get applications
kubectl --context kind-sre-lab --namespace argocd port-forward service/argocd-server 18081:443
```

Use the locally forwarded Argo UI; obtain its bootstrap admin credential privately from the cluster, rotate it, and do not commit it. Argo's self-signed UI certificate is separate from the application lab CA.

5. Verify dev smoke/load against that exact digest, then open and review the promotion PR with its evidence. The first promotion adds staging to the ApplicationSet as well as copying its image digest; later promotions only change the digest. This avoids a bootstrap dependency on an untested staging release.

If adopting a namespace previously deployed with local Helm values, inspect existing objects/PVCs first. Take a backup. Argo renders the same release name `taskflow`; it becomes the desired-state owner. Do not continue Helm upgrades in that namespace once GitOps is active.

## Normal promotion

Trigger “Promote to staging” on `main` and supply a committed evidence path or URL identifying the dev digest. The workflow opens a PR; it does not deploy directly, approve itself or rebuild an image. The human reviewer checks that the evidence and PR digest agree. Merging changes staging's desired state; Argo Rollouts controls traffic and candidate analysis.

GitOps does not guarantee that a commit was reviewed unless repository protection is actually configured. Nor does a supplied evidence string prove a test happened; it is a required review input, not automatic measurement.

## Drift and recovery

For an isolated drift exercise, change a harmless live label in `taskflow-dev`, record its previous value, and observe Argo self-heal. Do not modify Secrets or delete PVCs. For a broken release, capture Application conditions/events and Rollout/AnalysisRun status, then open a **Git revert PR** restoring the last good digest/configuration. A manual `kubectl set image` is temporary drift and will be undone.

If root sync stalls, inspect the lowest unfinished wave: controller/CRD, backend, collector, config or workload. `ServerSideApply=true` handles large CRDs. Required CRDs and the migration must become ready before dependent custom resources and application Pods can succeed.

Sources: [Argo automated sync](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/), [multiple sources](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/), [GitHub workflow triggering](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow), [runner security](https://docs.github.com/en/actions/reference/security/secure-use), [Docker SBOM attestations](https://docs.docker.com/build/metadata/attestations/sbom/).
