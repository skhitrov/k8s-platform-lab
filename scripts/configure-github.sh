#!/usr/bin/env bash
set -euo pipefail

# Run after the initial reviewed implementation is pushed and CI has succeeded.
# No self-hosted runner, cluster credential, PAT, or approval bypass is installed.
gh repo view skhitrov/k8s-platform-lab --json nameWithOwner,isPrivate
gh api --method PUT repos/skhitrov/k8s-platform-lab/actions/permissions \
  --field enabled=true --field allowed_actions=all --field sha_pinning_required=true
gh api --method PUT repos/skhitrov/k8s-platform-lab/actions/permissions/workflow \
  --field default_workflow_permissions=read --field can_approve_pull_request_reviews=true
gh api --method PUT repos/skhitrov/k8s-platform-lab/branches/main/protection \
  --input .github/branch-protection.json >/dev/null
echo "Protected main with required verify, one independent review, linear history, and no admin bypass."
