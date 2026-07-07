# Terminus (TRMNL BYOS)

Self-hosted [TRMNL](https://usetrmnl.com) server ([usetrmnl/terminus](https://github.com/usetrmnl/terminus)),
Ruby/Hanami app using the published `ghcr.io/usetrmnl/terminus` image.

Components: `terminus` (web, port 2300), `terminus-worker` (Sidekiq),
`terminus-postgres` (CloudNativePG cluster), `terminus-keyvalue` (Valkey).

## Manual setup (once, before first sync)

The app secret is NOT in git (public repo). Create it on the cluster:

```sh
kubectl create namespace terminus --dry-run=client -o yaml | kubectl apply -f -
kubectl -n terminus create secret generic terminus-app-secret \
  --from-literal=APP_SECRET="$(openssl rand -hex 64)"
```

Database credentials come from the CNPG-generated `terminus-postgres-app` secret.

## External access

`trmnl.coultonf.com` routes via the Cloudflare tunnel (see
`apps/cloudflared/cloudflared-config-configmap.yaml`). A DNS CNAME for
`trmnl` → `<tunnel-id>.cfargotunnel.com` must exist in Cloudflare
(same as the other hostnames). cloudflared needs a pod restart after its
ConfigMap changes.

## Devices

Point TRMNL devices at `https://trmnl.coultonf.com` (BYOS setup) or the
in-cluster service `terminus.terminus.svc.cluster.local:2300`.
