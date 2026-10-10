# 4. Dedicated NVMe pool for the cluster VM disk (etcd I/O isolation)

Date: 2026-10-10

## Status

Accepted

## Context

ADR-001 identifies etcd fsync sensitivity under disk pressure as the central
fragility of the single-node layout: etcd lives on the Talos EPHEMERAL
partition, which sits on a zvol of a ZFS pool shared with container images
and Longhorn replica writes; without a SLOG, sync writes commit through the
ZIL on the same vdevs that carry the async write bursts. Under saturation
(all CNPG/VolSync S3 restores firing during a fresh bootstrap), sync-write
latency spikes and the cluster freezes.

Constraints as of 2026-10-10:

- A spare 1 TB PCIe 3.0 x4 NVMe SSD became available at no cost
  (white-label Phison E15, PS5015-E15T controller —
  value-segment DRAM-less with HMB, TLC NAND; SMART verified:
  6% endurance used, zero media errors, full spare). It is white-label:
  no firmware updates, no warranty.
- The current mainboard (ASRock Rack B450D4U-V1L, a
  Hetzner-customized variant) has no M.2 slot and both PCIe slots are occupied (GPU +
  SATA HBA), so the NVMe cannot be attached without a board swap. The CPU
  (AMD Ryzen 5 4500) is a retail SKU that appears on B550 CPU
  support lists. Standard tower case; 4x16 GB ECC UDIMM carries over
  (consumer-board ECC activation is uncertain — see Consequences).
- Budget guidance was ~€200; the swap lands at ~€95 total with the free
  drive. The replacement board is the ASRock B550 Pro4.

## Decision

1. Create a **dedicated, single-device ZFS pool** on the spare NVMe on the
   TrueNAS host, and place the Talos VM's system/EPHEMERAL disk (and
   therefore etcd, containerd images, and Longhorn replica data) on it.
   This is the "stronger" isolation path of ADR-001 option 0: a second
   zvol on the same pool does NOT isolate; a separate pool on separate
   hardware does.
2. Attach it to the VM as a **zvol**, not as PCI passthrough of the NVMe
   controller: passthrough is complicated by poor IOMMU grouping on the
   current board, and zvol management is the proven TrueNAS pattern
   (snapshots, resize, migration).
3. Do the move **at the next rebuild**, not as a live migration. Rebuilds
   are the exact failure scenario this fixes, and the rebuild doubles as
   the DISASTER-RECOVERY.md Phase 1–3 rehearsal.
4. Swap the mainboard to a B550-class consumer board
   (ASRock B550 Pro4) chosen for: ECC UDIMM support, 4 DIMM slots, two M.2 sockets,
   6 SATA, and an x16 + x16(x4) slot layout that hosts GPU and SATA HBA
   simultaneously. The NVMe goes into the CPU-attached M.2 socket; the
   second M.2 remains free for the planned AI VM disk.
5. Accept **no redundancy** on this pool by design. EPHEMERAL is
   reconstructible from the GitOps repo, Garage backups, and etcd
   snapshots; durable PVC data is covered by the nightly VolSync/Restic
   regime regardless of where Longhorn stores its replicas.
6. This decision is deliberately **independent of ADR-001's open platform
   decision**: option 0 (Talos + etcd) gets the isolation it needs, and
   option 3 (k3s with SQLite/kine) equally fsyncs on the same VM disk and
   benefits from the same pool. The investment survives either outcome;
   that is why it is recorded here rather than inside ADR-001.

## Consequences

- etcd's fsync latency no longer competes with HDD/SSD pool saturation —
  the freeze mechanism of ADR-001 is structurally addressed for both
  platform options. ADR-001 option 3's remaining advantage narrows to
  datastore operational simplicity (no etcd quorum/maintenance in DR).
- PVC/Longhorn replica I/O moves from the mirrored SATA SSD pool to a
  single device: better latency, lost mirror redundancy. Accepted —
  nightly backups cover the data and the node is rebuildable. Revisit a
  mirror on the second M.2 if the drive proves unreliable.
- A SLOG on the existing pools is no longer required for the etcd problem.
  Remaining sync writers (CNPG, Garage) are not at freeze risk. Confirmed
  on-host (2026-10-10, zpool status): no SLOG device on any pool
  (boot-pool, chocolate-mint, strawberry, whippedcream) — sync writes
  commit through the ZIL on the regular vdevs, as assumed. The Talos
  VM system zvol is confirmed on whippedcream (2 TB SATA SSD mirror),
  alongside other VM zvols (zfs list -t volume, 2026-10-10).
- The NVMe is white-label: no firmware updates. SMART monitoring
  (Percentage Used, Media and Data Integrity Errors) must be added to the
  observability baseline.
- The value-segment drive has modest sustained-write speed, but every
  ingress path into it is slower (restores read from the HDD-backed Garage
  pool, image pulls arrive over 1 GbE) — it is not the bottleneck in the
  restore scenario that motivated this ADR.
- The board swap adds host-level operations to own: expected NIC change
  and interface renames in TrueNAS, a physical maintenance window, and a
  possible ECC-to-non-ECC RAM mode change (verify ECC activation in BIOS
  or dmidecode after the swap; non-ECC mode is acceptable but must be
  known). Execution lives in docs/runbooks/board-swap-etcd-isolation.md.
