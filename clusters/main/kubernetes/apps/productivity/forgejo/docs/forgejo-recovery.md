# Forgejo backup & recovery

Backup is a standalone VolSync `ReplicationSource` (see `app/backup.yaml`) — the
official Forgejo chart has no TrueCharts-style cnpg/volsync integration, so both
backup and recovery are explicit.

## What's backed up

- `gitea-shared-storage` PVC (repos, SQLite DB, LFS, config) via restic.
  The official forgejo chart inherits the upstream gitea chart's PVC naming
  (`<release>-shared-storage`) — it is NOT `forgejo-shared`.
- Destination: Garage S3, path `${GARAGE_S3_URL}/${GARAGE_S3_BUCKET}/forgejo`
- Schedule: nightly 01:07 UTC (`7 1 * * *`); retention 7 daily / 5 weekly / 12 monthly
- Copy method: Snapshot (crash-consistent for SQLite — WAL makes this reliable)

## Recovery (in-place restore)

**1. Stop Forgejo** (suspend HelmRelease or `kubectl scale sts -n forgejo --replicas=0`).

**2. Apply a one-shot ReplicationDestination:**

```yaml
apiVersion: volsync.backube/v1alpha1
kind: ReplicationDestination
metadata:
  name: forgejo-restore
  namespace: forgejo
spec:
  trigger:
    manual: restore-once
  destinationPVC: gitea-shared-storage    # overwrite existing PVC in place
  restic:
    repository: forgejo-backup-restic    # same Secret as the source
    # Direct: with destinationPVC the mover writes straight into the
    # existing volume; no snapshot is created (per the VolSync docs).
    copyMethod: Direct
    cacheStorageClassName: <storage-class>
    capacity: 10Gi
    moverSecurityContext:
      runAsUser: 1000
      runAsGroup: 1000
      fsGroup: 1000
```

**3. Pick a point in time** if not the latest snapshot:

```yaml
    restic:
      previous: 2        # N snapshots back
```

**4. When the sync completes** (`.status.lastSyncTime` set and the
`Synchronizing` condition False): delete the ReplicationDestination,
unsuspend Forgejo, and let it reconcile.

## Recovery to a fresh volume (safer)

Omit `destinationPVC` and set `capacity` **and `accessModes`**. Without
`destinationPVC`, `accessModes` is mandatory: VolSync rejects the object with
`accessModes must be provided when destinationPVC is not` (hit during the
2026-10-11 fire drill).

**This does NOT produce a PVC.** With `copyMethod: Snapshot`, VolSync restores
into a scratch volume, snapshots it, removes the scratch volume, and reports
the resulting **VolumeSnapshot** in `.status.latestImage` — after a successful
sync, `kubectl get pvc` still returns NotFound (confirmed during the drill).
Consuming the snapshot is a separate step: create a PVC whose `dataSource` is
that snapshot:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: forgejo-restored
  namespace: forgejo
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: <storage-class>
  dataSource:
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
    name: <from .status.latestImage.name>
```

(VolSync also ships a volume populator that lets a PVC's `dataSourceRef` point
directly at the ReplicationDestination; the explicit snapshot reference above
needs no extra controller and pins the exact point in time.)

A **failed manual-trigger sync does not retry on its own** — a new sync only
fires when the `trigger.manual` value changes (e.g. `restore-once` →
`restore-once-2`).

Note on the chart values: the forgejo chart has **no `existingClaim` key**.
Reuse an existing PVC with `persistence.create: false` plus `persistence.claimName`
(the chart's hardcoded default is `gitea-shared-storage`, which is why the live
PVC carries that name):

```yaml
persistence:
  enabled: true
  create: false                  # do NOT create a new PVC
  claimName: forgejo-restored    # the PVC you created from the snapshot
```

Also set `install.disableWait` / `upgrade.disableWait` on the HelmRelease
when it targets an async-restored PVC: the pod is expected to sit Pending
until the restore finishes, and helm's default readiness wait would stall
the install for the full `timeout` (times remediation retries) on a PVC
that does not exist yet (hit during the 2026-10-11 fire drill).

Recommended for fire drills: restore to a fresh volume, point a throwaway
Forgejo instance at the snapshot-backed PVC, confirm it boots and repos are
intact — without touching the live data. See `apps/testing/forgejo-drill/` for
the drill implementation: everything is applied and torn down via repo
commits. The restore lands in a VolumeSnapshot that `app/pvc.yaml` consumes
into a PVC, which the throwaway HelmRelease mounts in its own namespace.

## Raw restic escape hatch

If the cluster itself is gone, the repo is plain restic in Garage:

```sh
export RESTIC_REPOSITORY='s3:https://<garage-url>/<bucket>/forgejo'
export RESTIC_PASSWORD='<garage encryption key>'
export AWS_ACCESS_KEY_ID=...  AWS_SECRET_ACCESS_KEY=...

restic snapshots
restic restore latest --target /mnt/restore
```

## Rebuilding the cluster from scratch

1. Deploy volsync first (`system/volsync`).
2. Deploy Forgejo with an empty PVC.
3. Run the in-place restore (above) into the fresh PVC.
4. Confirm web UI + a repo pull before declaring victory.

## Preconditions to verify after first deploy

- [x] `kubectl get pvc -n forgejo` — PVC is named `gitea-shared-storage`
      (verified 2026-10-11; chart follows the upstream gitea naming, not `forgejo-shared`).
      The ReplicationSource pointed at `forgejo-shared` from 2026-10-08 to
      2026-10-11 and produced no backups in that window.
- [ ] Storage class supports VolumeSnapshots (else switch `copyMethod` to `None`)
- [ ] Mover can read the volume (uid/gid 1000 matches rootless chart)
- [ ] Fire drill performed at least once
