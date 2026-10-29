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
  (DISASTER-RECOVERY.md). Rationale: ADR-005 (Accepted).

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
  enforcement steps; ADR-007 (render-diff practice).

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

## Cluster-state verification (kubectl)

- Kind names can be ambiguous across API groups, and this cluster has a
  live collision: two CRDs register kind `Backup` —
  `backups.longhorn.io` (Longhorn, shortname `lhb`, no backup targets
  configured) and `backups.postgresql.cnpg.io` (CNPG, no shortname).
  Any new chart can add another.
- Plain `kubectl get backup` silently resolves to Longhorn's kind and
  returns "No resources found" — observed 2026-10-16 and 2026-10-19,
  traced via `kubectl get backup -v=6` to
  `/apis/longhorn.io/v1beta2/backups`. kubectl does not error on
  cross-group collisions; its priority-based resolver picks one group.
- Fully qualify generic kind names on every read:
  `kubectl get backup.postgresql.cnpg.io`,
  `kubectl get cluster.postgresql.cnpg.io`, … Unqualified names are
  acceptable only for kinds verified unambiguous on this cluster
  (e.g. `scheduledbackup`).
- An empty result from an ambiguous instrument means "unknown", never
  "absent" (observed 2026-10-19: a false "zero Backup CRs" reading
  triggered a multi-round investigation; the qualified census showed
  ~31 completed backups per CNPG namespace).
- To see which endpoint an unqualified command actually hits, append
  `-v=6` and read the request URL.

## Backup-state verification (VolSync/restic)

- Verify backup state from `ReplicationSource.status`, never from the
  absence of errors: `kubectl -n <ns> get replicationsource <name> -o
  yaml | sed -n '/^status:/,$p'` — `lastSyncTime`,
  `latestMoverStatus.result` (with its log tail), `restic.lastPruned`.
- The `resticrepository` CRD does not exist on the installed VolSync
  version (observed 2026-10-29: `error: the server doesn't have a
  resource type "resticrepository"`). Repository state comes from
  `ReplicationSource.status` plus the restic CLI — do not probe for
  the CRD.
- When a rollback point matters (pre-upgrade, pre-maintenance), prove it
  by snapshot census, not by schedule: run the restic CLI against the
  repository and confirm a timestamp before the change. Credentials live
  in the per-app `<app>-backup-restic` Secret (`RESTIC_REPOSITORY`,
  `RESTIC_PASSWORD`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`):
  decrypt clusterenv with `sops` where available, extract from the
  Secret, or run in-cluster as a one-off pod from the mover image with
  `envFrom` the secret — no credential value touches a terminal.
- Completed mover Job pods are `Succeeded` — `kubectl exec` is
  impossible; spawn a debug pod instead. PSS-restricted namespaces
  require the full securityContext inside `kubectl run --overrides`,
  which replaces the containers array wholesale (image + command +
  securityContext complete, or admission rejects the pod).
- restic renders snapshot timestamps in the listing client's local
  timezone; backup crons run UTC. DST shifts appear in snapshot history
  and are not schedule changes (observed 2026-10-29: 03:07 → 02:07
  across the DST end at an unchanged 01:07 UTC schedule).

## PKM vault seam

- Tasks touching the PKM vault or its hosting follow vault rules
  first: no cloud for vault contents; PKM credentials segmented from
  git-ops credentials.
- The vault repo is authoritative for vault rules; this repo
  cross-references them (ADR-003).
