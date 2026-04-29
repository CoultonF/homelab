# silver-springs-watch

Hourly CronJob that emails new Calgary Silver Springs real-estate listings to
`cjrfraser@gmail.com`.

## How it works

1. CronJob fires at `:05` every hour (America/Edmonton).
2. Container installs `python3` + `@openai/codex` at startup (~45s cold start).
3. `codex exec` runs against `/app/PROMPT.md`, which instructs it to query the
   HouseSigma iOS endpoint and emit a pure-JSON array of current listings.
4. `watcher.py` parses the JSON, diffs against `/state/seen.json` (PVC-backed),
   sends a Gmail SMTP email if any IDs are new, then unions the seen-set.

The split (LLM-fetch + deterministic-state) keeps `seen.json` safe from LLM
drift while letting codex absorb auth + response-shape changes.

## Bootstrap

ArgoCD will sync the manifests, but the secret is created out-of-band:

```sh
kubectl create secret generic silver-springs-secrets \
  -n silver-springs-watch \
  --from-literal=openai-api-key='sk-...' \
  --from-literal=smtp-password='<gmail-app-password>' \
  --from-literal=housesigma-url='https://housesigma.com/api/...' \
  --from-literal=housesigma-token='<bearer-token>' \
  --from-literal=silver-springs-area-code='<area-code>'
```

The Gmail app password is the same value already in `mealie-secrets`. To
retrieve it:

```sh
kubectl get secret mealie-secrets -n mealie \
  -o jsonpath='{.data.smtp-password}' | base64 -d
```

## Smoke test

Trigger one run on demand:

```sh
kubectl create job --from=cronjob/silver-springs-watch \
  silver-springs-watch-test -n silver-springs-watch
kubectl logs -n silver-springs-watch -l job-name=silver-springs-watch-test -f
```

The first run sees an empty `seen.json` and emails every current listing —
expect a large initial email. Subsequent runs only email net-new listings.

Inspect persisted state:

```sh
POD=$(kubectl get pod -n silver-springs-watch \
  -l job-name=silver-springs-watch-test -o name | head -1)
kubectl exec -n silver-springs-watch "$POD" -- cat /state/seen.json
```

## Files

- `namespace.yaml` — namespace.
- `pvc.yaml` — 1Gi `local-path` PVC for `seen.json`.
- `script-configmap.yaml` — `PROMPT.md` (codex instructions) + `watcher.py`.
- `cronjob.yaml` — hourly CronJob, `node:20-slim` base, runtime-installed deps.
