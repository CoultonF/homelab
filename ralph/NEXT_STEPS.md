# 🚀 Next Steps - iCloud to Immich Migration

**Current Status**: ⚠️ BLOCKED - Awaiting Immich Installation
**Last Updated**: 2026-01-18 (Iteration 2)

---

## 📊 Quick Status

```
Progress: [████████████░░░░░░░░] 43% (4/7 iterations complete)

✅ Photo-sync infrastructure fully deployed
✅ iCloud authentication completed
✅ Monthly CronJob configured
❌ BLOCKED: Immich not installed
```

---

## ⚡ What You Need to Do NOW

### Install Immich (10 minutes)

**Copy and paste these commands**:

```bash
# Add Immich Helm repository
helm repo add immich https://immich-app.github.io/immich-charts
helm repo update

# Install Immich
kubectl create namespace immich
helm install immich immich/immich -n immich

# Wait for pods to be ready (this may take 5-10 minutes)
kubectl wait --for=condition=Ready pods --all -n immich --timeout=600s

# Verify everything is running
kubectl get pods -n immich
```

**Expected output**:
```
NAME                                    READY   STATUS    RESTARTS   AGE
immich-machine-learning-xxx             1/1     Running   0          5m
immich-microservices-xxx                1/1     Running   0          5m
immich-postgresql-xxx                   1/1     Running   0          5m
immich-redis-master-0                   1/1     Running   0          5m
immich-server-xxx                       1/1     Running   0          5m
```

All pods should show `Running` and `1/1` (or `2/2` etc.) READY.

---

## ✅ What Happens After Immich is Installed

Once Immich is running, run the **next Ralph Loop iteration** which will automatically:

### Iteration 5: Immich Integration (15 min)
- Mount icloud-photos storage to Immich
- Configure External Library in Immich
- Scan and index photos

### Iteration 6: External Exposure (10 min)
- Create ingress for immich.coultonf.com
- Configure external access
- Set up TLS (if available)

### Iteration 7: Verification (30 min)
- Test photo sync from iCloud
- Configure mobile app
- Verify end-to-end pipeline
- Document workflow

**Total**: ~55 minutes of automated work

---

## 🎯 The End Goal

When complete, you'll have:

1. **Automated Monthly Sync**
   - CronJob runs on 1st of month at 3 AM
   - Downloads photos from iCloud
   - Stores in organized folders (by year/month)

2. **Immich Photo Management**
   - Access at https://immich.coultonf.com
   - Browse and manage all photos
   - Mobile app for ongoing backups
   - External library from iCloud sync

3. **Hybrid Storage Strategy**
   - Recent photos on iCloud (with "Optimize Storage")
   - Long-term archive on self-hosted Immich
   - Monthly migration workflow

---

## 🧹 Optional Cleanup

You can clean up the auth pod that's in Error state:

```bash
kubectl delete pod icloudpd-auth -n photo-sync
```

This was a one-time authentication pod and is no longer needed.

---

## 📋 Current Infrastructure

**Everything below is already deployed and working**:

```
photo-sync namespace:
├── ✅ CronJob: icloudpd-sync
│   └── Runs: 1st of month at 3 AM MST
├── ✅ PVC: icloud-photos (100Gi)
│   └── Storage for downloaded photos
├── ✅ PVC: icloudpd-config (1Gi)
│   └── Authentication session (2FA completed)
├── ✅ Secret: icloud-credentials
│   └── Apple ID: cjrfraser@gmail.com
├── ✅ ConfigMap: icloudpd-config
│   └── Sync settings and folder structure
└── ✅ ServiceAccount: icloudpd
    └── Permissions for CronJob
```

---

## 🔍 Verify Everything is Ready

Run these commands to confirm current state:

```bash
# Check photo-sync infrastructure
kubectl get all,pvc -n photo-sync

# Check for Immich (should be empty now, will show pods after install)
kubectl get pods -n immich

# Check reference ingress pattern (for immich.coultonf.com setup)
kubectl get ingress -n mealie
```

---

## 📚 Documentation Files

All project documentation is in `/Users/cfraser/Repos/homelab/ralph/`:

- **STATUS.md** - Current status overview (read first!)
- **NEXT_STEPS.md** - This file
- **ITERATION_2_SUMMARY.md** - Detailed technical report
- **ITERATION_2_STATE.json** - Machine-readable state for next iteration

---

## 🆘 Troubleshooting

### If Helm install fails

**Check if namespace exists**:
```bash
kubectl get namespace immich
# If it exists, delete it first
kubectl delete namespace immich
# Then retry helm install
```

**Check if Helm is installed**:
```bash
helm version
# If not: brew install helm (on macOS)
```

### If pods won't start

**Check pod status**:
```bash
kubectl get pods -n immich
kubectl describe pod <pod-name> -n immich
```

**Check storage**:
```bash
kubectl get pvc -n immich
```

### If you need to start over

```bash
# Uninstall Immich
helm uninstall immich -n immich
kubectl delete namespace immich

# Wait a minute for cleanup, then reinstall
helm install immich immich/immich -n immich
```

---

## 🎉 Ready to Proceed?

**Your task**: Run the Helm commands above to install Immich

**Once done**: Run the next Ralph Loop iteration

**Estimated time to completion**:
- Install Immich: 10 min (you)
- Remaining automation: 55 min (Ralph Loop)
- **Total: 65 minutes to full system**

---

## 💡 Questions?

**Where is Immich getting the photos from?**
- The monthly CronJob downloads from iCloud to `icloud-photos` PVC
- Immich mounts this storage and indexes the photos
- You can then manually delete from iCloud after verification

**Will this delete photos from iCloud?**
- No! Auto-delete is disabled (`auto_delete: "false"`)
- You manually delete from iCloud after verifying in Immich
- This is safer and gives you control

**What about new photos?**
- The Immich iOS app will back up new photos directly
- The monthly CronJob catches anything missed
- You'll have both real-time and batch backup

**Can I change the schedule?**
- Yes! Edit the CronJob: `kubectl edit cronjob icloudpd-sync -n photo-sync`
- Change the schedule line: `0 3 1 * *` (cron syntax)

---

**Last Updated**: 2026-01-18
**Next Action**: Install Immich (see commands above)
**Then**: Run next Ralph Loop iteration

=== READY TO PROCEED ===
