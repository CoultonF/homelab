# Setting Up Talos Access on Another Machine

## Overview

To access your Talos cluster from another machine, you need the Talos configuration file which contains certificates and cluster information.

## Method 1: Copy Existing Talos Config (Recommended)

### On the current machine (this machine):

The actual talosconfig with credentials is stored separately and not in this repo for security.

```bash
# The original talosconfig is located at:
/Users/cfraser/Repos/talosctl-test/talosconfig

# Copy this file to the new machine
scp /Users/cfraser/Repos/talosctl-test/talosconfig user@new-machine:~/.talos/config
```

### On the new machine:

```bash
# Create talos config directory
mkdir -p ~/.talos

# Copy the config file (if using scp as shown above)
# Or manually create ~/.talos/config and paste the contents

# Set proper permissions
chmod 600 ~/.talos/config

# Install talosctl if not already installed
# On macOS:
brew install siderolabs/tap/talosctl

# On Linux:
curl -sL https://talos.dev/install | sh

# Test the connection
talosctl --nodes 192.168.0.249 version
```

## Method 2: Generate New Admin Config (If Original Lost)

If you don't have the original talosconfig, you'll need to regenerate it from the cluster:

```bash
# This requires the original talosconfig or access to the control plane node
# From the control plane node or a machine with access:
talosctl config merge /path/to/original/talosconfig

# Generate a new admin config
talosctl -n 192.168.0.249 config new admin-config
```

## Method 3: Use Kubernetes Service Account (Read-Only)

For read-only access, you can use a Kubernetes service account:

```bash
# This uses kubectl, not talosctl
kubectl --kubeconfig /path/to/kubeconfig get nodes
```

## Current Cluster Endpoints

- **Control Plane**: 192.168.0.249
- **Kubernetes API**: https://192.168.0.249:6443
- **Talos API**: 192.168.0.249:50000 (default)

## Environment Variable

Alternatively, you can set the TALOSCONFIG environment variable:

```bash
export TALOSCONFIG=/path/to/custom/talosconfig
talosctl version
```

## Network Requirements

Ensure the new machine can reach:
- Port 50000 (Talos API) on 192.168.0.249
- Port 50001 (Talos trustd) on 192.168.0.249
- Port 6443 (Kubernetes API) on 192.168.0.249

## Troubleshooting

### Connection Refused
```bash
# Check network connectivity
ping 192.168.0.249
nc -zv 192.168.0.249 50000
```

### Certificate Errors
Your cluster currently has a certificate key size issue. You may see:
```
x509: certificate is using a broken key size
```

This is a known issue with the current cluster configuration and may require regenerating certificates.

## Security Notes

- **Never commit** `talosconfig` to git (it contains admin credentials)
- Keep `~/.talos/config` with `600` permissions
- Consider using separate configs for different access levels
- The talosconfig is already in `.gitignore`
