# Bootstrap

This directory contains ArgoCD bootstrap configurations using the App of Apps pattern.

## Structure

- `root-app.yaml` - Root Application that manages all other apps
- `argocd-apps/` - Individual Application manifests for each service

## Setup

### Prerequisites

1. ArgoCD must be installed in the cluster
2. GitHub repository must be accessible from the cluster

### Deploy ArgoCD Root Application

```bash
# Apply the root application
kubectl apply -f bootstrap/root-app.yaml
```

This will automatically deploy all applications defined in `argocd-apps/`:
- cloudflared
- mealie
- nginx-example
- local-path-storage

## App of Apps Pattern

The root application watches the `bootstrap/argocd-apps/` directory and automatically creates/updates child applications. Any new YAML files added to this directory will be automatically synced by ArgoCD.

## Accessing ArgoCD UI

```bash
# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Access via NodePort
# UI available at: http://<node-ip>:31323
```

## Managing Applications

To add a new application:

1. Create a new Application manifest in `argocd-apps/`
2. Commit and push to GitHub
3. ArgoCD will automatically sync the new application

To remove an application:

1. Delete the Application manifest from `argocd-apps/`
2. Commit and push to GitHub
3. ArgoCD will automatically remove the application (if prune is enabled)

## Sync Policy

All applications are configured with:
- **Automated sync**: Changes in git trigger automatic syncs
- **Self-heal**: Kubernetes resources are automatically corrected if modified
- **Prune**: Deleted resources in git are removed from the cluster
