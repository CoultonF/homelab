# TRMNL Vikunja plugin

TRMNL third-party plugin that shows Vikunja tasks on the TRMNL X. Source and
image: [CoultonF/trmnl-vikunja](https://github.com/CoultonF/trmnl-vikunja)
(`ghcr.io/coultonf/trmnl-vikunja:latest`).

## Resources

- Namespace: trmnl-vikunja
- Deployment: trmnl-vikunja (port 3000, `/healthz` probes)
- Service: trmnl-vikunja (ClusterIP, port 3000)
- PersistentVolumeClaim: trmnl-vikunja-data (1Gi, local-path) — SQLite with
  installs, settings, encrypted Vikunja tokens, and the last synced tasks
- Secret: trmnl-vikunja-secrets (not in git — see [Secret](#secret))

## Access

- Public: https://trmnl-vikunja.coultonf.com (Cloudflare Tunnel). TRMNL's
  servers call the webhooks and markup endpoint; your browser only visits the
  install and manage pages. No LAN ingress.
- Internal: http://trmnl-vikunja.trmnl-vikunja.svc.cluster.local:3000

## Routing

The route `trmnl-vikunja.coultonf.com -> http://trmnl-vikunja.trmnl-vikunja.svc.cluster.local:3000`
lives in `apps/cloudflared/cloudflared-config-configmap.yaml`. After ArgoCD
syncs it, delete the cloudflared pod (see `apps/cloudflared/README.md`).

DNS record (Cloudflare `coultonf.com` zone), created with
`cloudflared tunnel route dns baefdc8a-09d0-4432-8998-394b54cda77d trmnl-vikunja.coultonf.com`:

| Type  | Name          | Target                                                 | Proxy   |
|-------|---------------|--------------------------------------------------------|---------|
| CNAME | trmnl-vikunja | baefdc8a-09d0-4432-8998-394b54cda77d.cfargotunnel.com  | Proxied |

## Secret

`data-encryption-key` encrypts the Vikunja API tokens stored in SQLite. It is
NOT in git (public repo); `secret.yaml.template` shows the shape. Create it
once:

```sh
kubectl -n trmnl-vikunja create secret generic trmnl-vikunja-secrets \
  --from-literal=data-encryption-key="$(openssl rand -base64 32)"
```

Rotating it makes every saved Vikunja token unreadable; each install then shows
an error until its token is re-entered on the manage page.

## Reaching Vikunja

Inside the cluster `todo.coultonf.com` resolves to ingress-nginx's LAN IP
(split-horizon DNS), and the plugin refuses private addresses to avoid SSRF.
`ALLOWED_PRIVATE_VIKUNJA_HOSTS` in `deployment.yaml` allowlists
`todo.coultonf.com` and `vikunja.vikunja.svc.cluster.local`, so enter
`https://todo.coultonf.com` as the Vikunja URL.

## TRMNL plugin registration

Create the plugin at https://trmnl.com/plugins/my/new:

| Field | Value |
|---|---|
| Name | Vikunja |
| Description (max 50 chars) | Your Vikunja tasks, filtered and grouped |
| Icon | `assets/icon.png` from the plugin repo (512×512) |
| No Screen Padding | Off — the layouts use the framework's standard padding |
| Category | Productivity |
| Supported Refresh Interval | The fastest offered — every render is one live Vikunja query |
| Installation URL | https://trmnl-vikunja.coultonf.com/install |
| Installation Success Webhook URL | https://trmnl-vikunja.coultonf.com/webhooks/installation |
| Plugin Management URL | https://trmnl-vikunja.coultonf.com/manage |
| Plugin Markup URL | https://trmnl-vikunja.coultonf.com/markup |
| Uninstallation Webhook URL | https://trmnl-vikunja.coultonf.com/webhooks/uninstall |
| Knowledge Base URL | https://github.com/CoultonF/trmnl-vikunja#readme |

Then install it from My Plugins. The install page asks for the Vikunja URL
and an API token: in Vikunja open Settings → API Tokens and create one with
Read All for Tasks, Projects, and Labels.

## Upgrading

Pushing to the plugin repo's `main` publishes `latest`. The Deployment pulls
`Always` with a `Recreate` strategy, so delete the pod to pick up a new image:

```sh
kubectl -n trmnl-vikunja delete pod -l app=trmnl-vikunja
```
