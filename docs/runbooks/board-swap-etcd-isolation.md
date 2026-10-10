# Runbook: Host board swap + dedicated NVMe pool for the cluster VM

> **Status: DRAFT — never executed.** Hardware models are published per
> the ADR-002 redaction rule (models are publishable context, not
> secrets; device serial numbers are not). After execution, update
> this runbook and DISASTER-RECOVERY.md from what actually happened
> (RECOVERY-REPORT pattern).

## Goal

Structural fix for the etcd fsync freeze mechanism (ADR-001) per ADR-004:
swap the host mainboard to one with M.2 sockets, create a dedicated
single-device ZFS pool on the spare 1 TB NVMe, and rebuild the cluster VM
with its system/EPHEMERAL disk on that pool. The rebuild doubles as the
live rehearsal of DISASTER-RECOVERY.md Phases 1–3.

## Preconditions

- [ ] Replacement mainboard purchased (ASRock B550 Pro4): ECC UDIMM
      support verified, and the CPU (AMD Ryzen 5 4500) confirmed on the
      board's official CPU support list BEFORE ordering
- [ ] Case fits the new board's form factor (current board is micro-ATX;
      measure before ordering an ATX board)
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

## Phase A — Board swap (hardware)

- [ ] Power off; swap mainboard; transfer CPU, RAM, GPU, SATA HBA
- [ ] Reconnect all SATA data disks (count them — ~8)
- [ ] Install the NVMe in the CPU-attached (first) M.2 socket
- [ ] First boot into BIOS: verify POST, check ECC status if exposed,
      set boot device order
- [ ] Expect the onboard NIC to differ from the previous board —
      interface names WILL change in TrueNAS (Phase B)

## Phase B — TrueNAS bring-up (DR Phases 1–2)

- [ ] TrueNAS boots from its boot device
- [ ] Fix network config for the renamed interfaces
- [ ] Import all data pools (import, never recreate)
- [ ] Verify Garage comes up and buckets are reachable (DR Phase 2)
- [ ] Note whether ECC is active (BIOS / `dmidecode`); non-ECC mode is
      acceptable but must be recorded (ADR-004 consequence)

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

- New board fails to POST with the CPU: revert to the old board. Keep the
  old board until Phase D passes; sell only after the write-up.
- Rebuild stalls: the old VM zvol stays untouched until Phase D passes —
  do not destroy it early.

## Afterward

- [ ] Write the recovery report; update this runbook and
      DISASTER-RECOVERY.md with actuals (pool names, timings, surprises)
- [ ] Resolve the [VERIFY] markers in ADR-001, ADR-004, and here
- [ ] Sell or rehome the replaced mainboard
