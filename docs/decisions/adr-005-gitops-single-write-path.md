# 5. GitOps is the single write path to the cluster

Date: 2026-10-10

## Status

Proposed — records existing practice, pending review.

## Context

The cluster is Flux-managed from this repository (Kustomize rendering,
SOPS-encrypted secrets, Clustertool-generated bootstrap). This repo is the
authoritative source for the homelab (ADR-002), and disaster recovery
assumes a rebuilt cluster from repo + backups equals the running cluster
(DISASTER-RECOVERY.md). Imperative changes applied to the live cluster
(kubectl apply, helm install) would create state that exists nowhere in
the repository: invisible to recovery, to audits, and to any future
migration (ADR-001).

Related but distinct decisions: ADR-004 (dedicated NVMe pool for etcd
I/O isolation) concerns hardware topology; this ADR concerns the write
path.

Scope: this ADR governs the Kubernetes API surface only. The hypervisor
layer below it (TrueNAS VM configuration, zvol placement, pool and
dataset topology) is imperative by nature and is governed by the
runbooks' recorded-reference policy, not by GitOps. The DR claim
"rebuild from repo + backups reproduces the cluster" therefore covers
the cluster; the hypervisor layer is reproduced from runbook records.

Two Flux behaviors shape what imperative changes can achieve:

- Objects Flux owns are reverted to git state at the next reconcile
  interval (or merely logged under warn-mode drift detection).
  Imperative edits to managed objects do not persist — and do not
  need to.
- Objects Flux does not own produce no drift signal at all: sync
  status stays green while unmanaged state diverges. Checking sync
  state does not detect the drift this ADR cares about.

## Decision

- All persistent changes to the cluster go through commits to this
  repository; Flux is the only applier. "Persistent" means any change
  intended to outlive the incident or session that produced it.
- Cluster bootstrap (initial Clustertool/Flux bootstrap, full rebuilds
  per DISASTER-RECOVERY.md) is imperative by definition and is the one
  sanctioned bulk apply outside day-to-day GitOps.
- Imperative access (kubectl, helm) remains allowed for:
  - read-only operations (get, describe, logs, top),
  - emergency mitigation, held via `flux suspend` on the affected
    Kustomization/HelmRelease rather than imperative edits that the
    next reconcile would revert (`flux resume` ends the hold),
  - one-off maintenance operations.
- Emergency and one-off changes follow the same rule at different
  urgency: both must be reconciled into the repository afterwards.
  A change that cannot be expressed in the repo must not be made
  persistent.
- Enforcement is tooling, not discipline (per ADR-002), in two steps:
  - a Kyverno admission policy denying create/update on objects
    without Flux's managed-by label, with carve-outs for kube-system,
    the CNI, and Kyverno itself;
  - CI-side `kustomize build` validation plus `flux diff` against a
    read-only kubeconfig for drift on Flux-owned objects.
  Until both are deployed, suspended Kustomizations must be listed
  (`flux get ks`) as part of routine review; until then the gap is
  known and accepted, not covered by sync-status checks.

## Consequences

- Every persistent change is auditable, revertable, and present in a
  fresh bootstrap (cluster scope; hypervisor layer via runbook
  records).
- No hidden state within the Kubernetes API surface.
- Quick fixes are slower (commit, then reconcile). This friction is
  deliberate.
- Imperative edits to Flux-owned objects are futile past the next
  reconcile; `flux suspend` is the sanctioned way to hold state, at
  the cost of an explicit resume obligation.
- Unmanaged-object drift stays invisible until the Kyverno policy and
  `flux diff` CI are actually deployed.
- Commits are currently not pre-validated for manifest correctness
  (gitleaks CI covers secrets, not manifests — known gap, closed by
  the CI step above).
