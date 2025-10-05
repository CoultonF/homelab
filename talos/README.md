# Talos Configuration

This directory contains Talos Linux machine configurations for the homelab cluster.

## Cluster Information

- **Talos Version**: v1.10.6
- **Kubernetes Version**: v1.33.3
- **Nodes**:
  - Control Plane: talos-1ca-62z (192.168.0.249)

## Exporting Current Configuration

Due to a TLS certificate key size issue with the current Talos installation, the machine config cannot be directly exported via `talosctl`.

### To manually export configurations:

If you have physical or console access to the node:

```bash
# From the Talos node console or via SSH (if enabled)
talosctl read /system/state/config.yaml > controlplane.yaml
```

Or regenerate configurations based on your current cluster:

```bash
# Generate new configs (this creates new certificates)
talosctl gen config talos-cluster https://192.168.0.249:6443 \
  --output-dir talos/ \
  --with-docs=false \
  --with-examples=false

# This will create:
# - controlplane.yaml
# - worker.yaml
# - talosconfig
```

## Configuration Files (To Be Added)

- `controlplane.yaml` - Control plane node configuration
- `worker.yaml` - Worker node configuration (if applicable)
- `patches/` - Talos config patches for customization

## Known Issues

The current cluster has a certificate key size issue that prevents remote `talosctl` API access:
```
x509: "talos-1ca-62z" certificate is using a broken key size
```

This may require regenerating certificates or upgrading Talos to resolve.

## Bootstrap Process

Once configurations are added, the cluster can be bootstrapped with:

```bash
# Apply control plane config
talosctl apply-config --insecure \
  --nodes 192.168.0.249 \
  --file talos/controlplane.yaml

# Bootstrap the cluster
talosctl bootstrap --nodes 192.168.0.249

# Generate kubeconfig
talosctl kubeconfig --nodes 192.168.0.249
```
