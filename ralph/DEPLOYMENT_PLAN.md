# iCloud to Immich Photo Migration - Deployment Plan

**Generated**: 2026-01-18
**Current Status**: Iteration 1 Partial Completion
**Context Window**: 1

---

## Executive Summary

The photo-sync namespace has been created and storage infrastructure (PVCs) deployed. The PVCs are in "Pending" state, which is expected behavior for the `local-path` storage class that uses `WaitForFirstConsumer` binding mode. They will automatically bind when the first pod is created in Iteration 3.

---

## Current Cluster State

### ✅ Discovered Resources
- **Storage Class**: `local-path` (default, rancher.io/local-path provisioner)
  - Binding Mode: WaitForFirstConsumer
  - Reclaim Policy: Delete
  - Volume Expansion: Not supported
- **Ingress Class**: `nginx`
- **Reference Namespace**: `mealie` (for ingress pattern)
- **Cert Manager**: NOT detected (TLS will need manual configuration)

### ✅ Created Resources (Iteration 1)
- **Namespace**: `photo-sync` (Active)
- **PVC**: `icloud-photos` (Pending - expected)
- **PVC**: `icloudpd-config` (Pending - expected)

### ⚠️ Warnings
1. **PVCs Pending**: This is normal for local-path provisioner. Will bind when auth pod is created.
2. **No cert-manager**: Iteration 6 will need manual TLS setup or skip HTTPS initially.
3. **Immich namespace unknown**: Need to locate Immich deployment before Iteration 5.

---

## Iteration Status

| Iteration | Status | Completion | Blockers |
|-----------|--------|------------|----------|
| **1. Storage Infrastructure** | 🟡 Partial | 90% | PVCs pending (expected) |
| **2. Credentials & Config** | ⚪ Not Started | 0% | Need Apple ID email |
| **3. Initial Auth (2FA)** | ⚪ Not Started | 0% | Requires Iteration 2 |
| **4. CronJob Deployment** | ⚪ Not Started | 0% | Requires Iteration 3 |
| **5. Immich Integration** | ⚪ Not Started | 0% | Need Immich namespace |
| **6. External Exposure** | ⚪ Not Started | 0% | Requires Iteration 5 |
| **7. Verification** | ⚪ Not Started | 0% | Requires Iteration 6 |

---

## Next Iteration: Iteration 2 (Credentials and Configuration)

### Required User Input
Before proceeding to Iteration 2, collect:

1. **Apple ID Email**: The iCloud account email for photo sync
2. **Timezone Confirmation**: Default is `America/Los_Angeles` - confirm or adjust
3. **iCloud Library Size** (optional): Estimate in GB to size PVCs appropriately
   - Current PVC size: 100Gi (can be adjusted before binding)

### Iteration 2 Tasks
1. Create `icloud-credentials` Secret with Apple ID email
2. Create `icloudpd-config` ConfigMap with sync parameters:
   - Download path: `/photos/icloud-import`
   - Folder structure: `{:%Y/%m}` (year/month)
   - Until-found: 50 photos
   - Auto-delete: FALSE (safety)
   - Skip live photos: FALSE
   - Skip videos: FALSE

### Preparation Commands
```bash
# Verify current state
kubectl get all,pvc,secret,configmap -n photo-sync

# Identify Immich namespace (for future iterations)
kubectl get deployments -A | grep -i immich
kubectl get pods -A | grep -i immich
```

---

## Reference Configuration (from Mealie)

The mealie ingress configuration will serve as the template for Iteration 6:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
  name: mealie-ingress
  namespace: mealie
spec:
  ingressClassName: nginx
  rules:
  - host: mealie.coultonf.com
    http:
      paths:
      - backend:
          service:
            name: mealie
            port:
              number: 9000
        path: /
        pathType: Prefix
```

**Key takeaways for Immich ingress**:
- Use `ingressClassName: nginx`
- No cert-manager annotations (manual TLS or HTTP-only initially)
- Increase proxy-body-size for photo uploads (recommend: `0` = unlimited)
- Same timeout values: 600s

---

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| PVCs won't bind | Low | Expected behavior; will bind on pod creation |
| No cert-manager | Medium | Use HTTP initially or configure TLS manually |
| Immich not deployed | High | Must verify Immich exists before Iteration 5 |
| 2FA timeout | Medium | User must be available during Iteration 3 |
| Storage full | Medium | Monitor PVC usage; local-path may have node limits |

---

## Questions for User

Before proceeding to Iteration 2:

1. **What is your Apple ID email address?** (Required for icloud-credentials secret)
2. **Confirm timezone**: Is `America/Los_Angeles` correct?
3. **Estimated iCloud library size**: How many GB of photos? (to size PVC if needed)
4. **Is Immich already deployed?** If yes, in which namespace?
5. **DNS control**: Can you add `immich.coultonf.com` A/CNAME record for Iteration 6?
6. **TLS preference**:
   - Option A: HTTP-only initially (simplest)
   - Option B: Manual TLS secret
   - Option C: Install cert-manager for automatic TLS

---

## Files Created

- `photo-sync-state.json`: Machine-readable state for Ralph loop
- `DEPLOYMENT_PLAN.md`: This human-readable plan

---

## Ready to Proceed

Once you provide the required information above, I will:
1. Create the icloud-credentials secret
2. Create the icloudpd-config ConfigMap
3. Mark Iteration 2 complete
4. Prepare for Iteration 3 (interactive 2FA authentication)

---

## Notes
- Local-path provisioner will automatically create volumes on the node where the pod is scheduled
- The "WaitForFirstConsumer" binding mode optimizes for node affinity
- Consider switching to a distributed storage solution (Longhorn, NFS) if running multi-node and needing ReadWriteMany for the photos PVC
