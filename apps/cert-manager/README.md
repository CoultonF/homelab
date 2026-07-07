# cert-manager

`deploy.yaml` is the upstream static manifest (v1.20.3), unmodified.

`issuer.yaml` adds a Let's Encrypt ClusterIssuer (DNS-01 via Cloudflare) and
a wildcard `*.coultonf.com` Certificate in the `ingress-nginx` namespace,
which ingress-nginx uses as its default TLS certificate
(`--default-ssl-certificate`). Every `https://<app>.coultonf.com` served
locally by ingress-nginx gets a valid cert with no per-app TLS config.

## Manual setup (once)

DNS-01 needs a Cloudflare API token with **Zone → DNS → Edit** on
`coultonf.com` (create at dash.cloudflare.com → My Profile → API Tokens).
The secret is NOT in git (public repo):

```sh
kubectl -n cert-manager create secret generic cloudflare-api-token \
  --from-literal=api-token='<TOKEN>'
```

Renewals are automatic (cert-manager re-issues ~30 days before expiry).
