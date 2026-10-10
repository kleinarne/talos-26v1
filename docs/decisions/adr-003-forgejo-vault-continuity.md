# 3. Forgejo (PKM vault) continuity is a hard migration requirement

Date: 2026-10-10

## Status

Accepted

## Context

The PKM architecture (locked 2026-10-04) makes Forgejo on the fluxcd-managed
cluster the single source of truth for the vault repo. Any cluster migration
that does not guarantee Forgejo continuity destroys the PKM's source of
truth. PKM sync/credentials are already required to be segmented from the
cluster's production git-ops credentials.

## Decision

- Every migration option evaluated in ADR-001 must treat re-provisioning
  Forgejo (with the vault repo) as a hard, blocking requirement — before
  or with the cluster cutover, never "later".
- The vault repo must additionally have an offline, encrypted copy
  (git bundle on external media) taken on a schedule, so vault recovery
  does not depend on the cluster surviving. This respects the "no cloud"
  rule: offline media is not a cloud service. **[FILL IN: schedule and
  media]**
- The migration plan must include a tested Forgejo restore (repo + access)
  before the old cluster is decommissioned.

## Consequences

- Migration sequencing is constrained: Forgejo stands up early, on whatever
  the new platform is.
- Vault data has a recovery path independent of cluster health (offline
  bundle), at the cost of a manual, scheduled backup step.
- Decommissioning the old environment requires a sign-off item: "vault
  restored and verified on new platform".