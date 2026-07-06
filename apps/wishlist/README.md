# Wishlist

Self-hosted wishlist / gift registry. Upstream is
[cmintey/wishlist](https://github.com/cmintey/wishlist); we run a recolored
custom build (see [Theming](#theming)). SvelteKit app with an embedded SQLite
database — no separate database.

## Resources

- Namespace: wishlist
- Deployment: wishlist (ghcr.io/coultonf/wishlist:v0.64.1-slate.1 — custom build)
- Service: wishlist (ClusterIP, port 3280)
- Ingress: wishlist-ingress (shop.coultonf.com)
- PersistentVolumeClaims: wishlist-data, wishlist-uploads (local-path, 10Gi each)
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

## Theming

Wishlist has **no runtime theming** (no env var, no admin setting). Its accent
color is compiled into the CSS, default purple. We run a recolored fork:

- Fork: [CoultonF/wishlist](https://github.com/CoultonF/wishlist), branch
  `slate`, cut from upstream tag `v0.64.1`.
- Patch (one commit): `src/wishlist.css` — the 11 `--color-primary-*` tokens,
  keep upstream lightness ramp, drop chroma, rotate hue 320 → 255 (slate);
  `src/app.html` + `vite.config.ts` — browser/PWA chrome `#423654` → `#475569`.
- CI `.github/workflows/theme-image.yml` builds the upstream Dockerfile
  unmodified (Vite/Tailwind recompiles the patched CSS) and publishes
  `ghcr.io/coultonf/wishlist:v0.64.1-slate` (+ `:slate`). Package is public,
  so the cluster pulls with no imagePullSecret.

### Bumping upstream version

1. In the fork: `git fetch upstream tag vX.Y.Z --no-tags` then re-cut
   `git checkout -B slate vX.Y.Z` and re-apply the 3-file patch (or
   `git cherry-pick` the slate commit; resolve `src/wishlist.css` if upstream
   moved the tokens).
2. Edit the image tags in `.github/workflows/theme-image.yml` to
   `vX.Y.Z-slate`, push `slate` → CI publishes the new image.
3. Bump `image:` in `wishlist-deployment.yaml` to `:vX.Y.Z-slate`, commit,
   push `main`. For a pure theme re-tweak on the same upstream version, bump
   the suffix instead (`-slate.1`, `-slate.2`) — tags are immutable and
   `imagePullPolicy: IfNotPresent`.

## Storage

Two `local-path` PVCs, each direct-mounted (no `subPath`): `wishlist-data` ->
`/usr/src/app/data` (SQLite `prod.db`, auto-created and migrated on first
boot) and `wishlist-uploads` -> `/usr/src/app/uploads` (uploaded images).
The image runs as root, so no permission-fix initContainer is needed.

**Never use `subPath` mounts on this node.** Kubelet materializes subPath
bind sources inside its own container overlay (`/var/lib/kubelet/pods/*/
volume-subpaths/`), so the data never reaches the PV directory and evaporates
when the kubelet/sandbox restarts. This destroyed the live DB twice
(2026-07-01, 2026-07-06); recovery both times was from the restic B2
snapshots, which happen to capture the kubelet overlay under `/host-var`.
