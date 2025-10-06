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
