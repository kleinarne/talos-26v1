# Disaster recovery

> **Status: SKELETON — never executed.** Drafted 2026-10-10 from memory
> notes; every hardware, storage, and service fact must be verified against
> the live system. Execute a rehearsal recovery on a spare disk/VM before
> relying on this document. After each real or rehearsal recovery, update
> this file from what actually happened (see RECOVERY-REPORT pattern in
> dwoitzik/homelab-infrastructure).

## What must survive (assumption list)

If these are gone, this document cannot help:

1. This repository (public GitHub, clone on desktop as hedge)
2. SOPS/age private key — **[FILL IN: location]**
3. VolSync/Restic backup data + CNPG backups in Garage buckets
   **[VERIFY: what exactly is covered, retention]**
4. The storage disks themselves (ZFS pools, confirmed on-host
   2026-10-10: boot-pool; whippedcream = 2 TB SSD mirror (upgraded from
   1 TB), hosts the Talos VM system zvol and other VM zvols; strawberry
   = HDD mirror, holds zvol replications of whippedcream; chocolate-mint
   = RAID-Z1 3x8 TB, Garage backing) **[VERIFY: datasets, mounts]**
5. DDNS (DOMAIN_0 in the SOPS-encrypted clusterenv) — router-side
   (UXG-Lite), survives cluster loss
6. Off-site copy of backups — **[MISSING: currently the backup target
   (Garage) runs on the TrueNAS host itself. See "Known gaps".]**

## Recovery phases

### Phase 0 — Preconditions
- [ ] Working desktop (CachyOS) with repo clone, SSH keys, SOPS age key
- [ ] Physical access to the TrueNAS host

### Phase 1 — Hardware and TrueNAS
- [ ] Reinstall TrueNAS SCALE 25.10.7 **[VERIFY: use an installer image you
      actually want to recover to]**
- [ ] Import ZFS pools (do not re-create; import preserves datasets and
      Garage backup data)

### Phase 2 — Backup target first
- [ ] Re-provision Garage (or equivalent S3) **[VERIFY: config source —
      app config lives where? TrueNAS app or VM?]** backed by the HDD ZFS
      pool
- [ ] Verify buckets accessible and VolSync/CNPG backup data intact

### Phase 3 — Cluster
- [ ] Recreate the Talos VM **[VERIFY: still Clustertool? post-migration
      this step changes per ADR-001]**
- [ ] Bootstrap cluster from repo manifests (Kustomize + Flux)
- [ ] Verify Flux reconciles workloads

### Phase 4 — Data
- [ ] Restore PVCs via VolSync/Restic from Garage buckets
- [ ] Restore CNPG databases from backups

### Phase 5 — Verification checklist (per service)
- [ ] Blocky DNS (LAN hostname resolution — restores early or other
      services' hostnames fail) **[VERIFY: dependency order]**
- [ ] Unifi controller
- [ ] lldap + authelia (auth dependency for other services)
- [ ] Home Assistant (E3DC solar)
- [ ] Paperless — verify document data restored from PVC backup
- [ ] Jellyfin
- [ ] Grafana / kube-prometheus-stack
- [ ] Loki logging, OpenObserve
- [ ] Forgejo + PKM vault repo (per ADR-003; verify push/pull from
      mobile Working Copy)
- [ ] VolSync nightly backup jobs run again and succeed
- [ ] HTTPS reachable for all services (cert-manager/reverse proxy)
      **[VERIFY: reverse proxy setup]**

## Known gaps (fix before relying on this)

- **Backup target co-located with the cluster:** Garage runs on the
  TrueNAS host.
  A house-level event (fire, ransomware across the box) loses the backup
  data too. Add an encrypted off-site copy (friend's box or object
  storage) — this outranks any documentation concern.
- **Rehearsal never executed:** this document is theory until a rehearsal
  recovery has been performed and written up.
- **WireGuard clients** have a known DNS-update issue after reconnect —
  do not lose remote access during recovery expecting WireGuard DNS to
  "just work".
- **[FILL IN: secrets inventory — everything not covered by SOPS in the
  repo]**