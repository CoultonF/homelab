# ⚠️ USER ACTION REQUIRED

**Date**: 2026-01-18
**Status**: Deployment Blocked - Awaiting User Action

---

## 🎯 Quick Summary

The **photo-sync infrastructure is 100% deployed** and ready to sync your iCloud photos. However, before we can complete the integration, you need to:

1. **Install Immich** on your cluster (CRITICAL - blocks Iterations 5-7)
2. **Complete 2FA Authentication** for iCloud (5 minutes, can be done in parallel)

---

## 🚨 Critical: Install Immich

### Why This Blocks Progress

Iterations 5, 6, and 7 require Immich to be installed and running:
- **Iteration 5**: Mount icloud-photos PVC to Immich
- **Iteration 6**: Expose Immich at immich.coultonf.com
- **Iteration 7**: Verify photos flow from iCloud → Immich

**Current Status**: No Immich installation detected on cluster.

### Option 1: Quick Install with Helm (Recommended)

```bash
# Add Immich Helm repository
helm repo add immich https://immich-app.github.io/immich-charts
helm repo update

# Create namespace
kubectl create namespace immich

# Install with default values
helm install immich immich/immich -n immich

# Or install with custom storage size
helm install immich immich/immich -n immich \
  --set image.tag=latest \
  --set persistence.library.size=500Gi
```

### Option 2: Manual Deployment

Follow the official Kubernetes installation guide:
https://immich.app/docs/install/kubernetes

### Option 3: Use Existing Immich

If you already have Immich running elsewhere:
1. Install it on this cluster in a namespace (any name works)
2. Note the namespace, service name, and port
3. Continue to Iteration 5

### Verification

```bash
# Check if Immich is installed
kubectl get deployments -A | grep immich

# Check Immich service
kubectl get svc -A | grep immich

# Check Immich pods are running
kubectl get pods -A | grep immich
```

**When you see Immich pods running, you're ready to continue!**

---

## ⚠️ Required: Complete iCloud Authentication

### Why This Is Needed

The icloudpd CronJob needs a valid session with Apple to download photos. This requires:
- Your Apple ID password
- 2FA code from your trusted device
- ~5 minutes of your time

**Current Status**: Infrastructure ready, waiting for interactive 2FA session.

### How to Complete (5 Minutes)

#### Step 1: Deploy Authentication Pod
```bash
kubectl apply -f /Users/cfraser/Repos/homelab/ralph/photo-sync/auth-pod.yaml
```

#### Step 2: Wait for Pod to Start
```bash
kubectl wait --for=condition=Ready pod/icloudpd-auth -n photo-sync --timeout=120s
```

#### Step 3: Attach to Pod and Authenticate
```bash
kubectl attach -it icloudpd-auth -n photo-sync
```

You'll see prompts like:
```
2-factor authentication is required
Please enter validation code:
```

1. Enter your **Apple ID password** when prompted
2. Check your trusted Apple device for the **6-digit 2FA code**
3. Enter the **2FA code**
4. Wait for **"Authentication successful"** message
5. Press `Ctrl+C` to detach (or wait for timeout)

#### Step 4: Cleanup
```bash
kubectl delete pod icloudpd-auth -n photo-sync
```

#### Step 5: Verify Session Was Saved
```bash
kubectl get pvc -n photo-sync icloudpd-config
# Should show STATUS: Bound (authentication pod created a file)
```

### Full Detailed Guide

See: `/Users/cfraser/Repos/homelab/ralph/photo-sync/ITERATION_3_MANUAL_STEPS.md`

### Troubleshooting

**Pod stays in ContainerCreating**: The PVC is waiting to bind. This is normal with `local-path` storage - it will bind when the pod starts.

**Authentication fails**:
- Verify Apple ID email: `kubectl get secret -n photo-sync icloud-credentials -o jsonpath='{.data.username}' | base64 -d`
- Try again with fresh pod: `kubectl delete pod icloudpd-auth -n photo-sync && kubectl apply -f auth-pod.yaml`

**Session expires**: Sessions last ~90 days. Re-run this process if syncs start failing with auth errors.

---

## 📋 Recommended Action Plan

### Path A: Do Both in Parallel (Fastest)

```bash
# Terminal 1: Install Immich
helm repo add immich https://immich-app.github.io/immich-charts
helm install immich immich/immich -n immich

# Terminal 2: Authenticate with iCloud
kubectl apply -f /Users/cfraser/Repos/homelab/ralph/photo-sync/auth-pod.yaml
kubectl attach -it icloudpd-auth -n photo-sync
# [Complete 2FA]
kubectl delete pod icloudpd-auth -n photo-sync
```

**Time**: ~10 minutes total

### Path B: Install Immich First

If you want to focus on one thing at a time:
1. Install Immich (5-10 minutes)
2. Verify it works
3. Complete authentication (5 minutes)
4. Continue to Iteration 5

### Path C: Authenticate First

If Immich installation will take time to plan:
1. Complete authentication now (5 minutes)
2. Install Immich when ready
3. Continue to Iteration 5

---

## ✅ After Completing These Steps

Once both are done, run:

```bash
# Verify everything is ready
/Users/cfraser/Repos/homelab/ralph/photo-sync/verify-ready-for-iteration5.sh
```

Or manually check:

```bash
# 1. Immich is installed
kubectl get deployments -A | grep immich

# 2. Authentication completed
kubectl get pvc -n photo-sync icloudpd-config
# Should show STATUS: Bound

# 3. Photo sync infrastructure ready
kubectl get cronjob -n photo-sync icloudpd-sync
# Should show SCHEDULE: 0 3 1 * *
```

**When all three checks pass**, continue to **Iteration 5**: Immich Integration.

---

## 📖 What Happens Next

### Iteration 5: Immich Integration
- Mount icloud-photos PVC to Immich server
- Configure Immich External Library
- Point it to `/external/icloud/icloud-import`

### Iteration 6: External Access
- Create ingress for immich.coultonf.com
- Follow the mealie.coultonf.com pattern
- Access Immich from anywhere

### Iteration 7: Verification & Testing
- Trigger test sync job
- Verify photos appear in Immich
- Document workflow for monthly cleanup
- Configure Immich iOS app for ongoing backups

---

## 📁 Documentation Available

All guides are in `/Users/cfraser/Repos/homelab/ralph/photo-sync/`:

| File | Purpose |
|------|---------|
| `README.md` | Overview and quick status |
| `ITERATION_3_MANUAL_STEPS.md` | Detailed authentication guide |
| `ITERATION_5_STATUS.md` | Current blocker analysis |
| `REMAINING_ITERATIONS_GUIDE.md` | Complete plan for Iterations 5-7 |
| `reference-mealie-ingress.yaml` | Template for Iteration 6 |

---

## ❓ Questions?

**Q: Can I skip the authentication for now?**
A: Yes! The auth can wait. But the CronJob won't run successfully until it's done. It's quick though (5 minutes).

**Q: Do I need to install Immich on this specific cluster?**
A: Yes. The photo-sync infrastructure will mount the icloud-photos PVC to Immich pods, so they must be on the same cluster.

**Q: Can I use an existing Immich instance?**
A: If it's running on this cluster, yes! Just note the namespace and service name. If it's on a different cluster, you'll need to install Immich here or set up network storage sharing (more complex).

**Q: What if I want to change the storage size?**
A: Edit the PVCs before they bind:
```bash
kubectl edit pvc icloud-photos -n photo-sync
# Change storage: 100Gi to desired size
```

**Q: How much storage do I need?**
A: Check your iCloud library size and add buffer. For example:
- iCloud library: 80GB → Request 100-150Gi
- iCloud library: 200GB → Request 250-300Gi
- For Immich library storage, match or exceed iCloud size

---

## 🚀 Ready to Continue?

1. ✅ Install Immich
2. ✅ Complete authentication
3. ✅ Run verification checks
4. ✅ Continue to Iteration 5

**Let me know when you're ready, and we'll continue the deployment!**

---

**Last Updated**: 2026-01-18
**Current Iteration**: 5 (Blocked)
**Next Iteration**: 5 (when unblocked)
