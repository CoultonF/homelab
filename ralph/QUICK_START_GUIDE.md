# iCloud to Immich Migration - Quick Start Guide

## Current Status: 90% Complete ✅

**What's Done**:
- ✅ All infrastructure deployed and operational
- ✅ iCloud authentication complete (valid for ~90 days)
- ✅ CronJob scheduled for monthly syncs (next: Feb 1, 2026)
- ✅ Immich running with iCloud mount at `/external/icloud`
- ✅ Ingress created for external access

**What You Need to Do**: 7 configuration steps (~65 minutes)

---

## Quick Start: 7 Steps to Activate

### Step 1: Configure DNS (5 minutes) 🔴 REQUIRED

**Option A: Cloudflare Tunnel** (Recommended - matches your mealie setup)
1. Access Cloudflare Tunnel dashboard
2. Add public hostname: `immich.coultonf.com`
3. Point to: `http://immich-server.immich.svc.cluster.local:3001`

**Option B: DNS Record**
1. Open Cloudflare DNS settings
2. Add A/CNAME record: `immich.coultonf.com`
3. Point to same IP as `mealie.coultonf.com`

**Verify**:
```bash
dig immich.coultonf.com
curl -I https://immich.coultonf.com
```

---

### Step 2: Setup Immich (10 minutes) 🔴 REQUIRED

1. Open: https://immich.coultonf.com
2. Create admin account
3. Set server URL: `https://immich.coultonf.com`
4. Set timezone: `America/Edmonton`
5. Complete onboarding

---

### Step 3: Configure External Library (5 minutes) 🔴 REQUIRED

1. Navigate to: **Administration → Libraries → External Libraries**
2. Click **"Create Library"**
3. Settings:
   - Name: `iCloud Photos`
   - Import Path: `/external/icloud/icloud-import`
   - ✅ Watch for new files
   - ✅ Scan on startup
4. Save

---

### Step 4: Trigger First Sync (30 minutes) 🔴 REQUIRED

**Run manual test sync**:
```bash
kubectl create job --from=cronjob/icloudpd-sync -n photo-sync manual-sync-$(date +%s)
```

**Watch progress**:
```bash
# List jobs
kubectl get jobs -n photo-sync -w

# View logs (replace <job-name> with actual name from above)
kubectl logs -f -n photo-sync job/<job-name>
```

**Verify photos downloaded**:
```bash
kubectl exec -n photo-sync icloudpd-auth -- find /photos/icloud-import -type f | head -20
```

---

### Step 5: Scan Library in Immich (5 minutes) 🔴 REQUIRED

1. In Immich UI: **Administration → Libraries**
2. Select **iCloud Photos**
3. Click **"Scan Library Files"**
4. Wait for scan to complete
5. Verify photos appear in timeline

---

### Step 6: Configure Mobile App (10 minutes) 🟡 OPTIONAL

1. Install Immich app from App Store / Google Play
2. Server URL: `https://immich.coultonf.com`
3. Log in
4. Enable Background Backup
5. Grant photo library access (Always)
6. Test upload

---

### Step 7: Cleanup Auth Pod (1 minute) 🟡 OPTIONAL

After first sync succeeds:
```bash
kubectl delete pod -n photo-sync icloudpd-auth
```

---

## After Setup: How It Works

### Automated Monthly Sync
```
1st of each month, 3:00 AM MST:
  └─ icloudpd downloads new photos from iCloud
  └─ Immich External Library scans for new photos
  └─ Photos appear in Immich automatically
```

### Manual iCloud Cleanup (As Needed)
Once photos are in Immich:
1. Open iCloud.com or Photos app on Mac
2. Select old photos by date
3. Delete from iCloud
4. Empty "Recently Deleted" to free space

### Ongoing Mobile Backups
- New iPhone photos → Immich (via mobile app)
- iCloud "Optimize iPhone Storage" keeps recent photos
- Monthly sync captures anything missed

---

## Health Checks

### Check Last Sync
```bash
# View recent jobs
kubectl get jobs -n photo-sync --sort-by=.metadata.creationTimestamp | tail -2

# View logs
LAST_JOB=$(kubectl get jobs -n photo-sync -o jsonpath='{.items[-1].metadata.name}')
kubectl logs -n photo-sync job/$LAST_JOB --tail=50
```

### Check Photo Count
```bash
kubectl exec -n photo-sync icloudpd-auth -- find /photos/icloud-import -type f | wc -l
```

### Verify Immich Access
```bash
curl -I https://immich.coultonf.com
```

---

## Troubleshooting

### DNS Not Working
```bash
# Test internal access first
kubectl port-forward -n immich svc/immich-server 3001:3001
# Open http://localhost:3001

# Check ingress
kubectl get ingress -n immich
kubectl describe ingress -n immich immich-ingress

# Compare with working mealie
kubectl get ingress -A | grep mealie
```

### Sync Not Running
```bash
# Check CronJob
kubectl get cronjob -n photo-sync

# Check authentication
kubectl exec -n photo-sync icloudpd-auth -- ls -la /config/
# Should see: cjrfrasergmailcom and cjrfrasergmailcom.session

# If expired: Re-run authentication
kubectl apply -f /Users/cfraser/Repos/homelab/apps/photo-sync/auth-pod.yaml
kubectl attach -it icloudpd-auth -n photo-sync
# Enter 2FA code
```

### Photos Not Appearing
```bash
# Verify mount in Immich
kubectl exec -n immich deployment/immich-server -- ls -la /external/icloud/icloud-import

# Manual scan in Immich UI
# Administration → Libraries → iCloud Photos → Scan
```

---

## Re-authentication (Every ~90 days)

When 2FA expires (sync jobs start failing):

```bash
# 1. Deploy auth pod
kubectl apply -f /Users/cfraser/Repos/homelab/apps/photo-sync/auth-pod.yaml

# 2. Attach and complete 2FA
kubectl attach -it icloudpd-auth -n photo-sync
# Enter Apple ID password
# Enter 2FA code from trusted device

# 3. Delete auth pod
kubectl delete pod icloudpd-auth -n photo-sync
```

---

## Quick Reference

### Important Files
- Full docs: `/Users/cfraser/Repos/homelab/ralph/ITERATION_7_COMPLETE.md`
- Config files: `/Users/cfraser/Repos/homelab/apps/photo-sync/`
- Immich config: `/Users/cfraser/Repos/homelab/apps/immich/`

### Key Resources
```bash
# Photo sync namespace
kubectl get all -n photo-sync

# Immich namespace
kubectl get all -n immich

# CronJob schedule
kubectl get cronjob -n photo-sync icloudpd-sync

# Trigger manual sync
kubectl create job --from=cronjob/icloudpd-sync -n photo-sync manual-sync-$(date +%s)
```

### Next Scheduled Sync
**February 1, 2026 at 3:00 AM MST**

---

## Support

For detailed troubleshooting, architecture, and security information:
- Read: `/Users/cfraser/Repos/homelab/ralph/ITERATION_7_COMPLETE.md`
- Check: Previous iteration docs (ITERATION_5_COMPLETE.md, ITERATION_6_COMPLETE.md)

---

**Last Updated**: 2026-01-18 13:15 MST
**System Status**: Infrastructure deployed ✅ | User configuration pending ⏳
