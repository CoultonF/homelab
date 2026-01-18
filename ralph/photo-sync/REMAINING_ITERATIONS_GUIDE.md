# Remaining Iterations Guide (5-7)

## Overview

This document outlines the remaining iterations needed to complete the iCloud to Immich photo migration system.

**Current Status**: Iteration 4 complete (CronJob deployed)
**Remaining**: Iterations 5, 6, 7

---

## Iteration 5: Immich External Library Integration

### Objective
Mount the `icloud-photos` PVC to the Immich server and configure External Library scanning.

### Prerequisites
- ✅ Iteration 3 authentication completed
- ✅ Test sync successful (photos downloaded to PVC)
- 🔍 Immich already deployed in the cluster (need to identify namespace)

### Discovery Commands

```bash
# Find Immich namespace
kubectl get namespaces | grep -i immich
kubectl get deployments -A | grep -i immich

# Identify Immich deployment and service
kubectl get deployment -n <IMMICH_NAMESPACE>
kubectl get svc -n <IMMICH_NAMESPACE>

# Check if Immich is using Helm
helm list -A | grep -i immich
```

### Implementation Steps

#### Option A: Patch Existing Deployment (if not using Helm)

1. **Create cross-namespace access** (if needed)
   ```bash
   # Note: PVCs can typically only be mounted in the same namespace
   # Option 1: Mount in same namespace (photo-sync)
   # Option 2: Create PVC in immich namespace that uses same underlying volume
   # Option 3: Use NFS/shared storage
   ```

2. **Patch Immich server deployment**
   ```bash
   kubectl patch deployment immich-server -n <IMMICH_NAMESPACE> --type='json' -p='[
     {
       "op": "add",
       "path": "/spec/template/spec/volumes/-",
       "value": {
         "name": "icloud-import",
         "persistentVolumeClaim": {
           "claimName": "icloud-photos"
         }
       }
     },
     {
       "op": "add",
       "path": "/spec/template/spec/containers/0/volumeMounts/-",
       "value": {
         "name": "icloud-import",
         "mountPath": "/external/icloud",
         "readOnly": true
       }
     }
   ]'
   ```

#### Option B: Helm Values (if using Helm)

Create or update `immich-values.yaml`:
```yaml
immich:
  server:
    persistence:
      external:
        enabled: true
        existingClaim: icloud-photos
        mountPath: /external/icloud
        readOnly: true
```

Apply:
```bash
helm upgrade immich <chart> -n <IMMICH_NAMESPACE> -f immich-values.yaml
```

#### Option C: Create PVC in Immich Namespace (Recommended)

If cross-namespace PVC mounting is an issue:

```yaml
# File: immich-icloud-pvc.yaml (create in immich namespace)
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: icloud-photos-immich
  namespace: <IMMICH_NAMESPACE>
spec:
  accessModes:
    - ReadOnlyMany  # Or ReadWriteMany
  resources:
    requests:
      storage: 100Gi
  storageClassName: local-path
  # If using NFS or shared storage, configure accordingly
```

3. **Configure External Library in Immich UI**
   - Navigate to Immich web interface
   - Go to: Administration → Libraries → External Libraries
   - Click "Create External Library"
   - Settings:
     - Name: `iCloud Import`
     - Import Path: `/external/icloud/icloud-import`
     - Scan Schedule: `0 4 1 * *` (4 AM on 1st, after sync completes)
     - Enable "Watch for new files"
   - Save

4. **Trigger initial scan**
   - In Immich UI: Libraries → iCloud Import → Scan Now
   - Or via CLI (if available)

5. **Verify mount**
   ```bash
   kubectl exec -n <IMMICH_NAMESPACE> deployment/immich-server -- ls -la /external/icloud/
   kubectl exec -n <IMMICH_NAMESPACE> deployment/immich-server -- find /external/icloud/icloud-import -type f | head -20
   ```

### Completion Criteria
- ✅ PVC mounted in Immich server pod
- ✅ External Library configured
- ✅ Photos visible in Immich UI
- ✅ Automatic scanning enabled

---

## Iteration 6: External Network Exposure

### Objective
Expose Immich at `https://immich.coultonf.com` using Ingress (following the mealie.coultonf.com pattern).

### Prerequisites
- 🔍 Need to identify existing ingress configuration (mealie reference)
- 🔍 Identify ingress controller (Traefik, NGINX, etc.)
- 🔍 Identify cert-manager setup

### Discovery Commands

```bash
# Find mealie ingress for reference
kubectl get ingress -A | grep mealie
kubectl get ingress -n <MEALIE_NAMESPACE> <MEALIE_INGRESS_NAME> -o yaml > /tmp/mealie-ingress.yaml

# Check ingress controller
kubectl get ingressclass
kubectl get pods -A | grep -E 'traefik|nginx|ingress'

# Check cert-manager
kubectl get clusterissuer
kubectl get certificate -A
```

### Implementation Steps

1. **Analyze mealie ingress pattern**
   ```bash
   # Review mealie ingress configuration
   cat /tmp/mealie-ingress.yaml

   # Note:
   # - Ingress class name
   # - TLS configuration
   # - Annotations used
   # - Service backend name and port
   ```

2. **Verify Immich service**
   ```bash
   kubectl get svc -n <IMMICH_NAMESPACE> | grep immich
   # Note the service name and port (usually 3001 or 2283)
   ```

3. **Create Immich ingress** (template - adjust based on mealie pattern)

   ```yaml
   # File: immich-ingress.yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: immich
     namespace: <IMMICH_NAMESPACE>
     annotations:
       cert-manager.io/cluster-issuer: <CLUSTER_ISSUER>  # e.g., letsencrypt-prod
       # Copy other annotations from mealie ingress
       # For NGINX:
       # nginx.ingress.kubernetes.io/proxy-body-size: "0"
       # nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
       # For Traefik:
       # traefik.ingress.kubernetes.io/router.entrypoints: websecure
   spec:
     ingressClassName: <INGRESS_CLASS>  # e.g., traefik, nginx
     tls:
       - hosts:
           - immich.coultonf.com
         secretName: immich-tls
     rules:
       - host: immich.coultonf.com
         http:
           paths:
             - path: /
               pathType: Prefix
               backend:
                 service:
                   name: <IMMICH_SERVICE_NAME>  # e.g., immich-server
                   port:
                     number: <PORT>  # e.g., 3001 or 2283
   ```

4. **Apply ingress**
   ```bash
   kubectl apply -f immich-ingress.yaml
   ```

5. **Wait for TLS certificate**
   ```bash
   kubectl get certificate -n <IMMICH_NAMESPACE> immich-tls -w
   # Wait for READY: True
   ```

6. **Update DNS**
   ```bash
   # Check mealie DNS for reference
   dig mealie.coultonf.com

   # Ensure immich.coultonf.com points to same IP
   # (May be automatic if using wildcard DNS *.coultonf.com)
   ```

7. **Test external access**
   ```bash
   curl -I https://immich.coultonf.com
   # Should return 200 or 302 redirect to login

   # Test in browser
   open https://immich.coultonf.com
   ```

8. **Configure Immich external URL** (in Immich settings)
   - Administration → Server Settings → External Domain
   - Set to: `https://immich.coultonf.com`

### Completion Criteria
- ✅ Ingress created and healthy
- ✅ TLS certificate issued
- ✅ DNS resolves correctly
- ✅ https://immich.coultonf.com accessible externally
- ✅ Immich configured with external URL

---

## Iteration 7: Verification and Documentation

### Objective
End-to-end verification and workflow documentation.

### Tasks

#### 1. Test Manual Sync

```bash
# Trigger test job from CronJob
kubectl create job --from=cronjob/icloudpd-sync -n photo-sync manual-test-$(date +%s)

# Watch logs
kubectl logs -f -n photo-sync job/manual-test-xxxxx

# Verify success
kubectl get jobs -n photo-sync
```

#### 2. Verify Photos Downloaded

```bash
# Check photo count
kubectl exec -n photo-sync job/manual-test-xxxxx -- find /photos/icloud-import -type f | wc -l

# List recent files
kubectl exec -n photo-sync job/manual-test-xxxxx -- ls -lh /photos/icloud-import/$(date +%Y/%m)/ | head -20
```

#### 3. Verify Photos in Immich

```bash
# Check mount in Immich
kubectl exec -n <IMMICH_NAMESPACE> deployment/immich-server -- find /external/icloud -type f | head -20

# Via UI
open https://immich.coultonf.com
# Navigate to Libraries → iCloud Import
# Verify photo count and metadata
```

#### 4. Setup Immich Mobile App

- Install Immich app from App Store (iOS) or Play Store (Android)
- Server URL: `https://immich.coultonf.com`
- Log in with Immich credentials
- Settings → Backup:
  - Enable "Background Backup"
  - Grant full photo library access
  - Grant location permission (set to "Always")
  - Enable "Backup automatically"
- Test manual backup of a few photos

#### 5. Document Hybrid Workflow

Create user documentation for the ongoing monthly process.

#### 6. Create Verification Script (Optional)

```bash
#!/bin/bash
# File: verify-photo-sync.sh

echo "=== iCloud to Immich Sync Status ==="
echo ""

echo "📅 Last CronJob Run:"
kubectl get jobs -n photo-sync --sort-by=.metadata.creationTimestamp | tail -2
echo ""

echo "📊 Photo Statistics:"
echo -n "Photos in PVC: "
kubectl exec -n photo-sync deployment/... -- find /photos/icloud-import -type f | wc -l
echo ""

echo "🔍 Recent Sync Logs (last 30 lines):"
LAST_JOB=$(kubectl get jobs -n photo-sync -o jsonpath='{.items[-1].metadata.name}')
kubectl logs -n photo-sync job/$LAST_JOB --tail=30
echo ""

echo "🌐 External Access Check:"
curl -sI https://immich.coultonf.com | head -5
echo ""

echo "✅ Immich External Library:"
kubectl exec -n <IMMICH_NAMESPACE> deployment/immich-server -- ls /external/icloud/icloud-import
```

#### 7. Final Documentation

Create `WORKFLOW_GUIDE.md`:

```markdown
# iCloud to Immich Monthly Workflow

## Automated Monthly Sync

**Schedule**: 3 AM on the 1st of each month (America/Los_Angeles timezone)

**What Happens Automatically:**
1. icloudpd CronJob downloads new photos from iCloud to PVC
2. Photos organized by year/month (e.g., `/2025/01/`)
3. Immich External Library scans for new photos at 4 AM
4. Photos indexed and available in Immich

## Manual Steps (Monthly)

### 1. Verify Sync Success

```bash
# Check last job status
kubectl get jobs -n photo-sync --sort-by=.metadata.creationTimestamp | tail -1

# View logs if needed
kubectl logs -n photo-sync job/<job-name>
```

Or use verification script:
```bash
./verify-photo-sync.sh
```

### 2. Review Photos in Immich

- Open https://immich.coultonf.com
- Navigate to Libraries → iCloud Import
- Verify new photos appear with correct dates/metadata

### 3. Delete Verified Photos from iCloud

**⚠️ IMPORTANT: Only delete photos that are successfully in Immich!**

**Option A: Via iCloud.com**
1. Go to https://icloud.com/photos
2. Select photos by date range (e.g., all from previous month)
3. Click Delete
4. Empty "Recently Deleted" album after 30 days (or immediately if confident)

**Option B: Via Photos app on Mac**
1. Open Photos app
2. Filter by "iCloud Photos"
3. Select photos older than current month
4. Right-click → Delete
5. Photos → Recently Deleted → Delete All

### 4. Monitor Storage

```bash
# Check PVC usage
kubectl get pvc -n photo-sync icloud-photos
```

## Ongoing Mobile Backup

**Via Immich iOS App:**
- New photos automatically back up to Immich via app
- Background backup triggers when:
  - Significant location change
  - Daily at configured time
  - Manual trigger

**Hybrid Strategy:**
- iCloud keeps recent ~3 months (with "Optimize iPhone Storage")
- Monthly sync archives older photos to Immich
- Manual deletion from iCloud frees space
- Long-term archive in Immich

## Troubleshooting

### Sync Failed
```bash
# Check logs
kubectl logs -n photo-sync job/<latest-job>

# Common issues:
# - Auth expired: Re-run Iteration 3 authentication
# - Network timeout: Check cluster internet access
# - Storage full: Expand PVC
```

### Photos Not in Immich
- Check External Library scan status in Immich UI
- Manually trigger scan: Libraries → Scan
- Verify mount: `kubectl exec ... -- ls /external/icloud`

### Re-authentication Needed (~every 90 days)
```bash
cd /Users/cfraser/Repos/homelab/ralph/photo-sync
kubectl apply -f auth-pod.yaml
kubectl attach -it icloudpd-auth -n photo-sync
# Follow 2FA prompts
kubectl delete pod icloudpd-auth -n photo-sync
```

## Maintenance

### Update icloudpd Container
```bash
kubectl set image cronjob/icloudpd-sync -n photo-sync \
  icloudpd=boredazfcuk/icloudpd:latest
```

### Change Sync Schedule
```bash
kubectl edit cronjob icloudpd-sync -n photo-sync
# Modify .spec.schedule (cron format)
```

### Expand Storage
```bash
kubectl edit pvc icloud-photos -n photo-sync
# Increase .spec.resources.requests.storage
# (Note: storageClass must support expansion)
```
```

### Completion Criteria
- ✅ Manual test sync successful
- ✅ Photos visible in Immich
- ✅ Mobile app configured and tested
- ✅ Workflow documentation created
- ✅ Verification script created
- ✅ User trained on monthly process

---

## Summary

### Iteration Checklist

- [x] Iteration 1: Storage Infrastructure
- [x] Iteration 2: Credentials & Config
- [ ] Iteration 3: Authentication ⚠️ **USER ACTION REQUIRED**
- [x] Iteration 4: CronJob Deployment
- [ ] Iteration 5: Immich Integration
- [ ] Iteration 6: External Exposure
- [ ] Iteration 7: Verification & Documentation

### Dependencies

```
Iteration 3 (User) ──┐
                     ├──> Iteration 5 → Iteration 6 → Iteration 7
Iteration 4 ─────────┘
```

**Blockers:**
- Iteration 3 requires user to provide Apple ID and complete 2FA
- Iteration 5+ require Immich to be already deployed

**Next Action:**
Complete Iteration 3 using `ITERATION_3_MANUAL_STEPS.md`
