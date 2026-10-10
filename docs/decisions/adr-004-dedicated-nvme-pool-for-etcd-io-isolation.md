# 4. Dedicated NVMe pool for the cluster VM disk (etcd I/O isolation)

Date: 2026-10-10

## Status

Accepted — amended 2026-10-10 (replacement board changed; see Amendment)

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
  drive. The replacement board is the ASRock B550 Pro4
  (superseded by the Amendment below — the purchased board is a used
  ASRock Rack X470D4U, est. €150–250).

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
4. Swap the mainboard to an ASRock Rack **X470D4U** (used; amended
   2026-10-10 from the initially chosen ASRock B550 Pro4 — see
   Amendment) chosen for: native ECC UDIMM support, 4 DIMM slots,
   AST2500 IPMI, 8 onboard SATA ports (retires the SAS HBA), and three
   CPU-attached PCIe slots. The NVMe goes into M2_1 (chipset-attached,
   PCIe 3.0 x2 — bandwidth is irrelevant to the fsync-latency goal);
   M2_2 remains free for the planned AI VM disk.
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
- The board swap adds host-level operations to own: NIC change and
  interface renames in TrueNAS (dual Intel i210 GbE + dedicated IPMI LAN
  port), a physical maintenance window, and BMC ownership (AST2500:
  firmware update before LAN exposure — i.e. before the REAL LAN; the
  update itself runs over a direct laptop link or an isolated L2
  segment — never WAN-exposed; enable Onboard VGA so the KVM keeps
  video with a GPU installed). ECC is a native feature of this server
  board, and the 4500's ECC capability is verified fact, not inference:
  dmidecode on the running host (2026-10-10) shows Total Width 72 bits
  with the Ryzen 5 4500 and the Samsung M391A2K43BB1-CPB ECC UDIMMs —
  the non-PRO Renoir CPU runs ECC, and the spec sheet's "PRO only"
  footnote is moot for this combination. Re-verify after the swap.
  Caveat: Renoir has no EDAC MC driver — corrected errors are silent,
  uncorrectable errors surface as MCE; this ADR claims ECC operation,
  not ECC telemetry. Execution lives in
  docs/runbooks/board-swap-etcd-isolation.md.

## Amendment (2026-10-10): replacement board changed to ASRock Rack X470D4U

After this ADR was accepted and before purchase, the replacement board was
changed from the ASRock B550 Pro4 (~€95 new) to a used ASRock Rack X470D4U,
which was purchased on 2026-10-10. The core decision — a dedicated
single-device NVMe pool carrying the cluster VM disk — is unchanged; only
the board executing it changed.

Rationale:

- Closes the DISASTER-RECOVERY.md Phase 0 "physical access" gap for
  host-level failures: the AST2500 BMC provides remote KVM, virtual media,
  and power control — the one recovery layer no SSH path covers (the
  SPICE-over-SSH console reaches only the VM, not host BIOS/POST). With
  WireGuard/Cloudflared remote access in place, a hung host while away
  otherwise means dead-until-physical-access.
- Native ECC UDIMM support (proper server implementation) removes the
  consumer-board ECC-activation uncertainty from the original
  Consequences — and the 4500's own ECC capability is verified on the
  running sibling board (dmidecode Total Width 72 bits, 2026-10-10),
  so this is evidence, not a spec-sheet inference.
- 8 onboard SATA ports retire the SAS HBA: one less part, one freed PCIe
  slot. The pools sum to exactly 8 data disks — zero SATA headroom; the
  HBA is kept as a cold spare, not sold.
- Retail sibling of the current Hetzner-customized B450D4U-V1L: same
  platform generation, least-surprise migration.

Tradeoffs accepted:

- Used board, no warranty (est. €150–250 vs ~€95 new).
- M.2 limited to ~2 GB/s class (M2_1: PCIe 3.0 x2 or SATA3; M2_2: x4/x2
  depending on documentation), chipset-attached — not CPU lanes.
  Bandwidth is irrelevant to the etcd fsync-latency goal and to the
  latency-uncritical AI VM disk.
- IPMI does not address the ADR-001 etcd freeze mechanism (the host stays
  up during cluster freezes). The board was bought for host-level
  resilience and remote management, not for this ADR's failure mode.

On-execution notes (reflected in the runbook):

- PCIe layout, top → bottom: PCIE6 (x16, CPU lanes; auto x8/x8 when PCIE4
  is also populated; supports x4/4/4/4 bifurcation), PCIE5 (x8 physical,
  x4 electrical — LSI HBAs confirmed working there by owners), PCIE4
  (x16 physical, x8 electrical). A dual-slot GPU in PCIE6 ends at PCIE5:
  tight but usable with a true 2.0-slot card; thicker cards block PCIE5;
  PCIE4 is never blocked.
- Installing a GPU auto-selects it as primary video and blanks the BMC
  KVM until BIOS → Advanced → Chipset → Onboard VGA = Enabled.
- Update the AST2500 firmware before the BMC joins the real LAN: the
  update itself needs a network, so it runs over a direct laptop link
  or an isolated L2 segment first.
- The Ryzen 5 4500 is not explicitly covered by the board's official
  CPU support categories (4000-series appears only as G-Series or
  PRO). Compatibility rests on evidence: the B450D4U-V1L — same
  platform, same BIOS family, same user manual — runs the 4500 in
  production. Consequence: a used 2019–2020 board may carry an old
  BIOS that predates Ryzen-4000 support; read the BIOS version via
  the BMC and flash current via IPMI (works with no CPU installed)
  BEFORE the CPU goes in. Fallback is the runbook rollback to the
  old board.
- ECC: verified active with the 4500 (dmidecode Total Width 72 bits,
  2026-10-10, Samsung M391A2K43BB1-CPB ECC UDIMMs); re-verify after
  the swap. Renoir has no EDAC MC driver — corrected errors are
  silent, uncorrectable errors surface as MCE; monitor via kernel MCE
  scan, not EDAC.
