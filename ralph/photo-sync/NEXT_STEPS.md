# Next Steps: Iteration 2 → Iteration 3

## Current Status

### ✅ Iteration 2 - Completed (Partial)
- ConfigMap `icloudpd-config` created and applied
- Template and instructions for secret creation provided
- **BLOCKED**: Waiting for Apple ID email to create `icloud-credentials` secret

### 📋 Iteration 2 - Remaining Task

**ACTION REQUIRED**: Create the `icloud-credentials` secret

Choose one of the following methods:

#### Method 1: Using kubectl directly (Quick)
```bash
kubectl create secret generic icloud-credentials \
  --from-literal=username='YOUR_APPLE_ID@example.com' \
  -n photo-sync
```

Replace `YOUR_APPLE_ID@example.com` with your actual Apple ID.

#### Method 2: Using the template file (Recommended for GitOps)
```bash
cd /Users/cfraser/Repos/homelab/ralph/photo-sync

# 1. Copy template
cp secret-icloud-credentials.yaml.template secret-icloud-credentials.yaml

# 2. Edit and replace <APPLE_ID_EMAIL> with your Apple ID
vim secret-icloud-credentials.yaml

# 3. Apply
kubectl apply -f secret-icloud-credentials.yaml

# 4. IMPORTANT: Delete the file (contains unencrypted credentials)
rm secret-icloud-credentials.yaml
```

**Verify**:
```bash
kubectl get secret -n photo-sync icloud-credentials
```

---

## 🚀 Iteration 3: Initial Authentication (Next)

Once the secret is created, proceed to Iteration 3 which involves:

### Prerequisites
- ✅ Namespace `photo-sync` exists
- ✅ PVCs `icloud-photos` and `icloudpd-config` created
- ✅ ConfigMap `icloudpd-config` created
- ⏳ Secret `icloud-credentials` created (PENDING)
- ⏳ User available for interactive 2FA session

### What Iteration 3 Will Do

1. **Deploy Interactive Authentication Pod**
   - Runs `boredazfcuk/icloudpd:latest` container
   - Mounts credentials secret and config PVC
   - Provides interactive terminal for authentication

2. **Interactive 2FA Process** (User Required)
   - You'll attach to the pod's terminal
   - Enter your Apple ID password
   - Receive 2FA code on your trusted Apple device
   - Enter the 2FA code in the terminal
   - Session cookies saved to `icloudpd-config` PVC

3. **Session Verification**
   - Verify session files were created
   - Clean up the auth pod

### Files to Create for Iteration 3

```yaml
# auth-pod.yaml
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
          value: "America/Los_Angeles"
  volumes:
    - name: credentials
      secret:
        secretName: icloud-credentials
    - name: config
      persistentVolumeClaim:
        claimName: icloudpd-config
```

### Iteration 3 Commands

```bash
# 1. Create and apply auth pod
kubectl apply -f photo-sync/auth-pod.yaml

# 2. Wait for pod to be ready
kubectl wait --for=condition=Ready pod/icloudpd-auth -n photo-sync --timeout=120s

# 3. Attach to interactive session
kubectl attach -it icloudpd-auth -n photo-sync

# 4. Complete authentication (follow prompts)
# - Enter Apple ID password
# - Enter 2FA code from trusted device

# 5. Verify session saved
kubectl exec -n photo-sync icloudpd-auth -- ls -la /config/

# 6. Clean up auth pod
kubectl delete pod icloudpd-auth -n photo-sync
```

### Important Notes for Iteration 3

- **Be Available**: The 2FA process requires real-time interaction
- **Have Your Device Ready**: You'll need access to a trusted Apple device to receive the 2FA code
- **Session Duration**: Auth sessions typically last ~90 days before re-authentication needed
- **Security**: Session cookies are stored in the `icloudpd-config` PVC (persistent across pod restarts)

---

## Progress Tracker

```
[████████████████░░░░░░░░░░] 28% Complete (2/7 iterations)

Iteration 1: Storage Infrastructure    [████████████████████] 100% ✅
Iteration 2: Credentials & Config      [██████████░░░░░░░░░░]  50% ⏸️ (Waiting for Apple ID)
Iteration 3: Initial Authentication    [░░░░░░░░░░░░░░░░░░░░]   0% 🔜 (Ready once secret created)
Iteration 4: CronJob Deployment        [░░░░░░░░░░░░░░░░░░░░]   0%
Iteration 5: Immich Integration        [░░░░░░░░░░░░░░░░░░░░]   0%
Iteration 6: External Exposure         [░░░░░░░░░░░░░░░░░░░░]   0%
Iteration 7: Verification              [░░░░░░░░░░░░░░░░░░░░]   0%
```

---

## Quick Reference

### Check Iteration 2 Completion
```bash
# Both should exist
kubectl get secret -n photo-sync icloud-credentials
kubectl get configmap -n photo-sync icloudpd-config
```

### Proceed to Iteration 3
Once both resources exist, you can immediately proceed to Iteration 3 using the auth-pod.yaml manifest and commands listed above.
