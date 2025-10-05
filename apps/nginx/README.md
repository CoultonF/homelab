# Nginx Example

Simple nginx deployment for testing purposes.

## Resources

- Deployment: nginx-example
- Service: nginx-example (ClusterIP)

## Deployment

```bash
kubectl apply -f nginx-example-deployment.yaml
kubectl apply -f nginx-example-service.yaml
```

## Access

- Internal: http://nginx-example.default.svc.cluster.local
