# Vikunja

Self-hosted to-do list / project manager ([vikunja.io](https://vikunja.io)).
Single Go binary serving both API and frontend, with embedded SQLite — no
separate database.

## Resources

- Namespace: vikunja
- Deployment: vikunja (vikunja/vikunja:2.6.0)
- Service: vikunja (ClusterIP, port 3456)
- Ingress: vikunja-ingress (todo.coultonf.com)
- PersistentVolumeClaims: vikunja-db (1Gi), vikunja-files (10Gi) — local-path
- ConfigMap: vikunja-config
- Secret: vikunja-secrets (not in git — see [Secret](#secret))

## Access

- Internal: http://vikunja.vikunja.svc.cluster.local:3456
- Public: https://todo.coultonf.com (via Cloudflare Tunnel)
- LAN/tailnet: same URL; split-horizon DNS answers 192.168.0.249 and
  ingress-nginx serves it with the wildcard cert

## Routing

Public: the route `todo.coultonf.com -> http://vikunja.vikunja.svc.cluster.local:3456`
lives in `apps/cloudflared/cloudflared-config-configmap.yaml`. cloudflared
does not hot-reload its config — after ArgoCD syncs a route change, run
`kubectl -n cloudflared rollout restart deploy/cloudflared`.

LAN: `192.168.0.249 todo.coultonf.com` in the `hosts` block of
`apps/coredns/configmap.yaml` sends local clients to ingress-nginx, which
uses this app's Ingress.

DNS record (Cloudflare `coultonf.com` zone), created with
`cloudflared tunnel route dns baefdc8a-09d0-4432-8998-394b54cda77d todo.coultonf.com`:

| Type  | Name | Target                                                 | Proxy   |
|-------|------|--------------------------------------------------------|---------|
| CNAME | todo | baefdc8a-09d0-4432-8998-394b54cda77d.cfargotunnel.com  | Proxied |

## Secret

`service.secret` signs login sessions. If it's unset, Vikunja generates a
random one on every start and everyone is logged out on each restart. It
lives in the `vikunja-secrets` Secret, which is NOT in git (public repo);
`secret.yaml.template` shows the shape. Create it once:

```sh
kubectl -n vikunja create secret generic vikunja-secrets \
  --from-literal=service-secret="$(openssl rand -hex 32)"
```

Rotating it only logs everyone out.

## Users

Registration is off (`VIKUNJA_SERVICE_ENABLEREGISTRATION: "false"`) because
the instance is on the public internet. Manage accounts with the CLI in the
running pod. The image is `FROM scratch` (no shell), so call the binary
directly:

```sh
kubectl -n vikunja exec deploy/vikunja -- /app/vikunja/vikunja user create \
  -u <username> -e <email> -p '<password>'
kubectl -n vikunja exec deploy/vikunja -- /app/vikunja/vikunja user list
kubectl -n vikunja exec deploy/vikunja -- /app/vikunja/vikunja user reset-password <id> --direct -p '<password>'
```

No SMTP is configured, so password resets must use `--direct`.

## Storage

Two `local-path` PVCs, direct-mounted (no `subPath` — see
`apps/wishlist/README.md` for why): `vikunja-db` -> `/db` (SQLite
`vikunja.db`, created and migrated on first boot) and `vikunja-files` ->
`/app/vikunja/files` (attachments, avatars, project backgrounds).
local-path creates volume dirs `0777`, so the image's uid 1000 writes
without a permission-fix initContainer. Both live under
`/var/local-path-provisioner`, which the nightly restic job
(`infrastructure/backup/`) snapshots along with the rest of `/var`.

## Upgrading

Bump `image:` in `vikunja-deployment.yaml` (pinned tag,
`imagePullPolicy: IfNotPresent`), commit, and push. Database migrations run
automatically on start.
