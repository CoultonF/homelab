# Quick Start - Complete Your Photo Migration Setup

**Estimated Time**: 15 minutes total
**Current Status**: Infrastructure deployed, waiting for 2 manual steps

---

## ✋ Step 1: Complete iCloud Authentication (5 min)

The authentication pod is running and waiting for your input.

### Commands

```bash
# 1. Attach to the authentication pod
kubectl attach -it icloudpd-auth -n photo-sync
```

### What You'll See

```
Processing user: cjrfraser@gmail.com
Authenticating...
Enter iCloud password for cjrfraser@gmail.com:
```

**Type your Apple ID password** and press Enter.

```
Two-factor authentication required.
Enter code:
```

**Type the 6-digit 2FA code** from your trusted device and press Enter.

```
Authentication successful!
```

### Verify It Worked

```bash
# Check that session files were created
kubectl exec -n photo-sync icloudpd-auth -- ls -la /config/

# You should see files (not an empty directory)
```

### Clean Up

```bash
# Delete the auth pod (session is saved in PVC)
kubectl delete pod icloudpd-auth -n photo-sync
```

✅ **Authentication Complete!**

---

## ✋ Step 2: Install Immich (10 min)

### Commands

```bash
# Add Immich Helm repository
helm repo add immich https://immich-app.github.io/immich-charts
helm repo update

# Create namespace and install
kubectl create namespace immich
helm install immich immich/immich -n immich

# Wait for all pods to be ready (may take 5-10 minutes)
kubectl wait --for=condition=Ready pods --all -n immich --timeout=600s
```

### Verify It Worked

```bash
# Check all pods are running
kubectl get pods -n immich
```

**Expected Output**: All pods should show `Running` and `1/1` READY

```
NAME                                    READY   STATUS    RESTARTS   AGE
immich-machine-learning-xxx             1/1     Running   0          5m
immich-microservices-xxx                1/1     Running   0          5m
immich-postgresql-xxx                   1/1     Running   0          5m
immich-redis-master-0                   1/1     Running   0          5m
immich-server-xxx                       1/1     Running   0          5m
```

✅ **Immich Installed!**

---

## 🚀 Step 3: Run Next Iteration

Once both steps above are complete, run the next Ralph Loop iteration.

The automation will:
1. ✅ Mount iCloud photos to Immich
2. ✅ Configure External Library
3. ✅ Set up https://immich.coultonf.com
4. ✅ Verify end-to-end pipeline
5. ✅ Document iOS app setup

**Time**: ~55 minutes (fully automated)

---

## 🆘 Troubleshooting

### Authentication Issues

**"Pod not found"**
```bash
# Check if pod exists
kubectl get pods -n photo-sync

# If deleted, recreate it
kubectl apply -f /Users/cfraser/Repos/homelab/ralph/photo-sync/auth-pod.yaml
```

**"Connection lost" during auth**
```bash
# Reattach to the pod
kubectl attach -it icloudpd-auth -n photo-sync
```

**"Invalid password/code"**
- Re-enter when prompted
- Make sure you're using your Apple ID password (not device passcode)
- 2FA code expires quickly - request a new one if needed

### Immich Installation Issues

**"Helm not found"**
```bash
# Install Helm (macOS)
brew install helm

# Or see: https://helm.sh/docs/intro/install/
```

**Pods stuck in "Pending" or "CrashLoopBackOff"**
```bash
# Check pod details
kubectl describe pod <pod-name> -n immich

# Check pod logs
kubectl logs <pod-name> -n immich
```

**Need to start over?**
```bash
# Uninstall and retry
helm uninstall immich -n immich
kubectl delete namespace immich

# Wait 30 seconds, then reinstall
kubectl create namespace immich
helm install immich immich/immich -n immich
```

---

## ✅ Checklist

- [ ] Complete iCloud authentication (Step 1)
- [ ] Verify session files created
- [ ] Delete auth pod
- [ ] Install Immich (Step 2)
- [ ] Verify all Immich pods running
- [ ] Run next Ralph Loop iteration

---

## 📊 What You've Built So Far

```
✅ Namespace and storage infrastructure
✅ iCloud credentials configured (cjrfraser@gmail.com)
✅ Monthly sync CronJob (1st of month at 3 AM)
✅ 100Gi storage for photos
⚠️  iCloud authentication (you're doing this now)
⚠️  Immich installation (next step)

Still to come (automated):
🚫 Immich integration
🚫 External access at immich.coultonf.com
🚫 End-to-end verification
```

---

## 📞 Need Help?

Refer to:
- **STATUS.md** - Current status overview
- **ITERATION_3_STATUS.md** - Detailed technical findings
- **ITERATION_3_SUMMARY.md** - Complete iteration report

---

**Ready?** Start with Step 1 above! ⬆️
