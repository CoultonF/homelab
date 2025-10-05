# Homelab Kubernetes Cluster

This repository contains the GitOps configuration for a Talos Linux Kubernetes cluster managed with ArgoCD.

## Directory Structure

```
.
├── bootstrap/      # ArgoCD installation and root application
├── apps/          # Application manifests
├── infrastructure/ # Core infrastructure components (ingress, storage, etc.)
└── talos/         # Talos configuration files
```

## Prerequisites

- Talos Linux cluster up and running
- `kubectl` configured to access the cluster
- ArgoCD installed in the cluster

## Getting Started

1. Configure Talos cluster (see `talos/` directory)
2. Install ArgoCD (see `bootstrap/` directory)
3. Apply the root application to sync all resources

## Repository Structure

- **bootstrap/**: Contains ArgoCD installation manifests and the App of Apps pattern root application
- **apps/**: Application-specific manifests organized by application name
- **infrastructure/**: Infrastructure components like ingress controllers, cert-manager, storage classes, etc.
- **talos/**: Talos Linux machine configurations and patches

## ArgoCD Sync

This repository is designed to be synced by ArgoCD using the App of Apps pattern. The root application in `bootstrap/` will automatically sync all applications and infrastructure components.
