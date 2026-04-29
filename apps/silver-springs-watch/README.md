# silver-springs-watch

Hourly CronJob that emails new Calgary Silver Springs real-estate listings to
`cjrfraser@gmail.com`.

## How it works

1. CronJob fires at `:05` every hour (America/Edmonton).
2. `python:3.12-slim` container pip-installs `requests`, runs `watcher.py`.
3. `watcher.py` calls HouseSigma's `bkv2/api`:
   - `POST /init/accesstoken/new` for a fresh bearer token.
   - `POST /auth/user/signin` with email/password + token to issue cookies.
   - `POST /search/mapsearchv3/list` with a Silver Springs bbox to list properties.
4. Filters response to Silver Springs by community-name match.
5. Diffs against `/state/seen.json` (PVC). Emails any new listings via Gmail SMTP.
6. Persists union of seen + current ids.

## Bootstrap

Create the secret out-of-band before Argo syncs the CronJob:

```sh
kubectl create namespace silver-springs-watch --dry-run=client -o yaml | kubectl apply -f -

SMTP_PW=$(kubectl get secret mealie-secrets -n mealie -o jsonpath='{.data.smtp-password}' | base64 -d)

kubectl create secret generic silver-springs-secrets \
  -n silver-springs-watch \
  --from-literal=house-sigma-email='<housesigma-account-email>' \
  --from-literal=house-sigma-password='<housesigma-account-password>' \
  --from-literal=smtp-password="$SMTP_PW"
```

The `house-sigma-*` values are the same ones in
`github.com/CoultonF/calgary-home-search` (`.env` vars `HOUSE_SIGMA_EMAIL` /
`HOUSE_SIGMA_PASSWORD`).

## Smoke test

Trigger one run on demand:

```sh
kubectl create job --from=cronjob/silver-springs-watch \
  silver-springs-watch-test -n silver-springs-watch
kubectl logs -n silver-springs-watch -l job-name=silver-springs-watch-test -f
```

The first run sees an empty `seen.json` and emails every current Silver
Springs listing — expect a large initial email. Subsequent runs only email
net-new listings.

Inspect persisted state:

```sh
POD=$(kubectl get pod -n silver-springs-watch \
  -l job-name=silver-springs-watch-test -o name | head -1)
kubectl exec -n silver-springs-watch "$POD" -- cat /state/seen.json
```

## Files

- `namespace.yaml` — namespace.
- `pvc.yaml` — 1Gi `local-path` PVC for `seen.json`.
- `script-configmap.yaml` — `watcher.py`.
- `cronjob.yaml` — hourly CronJob, `python:3.12-slim` base.

## Notes

- HouseSigma's bbox search returns paginated results. `page_size=50` is enough
  for a single Calgary neighbourhood; pagination not implemented.
- Bbox is hard-coded to roughly cover the Silver Springs polygon; results are
  also community-name filtered as a safety net so neighbouring communities
  (Scenic Acres, Dalhousie) don't slip in.
- Gmail app password is shared with `mealie-secrets/smtp-password`.
- HouseSigma may rotate `HS-Client-Version` periodically; if requests start
  failing with 4xx, bump `HS-Client-Version` in `watcher.py`.
