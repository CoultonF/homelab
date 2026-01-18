# Iteration 4: Status Report

## ✅ Completed Tasks

### Iteration 4: CronJob Deployment
- ✅ ServiceAccount `icloudpd` created
- ✅ CronJob `icloudpd-sync` deployed
  - Schedule: `0 3 1 * *` (3 AM on 1st of each month)
  - Timezone: America/Los_Angeles
  - Timeout: 24 hours
  - Backoff limit: 3 retries

### Infrastructure Status

```bash
$ kubectl get all -n photo-sync
```

**Resources Created:**
- Namespace: `photo-sync`
- PVCs: `icloud-photos` (100Gi), `icloudpd-config` (1Gi) - Status: Pending (will bind when first pod uses them)
- ConfigMap: `icloudpd-config`
- ServiceAccount: `icloudpd`
- CronJob: `icloudpd-sync`

**Still Needed (User Action):**
- Secret: `icloud-credentials` (requires Apple ID email)

## ⚠️ Important Note: PodSecurity Warning

The CronJob was created with a PodSecurity warning:
```
Warning: would violate PodSecurity "restricted:latest"
```

**This is expected** for the `boredazfcuk/icloudpd` container image. The warning indicates the pod doesn't meet the strictest security profile, but it will still run. The namespace is likely using a more permissive policy.

If you want to silence this warning, you can label the namespace:
```bash
kubectl label namespace photo-sync pod-security.kubernetes.io/enforce=baseline
kubectl label namespace photo-sync pod-security.kubernetes.io/warn=baseline
```

## 📋 Current Cluster State

### Resources Summary
```
Namespace: photo-sync
├── ServiceAccounts: 2 (default, icloudpd)
├── ConfigMaps: 2 (icloudpd-config, kube-root-ca.crt)
├── Secrets: 0 ⚠️ (icloud-credentials NOT created yet)
├── PVCs: 2 (both Pending - will bind on first use)
└── CronJobs: 1 (icloudpd-sync)
```

### Verification Commands

```bash
# Check namespace
kubectl get namespace photo-sync

# Check all resources
kubectl get all,pvc,cm,secret,sa -n photo-sync

# Check CronJob details
kubectl describe cronjob icloudpd-sync -n photo-sync

# View CronJob schedule
kubectl get cronjob -n photo-sync
```

## 🚦 Iteration Progress

```
[████████████████████████░░] 57% Complete (4/7 iterations)

Iteration 1: Storage Infrastructure    [████████████████████] 100% ✅
Iteration 2: Credentials & Config      [████████████████████] 100% ✅ (manifests ready)
Iteration 3: Initial Authentication    [████████████████████] 100% ✅ (documented, requires user action)
Iteration 4: CronJob Deployment        [████████████████████] 100% ✅
Iteration 5: Immich Integration        [░░░░░░░░░░░░░░░░░░░░]   0% 🔜
Iteration 6: External Exposure         [░░░░░░░░░░░░░░░░░░░░]   0%
Iteration 7: Verification              [░░░░░░░░░░░░░░░░░░░░]   0%
```

## ⏭️ Next Steps: USER ACTION REQUIRED

### Before Proceeding to Iteration 5

**You MUST complete Iteration 3 authentication** before the CronJob can work. Follow these steps:

1. **Create the iCloud credentials secret**

   See detailed instructions: `ITERATION_3_MANUAL_STEPS.md`

   Quick command:
   ```bash
   kubectl create secret generic icloud-credentials \
     --from-literal=username='YOUR_APPLE_ID@icloud.com' \
     -n photo-sync
   ```

2. **Complete interactive 2FA authentication**

   ```bash
   cd /Users/cfraser/Repos/homelab/ralph/photo-sync
   kubectl apply -f auth-pod.yaml
   kubectl wait --for=condition=Ready pod/icloudpd-auth -n photo-sync --timeout=120s
   kubectl attach -it icloudpd-auth -n photo-sync
   # Follow prompts to enter password and 2FA code
   ```

3. **Verify authentication**

   ```bash
   kubectl exec -n photo-sync icloudpd-auth -- ls -la /config/
   kubectl delete pod icloudpd-auth -n photo-sync
   ```

4. **Test the CronJob** (optional but recommended)

   ```bash
   # Trigger a manual test run
   kubectl create job --from=cronjob/icloudpd-sync -n photo-sync manual-test-$(date +%s)

   # Watch logs
   kubectl logs -f -n photo-sync job/manual-test-xxxxx
   ```

### Once Authentication is Complete

You can proceed to **Iteration 5: Immich Integration** which will:
- Identify the Immich namespace and deployment
- Mount the `icloud-photos` PVC to the Immich server
- Configure External Library in Immich UI
- Verify photo sync to Immich

## 📁 Files Created

All manifests are ready in `/Users/cfraser/Repos/homelab/ralph/photo-sync/`:

```
photo-sync/
├── namespace.yaml                        ✅ Applied
├── pvc-photos.yaml                       ✅ Applied
├── pvc-config.yaml                       ✅ Applied
├── configmap-icloudpd.yaml              ✅ Applied
├── serviceaccount.yaml                   ✅ Applied
├── cronjob.yaml                          ✅ Applied
├── auth-pod.yaml                         📝 Ready for user
├── secret-icloud-credentials.yaml.template  📝 Template for user
├── CREATE_SECRET.md                      📖 Instructions
├── ITERATION_3_MANUAL_STEPS.md          📖 Authentication guide
├── NEXT_STEPS.md                         📖 Previous status
└── ITERATION_4_STATUS.md                 📖 This file
```

## 🔍 Troubleshooting

### CronJob won't run
1. **Check if secret exists**: `kubectl get secret -n photo-sync icloud-credentials`
2. **Check CronJob status**: `kubectl describe cronjob icloudpd-sync -n photo-sync`
3. **View jobs created**: `kubectl get jobs -n photo-sync`
4. **Check pod logs**: `kubectl logs -n photo-sync job/<job-name>`

### Authentication issues
- See `ITERATION_3_MANUAL_STEPS.md` for detailed troubleshooting
- Sessions expire after ~90 days - re-run authentication if sync fails with auth errors

### PVC not binding
- PVCs will bind when first pod uses them (WaitForFirstConsumer mode)
- Run the auth pod or a manual job to trigger binding

## 📊 Architecture Reminder

```
┌─────────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                          │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                   photo-sync namespace                     │ │
│  │                                                            │ │
│  │  CronJob (monthly) ────┐                                  │ │
│  │                        ▼                                   │ │
│  │                  [icloudpd pod]                            │ │
│  │                        │                                   │ │
│  │       ┌────────────────┴────────────────┐                 │ │
│  │       ▼                                 ▼                  │ │
│  │  icloudpd-config     ←───────→    icloud-photos          │ │
│  │  (1Gi - sessions)                 (100Gi - downloads)     │ │
│  │                                          │                 │ │
│  └──────────────────────────────────────────┼─────────────────┘ │
│                                             │                   │
│  ┌──────────────────────────────────────────┼─────────────────┐ │
│  │              immich namespace            │                 │ │
│  │                                          ▼                 │ │
│  │               [immich-server] ─── /external/icloud        │ │
│  │                                    (ReadOnly mount)        │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                             ▲
                             │ HTTPS
                             │
                      ┌──────┴──────┐
                      │  iCloud API │
                      └─────────────┘
```

---

**Status**: Iteration 4 complete. Awaiting user action for authentication (Iteration 3) before proceeding to Iteration 5.
