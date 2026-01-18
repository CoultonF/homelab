# Create iCloud Credentials Secret

## Required Information
You need to provide your **Apple ID email address** to create the credentials secret.

## Steps

### Option 1: Using the template file (Recommended)

1. Copy the template:
```bash
cp secret-icloud-credentials.yaml.template secret-icloud-credentials.yaml
```

2. Edit the file and replace `<APPLE_ID_EMAIL>` with your actual Apple ID:
```bash
# Use your preferred editor
vim secret-icloud-credentials.yaml
# OR
nano secret-icloud-credentials.yaml
```

3. Apply the secret:
```bash
kubectl apply -f secret-icloud-credentials.yaml
```

4. **IMPORTANT**: Delete the unencrypted file after applying:
```bash
rm secret-icloud-credentials.yaml
```

### Option 2: Using kubectl directly

```bash
kubectl create secret generic icloud-credentials \
  --from-literal=username='your-apple-id@example.com' \
  -n photo-sync
```

Replace `your-apple-id@example.com` with your actual Apple ID email.

## Verification

After creating the secret, verify it exists:
```bash
kubectl get secret -n photo-sync icloud-credentials
```

You should see output similar to:
```
NAME                 TYPE     DATA   AGE
icloud-credentials   Opaque   1      5s
```

## Next Steps

Once the secret is created, you can proceed to **Iteration 3: Initial Authentication** which requires:
- Interactive terminal session for 2FA
- Access to your trusted Apple device to receive 2FA codes
