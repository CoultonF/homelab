# Mealie

Recipe management application with a PostgreSQL database backend.

## Resources

- Namespace: mealie
- Deployments: mealie, postgres
- Services: mealie (NodePort 30925), postgres
- Ingress: mealie-ingress (mealie.coultonf.com)
- PersistentVolumes: mealie-data-pv (10Gi), mealie-pgdata-pv (5Gi)
- PersistentVolumeClaims: mealie-data-pvc, mealie-pgdata-pvc
- ConfigMap: mealie-config

## Required Secrets

Create the required secrets before deploying:

```bash
kubectl create secret generic mealie-secrets \
  --from-literal=postgres-password=<your-postgres-password> \
  --from-literal=smtp-password=<your-smtp-password> \
  -n mealie
```

## Deployment Order

```bash
# 1. Create namespace
kubectl apply -f namespace.yaml

# 2. Create secrets (see above)

# 3. Create PersistentVolumes
kubectl apply -f mealie-data-pv.yaml
kubectl apply -f mealie-pgdata-pv.yaml

# 4. Create PersistentVolumeClaims
kubectl apply -f mealie-data-pvc-pvc.yaml
kubectl apply -f mealie-pgdata-pvc-pvc.yaml

# 5. Create ConfigMap
kubectl apply -f mealie-config-configmap.yaml

# 6. Deploy PostgreSQL
kubectl apply -f postgres-deployment.yaml
kubectl apply -f postgres-service.yaml

# 7. Deploy Mealie
kubectl apply -f mealie-deployment.yaml
kubectl apply -f mealie-service.yaml
kubectl apply -f mealie-ingress-ingress.yaml
```

## Access

- Internal: http://mealie.mealie.svc.cluster.local:9000
- NodePort: http://<node-ip>:30925
- Ingress: http://mealie.coultonf.com
