# ingress-nginx

Vendored from upstream `deploy/static/provider/baremetal/deploy.yaml`
(controller-v1.13.3), with two changes:

1. **hostNetwork: true** on the controller — it binds ports 80/443 directly
   on the node (192.168.0.249), making every `ingressClassName: nginx`
   Ingress in this repo reachable on the LAN without Cloudflare.
2. **Admission webhook removed** (ValidatingWebhookConfiguration, certgen
   Jobs, and the webhook args/ports/volumes) — one less moving part, and
   ArgoCD auto-sync doesn't fight completed Jobs.

Split-horizon DNS lives in `apps/coredns/configmap.yaml`: hostnames listed
in the `hosts` block of the default zone resolve to the node LAN IP for
local/tailnet clients. Add one line there per hostname to short-circuit
more apps.

Local HTTPS serves the Let's Encrypt wildcard `*.coultonf.com` cert
(`--default-ssl-certificate`, issued by cert-manager — see
`apps/cert-manager/`), so internal `https://` validates for every
app hostname. The controller uses hostPort bound to 192.168.0.249
specifically because tailscaled owns 443 on the node's tailscale IP.
