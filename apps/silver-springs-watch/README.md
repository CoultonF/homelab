# silver-springs-watch

Hourly CronJob that emails new Calgary Silver Springs real-estate listings to
`cjrfraser@gmail.com`.

## How it works

1. CronJob fires at `:05` every hour (America/Edmonton).
2. `python:3.12-slim` container pip-installs `requests`, runs `watcher.py`.
3. `watcher.py` hits the **HouseSigma iOS API** at `api.housesigma.com`:
   - `POST /bkv2/api/search/mapsearchv3/listing` (clusters/markers with ids)
   - `POST /bkv2/api/search/mapsearchv3/feature` (featured listings + MLS)
4. Auth is a long-lived bearer token (`HOUSE_SIGMA_TOKEN`) captured from the
   iOS app via mitmproxy. No signin, no signing, no payload encryption.
5. Filters by Silver Springs lat/lng bbox in the request itself.
6. Diffs ids against `/state/seen.json` (PVC). Emails any new listings via
   Gmail SMTP.
7. Persists union of seen + current ids.

The detailed-listing endpoint (`/listing/preview/many`) is AES-encrypted
and intentionally not used; the email links to the HouseSigma webview
(`https://housesigma.com/h5/en/listing/<id>`) where the user can see
full address / beds / baths / photos.

## Bootstrap

Create the secret out-of-band before Argo syncs the CronJob:

```sh
kubectl create namespace silver-springs-watch --dry-run=client -o yaml | kubectl apply -f -

SMTP_PW=$(kubectl get secret mealie-secrets -n mealie -o jsonpath='{.data.smtp-password}' | base64 -d)

kubectl create secret generic silver-springs-secrets \
  -n silver-springs-watch \
  --from-literal=house-sigma-token='<bearer-token-from-ios-app>' \
  --from-literal=smtp-password="$SMTP_PW"
```

To recapture the token (e.g. if it rotates), run mitmproxy on a Mac, set
the iPhone's Wi-Fi proxy to it, install the mitmproxy CA cert, open the
HouseSigma app, and grab the `Authorization: Bearer …` header value from
any `api.housesigma.com` request.

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

- Bbox is hard-coded to cover the Silver Springs polygon (roughly
  51.105–51.130 lat, -114.215 to -114.165 lon). Tighten in `watcher.py` if
  neighbouring communities (Scenic Acres, Dalhousie) leak in.
- Gmail app password is shared with `mealie-secrets/smtp-password`.
- HouseSigma may rotate the iOS `HS-Client-Version` periodically; if requests
  start failing with 4xx, bump it in `watcher.py` to match the current
  iOS app build.
- The bearer token is long-lived but not infinite — the captured one starts
  with `20241231...` (Dec 31 2024 issue date). If 4xx returns, recapture.
