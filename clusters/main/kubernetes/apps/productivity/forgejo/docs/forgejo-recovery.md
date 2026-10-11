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

Omit `destinationPVC` and set `capacity` instead — VolSync creates a **new** PVC,
named after the ReplicationDestination CR. Then point the HelmRelease at it and
remove the old PVC.

Note on the chart values: the forgejo chart has **no `existingClaim` key**.
Reuse an existing PVC with `persistence.create: false` plus `persistence.claimName`
(the chart's hardcoded default is `gitea-shared-storage`, which is why the live
PVC carries that name):

```yaml
persistence:
  enabled: true
  create: false                  # do NOT create a new PVC
  claimName: forgejo-restored    # the PVC VolSync created
```

Recommended for fire drills: restore to a fresh PVC, point a throwaway
Forgejo instance at it, confirm it boots and repos are intact — without
touching the live data. See `apps/testing/forgejo-drill/` for the drill
implementation: everything is applied and torn down via repo commits, the
throwaway instance runs in its own namespace on the restored PVC.

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
