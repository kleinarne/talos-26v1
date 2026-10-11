# 7. Forgejo SSH access is LAN/WireGuard-only via the nginx-external TCP proxy

Date: 2026-10-11

## Status

Accepted

## Context

Forgejo (PKM vault host, ADR-003) serves the web UI over HTTPS via the
nginx-external ingress (cert-manager certificates, LAN/WireGuard). Plain
git-over-HTTPS is not a usable transport for vault sync: it is not relied on
for non-interactive clients, and the vault's no-cloud rule disqualifies
cloud-relayed git transit regardless.

CLI git and Working Copy (iOS) sync therefore need SSH. The PKM
architecture makes mobile commits to main a first-class path, so SSH must
work over WireGuard, not just the LAN. Forgejo's chart runs an internal
sshd exposed on the `forgejo-ssh` service (ClusterIP:22); Forgejo is not
published to the WAN. Hostname-based access (`git.${DOMAIN_0}`) resolves
through blocky's k8sgateway to the nginx-external MetalLB LoadBalancer IP.

## Decision

- Expose SSH by proxying TCP 22 through nginx-external via the
  ingress-nginx `tcp-services` ConfigMap (`"22": "forgejo/forgejo-ssh:22"`),
  reached on the existing nginx-external MetalLB IP. LAN and WireGuard
  only; no WAN exposure and no pre-wiring of any tunnel path for SSH.
- Pin `SSH_DOMAIN: git.${DOMAIN_0}` and `SSH_PORT: 22` explicitly in the
  chart values instead of relying on chart auto-derivation. Render-neutral
  with the current chart; guards against derivation drift on chart
  upgrades.
- SSH is the git transport for CLI and mobile clients; HTTPS remains the
  web-UI path.

## Considered alternatives (rejected)

- **Dedicated MetalLB service/IP for forgejo-ssh:** same hostname/DNS
  dependency on the client side, one more IP and service to own. No
  added isolation.
- **SSH via Cloudflare tunnel behind Cloudflare Access (short-lived client
  certs):** a genuine added identity layer, but Working Copy cannot run a
  ProxyCommand, so the mobile vault path would need dual transports
  permanently; vault transit would pass the CF edge (no-cloud gray zone);
  a CF outage would become a git outage. Rejected for a need that does not
  exist today.
- **Bare tunnel without Access:** zero inbound surface but no identity
  check — pure forwarding with a cloud dependency added.

## Consequences

- `ssh -T git@git.${DOMAIN_0}` works from LAN and WireGuard. Verified
  2026-10-11: DNS resolves to the nginx-external LB IP (explicitly checked
  against ClusterIP and pod IP), auth, clone, push, and Working Copy over
  WireGuard all pass.
- Port 22 on the nginx-external LB serves Forgejo SSH; nginx-external owns
  one TCP proxy entry. Future HelmRelease changes must be validated with
  `scripts/helm-render-diff.sh` before merge.
- Any future WAN exposure is a new decision. If it ever becomes real, the
  proven default is Cloudflare Access + short-lived certs for desktop
  clients with mobile staying on WireGuard — accepting dual transports as
  permanent structure, and re-evaluating the vault no-cloud rule explicitly
  before configuring anything.
- Forgejo restore verification must not depend on WireGuard client DNS
  (known roam/reconnect gap, DISASTER-RECOVERY.md). SSH host key and
  authorized keys are part of a complete Forgejo restore.
