# 0. Record architecture decisions

Date: 2026-10-10

## Status

Accepted — superseded by ADR-006 (2026-10-11).

## Context

The homelab is being migrated away from TrueNAS/TrueCharts toward a less
opinionated, right-sized, more flexible platform (ADR-001). The cluster is being rebuilt
on a larger timeframe, and past homelab knowledge lives in chat logs and
memory, which are unversioned and unverifiable. Decisions need a durable,
timestamped, reviewable record that survives the infrastructure they
describe (ADR-002).

## Decision

We record architecture decisions in Architecture Decision Records:

- Format: Nygard (Title, Status, Context, Decision, Consequences) — same
  format as the PKM vault's ADR process, for consistency across projects.
- Location: `docs/decisions/` in the authoritative infrastructure repo.
- Numbering: three digits, strictly increasing, never reused — matching the
  PKM vault's ADR numbering for consistency.
- ADRs are immutable once accepted. To change an accepted decision, write a
  new ADR and mark the old one **Superseded by ADR-XXXX**. Never edit or
  delete history.
- Lifecycle: Proposed → Accepted → (Deprecated | Superseded).

## Consequences

- Decisions are auditable: what was chosen, why, when, and what was
  rejected.
- Change requires writing, which is deliberate friction for architecture
  churn.
- The ADR record is versioned in git alongside the infrastructure, so it
  survives the cluster it describes (see ADR-002).
