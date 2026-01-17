# Admin Pod

SSH-accessible container for managing the homelab cluster remotely. This pod provides a secure environment to clone the homelab repo, make changes, and push them back to trigger ArgoCD syncs.

## Features

- **SSH Access**: Connect via SSH on NodePort 30022
- **Dev Tools**: Pre-installed git, kubectl, vim, nano, curl, wget
- **Cluster Admin**: Full RBAC permissions to manage the cluster
- **GitOps Ready**: Clone the homelab repo, make changes, push to trigger ArgoCD syncs

## Initial Setup

### 1. Add Your SSH Public Key

Edit the secret file to add your SSH public key:

```bash
# Generate an SSH key if you don't have one
ssh-keygen -t ed25519 -C "your-email@example.com"

# Copy your public key
cat ~/.ssh/id_ed25519.pub
```

Edit `apps/admin-pod/ssh-keys.secret.yaml` and paste your public key:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: admin-pod-ssh-keys
  namespace: admin-pod
type: Opaque
stringData:
  authorized_keys: |
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... your-email@example.com
```

### 2. Apply the Secret to the Cluster

The secret file is excluded from git (via `.gitignore`), so you need to apply it manually:

```bash
kubectl apply -f apps/admin-pod/ssh-keys.secret.yaml
```

### 3. Deploy via ArgoCD

Commit and push the other manifests:

```bash
git add bootstrap/argocd-apps/admin-pod.yaml apps/admin-pod/
git commit -m "Add admin-pod for SSH cluster access"
git push
```

ArgoCD will automatically:
- Create the `admin-pod` namespace
- Deploy the SSH server
- Create the Service on NodePort 30022
- Set up RBAC permissions

### 4. Wait for the Pod to be Ready

```bash
kubectl get pods -n admin-pod -w
```

Wait until the pod shows `1/1 Running`.

## Connecting to the Admin Pod

### Find Your Node IP

```bash
# List your nodes
kubectl get nodes -o wide

# Or get the first node's IP
kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'
```

### SSH Into the Pod

```bash
ssh -p 30022 root@<NODE-IP>
```

Example:
```bash
ssh -p 30022 root@192.168.1.100
```

## Using the Admin Pod

Once inside the pod, you can manage your cluster:

### Clone the Homelab Repo

```bash
# Configure git
git config --global user.name "Your Name"
git config --global user.email "your-email@example.com"

# Clone the repo (you'll need to set up git credentials)
cd ~
git clone https://github.com/CoultonF/homelab.git
cd homelab
```

### Configure Git Authentication

For pushing changes, you have several options:

**Option 1: Personal Access Token (Recommended)**
```bash
# GitHub personal access token
git remote set-url origin https://<YOUR-TOKEN>@github.com/CoultonF/homelab.git
```

**Option 2: SSH Key**
```bash
# Generate SSH key inside the pod
ssh-keygen -t ed25519 -C "admin-pod@homelab"
cat ~/.ssh/id_ed25519.pub
# Add the public key to your GitHub account
# Change remote to SSH
git remote set-url origin git@github.com:CoultonF/homelab.git
```

### Make Changes and Push

```bash
# Make changes to your manifests
vim apps/someapp/deployment.yaml

# Commit and push
git add .
git commit -m "Update deployment configuration"
git push

# ArgoCD will automatically sync the changes!
```

### Use kubectl

The pod has cluster-admin access:

```bash
# View all pods
kubectl get pods -A

# Check ArgoCD applications
kubectl get applications -n argocd

# View logs
kubectl logs -n somenamespace somepod

# Execute commands in other pods
kubectl exec -it -n somenamespace somepod -- /bin/bash
```

## Troubleshooting

### Can't SSH into the pod

1. Check if the pod is running:
   ```bash
   kubectl get pods -n admin-pod
   ```

2. Check if the service is created:
   ```bash
   kubectl get svc -n admin-pod
   ```

3. Check pod logs:
   ```bash
   kubectl logs -n admin-pod -l app=admin-pod
   ```

4. Verify the secret exists:
   ```bash
   kubectl get secret -n admin-pod admin-pod-ssh-keys
   ```

5. Test from another pod first:
   ```bash
   kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- ssh -p 22 root@admin-pod-ssh.admin-pod.svc.cluster.local
   ```

### SSH Key Permission Denied

Make sure your public key is correctly added to `ssh-keys.secret.yaml` and applied:

```bash
kubectl delete secret -n admin-pod admin-pod-ssh-keys
kubectl apply -f apps/admin-pod/ssh-keys.secret.yaml
kubectl rollout restart deployment -n admin-pod admin-pod
```

### Pod Crashes on Startup

Check logs:
```bash
kubectl logs -n admin-pod -l app=admin-pod --previous
```

### Git Push Authentication Fails

You need to configure git credentials inside the pod (see "Configure Git Authentication" above).

## Security Considerations

- **Cluster Admin Access**: This pod has full cluster-admin RBAC permissions. Protect your SSH keys!
- **SSH Key Only**: Password authentication is disabled. Only SSH key authentication is allowed.
- **NodePort Exposure**: Port 30022 is exposed on all nodes. Consider firewall rules if needed.
- **Secret Management**: The SSH keys secret is excluded from git. Don't commit it!

## GitOps Workflow

The typical workflow is:

1. **SSH into admin-pod** → `ssh -p 30022 root@<node-ip>`
2. **Make changes** → Edit files in the cloned repo
3. **Commit & push** → `git add . && git commit -m "..." && git push`
4. **ArgoCD syncs** → Changes automatically applied to cluster
5. **Verify** → `kubectl get ...` to verify changes

This creates a full GitOps loop where all cluster changes flow through git!
