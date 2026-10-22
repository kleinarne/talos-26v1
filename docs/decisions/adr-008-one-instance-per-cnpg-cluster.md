# 8. Run every CNPG database with a single Postgres instance

Date: 2026-10-22

## Status

Accepted

## Context

The cluster runs seven CloudNativePG-backed apps (authelia, grafana,
immich, lldap, nextcloud, paperless-ngx, vaultwarden), each
chart-provisioned with two Postgres instances (primary + one replica) on
a single-node Talos cluster.

- Single node means the replica shares the primary's failure domain:
  node, hypervisor, and VM failures kill both simultaneously. The
  replica provides no availability against the failures that actually
  occur; it covers only per-pod crashes of the primary, which
  restart-based recovery already covers in 10-60 s. HA replication on
  one node is theater (adjudicated 2026-10-13, challenge review Q3).
- The 2026-10-16 lldap incident demonstrated the operative cost: a
  bootstrap-time promotion race left the second replica crash-looping
  for 23 days (~6,500 restarts) with a timeline-divergent data directory
  Postgres cannot reconcile. CNPG does not auto-heal such a replica -
  recovery is manual PVC deletion + re-clone. A replica whose recovery
  requires manual intervention is not failover; it is a liability with a
  delay fuse. (The fix applied to lldap - pod + PVC deletion, operator
  re-clone - was incident recovery, not a downscale.)
- The QoS workstream (2026-10-13 adjudication) identified Guaranteed-
  class sizing (requests == limits -> oom_score_adj -997) as the
  strongest node-OOM protection for databases, funded per-database by
  halving the instance count. Two Guaranteed replicas per cluster was
  judged out of proportion; one is the coherent form.
- The backup path is the actual recovery story: nightly CNPG base
  backups to Garage (31-backup store verified live 2026-10-19; 30-day
  recovery window; catalog and retention proven), with the
  recovery-bootstrap drill (lldap as first subject) as the standing gate
  before any new memory consumer lands. Restores remain the open
  acceptance test.

## Decision

Every CNPG cluster runs one Postgres instance - chart override
`cnpg.main.cluster.instances: 1` in each app's helm-release.yaml
(TrueCharts common default is 2) - and no local HA replicas. Funding
Guaranteed memory sizing for the databases is the intended follow-
through (after OOM classification and the 14-day peak re-tune), not a
condition of this ADR.

## Consequences

- Per-database failover protection is restart-based (10-60 s),
  accepted; there is no second pod to fail over to.
- Memory freed by the second replicas becomes available for Guaranteed
  database sizing and headroom for the AI namespace quota.
- The CNPG operator deliberately stays single-replica at `critical`
  priority (adjudicated Q4/C6 - it is the recovery path for evicted
  Postgres pods).
- Recovery from data loss rests with backup/restore, not replication -
  with the RPO trade stated explicitly: the second instance's only real
  insurance was the narrow differential failure (primary pod/PVC loss
  with a surviving replica, RPO 0); with one instance that case costs
  up to 24 h of writes (nightly base backups, no WAL archiving in the
  current setup). Replication never covered the other loss modes
  anyway - node loss and pool loss kill both copies, and logical
  corruption or accidental deletion replicates to the standby
  instantly; backup/restore covers those, and the Garage target
  (separate host from the cluster VM) is a failure-domain separation
  single-node replication never had. WAL archiving to Garage is the
  natural mitigation (PITR, RPO -> minutes) if the 24 h window ever
  bites. The recovery-bootstrap drill remains the gate for restore
  confidence (open follow-up).
- Revisit trigger: a second node joining the cluster creates real
  failure-domain separation and re-opens the HA question - CNPG's
  built-in replication becomes meaningful again at that point.
- Executed 2026-10-22 (single values PR, render-diff gated): all seven
  clusters converted; each surviving pod verified as the current
  primary; the operator removed the standbys' data+wal PVCs itself (no
  `enablePVCDeletion` field in the installed CRD - scale-down cleanup is
  unconditional; a scale-back-up re-clones fresh volumes instead of
  reusing old ones).
