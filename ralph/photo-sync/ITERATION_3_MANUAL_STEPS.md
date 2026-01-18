# Iteration 3: Manual Authentication Steps

## ⚠️ USER ACTION REQUIRED

This iteration requires **interactive user participation** for 2FA authentication with iCloud.

## Prerequisites

Before starting, ensure:
- ✅ You have created the `icloud-credentials` secret with your Apple ID
- ✅ You have access to a trusted Apple device (iPhone, iPad, Mac) to receive 2FA codes
- ✅ You are ready to complete the process in one session (takes ~5 minutes)

## Steps

### 1. Create the iCloud Credentials Secret

**If you haven't already created the secret**, run ONE of these commands:

**Option A: Quick method (kubectl)**
```bash
kubectl create secret generic icloud-credentials \
  --from-literal=username='YOUR_APPLE_ID@example.com' \
  -n photo-sync
```

**Option B: Using template file**
```bash
cd /Users/cfraser/Repos/homelab/ralph/photo-sync

# Copy and edit template
cp secret-icloud-credentials.yaml.template secret-icloud-credentials.yaml
# Edit the file and replace <APPLE_ID_EMAIL> with your Apple ID
vim secret-icloud-credentials.yaml

# Apply
kubectl apply -f secret-icloud-credentials.yaml

# Delete file (contains unencrypted credentials)
rm secret-icloud-credentials.yaml
```

**Verify secret exists:**
```bash
kubectl get secret -n photo-sync icloud-credentials
```

### 2. Deploy the Authentication Pod

```bash
cd /Users/cfraser/Repos/homelab/ralph/photo-sync
kubectl apply -f auth-pod.yaml
```

### 3. Wait for Pod to Be Ready

```bash
kubectl wait --for=condition=Ready pod/icloudpd-auth -n photo-sync --timeout=120s
```

You should see: `pod/icloudpd-auth condition met`

### 4. Attach to Interactive Session

```bash
kubectl attach -it icloudpd-auth -n photo-sync
```

### 5. Complete Interactive Authentication

You will see prompts like this:

```
Enter iCloud password for YOUR_APPLE_ID@example.com:
```

**Actions:**
1. **Enter your Apple ID password** (typing will be hidden)
2. **Press Enter**
3. Wait for 2FA code to be sent to your trusted device
4. You'll see a prompt like:
   ```
   Enter the 2FA code sent to your device:
   ```
5. **Enter the 6-digit 2FA code**
6. **Press Enter**

If successful, you'll see:
```
Authentication successful
Cookies saved
```

The session will stay open for 3600 seconds (1 hour) to allow verification.

### 6. Verify Session Was Saved

**Open a NEW terminal window** and run:

```bash
kubectl exec -n photo-sync icloudpd-auth -- ls -la /config/
```

You should see session/cookie files created in the `/config/` directory.

### 7. Clean Up Authentication Pod

Once verified, delete the auth pod:

```bash
kubectl delete pod icloudpd-auth -n photo-sync
```

The authentication session is now saved in the `icloudpd-config` PVC and will persist for ~90 days.

## Troubleshooting

### Pod won't start
```bash
# Check pod status
kubectl describe pod icloudpd-auth -n photo-sync

# Common issues:
# - Secret not created: Verify with `kubectl get secret -n photo-sync icloud-credentials`
# - PVC not available: Check `kubectl get pvc -n photo-sync`
```

### Authentication fails
- **Wrong password**: Delete pod and try again: `kubectl delete pod icloudpd-auth -n photo-sync`
- **2FA timeout**: You have ~1 minute to enter the code. If it times out, delete pod and restart
- **Account locked**: Check your Apple ID account status at appleid.apple.com

### Can't attach to pod
```bash
# Check if pod is running
kubectl get pod -n photo-sync icloudpd-auth

# View logs
kubectl logs -n photo-sync icloudpd-auth
```

## Success Criteria

After completing these steps, you should have:
- ✅ Secret `icloud-credentials` exists
- ✅ Auth pod deleted (temporary resource)
- ✅ Session files saved in `icloudpd-config` PVC
- ✅ Ready to proceed to Iteration 4 (CronJob deployment)

## Next Steps

Once authentication is complete, proceed to **Iteration 4** to deploy the scheduled sync CronJob.
