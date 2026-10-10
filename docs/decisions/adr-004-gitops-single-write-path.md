# 4. GitOps is the single write path to the cluster

Date: 2026-10-10

## Status

Accepted (records existing practice)

## Context

The cluster is Flux-managed from this repository (Kustomize rendering,
SOPS-encrypted secrets, Clustertool-generated bootstrap). This repo is the
authoritative source for the homelab (ADR-002), and disaster recovery
assumes a rebuilt cluster from repo + backups equals the running cluster
(DISASTER-RECOVERY.md). Imperative changes applied to the live cluster
(kubectl apply, helm install) would create state that exists nowhere in
the repository: invisible to recovery, to audits, and to any future
migration (ADR-001).

## Decision

- All persistent state changes to the cluster go through commits to this
  repository; Flux is the only applier.
- Imperative access (kubectl, helm) remains allowed for:
  - read-only operations (get, describe, logs, top),
  - temporary emergency mitigation,
  - one-off maintenance operations.
- Any emergency or one-off change must be reconciled into the repository
  afterwards. A change that cannot be expressed in the repo must not be
  made persistent.

## Consequences

- Every persistent change is auditable, revertable, and present in a
  fresh bootstrap.
- No hidden state: rebuild from repo + backups reproduces the cluster.
- Quick fixes are slower (commit, then reconcile). This friction is
  deliberate.
- Emergency reconciliation requires follow-up discipline; residual drift
  should be surfaced by checking Flux sync state.
- Commits are currently not pre-validated (no dry-run / CI gate yet —
  known gap). Candidate improvement: CI-side `kustomize build` /
  `flux diff` validation.
