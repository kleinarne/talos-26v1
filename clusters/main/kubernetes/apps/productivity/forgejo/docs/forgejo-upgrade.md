# Forgejo major-upgrade runbook

For major hops of the in-cluster Forgejo (official Helm chart, rootless
image, SQLite on the data PVC, VolSync/restic nightly backup behind
nginx). Sibling: `forgejo-recovery.md` (restore mechanics — this
runbook points into it, does not repeat it). Dated hop events live in
the `helm-release.yaml` comment block and git history; this file
carries only maintained procedure. Chart-upgrade scheduling is the
upgrade monitor's job — not this runbook.

## 1. Pre-hop

- **Upstream bug-class check:** read the target patch's release notes
  against the previous advisory window before pinning. 17.0.0 was
  blacklisted: forgejo#14866 (an empty `receive.hideRefs` written into
  the git config on v16-upgraded instances; with git 2.42–2.49, pushes
  and web merges to packed-refs branches fail with `cannot lock ref …
  reference already exists`; fix !14869, backport !14870). 17.0.1
  removes the key at application startup — no admin cleanup. The
  container image ships its own git (2.54.0 at that hop) and escapes
  host-git dependencies.
- **Backup census:** prove the rollback point by restic snapshot census
  (operating-floor.md, backup-state verification) — a snapshot
  timestamped before the hop must exist. Rollback = restore that
  snapshot via `forgejo-recovery.md` (`previous:` point-in-time
  selector) + revert `image.tag`. SQLite rides the data PVC, so one
  restore unit covers DB, repos, and the packages registry.

## 2. Hop

- `image.tag` via chart values (chart-sanctioned; `image.rootless`
  appends `-rootless`); strategy `Recreate`. Record the hop and
  accepted breaking changes in the values comment block — that comment
  is the dated event record (16.0.6 → 17.0.1 on 2026-10-28, including
  the v17 link-resolution breaking change, is documented there).

## 3. Post-hop baseline (executed, not assumed)

- Startup log: app version + `Git version … (home: /data/home)`.
- Full-body gitconfig read: `kubectl -n forgejo exec deploy/forgejo --
  cat /data/home/.gitconfig`. `git config --file` exit codes are
  ambiguous — missing key and missing file both exit 1.
- One push per client class (desktop SSH, mobile Working Copy); one
  web PR merge (expect no `PushRejected`).
- Client-IP attribution behind nginx: request from a known client.
  PASS = the client's IP in the log line; FAIL = the ingress pod IP →
  check `REVERSE_PROXY_TRUSTED_PROXIES` (see below).
- Broker chain, when the broker is live: vault-sync run green, one
  stage_write, one registry-pull probe (debug pod,
  `imagePullPolicy: Always`, PSS-restricted `--overrides`).

## 4. Trusted-proxy mechanics (behind nginx)

- `REVERSE_PROXY_TRUSTED_PROXIES` must name the ingress pod CIDR
  (clusterenv `PODNET`), never the MetalLB VIPs — VIPs are
  destinations; the TCP source the app sees is always the ingress
  pod. The default is loopback-only, so without an override every
  request logs as the ingress pod and rate limiting treats all
  clients as one identity (observed 2026-10-29). Loopback-only is also
  the safe end: the CVE-2026-20896 header-auth class requires
  reverse-proxy authentication, which this instance does not enable.
- Pair the override with an ingress-controller-only NetworkPolicy on
  the forgejo pod, so in-cluster XFF spoofing is unreachable, not
  just ignored.

## 5. Cadence

- Quarterly releases; non-LTS lines live ~3.5 months; LTS every
  fourth release. 17.0 EOL 2027-01-28; 19.0 LTS lands 2027-04-15.
  The monitor owns the schedule; this runbook only defines what a
  hop must prove.
