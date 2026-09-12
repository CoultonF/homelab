# Cloudflared Tunnel

Cloudflare Tunnel client for exposing services through Cloudflare's network.

## Resources

- Deployment: cloudflared
- ConfigMap: cloudflared-config

## Configuration Files

- `cloudflared-config-configmap.yaml` - Cloudflare Tunnel configuration
- `cloudflared-deployment.yaml` - Deployment manifest
- `tunnel-credentials.secret.yaml` - Cloudflare credentials (not in git)

## Required Secrets

The tunnel credentials file is excluded from git. Apply it before deployment:

```bash
kubectl apply -f tunnel-credentials.secret.yaml
```

## Deployment

```bash
kubectl apply -f namespace.yaml
kubectl apply -f tunnel-credentials.secret.yaml
kubectl apply -f cloudflared-config-configmap.yaml
kubectl apply -f cloudflared-deployment.yaml
```

## Applying route changes

cloudflared does not hot-reload `config.yaml`. After ArgoCD syncs a change to
`cloudflared-config-configmap.yaml`, delete the pod so the ReplicaSet
recreates it with the new config (public routes blip for a few seconds):

```bash
kubectl -n cloudflared delete pod -l app=cloudflared
```

Don't use `kubectl rollout restart`: `cloudflared-deployment.yaml` pins
`kubectl.kubernetes.io/restartedAt` in the pod template, so ArgoCD selfHeal
reverts the restart and the old pod keeps serving the old routes.
