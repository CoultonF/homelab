# Homebox

Self-hosted home inventory manager ([homebox.software](https://homebox.software)).
Single Go binary with embedded SQLite — no separate database.

## Resources

- Namespace: homebox
- Deployment: homebox (ghcr.io/sysadminsmedia/homebox:v0.25.0)
- Service: homebox (ClusterIP, port 7745)
- Ingress: homebox-ingress (home.coultonf.com)
- PersistentVolume: homebox-data-pv (10Gi)
- PersistentVolumeClaim: homebox-data-pvc
- ConfigMap: homebox-config

No Secrets required (SQLite, no SMTP configured).

## Access

- Internal: http://homebox.homebox.svc.cluster.local:7745
- Public: https://home.coultonf.com (via Cloudflare Tunnel)

## Routing

Public access is via the Cloudflare Tunnel, not the nginx Ingress. The route
`home.coultonf.com -> http://homebox.homebox.svc.cluster.local:7745` lives in
`apps/cloudflared/cloudflared-config-configmap.yaml`. The Ingress object is
kept only for parity with the other apps.

DNS record (set in Cloudflare `coultonf.com` zone):

| Type  | Name | Target                                                 | Proxy   |
|-------|------|--------------------------------------------------------|---------|
| CNAME | home | baefdc8a-09d0-4432-8998-394b54cda77d.cfargotunnel.com  | Proxied |

## Lock down registration

Deployed with `HBOX_OPTIONS_ALLOW_REGISTRATION: "true"` so the first account
can be created. After signing up at https://home.coultonf.com, set it to
`"false"` in `homebox-config-configmap.yaml`, commit, and push. ArgoCD
redeploys and new signups are blocked (existing logins still work).

## Storage

`homebox-data-pv` is a manual hostPath volume at `/var/lib/homebox-data` on
the node, reclaim policy `Retain`. Holds the SQLite DB and uploaded
attachments. The deployment's `fix-perms` initContainer chowns it to uid/gid
65532 (the image's runtime user) on every start.
