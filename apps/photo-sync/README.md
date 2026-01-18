# iCloud to Immich Photo Sync

Automated photo migration pipeline that syncs photos from iCloud to a self-hosted Immich instance on a monthly basis.

## Overview

This deployment creates an automated pipeline to:
- Download photos from iCloud monthly using `icloudpd`
- Store photos in persistent storage
- Make photos available to Immich for long-term archival

## Architecture

```
iCloud Photos → icloudpd CronJob → PVC Storage → Immich External Library
```

## Components

### Namespace
- `photo-sync`: Isolated namespace for photo sync infrastructure

### Storage
- `icloud-photos` (100Gi): Stores downloaded photos organized by year/month
- `icloudpd-config` (1Gi): Stores iCloud authentication session cache

### Configuration
- `icloud-credentials`: Secret containing Apple ID email
- `icloudpd-config`: ConfigMap with sync settings

### Workload
- `icloudpd-sync`: CronJob that runs monthly (3 AM on 1st of month, America/Edmonton)
  - Downloads new photos from iCloud
  - Stops after finding 50 already-downloaded photos (incremental sync)
  - Sets EXIF datetime metadata
  - Never auto-deletes from iCloud

## Deployment Status

**Current State**: Resources deployed directly to cluster
**ArgoCD Status**: Application created, pending sync

## Initial Setup Required

### 1. iCloud Authentication (One-time, ~5 minutes)

Authentication must be completed interactively before the CronJob can run:

```bash
# Create temporary authentication pod
kubectl apply -f /Users/cfraser/Repos/homelab/ralph/photo-sync/auth-pod.yaml

# Wait for pod to be ready
kubectl wait --for=condition=Ready pod/icloudpd-auth -n photo-sync --timeout=120s

# Attach to pod and complete 2FA
kubectl attach -it icloudpd-auth -n photo-sync
# Enter Apple ID password when prompted
# Enter 2FA code sent to trusted device
# Wait for "Authentication successful"

# Cleanup auth pod
kubectl delete pod icloudpd-auth -n photo-sync
```

**Session Lifetime**: ~90 days. Re-run authentication when session expires.

### 2. Verify Setup

```bash
# Check all resources
kubectl get all,pvc,secret,configmap -n photo-sync

# Verify CronJob schedule
kubectl get cronjob -n photo-sync icloudpd-sync

# Check PVC status (will be Pending until first pod runs)
kubectl get pvc -n photo-sync
```

## Testing

Trigger a manual sync job:

```bash
kubectl create job --from=cronjob/icloudpd-sync -n photo-sync test-sync-$(date +%s)

# Watch logs
kubectl logs -f -n photo-sync job/test-sync-<timestamp>
```

## Immich Integration

To integrate with Immich (see Iteration 5):
1. Mount `icloud-photos` PVC to Immich server at `/external/icloud`
2. Configure Immich External Library pointing to `/external/icloud/icloud-import`
3. Enable automatic library scanning

## Configuration

### Apple ID
- Configured: `cjrfraser@gmail.com`
- Stored in: `secret/icloud-credentials`

### Sync Schedule
- Monthly: 1st of month at 3:00 AM (America/Edmonton timezone)
- Configured in: `cronjob.yaml` (spec.schedule)

### Storage Paths
- Download path: `/photos/icloud-import`
- Folder structure: `{:%Y/%m}` (year/month organization)
- Example: `/photos/icloud-import/2026/01/IMG_1234.jpg`

### Sync Behavior
- Until found: 50 (stops after finding 50 existing photos)
- Set EXIF datetime: true
- Auto-delete from iCloud: false (NEVER deletes)
- Include live photos: true
- Include videos: true

## Troubleshooting

### PVCs in Pending State
Normal with `WaitForFirstConsumer` binding mode. PVCs bind when first pod uses them.

### Authentication Errors
Session expired. Re-run authentication steps above.

### CronJob Not Running
Check schedule and last run:
```bash
kubectl describe cronjob -n photo-sync icloudpd-sync
kubectl get jobs -n photo-sync
```

### View Logs
```bash
# Latest job
kubectl logs -n photo-sync job/$(kubectl get jobs -n photo-sync -o jsonpath='{.items[-1].metadata.name}')

# All jobs
kubectl get jobs -n photo-sync
```

## Manual Operations

### Trigger Immediate Sync
```bash
kubectl create job --from=cronjob/icloudpd-sync -n photo-sync manual-sync-$(date +%s)
```

### Check Downloaded Photos
```bash
# Via direct PVC inspection (requires debug pod)
kubectl run -it --rm check-photos --image=busybox -n photo-sync \
  --overrides='{"spec":{"containers":[{"name":"check","image":"busybox","command":["sh","-c","ls -lah /photos/icloud-import/"],"volumeMounts":[{"name":"photos","mountPath":"/photos"}]}],"volumes":[{"name":"photos","persistentVolumeClaim":{"claimName":"icloud-photos"}}]}}'
```

## Next Steps

1. ✅ **Iteration 4 Complete**: CronJob deployed and ready
2. ⏸️ **Pending**: Complete iCloud authentication (user action required)
3. 🔜 **Iteration 5**: Mount storage to Immich and configure External Library
4. 🔜 **Iteration 6**: Expose Immich at immich.coultonf.com
5. 🔜 **Iteration 7**: End-to-end verification and iOS app setup

## Resources

- icloudpd: https://github.com/boredazfcuk/docker-icloudpd
- Immich: https://immich.app/docs

## Monitoring

To check sync health:
```bash
# Recent jobs
kubectl get jobs -n photo-sync --sort-by=.metadata.creationTimestamp

# Failed jobs
kubectl get jobs -n photo-sync --field-selector status.successful=0

# Storage usage
kubectl exec -n photo-sync <pod-name> -- df -h /photos
```
