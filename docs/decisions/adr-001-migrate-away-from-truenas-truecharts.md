# 1. Migrate the cluster away from TrueNAS/TrueCharts

Date: 2026-10-10

## Status

Proposed — target platform not yet selected. This ADR records the drivers
and the options under evaluation; it is not a decision about *where* to
migrate.

## Context

Current state (verify against the live system — from notes, not audited):

- Single host: Ryzen 5 4500, 64 GB DDR4, GTX 1050 Ti (currently
  unused; planned GPU passthrough for a latency-uncritical AI workload VM).
  Storage: 1 TB mirrored SSD, 3 TB mirrored HDD, RAID-Z1 3x8 TB, small
  system drive.
- TrueNAS SCALE 25.10.7 as storage backend and hypervisor, native ZFS.
- Single-node Talos VM (32 GB RAM) provisioned via TrueForge Clustertool
  (https://github.com/trueforge-org/clustertool), successor project of the
  TrueCharts tooling.
- Workloads managed via GitOps (Flux) with Kustomize rendering. Commits
  are applied without pre-merge validation: syntax errors surface as failed
  Flux reconciliations and get fixed through retry cycles — a known pain
  point (candidate improvement: CI-side `kustomize build` / `flux diff`).
- PVCs on Longhorn, nightly VolSync/Restic backups; Garage (on the TrueNAS
  host, HDD-backed ZFS pool) as S3 target for VolSync and CNPG backups.

Drivers for change:

- TrueCharts' opinionation is genuinely valued: CNPG as the database
  layer, storage backend integration, backup tooling — well-informed
  shared decisions that removed the need to choose and operate these
  components personally (Longhorn vs. OpenEBS, which database, backup
  setup). Migrating away means owning those decisions — a real cost,
  not a benefit.
- The problem is not opinionation but operational fragility under disk
  pressure, centered on etcd's fsync sensitivity:
  - Simultaneously triggered backups froze the whole cluster (since
    mitigated by scheduling backups sequentially).
  - Cluster rebuilds are worse: a fresh bootstrap reads the whole repo and
    TrueCharts installs all productive charts at once, then all
    CNPG/VolSync S3 restores fire simultaneously — extreme disk pressure,
    etcd fails, cluster infrastructure breaks. Workaround so far:
    rebuilding one chart at a time (the origin of the talos-26v1 repo
    name). Root cause is Flux reconciling everything concurrently; it is
    an orchestration problem, not a TrueCharts problem.
  - etcd also lives on the Talos EPHEMERAL partition together with
    container images and Longhorn writes — maximum contention by design
    of the current single-VM layout. On ZFS without a SLOG, etcd's sync
    writes (fsync) commit through the ZIL on the same vdevs that carry
    the async write bursts; under saturation, sync-write latency spikes —
    the direct freeze mechanism. Confirmed on-host (2026-10-10, zpool
    status): no SLOG on any pool. **[VERIFY: which pool holds the Talos
    VM zvol?]**
- Main driver: make rebuilds, restores, backups, and heavy AI workloads
  coexist reliably on the current single 64 GB node — keeping the
  shared-infrastructure convenience if possible.

## Options considered

0. **Mitigate in place** — stay on TrueNAS + TrueCharts + Talos.
   - Flux `dependsOn` waves so restores run in batches, not simultaneously
     (needed in every option; the fix is portable).
   - etcd sync-write latency isolation: SLOG device (targeted, cheap) or
     separate pool / NVMe passthrough for the VM disk (stronger).
     A second zvol on the same pool does NOT isolate — not a fix.
     Implemented (decision-agnostic) in ADR-004.
   - Rehearsal rebuild under simulated AI load as the acceptance test.
   - Pro: keeps the valued TrueCharts infrastructure; cheap, reversible.
   - Con: keeps the etcd failure mode structurally — reduced by ADR-004,
     which moves the VM disk off the shared pool in every option; the
     residual risk there is the single, non-redundant NVMe. SLOG/pool
     choice adds host-level configuration to own.
1. **Status quo** — rejected: addresses none of the drivers.
2. **TrueNAS stays, drop TrueCharts, keep Talos** — plain Helm/Kustomize.
   - Addresses opinionation (which is NOT a driver anymore) — effectively
     superseded by option 0 unless other reasons emerge.
3. **TrueNAS stays, replace Talos with single-server k3s (SQLite/kine)** —
   the structural fix for the etcd failure mode, at the cost of the
   datastore migration. Also benefits from ADR-004 (SQLite/kine fsyncs on
   the same VM disk).
4. **Proxmox VE + k3s VM(s)** — full dwoitzik pattern; largest migration.
5. **Talos bare metal** — rejected: ZFS/storage role, keeps etcd.

## Decision

**[FILL IN after evaluation]** — chosen option, with date. Record the
evaluation criteria and scores against:

- Bootstrapping and disaster recovery simplicity
- Storage integration (ZFS pools must remain intact/usable)
- Backup continuity (VolSync/Restic targets, Garage)
- GPU passthrough for the planned AI workload VM
- Right-sizing: control-plane datastore (etcd vs. embedded SQLite), database
  layer, and storage backend — resource profile under AI load on a single
  64 GB node
- TrueNAS host role afterwards (keep as pure storage VM host vs retire)

## Consequences

- Until this ADR is Accepted, the cluster stays on TrueNAS + TrueCharts.
- ADR-003 (Forgejo vault continuity) applies to every option above.
- ADR-004 (dedicated NVMe pool for the VM disk) applies to every option
  above and is already Accepted.
- When accepted, supersede this ADR with the concrete decision and open
  a migration ROADMAP entry with phases and rollback points.
