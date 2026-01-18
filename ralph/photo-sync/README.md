# iCloud to Immich Photo Migration System

Automated monthly photo sync from iCloud to self-hosted Immich on Talos Kubernetes cluster.

## Quick Status

```
Progress: [████████████████████████░░] 57% (Iteration 4/7 Complete)
Status:   ⚠️ AWAITING USER ACTION (10-15 min required)
Updated:  2026-01-18 (Iteration 6 - Fresh Context)
```

| Iteration | Task | Status |
|-----------|------|--------|
| 1 | Storage Infrastructure | ✅ Complete |
| 2 | Credentials & Config | ✅ Complete |
| 3 | Initial Authentication | ⚠️ **USER ACTION REQUIRED** |
| 4 | CronJob Deployment | ✅ Complete |
| 5 | Immich Integration | ❌ **BLOCKED - No Immich Installed** |
| 6 | External Exposure | 🔜 Waiting |
| 7 | Verification | 🔜 Waiting |

## 🚨 ACTION REQUIRED

**Infrastructure is 100% deployed and ready!** Two quick user actions needed before continuing:

1. **Install Immich** (5-10 min) - BLOCKS Iterations 5-7
2. **Complete 2FA Authentication** (5 min) - Can be done in parallel

**Total Time**: 10-15 minutes (if done in parallel)

**See `USER_ACTION_REQUIRED.md` for detailed instructions.**

**Quick Check**: Run `./verify-ready-for-iteration5.sh` to see what's missing.

## What's Been Deployed

### Kubernetes Resources (photo-sync namespace)
- ✅ Namespace: `photo-sync`
- ✅ PVCs: `icloud-photos` (100Gi), `icloudpd-config` (1Gi)
- ✅ ConfigMap: `icloudpd-config` (sync settings)
- ✅ ServiceAccount: `icloudpd`
- ✅ CronJob: `icloudpd-sync` (runs monthly: 3 AM on 1st)
- ✅ Secret: `icloud-credentials` (cjrfraser@gmail.com)

### Files Created

```
photo-sync/
├── namespace.yaml                        ✅ Applied
├── pvc-photos.yaml                       ✅ Applied
├── pvc-config.yaml                       ✅ Applied
├── configmap-icloudpd.yaml              ✅ Applied
├── serviceaccount.yaml                   ✅ Applied
├── cronjob.yaml                          ✅ Applied
├── auth-pod.yaml                         📝 Ready for you
├── secret-icloud-credentials.yaml.template 📝 Template
│
├── README.md                             📖 This file
├── USER_ACTION_REQUIRED.md              📖 ⚠️ START HERE
├── verify-ready-for-iteration5.sh        🔧 Readiness check
├── ITERATION_3_MANUAL_STEPS.md          📖 Authentication guide
├── ITERATION_4_COMPLETE.md              📖 Iteration 4 results
├── ITERATION_5_STATUS.md                📖 Current status (Blocked)
├── REMAINING_ITERATIONS_GUIDE.md        📖 Next iterations
├── reference-mealie-ingress.yaml         📖 Ingress template
└── CREATE_SECRET.md                      📖 Secret creation help
```

## ⚠️ CRITICAL: Two Actions Required

The photo-sync infrastructure is deployed and ready, but **two things must be completed** before the system will work:

### 1. 🚨 Install Immich (CRITICAL)
Without Immich, Iterations 5-7 cannot proceed. See `USER_ACTION_REQUIRED.md` for installation options.

### 2. ⚠️ Complete iCloud Authentication
The CronJob won't run successfully without valid authentication.

### Detailed Instructions

See `USER_ACTION_REQUIRED.md` for complete guide on both actions.

### Quick Authentication Start

```bash
# 1. Credentials already created (cjrfraser@gmail.com)

# 2. Deploy authentication pod
cd /Users/cfraser/Repos/homelab/ralph/photo-sync
kubectl apply -f auth-pod.yaml

# 3. Wait for pod to be ready
kubectl wait --for=condition=Ready pod/icloudpd-auth -n photo-sync --timeout=120s

# 4. Attach to interactive session
kubectl attach -it icloudpd-auth -n photo-sync

# 5. Follow prompts:
#    - Enter Apple ID password
#    - Enter 2FA code from your trusted device
#    - Wait for "Authentication successful"

# 6. Verify session saved
kubectl exec -n photo-sync icloudpd-auth -- ls -la /config/

# 7. Clean up auth pod
kubectl delete pod icloudpd-auth -n photo-sync
```

### What Happens During Authentication

- You'll be prompted for your iCloud password (hidden input)
- Apple sends a 6-digit 2FA code to your trusted device
- You enter the code in the terminal
- Session cookies are saved to persistent storage (~90 day validity)
- The CronJob can now sync photos automatically

## How It Will Work (Once Complete)

```
     ┌─────────────┐
     │   iCloud    │
     │   Photos    │
     └──────┬──────┘
            │ Monthly download (1st of month, 3 AM)
            │
     ┌──────▼──────────────────────────────┐
     │  icloudpd CronJob (photo-sync)      │
     │  - Downloads new photos              │
     │  - Organized by year/month           │
     │  - Stops after 50 duplicates         │
     └──────┬──────────────────────────────┘
            │
     ┌──────▼──────────────────────────────┐
     │  icloud-photos PVC (100Gi)          │
     │  /icloud-import/2025/01/            │
     │                /02/                  │
     └──────┬──────────────────────────────┘
            │ Mounted read-only
            │
     ┌──────▼──────────────────────────────┐
     │  Immich Server                       │
     │  - External Library scans new files  │
     │  - Indexes photos                    │
     │  - Available at immich.coultonf.com  │
     └──────────────────────────────────────┘
```

## Monthly Workflow (Future)

1. **Automatic** (1st of month):
   - icloudpd downloads new photos from iCloud
   - Immich scans and indexes them

2. **Manual** (you):
   - Verify photos in Immich at https://immich.coultonf.com
   - Delete verified photos from iCloud to free space
   - (Repeat monthly)

## Architecture

### Storage Strategy
- **iCloud**: Recent 2-3 months (with "Optimize iPhone Storage")
- **Immich**: Long-term archive (all photos, full resolution)
- **Monthly Migration**: Moves older photos from iCloud → Immich

### Security
- Apple ID password never stored (only session cookies)
- Sessions expire after ~90 days (re-auth required)
- Read-only Immich mount (can't accidentally delete originals)

## Verification Commands

```bash
# Check all resources
kubectl get all,pvc,cm,secret,sa -n photo-sync

# Check CronJob schedule
kubectl get cronjob -n photo-sync

# View CronJob details
kubectl describe cronjob icloudpd-sync -n photo-sync

# Trigger manual test (after authentication)
kubectl create job --from=cronjob/icloudpd-sync -n photo-sync test-$(date +%s)
kubectl logs -f -n photo-sync job/test-xxxxx
```

## Remaining Work

### Iteration 5: Immich Integration
- Mount icloud-photos PVC to Immich server
- Configure External Library
- Verify photos appear in Immich UI

### Iteration 6: External Exposure
- Create Ingress for immich.coultonf.com
- Configure TLS certificate
- Test external access

### Iteration 7: Verification
- End-to-end testing
- Mobile app setup
- Workflow documentation

See `REMAINING_ITERATIONS_GUIDE.md` for detailed next steps.

## Troubleshooting

### CronJob won't run
- Missing secret: `kubectl get secret -n photo-sync icloud-credentials`
- Check logs: `kubectl logs -n photo-sync job/<job-name>`

### Authentication expires
- Re-run authentication steps (every ~90 days)
- See `ITERATION_3_MANUAL_STEPS.md`

### PVCs stuck in Pending
- Normal behavior with `WaitForFirstConsumer` storage
- Will bind when first pod uses them (during auth or first sync)

## Support

For detailed guides, see:
- `ITERATION_3_MANUAL_STEPS.md` - Authentication walkthrough
- `ITERATION_4_STATUS.md` - Current deployment status
- `REMAINING_ITERATIONS_GUIDE.md` - Future iterations
- `CREATE_SECRET.md` - Secret creation help

---

**Next Action**: See `USER_ACTION_REQUIRED.md` - Install Immich and complete authentication

**Quick Check**: Run `./verify-ready-for-iteration5.sh` to verify readiness
