# Runbook: Host board swap + dedicated NVMe pool for the cluster VM

> **Status: DRAFT — never executed.** Hardware models are published per
> the ADR-002 redaction rule (models are publishable context, not
> secrets; device serial numbers are not). After execution, update this
> runbook and DISASTER-RECOVERY.md from what actually happened
> (RECOVERY-REPORT pattern).

## Goal

Structural fix for the etcd fsync freeze mechanism (ADR-001) per ADR-004:
swap the host mainboard to one with M.2 sockets, create a dedicated
single-device ZFS pool on the spare 1 TB NVMe, and rebuild the cluster VM
with its system/EPHEMERAL disk on that pool. The rebuild doubles as the
live rehearsal of DISASTER-RECOVERY.md Phases 1–3.

## Preconditions

- [ ] Replacement mainboard purchased: ASRock Rack X470D4U, used
      (2026-10-10, per the ADR-004 Amendment). The Ryzen 5 4500 is NOT
      explicitly covered by the board's official CPU support list
      (4000-series appears only as G-Series or PRO) — compatibility
      rests on evidence: the B450D4U-V1L (same platform, same BIOS
      family, same user manual) runs the 4500 in production today.
      Do NOT buy a spare CPU to bench-test this: it would prove the
      board, not the 4500
- [ ] No pre-window bench — no spare PSU exists. All board checks run
      in-window instead (Phase A0): after shutdown, power the X470D4U
      on the desk from the host's own PSU (board + PSU only, no
      CPU/RAM — the AST2500 runs on standby power): BMC reachable on
      the dedicated IPMI LAN port via a direct laptop link or isolated
      L2 segment; update the AST2500 BMC firmware there (the update
      needs a network — "before LAN exposure" means before the REAL
      LAN, which an isolated in-window link satisfies identically);
      read the installed BIOS version in the BMC web UI and flash the
      current BIOS via IPMI (supported with no CPU installed — a used
      2019–2020 board may predate Ryzen-4000 support); seat the spare
      NVMe in M2_1 (physical seating only — the BMC cannot enumerate
      it; real M.2 verification happens at Phase C pool creation
      regardless); record BIOS/BMC versions
- [ ] DOA-board risk is accepted explicitly: with zero pre-window
      power-on, a dead used board is discovered only after production
      shutdown. Mitigate at purchase time (seller return window or
      POST proof); if unavailable, the revert path makes it a lost
      window, not lost data
- [ ] CPU/RAM-dependent checks (POST, 4 DIMMs, ECC) are NOT benchable
      outside the window — the 4500 and the DIMMs only exist inside the
      running host. They run as Phase A0's in-case first boot (the
      desk-powered pre-check deliberately avoids a second assembly
      cycle); 8-SATA-port health is verified at Phase B pool import
      (no spare disks exist)
- [ ] ECC verified active on the CURRENT system (2026-10-10,
      `dmidecode -t memory`: Total Width 72 bits; 4x Samsung
      M391A2K43BB1-CPB DDR4-2133 ECC UDIMM) — expected to carry over,
      re-verify after the swap. Renoir has no EDAC MC driver: corrected
      errors are silent, uncorrectable errors surface as MCE — claim
      ECC operation, not ECC telemetry. The DIMMs are DDR4-2133 by SPD
      (ECC UDIMMs ship without XMP): 2133 MT/s is the module ceiling,
      not a board fault, and the swap does not change it
- [ ] Case fit: the X470D4U is micro-ATX like the current board — no
      case-fit risk (this precondition is closed)
- [ ] Spare NVMe wiped (`nvme format` / `blkdiscard`); SMART baseline
      saved (2026-10-10: 6% used, 0 media errors, full spare)
- [ ] Fresh etcd snapshot taken and stored off-host
      (`talosctl -n <node> etcd snapshot <file>`)
- [ ] Desktop recovery kit verified per DR Phase 0: repo clone, SSH keys,
      SOPS age key
- [ ] Nightly VolSync/CNPG backups green; Garage buckets accessible
- [ ] Current host outputs re-saved on execution day:
      `zpool status` and `zfs list -t volume` (topology findings as of
      2026-10-10 are already recorded in ADR-001/ADR-004 and here)

## Phase A0 — In-window board checks (window start, ~45 min)

- [ ] Shut down production; pull the host PSU and desk-power the X470D4U
      (board + PSU only, no CPU/RAM): BMC reachable, AST2500 firmware
      updated on the isolated link, installed BIOS version read, current
      BIOS flashed via IPMI, spare NVMe seated in M2_1 (physical check
      only — enumeration happens at Phase C); record BIOS/BMC versions
- [ ] Abort is cheapest here: nothing is disassembled except the PSU —
      a dead board ends the window before any teardown
- [ ] Then install the board in the case with CPU, RAM, GPU in one
      build (no separate bench assembly); first boot IS the POST test:
      verify POST, all 4 DIMMs detected, ECC active in BIOS
- [ ] Fails → reinstall CPU/RAM in the old board and abort the window
      (rollback path below)

## Phase A — Board swap (hardware)

- [ ] Power off; swap mainboard; transfer CPU, RAM, GPU — do NOT
      reinstall the SAS HBA (it is the cold spare)
- [ ] Reconnect all 8 SATA data disks onto the 8 onboard SATA ports
      (exactly 8 ports, zero headroom; port order is irrelevant to ZFS
      import, but photograph the mapping anyway)
- [ ] NVMe already seated in M2_1 (Phase A0) — verify screw and socket
      after in-case handling; M2_2 stays free
      for the planned AI VM disk
- [ ] Install the GPU in PCIE6 (top slot, x16). A dual-slot card ends at
      PCIE5 — PCIE5 stays usable with a true 2.0-slot card, PCIE4
      (bottom) is never blocked. Do not populate PCIE4 simultaneously
      unless GPU x8 is acceptable (PCIE6 + PCIE4 auto-switch to x8/x8)
- [ ] First boot into BIOS: verify POST, check ECC status via the BMC
      (native server ECC — report if NOT active), set boot device order
- [ ] Set BIOS → Advanced → Chipset → Onboard VGA = Enabled so the
      AST2500 KVM keeps video with the GPU installed (otherwise the GPU
      auto-becomes primary video and the KVM shows a black screen)
- [ ] Expect the onboard NICs to differ from the previous board (dual
      Intel i210 GbE + dedicated IPMI LAN port) — interface names WILL
      change in TrueNAS (Phase B)

## Phase B — TrueNAS bring-up (DR Phases 1–2)

- [ ] TrueNAS boots from its boot device
- [ ] Fix network config for the renamed interfaces
- [ ] Import all data pools (import, never recreate)
- [ ] All 8 disks online in `zpool status` — this IS the 8-port health
      check (no spare disks existed for the bench). 2 of the 8 ports
      hang off the ASM1061 behind the chipset: a disk showing link
      resets goes on a native X470 port instead
- [ ] Verify Garage comes up and buckets are reachable (DR Phase 2)
- [ ] Re-verify ECC active (`dmidecode -t memory`: Total Width 72 bits;
      ignore the type-16 "Error Correction Type" field — it is
      unreliable in vendor DMI tables). Non-ECC here is a HALT, not a
      note: on this board with this verified CPU/RAM combo it means
      wrong DIMMs or a config fault

## Phase C — NVMe pool + cluster rebuild (DR Phases 3–4)

- [ ] Create the single-device pool on the NVMe (working name `tank-vm`),
      no redundancy, ashift=12
- [ ] Recreate the cluster VM with its system disk as a zvol on `tank-vm`
      **[VERIFY: Clustertool zvol placement or manual VM edit needed?]**
- [ ] Before destroying anything: the attached system zvol is confirmed
      (midclt vm.query, 2026-10-10) as
      whippedcream/vm-zvols/talos_systemdrive_2026-09-14 — keep it as the
      rollback zvol
- [ ] Bootstrap the cluster from repo manifests; if the Flux `dependsOn`
      restore waves (ADR-001 option 0) are not merged yet, keep the
      one-chart-at-a-time procedure — do not let all restores fire at once
- [ ] Restore PVCs via VolSync/Restic and CNPG databases from Garage
      backups (batched)

## Phase D — Verification

- [ ] All DISASTER-RECOVERY.md Phase 5 checklist items pass
- [ ] etcd disk fsync latency in a healthy band (etcd Prometheus metrics
      or `talosctl etcd status`)
- [ ] The ADR-001 acceptance test: simulated restore burst under AI load
      does not freeze the cluster
- [ ] NVMe SMART monitoring added to Grafana (Percentage Used,
      Media and Data Integrity Errors)

## Reference: current VM config (midclt vm.query, 2026-10-10)

VM `talos_cluster` (id 6), RUNNING, autostart on. 32 GB RAM, 1 socket ×
5 cores × 2 threads, cpu_mode HOST-MODEL, UEFI (OVMF_CODE.fd), no TPM,
no secure boot. VIRTIO disk via zvol (system zvol:
whippedcream/vm-zvols/talos_systemdrive_2026-09-14), VIRTIO NIC on br0,
SPICE display bound to 0.0.0.0 with password — change the bind to
127.0.0.1 at recreation (see "Console access" below). The Talos installer ISO
(strawberry/encrypted/install/metal-amd64.iso) is still attached as CDROM
— a rebuild leftover; do not carry it over unless reinstalling. Display
password and NIC MAC deliberately not recorded (ADR-002 redaction rule;
the disk `serial` in the VM config is a libvirt-emulated value, not a
hardware identifier).

## Reference: X470D4U PCIe / M.2 layout (per ADR-004 Amendment)

Expansion slots, top → bottom: PCIE6 (x16 physical and electrical, Gen3,
CPU lanes; auto-switches to x8/x8 when PCIE4 is also populated; supports
x4/4/4/4 bifurcation), PCIE5 (x8 physical, x4 electrical, CPU lanes —
LSI 9207-8i HBAs confirmed working there by owners), PCIE4 (x16 physical,
x8 electrical, CPU lanes). A dual-slot GPU in PCIE6 ends exactly at
PCIE5: tight but usable with a true 2.0-slot card; 2.2-slot and thicker
cards block PCIE5; PCIE4 is never blocked. M.2: M2_1 (PCIe 3.0 x2 or
SATA3) and M2_2 (~2 GB/s class, x4/x2 depending on documentation) — both
chipset-attached, not CPU lanes; accepted per ADR-004 (bandwidth is not
the goal, fsync-latency isolation is). Onboard storage: 8 SATA ports
(6x X470 chipset incl. 1 SATA-DOM port, 2x ASMedia ASM1061) — exactly
enough for the 8 data disks, zero headroom. Networking: dual Intel i210
GbE + dedicated IPMI LAN port (AST2500 with RTL8211E NCSI). BMC hygiene:
update AST2500 firmware on an isolated link before real-LAN exposure;
never expose the BMC to WAN.

## Console access (VM display)

At recreation, bind the SPICE display to 127.0.0.1 instead of 0.0.0.0
and reach the console from the desktop through the existing SSH path:

    ssh -N -L 5902:127.0.0.1:5902 -L 5903:127.0.0.1:5903 root@<truenas-host>
    remote-viewer spice://127.0.0.1:5902     # or browser: http://127.0.0.1:5903

Keep the SPICE password: the loopback bind, the SSH key, and the password
are layered, and the password remains the gate on the tunneled port.
DR Phase 0 already requires SSH keys on the desktop, so console access
adds no new recovery dependency. This is the documented
TrueNAS/remote-viewer pattern; no secrets, IPs, or internal hostnames
recorded (ADR-002 rule). Verify the bind after the swap on the host:

    ss -tlnp | grep 590    # expect 127.0.0.1 entries only

## Rollback

- New board fails to POST with the CPU: revert to the old board — a
  full second board swap (disassemble, remount, re-cable 8 SATA,
  reseat GPU); budget 1.5–2 h, not minutes. Interface names revert
  with the board, and SATA port order is irrelevant to ZFS import, so
  the old host comes back without config churn. Keep the old board
  until Phase D passes; sell only after the write-up.
- SATA port or cabling trouble mid-swap: install the SAS HBA (cold spare)
  in PCIE4 (x8, never blocked by the GPU) and continue; PCIE5 is only
  usable if the GPU is a true 2.0-slot card (2.2-slot and thicker cards
  block it) — check GPU thickness before relying on it. Do not abort
  the maintenance window over a port issue.
- Rebuild stalls: the old VM zvol stays untouched until Phase D passes —
  do not destroy it early.

## Afterward

- [ ] Write the recovery report; update this runbook and
      DISASTER-RECOVERY.md with actuals (pool names, timings, surprises)
- [ ] Resolve the [VERIFY] markers in ADR-001, ADR-004, and here
- [ ] Sell or rehome the replaced mainboard
