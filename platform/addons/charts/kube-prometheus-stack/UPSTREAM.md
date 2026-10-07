# Upstream and local patch

This directory contains the complete packaged kube-prometheus-stack chart
89.2.2, including its packaged dependencies. The source archive is:

    https://github.com/prometheus-community/helm-charts/releases/download/
    kube-prometheus-stack-89.2.2/kube-prometheus-stack-89.2.2.tgz

SHA-256 of that archive:

    05483f2ca0b047880e39869927ed7d313a365e7cd030e8fa782a755e44514d8f

Chart metadata declares Apache-2.0. The upstream license text is in
`LICENSE`.

Two upstream admission Job templates have one local change: their Helm hook
delete policy is `before-hook-creation` only. This keeps successful Job
objects available for Argo CD hook tracking until a later sync replaces them.
The Helm hook phases, chart version, dependencies, and other chart files are
unchanged.

Changed templates:

- `templates/prometheus-operator/admission-webhooks/job-patch/`
  `job-createSecret.yaml`
- `templates/prometheus-operator/admission-webhooks/job-patch/`
  `job-patchWebhook.yaml`
