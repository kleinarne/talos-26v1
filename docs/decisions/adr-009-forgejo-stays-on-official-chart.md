# 9. Forgejo stays on the official Helm chart (the deliberate TrueCharts exception)

Date: 2026-11-14

## Status

Accepted

## Context

Nearly every chart on the cluster is TrueCharts; Forgejo is the one
deliberate exception, installed from the official Forgejo Helm chart.
Forgejo is also the PKM vault host (ADR-003) — one of the most critical
workloads on the cluster.

The restore-coverage audit (2026-11-12, DR-rehearsal abort) found that
Forgejo backs up (VolSync ReplicationSource) but has no restore path:
SQLite + git repos + the vault ride one restic bucket with no
ReplicationDestination. That gap made migrating Forgejo onto the
TrueCharts Gitea chart attractive — it would add the house-standard
backup tooling (VolSync + CNPG recovery) without rolling our own. The
option was evaluated 2026-11-14, with the mechanics verified
against the live TrueCharts chart and the Forgejo image.

## Decision

- Forgejo stays on the official Forgejo Helm chart. The TrueCharts Gitea
  chart is rejected as a wrapper; revisiting requires a new ADR
  superseding this one (ADR-006 supersession rule).
- The one-chart exception is a design choice, not drift.
- Forgejo's restore-path gap is closed on the current install
  (repo-managed paused ReplicationDestination, PR #460) — not by chart
  migration.
- A future SQLite→Postgres migration remains open as a standalone
  data-layer decision under the official chart, argued on its own
  merits (house DB standard, ADR-008) — never from wrapper convenience.

## Considered alternatives (rejected)

**TrueCharts Gitea chart running the Forgejo image.** Mechanically
viable today (verified 2026-11-14):

- The chart pins the stock upstream Gitea image (28.x-rootless);
  overriding image.repository/tag to
  codeberg.org/forgejo/forgejo:*-rootless is a standard common-library
  values change.
- The chart injects its own init scripts (mounted over /usr/sbin)
  calling `gitea migrate` and `gitea admin ...`; the Forgejo image ships
  its binary as /usr/local/bin/gitea (forgejo is the symlink) and keeps
  the GITEA_* env and layout conventions, so the chart automation runs
  unmodified.
- The chart unconditionally renders DB_TYPE = postgres against its
  CNPG dependency — the switch forces a one-time SQLite→Postgres
  conversion on the vault host (acceptable on its own merits, not
  decisive).

Rejected because:

1. **Unsupported combination.** TrueCharts supports its pinned Gitea
   image only; we would be off the support path for a TrueCharts chart
   while carrying its abstraction and maintenance cost.
2. **Hard-fork drift compounds.** The chart tracks Gitea 28.x while
   Forgejo stable is 16.x. Forgejo is a hard fork, so chart template and
   script changes may assume behavior Forgejo no longer shares; any
   future Forgejo release may break the wrapper. The end state of that
   path is an ill-fitting wrapper around an unsupported core image,
   forcing a reversal of this exact decision at higher cost.
3. **Blast radius.** Forgejo's continuity is a hard migration
   requirement (ADR-003) and it sits in the most critical workload
   category — an unsupported configuration is a bad fit for any
   workload in it.

## Consequences

- Forgejo remains the only non-TrueCharts chart, by design; its
  backup/restore is hand-rolled to the house pattern and validated in
  the DR re-run alongside the other gap charts (install → restore →
  verify → unsuspend).
- Chart and Forgejo version upgrades ride the official upstream path;
  image pinning stays ours (unchanged from today).
- Re-evaluating the wrapper requires evidence that the support-path and
  drift objections no longer hold — not the restore gap, which PR #460
  closes on the current install.
