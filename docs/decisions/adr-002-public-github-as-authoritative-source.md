# 2. Public GitHub repo is the authoritative homelab source of truth

Date: 2026-10-10

## Status

Accepted

## Context

The authoritative source for rebuilding the homelab must not depend on the
homelab itself (bootstrap problem). Forgejo, which runs on the cluster, is
reserved for the PKM vault (ADR-003) and is a cluster workload — if the
cluster is down, so is the recovery documentation. The PKM architecture's
"no cloud" hard requirement covers vault *content*; homelab infrastructure
manifests, ADRs, and runbooks are not personal data. The cluster GitOps
repo (`kleinarne/talos-26v1`, a TrueForge Clustertool-generated Flux
monorepo) is already public on GitHub.

## Decision

- The authoritative homelab source is a public GitHub repository — extend
  `kleinarne/talos-26v1` with `docs/` (decisions, runbooks, incidents) and
  a root `DISASTER-RECOVERY.md`, keeping everything outside Clustertool's
  tool-owned file sections.
- Forgejo on-cluster is used exclusively for the PKM vault; homelab
  infrastructure never depends on Forgejo.
- Secrets may exist in the public repo only SOPS-encrypted (age) — this is
  already current practice in `talos-26v1` (`.sops.yaml`). The age
  private key lives off-repo and off-cluster (password manager and/or
  paper). **[FILL IN: key location(s)]**
- Public-repo hygiene is enforced by tooling, not discipline: gitleaks in
  pre-commit and CI, plus a review rule.
- Redaction rule for public content: no LAN IPs, internal hostnames, or
  internal DNS topology in prose; no personal data (paperless documents,
  media libraries); no device identifiers (serial numbers, WWNs, MACs);
  hardware *models* are publishable context, not secrets (applied in
  ADR-004 and the board-swap runbook); service inventory disclosure is
  a deliberate, reviewed choice.
- A recent clone of the repo stays on the desktop (CachyOS) as a hedge
  against GitHub unavailability during recovery.

## Consequences

- One clone of one public repo is sufficient to start a full recovery.
- The repo is a disclosure surface; the redaction rule above must be
  enforced in review until it can be automated.
- Forgejo's role shrinks to the vault only, which also shrinks the
  migration's blast radius on the PKM (ADR-003).
- This decision does not weaken the PKM "no cloud" rule — the vault and
  its contents are unaffected.