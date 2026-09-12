# Vikunja

Self-hosted to-do list / project manager ([vikunja.io](https://vikunja.io)).
Single Go binary serving both API and frontend, with embedded SQLite — no
separate database. We run a fork renamed **To Do** (see [Fork](#fork)).

## Resources

- Namespace: vikunja
- Deployment: vikunja (ghcr.io/coultonf/vikunja — custom build, see [Fork](#fork); tag pinned in `vikunja-deployment.yaml`)
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
does not hot-reload its config — after ArgoCD syncs a route change, delete
the cloudflared pod (see `apps/cloudflared/README.md`).

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

## Fork

We run a fork renamed **To Do**: [CoultonF/vikunja](https://github.com/CoultonF/vikunja),
branch `todo` (the fork's default branch), cut from upstream tag `v2.6.0`.
Three commits on top of upstream:

1. `ci:` — deletes upstream's `.github/workflows/*` (their crons and PR/issue
   bots would otherwise run on the fork) and adds `todo-image.yml`, which
   builds the upstream Dockerfile on every push to `todo` and publishes
   `ghcr.io/coultonf/vikunja:<VERSION>` (+ `:todo`). The package must be
   public — the cluster pulls with no imagePullSecret.
2. `feat:` rename — page and tab titles, PWA manifest name (home-screen
   label), 2FA issuer, 32 English UI strings, and the logo wordmark
   (`frontend/src/assets/logo-full*.svg`: "To Do" outlined in Quicksand Bold
   at the original's size and baseline). Kept on purpose: "Powered by
   Vikunja", the "Vikunja" quick-add-magic mode, the CalDAV docs link, and
   the "Vikunja Export" importer. Other UI languages are unchanged.
3. `feat:` dog icons — `frontend/src/assets/dog-front.svg` and `dog-cool.svg`
   (the source art, verbatim) replace the llama on the login page and the
   empty task list, and dog-front sits in the logo circle (`logo.svg`,
   `logo-full*.svg`). Every icon in `frontend/public/` (favicon, Apple touch,
   Android/PWA, maskable, time-tracking favicon) is regenerated from the
   logo. The two llama photos — `llama-nightscape.jpg` (loading screen) and
   `no-auth-image.jpg` (login page) — are unchanged.

### Making a change

1. Commit on `todo` in the fork, bump `VERSION` in
   `.github/workflows/todo-image.yml` (`v2.6.0-todo.2`, `.3`, …), and push —
   CI publishes the image. Tags are immutable and the Deployment uses
   `imagePullPolicy: IfNotPresent`, so every change needs a new suffix.
2. Bump `image:` in `vikunja-deployment.yaml` to that tag, commit, and push
   `main`. Wait for CI to finish first: the Deployment is `Recreate`, so a
   tag that doesn't exist yet takes the app down until it does.

### Bumping upstream version

1. In the fork: `git fetch upstream tag vX.Y.Z --no-tags`, then
   `git checkout -B todo vX.Y.Z` and `git cherry-pick` the fork commits,
   resolving conflicts in favour of the fork's versions (workflows stay
   deleted, logos stay "To Do").
2. Set `VERSION: vX.Y.Z-todo.1` and force-push `todo`.
3. Bump the image tag here. Database migrations run automatically on start.
