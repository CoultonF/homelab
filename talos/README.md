# Talos Configuration

This directory contains Talos Linux machine configurations for the homelab cluster.

## Cluster Information

- **Talos Version**: v1.10.6
- **Kubernetes Version**: v1.33.3
- **Cluster Name**: homelab
- **Nodes**:
  - Control Plane: talos-1ca-62z (192.168.0.249)

## Configuration Files

**Note**: Machine configurations (`controlplane.yaml`, `worker.yaml`) and talosconfig are **NOT** stored in this repository for security reasons. They are kept in `.gitignore`.

**Actual configs location**: `/Users/cfraser/Repos/talosctl-test/`

Files in this directory:
- `talosconfig.example` - Example talosconfig structure (credentials redacted)
- `SETUP.md` - Instructions for accessing Talos from another machine
- `README.md` - This file

## Using These Configurations

### Initial Cluster Bootstrap

```bash
# Apply control plane configuration
talosctl apply-config --insecure \
  --nodes 192.168.0.249 \
  --file controlplane.yaml

# Bootstrap etcd
talosctl bootstrap --nodes 192.168.0.249

# Generate kubeconfig
talosctl kubeconfig --nodes 192.168.0.249
```

### Adding Worker Nodes

```bash
# Apply worker configuration (modify IP as needed)
talosctl apply-config --insecure \
  --nodes <worker-ip> \
  --file worker.yaml
```

### Updating Configurations

```bash
# Apply updated config to running node
talosctl apply-config \
  --nodes 192.168.0.249 \
  --file controlplane.yaml
```

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
