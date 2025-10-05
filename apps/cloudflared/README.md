# Cloudflared Tunnel

Cloudflare Tunnel client for exposing services through Cloudflare's network.

## Resources

- Deployment: cloudflared
- ConfigMap: cloudflared-config

## Required Secrets

The following secrets need to be created before deploying:

```bash
kubectl create secret generic cloudflared-token \
  --from-literal=token=<your-cloudflare-tunnel-token> \
  -n cloudflared

kubectl create secret generic tunnel-credentials \
  --from-file=credentials.json=<path-to-credentials-json> \
  -n cloudflared
```

## Deployment

```bash
kubectl apply -f namespace.yaml
# Create secrets (see above)
kubectl apply -f cloudflared-config-configmap.yaml
kubectl apply -f cloudflared-deployment.yaml
```
