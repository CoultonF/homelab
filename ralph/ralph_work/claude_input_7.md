# iCloud to Immich Photo Migration System

## OVERALL OBJECTIVE
Deploy an automated photo migration pipeline on a Talos Linux Kubernetes cluster that syncs photos from iCloud to a self-hosted Immich instance on a monthly basis. This enables a hybrid storage strategy: iCloud handles recent photos with "Optimize iPhone Storage" enabled, while Immich serves as the long-term archive.

my apple id is cjrfraser@gmail.com

you need to deploy this through my argo cd setup that is running talos linux on a single tainted node. The argo setup is in the folder of /Users/cfraser/Repos/homelab/ . dont use a src folder.

## ITERATION PLAN
1. **Iteration 1**: Create namespace and storage infrastructure
2. **Iteration 2**: Deploy icloudpd credentials and configuration
3. **Iteration 3**: Complete initial iCloud authentication (interactive 2FA)
4. **Iteration 4**: Deploy icloudpd CronJob for scheduled syncs
5. **Iteration 5**: Configure Immich External Library integration
6. **Iteration 6**: Expose Immich externally at immich.coultonf.com (follow mealie.coultonf.com pattern)
7. **Iteration 7**: Verify end-to-end pipeline and document manual deletion workflow

## CURRENT TASK DETERMINATION RULES
Check cluster state to determine current task:

```bash
# Iteration 1: Storage setup
kubectl get namespace photo-sync
kubectl get pvc -n photo-sync icloud-photos
kubectl get pvc -n photo-sync icloudpd-config
# If namespace or PVCs don't exist → Run Iteration 1

# Iteration 2: Credentials and config
kubectl get secret -n photo-sync icloud-credentials
kubectl get configmap -n photo-sync icloudpd-config
# If secret or configmap don't exist → Run Iteration 2

# Iteration 3: Authentication
kubectl get pvc -n photo-sync icloudpd-config -o jsonpath='{.status.phase}'
# Check if auth cookie exists in PVC
kubectl run --rm -it auth-check --image=busybox -n photo-sync --restart=Never -- ls /config/
# If cookie/session files don't exist → Run Iteration 3

# Iteration 4: CronJob deployment
kubectl get cronjob -n photo-sync icloudpd-sync
# If cronjob doesn't exist → Run Iteration 4

# Iteration 5: Immich integration
kubectl get deployment -n <immich-namespace> immich-server -o yaml | grep icloud-import
# Or check Immich Admin UI for External Library pointing to /external/icloud
# If mount or external library not configured → Run Iteration 5

# Iteration 6: External network exposure
kubectl get ingress -n <immich-namespace> | grep immich
# Reference existing mealie ingress for pattern:
kubectl get ingress -A | grep mealie
kubectl get ingress -n <mealie-namespace> mealie -o yaml
# If immich ingress doesn't exist or immich.coultonf.com not configured → Run Iteration 6

# Iteration 7: Verification
kubectl create job --from=cronjob/icloudpd-sync -n photo-sync test-sync-$(date +%s)
# If test sync hasn't been run or verification doc doesn't exist → Run Iteration 7
```

## TASK TEMPLATES

### Iteration 1: Storage Infrastructure

**Prerequisites**: Identify existing storage class (check `kubectl get storageclass`)

**Steps**:
1. Create namespace
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: photo-sync
```

2. Create PVC for downloaded photos (adjust storageClassName)
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: icloud-photos
  namespace: photo-sync
spec:
  accessModes:
    - ReadWriteMany  # Use ReadWriteOnce if single-node or same-node scheduling
  resources:
    requests:
      storage: 100Gi  # Adjust based on iCloud library size
  storageClassName: <STORAGE_CLASS>  # e.g., longhorn, nfs-client
```

3. Create PVC for icloudpd auth/config cache
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: icloudpd-config
  namespace: photo-sync
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: <STORAGE_CLASS>
```

4. Verify PVCs are bound
```bash
kubectl get pvc -n photo-sync
# Both should show STATUS: Bound
```

**Completion marker**: Both PVCs in `Bound` state

---

### Iteration 2: Credentials and Configuration

**Prerequisites**: Obtain Apple ID email from user

**Steps**:
1. Create iCloud credentials secret
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: icloud-credentials
  namespace: photo-sync
type: Opaque
stringData:
  username: "<APPLE_ID_EMAIL>"
```

2. Create icloudpd configuration
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: icloudpd-config
  namespace: photo-sync
data:
  # Download directory inside the PVC
  download_path: "/photos/icloud-import"
  # Folder structure: organize by year/month
  folder_structure: "{:%Y/%m}"
  # Sync behavior
  until_found: "50"  # Stop after finding 50 already-downloaded photos
  set_exif_datetime: "true"
  auto_delete: "false"  # NEVER auto-delete from iCloud
  skip_live_photos: "false"
  skip_videos: "false"
  # Optional: filter by album
  # album: "Recent"
```

3. Verify resources created
```bash
kubectl get secret -n photo-sync icloud-credentials
kubectl get configmap -n photo-sync icloudpd-config
```

**Completion marker**: Secret and ConfigMap exist

---

### Iteration 3: Initial Authentication (Interactive)

**Prerequisites**: User must be available to enter 2FA code

**Steps**:
1. Deploy authentication pod
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: icloudpd-auth
  namespace: photo-sync
spec:
  restartPolicy: Never
  containers:
    - name: icloudpd
      image: boredazfcuk/icloudpd:latest
      command: ["/bin/sh", "-c", "icloud --username $(cat /credentials/username) && sleep 3600"]
      stdin: true
      tty: true
      volumeMounts:
        - name: credentials
          mountPath: /credentials
          readOnly: true
        - name: config
          mountPath: /config
      env:
        - name: TZ
          value: "America/Los_Angeles"  # Adjust timezone
  volumes:
    - name: credentials
      secret:
        secretName: icloud-credentials
    - name: config
      persistentVolumeClaim:
        claimName: icloudpd-config
```

2. Attach to pod and complete 2FA
```bash
kubectl apply -f auth-pod.yaml
kubectl wait --for=condition=Ready pod/icloudpd-auth -n photo-sync --timeout=120s
kubectl attach -it icloudpd-auth -n photo-sync
# Enter Apple ID password when prompted
# Enter 2FA code sent to trusted device
# Wait for "Authentication successful" message
```

3. Verify session was saved
```bash
kubectl exec -n photo-sync icloudpd-auth -- ls -la /config/
# Should see session files/cookies
```

4. Cleanup auth pod
```bash
kubectl delete pod icloudpd-auth -n photo-sync
```

**Completion marker**: Session files exist in icloudpd-config PVC

---

### Iteration 4: Deploy CronJob

**Prerequisites**: Authentication completed successfully

**Steps**:
1. Create ServiceAccount (minimal permissions)
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: icloudpd
  namespace: photo-sync
automountServiceAccountToken: false
```

2. Deploy CronJob
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: icloudpd-sync
  namespace: photo-sync
spec:
  schedule: "0 3 1 * *"  # 3 AM on 1st of each month
  timeZone: "America/Los_Angeles"  # Adjust timezone
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 3
      activeDeadlineSeconds: 86400  # 24h timeout
      template:
        spec:
          serviceAccountName: icloudpd
          restartPolicy: OnFailure
          containers:
            - name: icloudpd
              image: boredazfcuk/icloudpd:latest
              command:
                - /bin/sh
                - -c
                - |
                  icloudpd --directory /photos/icloud-import \
                    --username $(cat /credentials/username) \
                    --cookie-directory /config \
                    --folder-structure "{:%Y/%m}" \
                    --until-found 50 \
                    --set-exif-datetime \
                    --no-progress-bar
              volumeMounts:
                - name: credentials
                  mountPath: /credentials
                  readOnly: true
                - name: config
                  mountPath: /config
                - name: photos
                  mountPath: /photos
              resources:
                requests:
                  memory: "256Mi"
                  cpu: "100m"
                limits:
                  memory: "1Gi"
                  cpu: "1000m"
          volumes:
            - name: credentials
              secret:
                secretName: icloud-credentials
            - name: config
              persistentVolumeClaim:
                claimName: icloudpd-config
            - name: photos
              persistentVolumeClaim:
                claimName: icloud-photos
```

3. Verify CronJob created
```bash
kubectl get cronjob -n photo-sync
```

**Completion marker**: CronJob exists and shows schedule

---

### Iteration 5: Immich External Library Integration

**Prerequisites**: Identify Immich namespace and deployment names

**Steps**:
1. Patch Immich server deployment to mount icloud-photos PVC
```bash
# First, identify Immich deployment
kubectl get deployments -A | grep immich

# Patch to add volume mount (adjust namespace and deployment name)
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

**Alternative**: If using Helm, add to values.yaml:
```yaml
immich:
  persistence:
    external:
      enabled: true
      existingClaim: icloud-photos
      mountPath: /external/icloud
      readOnly: true
```

2. Configure External Library in Immich UI
   - Navigate to: Administration → External Libraries
   - Click "Create Library"
   - Set import path: `/external/icloud/icloud-import`
   - Enable "Scan library automatically" (or set cron schedule)
   - Save configuration

3. Trigger initial library scan
   - In Immich UI: Libraries → Select icloud library → Scan

4. Verify mount is working
```bash
kubectl exec -n <IMMICH_NAMESPACE> deployment/immich-server -- ls /external/icloud/
```

**Completion marker**: External Library visible in Immich with correct path

---

### Iteration 6: External Network Exposure (immich.coultonf.com)

**Prerequisites**:
- Immich server running and accessible internally
- Reference existing mealie.coultonf.com ingress configuration for pattern

**Steps**:
1. Examine existing mealie ingress as reference pattern
```bash
# Find mealie ingress and export as template
kubectl get ingress -A | grep mealie
kubectl get ingress -n <MEALIE_NAMESPACE> <MEALIE_INGRESS_NAME> -o yaml > mealie-ingress-reference.yaml

# Note the following from mealie ingress:
# - Ingress class (nginx, traefik, etc.)
# - TLS configuration (cert-manager annotations, secret name pattern)
# - Any middleware or annotations used
```

2. Create Immich ingress (adapt based on mealie pattern)

**If using Traefik (common on k3s/Talos):**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: immich
  namespace: <IMMICH_NAMESPACE>
  annotations:
    # Copy relevant annotations from mealie ingress
    cert-manager.io/cluster-issuer: <CLUSTER_ISSUER>  # e.g., letsencrypt-prod
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    # Add any other annotations from mealie
spec:
  ingressClassName: traefik  # Match mealie's ingress class
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
                name: immich-server  # Verify actual service name
                port:
                  number: 3001  # Default Immich port
```

**If using NGINX Ingress:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: immich
  namespace: <IMMICH_NAMESPACE>
  annotations:
    cert-manager.io/cluster-issuer: <CLUSTER_ISSUER>
    nginx.ingress.kubernetes.io/proxy-body-size: "0"  # Important for photo uploads
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
spec:
  ingressClassName: nginx
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
                name: immich-server
                port:
                  number: 3001
```

3. Verify Immich service exists and note correct name/port
```bash
kubectl get svc -n <IMMICH_NAMESPACE> | grep immich
# Update ingress backend service name and port accordingly
```

4. Apply ingress
```bash
kubectl apply -f immich-ingress.yaml
```

5. Verify TLS certificate is issued
```bash
kubectl get certificate -n <IMMICH_NAMESPACE>
kubectl describe certificate immich-tls -n <IMMICH_NAMESPACE>
# Wait for READY: True
```

6. Update DNS (if not using wildcard)
```bash
# Add A record or CNAME for immich.coultonf.com pointing to cluster ingress IP
# Check mealie.coultonf.com DNS for reference:
dig mealie.coultonf.com
# immich.coultonf.com should point to same IP
```

7. Test external access
```bash
curl -I https://immich.coultonf.com
# Should return 200 or redirect to login
```

8. Configure Immich for external URL (if needed)
   - In Immich settings, set external URL to `https://immich.coultonf.com`
   - This ensures shared links and mobile app work correctly

**Completion marker**: https://immich.coultonf.com accessible externally with valid TLS

---

### Iteration 7: Verification and Documentation

**Prerequisites**: All previous iterations complete

**Steps**:
1. Trigger a test sync
```bash
kubectl create job --from=cronjob/icloudpd-sync -n photo-sync manual-test-$(date +%s)
kubectl logs -f -n photo-sync job/manual-test-*
```

2. Verify photos downloaded
```bash
kubectl exec -n photo-sync -it deploy/... -- ls -la /photos/icloud-import/
# Or via Immich server pod
kubectl exec -n <IMMICH_NAMESPACE> deployment/immich-server -- find /external/icloud -type f | head -20
```

3. Verify photos appear in Immich (via external URL)
   - Open https://immich.coultonf.com in browser
   - Log in and navigate to Library
   - Confirm new photos from iCloud are visible
   - Spot-check dates and metadata

4. Configure and test Immich iOS app for backup
   - Install Immich app from App Store
   - Server URL: `https://immich.coultonf.com`
   - Log in with Immich credentials
   - Settings → Backup → Enable "Background Backup"
   - Grant full photo library access
   - Grant location permission (set to "Always" for background triggers)
   - Test manual backup of a few photos

5. Document the hybrid workflow for user
   ```
   MONTHLY WORKFLOW:
   1. icloudpd CronJob runs on 1st of month (automatic)
   2. Immich External Library scans new photos (automatic)
   3. User verifies photos in Immich at https://immich.coultonf.com
   4. User manually deletes verified photos from iCloud:
      - Open iCloud.com or Photos app on Mac
      - Select photos by date range
      - Delete from iCloud
      - (Optional) Empty "Recently Deleted"

   ONGOING (via iOS app):
   - New photos back up to Immich via iOS app
   - iCloud keeps recent photos with "Optimize Storage"
   - Monthly migration moves older photos to long-term Immich storage
   ```

6. Create verification script (optional)
```bash
#!/bin/bash
# verify-sync.sh
echo "=== iCloud Sync Status ==="
echo "Last job:"
kubectl get jobs -n photo-sync --sort-by=.metadata.creationTimestamp | tail -2

echo -e "\n=== Photo count in PVC ==="
kubectl exec -n photo-sync deployment/... -- find /photos/icloud-import -type f | wc -l

echo -e "\n=== Recent sync logs ==="
kubectl logs -n photo-sync job/$(kubectl get jobs -n photo-sync -o jsonpath='{.items[-1].metadata.name}') --tail=20

echo -e "\n=== External access check ==="
curl -sI https://immich.coultonf.com | head -5
```

**Completion marker**: Test sync successful, photos visible in Immich at https://immich.coultonf.com, iOS app connected

---

## FILE STRUCTURE EXPECTED

```
photo-sync namespace:
├── PVC: icloud-photos (100Gi)
│   └── icloud-import/
│       ├── 2024/
│       │   ├── 01/
│       │   ├── 02/
│       │   └── ...
│       └── 2025/
│           └── ...
├── PVC: icloudpd-config (1Gi)
│   └── <session cookies and auth cache>
├── Secret: icloud-credentials
├── ConfigMap: icloudpd-config
├── ServiceAccount: icloudpd
└── CronJob: icloudpd-sync

<immich-namespace>:
└── Deployment: immich-server
    └── Volume mount: /external/icloud → icloud-photos PVC
```

## ARCHITECTURE DIAGRAM

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Talos Linux Kubernetes Cluster                      │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    photo-sync namespace                          │   │
│  │                                                                  │   │
│  │   ┌──────────────┐     ┌──────────────┐     ┌──────────────┐   │   │
│  │   │   Secret     │     │  ConfigMap   │     │    CronJob   │   │   │
│  │   │  icloud-     │     │  icloudpd-   │     │  icloudpd-   │   │   │
│  │   │  credentials │     │  config      │     │  sync        │   │   │
│  │   └──────┬───────┘     └──────┬───────┘     │  (monthly)   │   │   │
│  │          │                    │             └───────┬──────┘   │   │
│  │          └────────────────────┼─────────────────────┘          │   │
│  │                               ▼                                 │   │
│  │                    ┌──────────────────┐                        │   │
│  │                    │   icloudpd pod   │                        │   │
│  │                    │  (runs monthly)  │                        │   │
│  │                    └────────┬─────────┘                        │   │
│  │                             │                                   │   │
│  │              ┌──────────────┴──────────────┐                   │   │
│  │              ▼                              ▼                   │   │
│  │   ┌──────────────────┐          ┌──────────────────┐          │   │
│  │   │ PVC: icloudpd-   │          │ PVC: icloud-     │          │   │
│  │   │ config (1Gi)     │          │ photos (100Gi)   │◄─────┐   │   │
│  │   │ [auth cookies]   │          │ [downloaded      │      │   │   │
│  │   └──────────────────┘          │  photos]         │      │   │   │
│  │                                 └──────────────────┘      │   │   │
│  └───────────────────────────────────────────────────────────┼───┘   │
│                                                              │       │
│  ┌───────────────────────────────────────────────────────────┼───┐   │
│  │                    immich namespace                        │   │   │
│  │                                                            │   │   │
│  │   ┌────────────────────────────────────────────────────┐  │   │   │
│  │   │              immich-server deployment              │  │   │   │
│  │   │                                                    │  │   │   │
│  │   │   /external/icloud ────────────────────────────────┼──┘   │   │
│  │   │   (ReadOnly mount)                                 │      │   │
│  │   │                                                    │      │   │
│  │   │   External Library: watches /external/icloud       │      │   │
│  │   └────────────────────────────────────────────────────┘      │   │
│  │                                                                │   │
│  └────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
                                    ▲
                                    │ HTTPS (iCloud API)
                                    │
                              ┌─────┴─────┐
                              │  iCloud   │
                              │  Photos   │
                              └───────────┘
```

## VARIABLES TO COLLECT FROM USER/CLUSTER

| Variable | How to Determine | Example |
|----------|------------------|---------|
| `<STORAGE_CLASS>` | `kubectl get storageclass` | `longhorn`, `nfs-client` |
| `<APPLE_ID_EMAIL>` | Ask user | `user@icloud.com` |
| `<IMMICH_NAMESPACE>` | `kubectl get ns \| grep immich` | `immich`, `default` |
| `<MEALIE_NAMESPACE>` | `kubectl get ingress -A \| grep mealie` | `mealie`, `default` |
| `<CLUSTER_ISSUER>` | `kubectl get clusterissuer` | `letsencrypt-prod` |
| `<INGRESS_CLASS>` | From mealie ingress `spec.ingressClassName` | `traefik`, `nginx` |
| `<TIMEZONE>` | User preference | `America/Los_Angeles` |
| PVC size | Based on iCloud library size | `100Gi`, `500Gi` |

## TROUBLESHOOTING

### Authentication expires
- Sessions last ~90 days
- Re-run Iteration 3 if sync fails with auth errors
- Check: `kubectl logs -n photo-sync job/<latest-job>`

### Photos not appearing in Immich
- Verify mount: `kubectl exec -n <IMMICH_NS> deployment/immich-server -- ls /external/icloud/`
- Check External Library scan status in Immich UI
- Manually trigger scan: Libraries → Scan

### CronJob not running
- Check schedule: `kubectl get cronjob -n photo-sync`
- Check for failed jobs: `kubectl get jobs -n photo-sync`
- Check events: `kubectl describe cronjob icloudpd-sync -n photo-sync`

### Storage issues
- Check PVC status: `kubectl get pvc -n photo-sync`
- Check if storage class supports RWX (needed if pods on different nodes)

### External access / Ingress issues
- Check ingress status: `kubectl get ingress -n <IMMICH_NAMESPACE>`
- Check certificate status: `kubectl get certificate -n <IMMICH_NAMESPACE>`
- Compare with working mealie ingress: `kubectl get ingress -n <MEALIE_NAMESPACE> -o yaml`
- Check ingress controller logs: `kubectl logs -n <ingress-namespace> -l app.kubernetes.io/name=traefik`
- Verify DNS resolves: `dig immich.coultonf.com`
- Test internally first: `kubectl port-forward -n <IMMICH_NAMESPACE> svc/immich-server 3001:3001`

---

# ITERATION 7
## Context Window Reset
This is a fresh context window. Previous context has been cleared.

## Previous Iteration Summary
```json
```

## What's Ready Now
- ✅ Immich web interface accessible at `immich.coultonf.com`
- ✅ iCloud mount ready to receive photos
- ✅ Infrastructure complete and verified

## What's Needed
- ⏳ Complete Iteration 3: iCloud 2FA authentication
- ⏳ Deploy icloudpd CronJob (Iteration 4)
- ⏳ Configure Immich External Library
- ⏳ Test end-to-end photo pipeline

**Estimated time to complete remaining work:** 30-45 minutes

---

All state files have been updated. Ready for Iteration 7 once Iteration 3 (iCloud authentication) is completed!

=== CLAUDE EXECUTION END ===
```

## Current Task
1. Final validation of all iterations
2. Create comprehensive summary
3. Generate final report
4. Clean up temporary files

## Instructions
- This is a fresh context window
- Use files for persistence only
- Output should include:
  1. Task completion status
  2. Any errors encountered
  3. State for next iteration
  4. Next steps
