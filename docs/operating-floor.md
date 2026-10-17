# Operating floor

Non-negotiable rules for every actor — human or AI — working on this
repository, the cluster it manages, or anything published from them.
This is the canonical copy; rationale and decision records live in the
cited ADRs. It binds regardless of tooling: sessions, scripts, and
reviews must all assume it applies.

## Write path

- Persistent cluster changes happen only as commits to this repo; Flux
  is the only applier.
- Imperative access (kubectl, helm) is allowed for reads, emergency
  mitigation, and one-off maintenance — every change made that way is
  reconciled into the repo afterwards.
- Emergency holds use `flux suspend` on the affected
  Kustomization/HelmRelease, not imperative edits the next reconcile
  would revert.
- Rebuild posture: repo + backups reproduce the cluster
  (DISASTER-RECOVERY.md). Rationale: ADR-005 (Proposed, PR #132).

## Secrets

- No plaintext secrets in commits, ever. Secrets are SOPS-encrypted
  with age; the age key lives off-repo and off-cluster.
- Rationale: ADR-002 (gitleaks pre-commit and CI).

## Public-output hygiene

Applies to any public artifact — this repo, issues, chat, posts — not
only to commits:

- Never publish device identifiers (serials, WWNs, MACs), internal
  hostnames, or the DDNS domain. Hardware models are publishable
  context.
- Never paste raw tool output (`zpool status`, `kubectl get`, …) into
  anything public unchecked. Redact first.
- Rationale: ADR-002 redaction rule.

## Validation before merge

- Validate manifests before proposing a commit: `kustomize build` on
  the overlays touched, plus `scripts/helm-render-diff.sh` for
  HelmRelease changes. Reconciliation retries are not validation.
- Drift on Flux-owned objects is detected in-cluster (controller
  apply dry-run each interval; HelmRelease `driftDetection`), not in
  CI. CI carries no cluster credentials. Rationale: ADR-005
  enforcement steps (Proposed); ADR-007 (render-diff practice).

## Repo-state verification

- GitHub code search — web or API — is a discovery aid, never
  evidence of absence: the index lags on fresh repos and covers only
  the default branch, producing silent false negatives (observed
  2026-10-11: zero hits for a string present in 43 files on main).
  A zero-result search means "unknown", not "absent".
- Verify repo state by reading files (GitHub UI/API) or grepping a
  fresh clone.
- Never work from stale state: read current main before proposing or
  pushing any change.
- Machine-checked invariants belong in CI, where they run on every
  change — not in interactive search, which runs only when someone
  remembers.
- AI actors: cite the file you read, not the search you ran.

## PKM vault seam

- Tasks touching the PKM vault or its hosting follow vault rules
  first: no cloud for vault contents; PKM credentials segmented from
  git-ops credentials.
- The vault repo is authoritative for vault rules; this repo
  cross-references them (ADR-003).
