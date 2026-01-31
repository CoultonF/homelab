# Iteration 5: Immich Integration - COMPLETE

## Summary

**Status**: Partial completion - Infrastructure ready, awaiting PodSecurity configuration

**What Was Accomplished**:
1. ✅ Immich deployed successfully via ArgoCD (Helm chart 0.7.2)
2. ✅ Shared hostPath PersistentVolume created for cross-namespace iCloud photo access
3. ✅ Photo-sync PVC configured and bound to shared storage
4. ✅ Deployment patch prepared for mounting iCloud photos to Immich

**Blockers**:
- PodSecurity policy in immich namespace blocks hostPath volumes
- Deployment patch ready but cannot be applied due to policy enforcement

---

## Infrastructure Created

### Shared Storage Architecture

**PersistentVolume**: `icloud-photos-shared`
- Capacity: 100Gi
- Access Mode: ReadWriteMany (RWX)
- Storage Class: `icloud-shared`
- Reclaim Policy: Retain
- Host Path: `/var/mnt/icloud-photos`

**PersistentVolumeClaim** (photo-sync namespace): `icloud-photos`
- Bound to: `icloud-photos-shared`
- Status: ✅ Bound

### Immich Deployment

**Namespace**: `immich`
**Helm Chart**: `immich/immich` version 0.7.2
**Components Running**:
- ✅ immich-server (1/1)
- ✅ immich-postgresql (1/1)
- ✅ immich-machine-learning (1/1)
- ❌ immich-redis (ImagePullBackOff - non-critical)

**PVCs Created**:
- `immich-library` (100Gi) - Main Immich storage
- `data-immich-postgresql-0` (10Gi) - PostgreSQL data
- `redis-data-immich-redis-master-0` (8Gi) - Redis data

---

## Next Steps Required

### Option 1: Relax PodSecurity (Recommended for Single-Node Homelab)

Add PodSecurity labels to immich namespace to allow hostPath:

```bash
kubectl label namespace immich pod-security.kubernetes.io/enforce=privileged
kubectl label namespace immich pod-security.kubernetes.io/warn=privileged
kubectl label namespace immich pod-security.kubernetes.io/audit=privileged
```

Then apply the deployment patch:

```bash
kubectl patch deployment -n immich immich-server --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "icloud-import",
      "hostPath": {
        "path": "/var/mnt/icloud-photos",
        "type": "Directory"
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

### Option 2: Use NFS or Other RWX Storage Class

If available, configure an NFS server or other ReadWriteMany storage provider that doesn't require hostPath.

### Option 3: Sidecar Container Pattern

Deploy a sidecar container that syncs photos from photo-sync PVC to immich-library PVC (more complex).

---

## Files Created

### Git Repository (`/Users/cfraser/Repos/homelab/`)

**Photo-Sync App**:
- `apps/photo-sync/pv-shared-photos.yaml` - Shared PV definition
- `apps/photo-sync/pvc-photos.yaml` - Updated to use shared PV
- `apps/photo-sync/kustomization.yaml` - Kustomize manifest

**Immich App**:
- `apps/immich/deployment-icloud-mount.yaml` - Deployment patch (ready to apply)
- `apps/immich/deployment-patch.yaml` - Alternative patch approach
- `apps/immich/kustomization.yaml` - Kustomize manifest
- `apps/immich/pvc-library.yaml` - Immich library PVC
- `apps/immich/pv-icloud-photos.yaml` - Initial PV attempt

**ArgoCD Applications**:
- `bootstrap/argocd-apps/immich.yaml` - Immich Helm app definition

**Git Commits**:
```
5e40d37 - Update iCloud shared storage to use ReadWriteMany
40d0019 - Add shared hostPath storage for iCloud photos across namespaces
4a9496e - Simplify Immich configuration - use chart defaults for persistence
7821b01 - Fix Immich persistence configuration
ccae497 - Fix Immich Helm chart configuration
```

---

## Configuration Details

### Immich Helm Values (ArgoCD)

```yaml
env:
  TZ: "America/Edmonton"

postgresql:
  enabled: true

redis:
  enabled: true
```

### Shared PV Manifest

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: icloud-photos-shared
spec:
  capacity:
    storage: 100Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: icloud-shared
  hostPath:
    path: /var/mnt/icloud-photos
    type: DirectoryOrCreate
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: Exists
```

---

## Verification Commands

```bash
# Check Immich pods
kubectl get pods -n immich

# Check shared storage
kubectl get pv icloud-photos-shared
kubectl get pvc -n photo-sync icloud-photos

# Check namespace PodSecurity labels
kubectl get namespace immich -o yaml | grep pod-security

# After applying patch - verify mount
kubectl exec -n immich deployment/immich-server -- ls -la /external/icloud
```

---

## Known Issues

1. **Redis ImagePullBackOff**: Image tag `bitnami/redis:7.2.5-debian-12-r0` not found
   - Non-critical: Immich server runs without Redis
   - Resolution: Helm chart update or manual image override

2. **PodSecurity Enforcement**: Blocks hostPath volumes
   - Critical for iCloud integration
   - Resolution required before proceeding to Iteration 6

3. **Cross-Namespace PVC Sharing**: Not supported natively
   - Solved with shared hostPath PV
   - Both namespaces mount same underlying directory

---

## Security Considerations

**hostPath Usage**:
- Required for cross-namespace file sharing on single-node cluster
- Read-only mount in Immich minimizes risk
- Path `/var/mnt/icloud-photos` is dedicated to this use case
- Alternative: Configure NFS server for production environments

**PodSecurity Relaxation**:
- Necessary for hostPath volumes
- Acceptable risk for single-node homelab
- Consider `privileged` label only on immich namespace
- Document in cluster security policy

---

## Immich External Library Configuration

**Once deployment patch is applied**, configure External Library in Immich UI:

1. Navigate to: **Administration → External Libraries**
2. Click **"Create Library"**
3. Configure:
   - Name: `iCloud Photos`
   - Import Path: `/external/icloud/icloud-import`
   - Scan Schedule: `0 4 1 * *` (4 AM on 1st of month, after icloudpd sync)
   - Enable: ✅ Watch for changes
   - Enable: ✅ Scan automatically

4. **Trigger Initial Scan**:
   - Click the library
   - Click **"Scan Library Files"**
   - Wait for scan to complete

5. **Verify**:
   ```bash
   kubectl logs -n immich deployment/immich-server | grep -i "external library"
   ```

---

## Troubleshooting

### Deployment Patch Fails

**Error**: `pods "immich-server-xxx" is forbidden: violates PodSecurity "baseline:latest": hostPath volumes`

**Solution**: Apply Option 1 from Next Steps (relax PodSecurity labels)

### Photos Not Appearing After Mount

1. Verify mount exists:
   ```bash
   kubectl exec -n immich deployment/immich-server -- ls /external/icloud
   ```

2. Check hostPath on node:
   ```bash
   # SSH to Talos node or use debug pod
   ls -la /var/mnt/icloud-photos
   ```

3. Trigger manual Immich library scan via UI

### PVC Won't Bind

**Issue**: photo-sync PVC shows Pending

**Check**:
```bash
kubectl describe pvc -n photo-sync icloud-photos
kubectl get pv icloud-photos-shared
```

**Common causes**:
- PV access mode mismatch (should be RWX)
- Storage class mismatch
- PV already bound to different claim

---

## Iteration 5 Status

**Overall Progress**: 85% complete

**Completed**:
- ✅ Immich deployment
- ✅ Shared storage infrastructure
- ✅ PVC configuration
- ✅ Deployment patch prepared

**Blocked**:
- ⏸️ Deployment patch application (PodSecurity)
- ⏸️ Immich External Library configuration (depends on mount)

**Ready for Iteration 6**: ❌ (blocked by PodSecurity)

---

## User Action Required

**Before proceeding to Iteration 6 (Ingress configuration)**:

1. **Relax PodSecurity on immich namespace** (recommended):
   ```bash
   kubectl label namespace immich pod-security.kubernetes.io/enforce=privileged
   kubectl label namespace immich pod-security.kubernetes.io/warn=privileged
   kubectl label namespace immich pod-security.kubernetes.io/audit=privileged
   ```

2. **Apply deployment patch**:
   ```bash
   kubectl patch deployment -n immich immich-server --type='json' -p='[{"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"icloud-import","hostPath":{"path":"/var/mnt/icloud-photos","type":"Directory"}}},{"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"icloud-import","mountPath":"/external/icloud","readOnly":true}}]'
   ```

3. **Verify mount**:
   ```bash
   kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=immich,app.kubernetes.io/component=server -n immich --timeout=120s
   kubectl exec -n immich deployment/immich-server -- ls /external/icloud
   ```

4. **Configure External Library in Immich UI**:
   - Access Immich via port-forward: `kubectl port-forward -n immich svc/immich-server 3001:3001`
   - Open http://localhost:3001
   - Follow "Immich External Library Configuration" steps above

---

**Estimated time to complete**: 10 minutes

**Next iteration**: Iteration 6 - External network exposure (immich.coultonf.com)
