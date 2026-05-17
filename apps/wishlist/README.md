# Wishlist

Self-hosted wishlist / gift registry ([cmintey/wishlist](https://github.com/cmintey/wishlist)).
SvelteKit app with an embedded SQLite database — no separate database.

## Resources

- Namespace: wishlist
- Deployment: wishlist (ghcr.io/cmintey/wishlist:v0.64.1)
- Service: wishlist (ClusterIP, port 3280)
- Ingress: wishlist-ingress (shop.coultonf.com)
- PersistentVolume: wishlist-data-pv (10Gi)
- PersistentVolumeClaim: wishlist-data-pvc
- ConfigMap: wishlist-config

No Secrets required (SQLite, SMTP configured later in-app if wanted).

## Access

- Internal: http://wishlist.wishlist.svc.cluster.local:3280
- Public: https://shop.coultonf.com (via Cloudflare Tunnel)

## Routing

Public access is via the Cloudflare Tunnel, not the nginx Ingress. The route
`shop.coultonf.com -> http://wishlist.wishlist.svc.cluster.local:3280` lives in
`apps/cloudflared/cloudflared-config-configmap.yaml`. The Ingress object is
kept only for parity with the other apps.

DNS record (set in Cloudflare `coultonf.com` zone):

| Type  | Name | Target                                                 | Proxy   |
|-------|------|--------------------------------------------------------|---------|
| CNAME | shop | baefdc8a-09d0-4432-8998-394b54cda77d.cfargotunnel.com  | Proxied |

## ORIGIN

`ORIGIN` in `wishlist-config-configmap.yaml` MUST exactly equal the public URL
`https://shop.coultonf.com` (no trailing slash). This SvelteKit app uses it for
CSRF/form validation — a mismatch breaks login and submissions behind the
tunnel. Change it here, commit, and push if the hostname ever changes.

## Lock down registration

Wishlist has no registration env var. The **first account created** at
https://shop.coultonf.com becomes the admin. After signing up, go to
Admin settings and turn **off** public signup (invite-only). No redeploy
needed — this is an in-app toggle, not a manifest change.

## Storage

`wishlist-data-pv` is a manual hostPath volume at `/var/lib/wishlist-data` on
the node, reclaim policy `Retain`. Two subdirectories are mounted into the
container: `data/` -> `/usr/src/app/data` (SQLite `prod.db`, auto-created and
migrated on first boot) and `uploads/` -> `/usr/src/app/uploads` (uploaded
images). The image runs as root, so no permission-fix initContainer is needed.
