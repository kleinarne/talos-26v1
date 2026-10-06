# Forgejo backup & recovery

Backup is a standalone VolSync `ReplicationSource` (see `app/backup.yaml`) — the
official Forgejo chart has no TrueCharts-style cnpg/volsync integration, so both
backup and recovery are explicit.

## What's backed up

- `forgejo-shared` PVC (repos, SQLite DB, LFS, config) via restic
- Destination: Garage S3, path `${GARAGE_S3_URL}/${GARAGE_S3_BUCKET}/forgejo`
- Schedule: nightly 01:07 (`7 1 * * *`); retention 7 daily / 5 weekly / 12 monthly
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
  destinationPVC: forgejo-shared        # overwrite existing PVC in place
  restic:
    repository: forgejo-backup-restic    # same Secret as the source
    copyMethod: Snapshot
    cacheStorageClassName: <storage-class>
    storageClassName: <storage-class>
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

**4. When `status.completed` is set:** delete the ReplicationDestination,
unsuspend Forgejo, and let it reconcile.

## Recovery to a fresh volume (safer)

Omit `destinationPVC` and set `capacity` instead — VolSync creates a **new** PVC.
Then switch the HelmRelease to it and remove the old PVC:

```yaml
persistence:
  enabled: true
  existingClaim: forgejo-restored
```

Recommended for fire drills: restore to a fresh PVC, point a throwaway
Forgejo instance at it, confirm it boots and repos are intact — without
touching the live data.

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

- [ ] `kubectl get pvc -n forgejo` — PVC is actually named `forgejo-shared`
- [ ] Storage class supports VolumeSnapshots (else switch `copyMethod` to `None`)
- [ ] Mover can read the volume (uid/gid 1000 matches rootless chart)
- [ ] Fire drill performed at least once
