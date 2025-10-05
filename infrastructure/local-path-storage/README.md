# Local Path Storage Provisioner

Dynamic local storage provisioner for Kubernetes.

## Resources

- Namespace: local-path-storage
- Deployment: local-path-provisioner
- ConfigMap: local-path-config

## Deployment

```bash
kubectl apply -f namespace.yaml
kubectl apply -f local-path-config-configmap.yaml
kubectl apply -f local-path-provisioner-deployment.yaml
```

## Usage

This provisioner enables dynamic provisioning of local storage volumes. Configure StorageClass to use `local-path` provisioner.
