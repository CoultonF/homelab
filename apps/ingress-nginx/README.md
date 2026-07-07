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

Note: local HTTPS serves the controller's self-signed cert (Cloudflare
terminates TLS for public traffic). Use plain HTTP locally, or add
cert-manager later if local TLS matters.
