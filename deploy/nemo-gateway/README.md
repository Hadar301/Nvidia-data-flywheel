# NeMo Gateway - Standalone Deployment

This directory contains Kubernetes manifests for deploying the NeMo Gateway as a standalone component.

## Overview

The NeMo Gateway is an NGINX-based reverse proxy that provides unified routing to NeMo Microservices and includes mock endpoints for base model metadata. It's deployed separately from the data-flywheel Helm chart to allow independent management.

## Components

- **deployment.yaml** - NeMo Gateway deployment (1 replica, NGINX 1.25-alpine)
- **service.yaml** - ClusterIP service (port 80)
- **configmap.yaml** - NGINX configuration with routing rules
- **route.yaml** - OpenShift Route for external HTTPS access
- **kustomization.yaml** - Kustomize manifest for easy deployment

## Deployment

### Using Kustomize (Recommended)

```bash
oc apply -k deploy/nemo-gateway/
```

### Using kubectl/oc directly

```bash
oc apply -f deploy/nemo-gateway/configmap.yaml
oc apply -f deploy/nemo-gateway/deployment.yaml
oc apply -f deploy/nemo-gateway/service.yaml
oc apply -f deploy/nemo-gateway/route.yaml
```

## Verify Deployment

```bash
# Check pods and services
oc get pods,svc,route -n hacohen-flywheel -l app=nemo-gateway

# Test health endpoint
GATEWAY_URL=$(oc get route nemo-gateway -n hacohen-flywheel -o jsonpath='https://{.spec.host}')
curl -k ${GATEWAY_URL}/healthz
```

Expected output: `OK`

## Gateway Routes

The gateway proxies the following NeMo service endpoints:

### NeMo Microservices
- `/v1/datasets` → `nemodatastore-sample:8000` - Dataset metadata registration
- `/v1/customization` → `nemocustomizer-sample:8000` - Fine-tuning jobs and LoRA configs
- `/v1/evaluation` → `nemoevaluator-sample:8000` - Model evaluation jobs
- `/v1/guardrails` → `nemoguardrails-sample:8000` - Safety filters
- `/v1/entity-store` → `nemoentitystore-sample:8000` - Model metadata (customized models)
- `/v1/namespaces` → `nemoentitystore-sample:8000` - Namespace management
- `/v1/datastore` → `nemodatastore-sample:8000` - Datastore operations
- `/v1/hf` → `nemodatastore-sample:8000` - HuggingFace API (repos, files)

### Git/LFS Operations
- `/{namespace}/{repo}.git/*` → `nemodatastore-sample:8000` - Git/LFS operations for HuggingFace Hub compatibility

### Mock Endpoints
- `/v1/deployment/model-deployments` - Returns success for NIM deployment requests (NIMs are pre-deployed)
- `/v1/deployment/model-deployments/{id}/{name}` - Returns ready status for deployed NIMs
- `/v1/models/meta/llama-3.2-1b-instruct` - Returns hardcoded metadata for base Llama model
- `/v1/models/{namespace}/customized-*` → `nemoentitystore-sample:8000` - Customized model metadata

## Configuration

### Namespace

The default namespace is `hacohen-flywheel`. To deploy to a different namespace:

1. Edit `kustomization.yaml` and update the `namespace` field
2. Edit `configmap.yaml` and update all service URLs to use your namespace

### NeMo Service Names

If your NeMo services have different names, update the upstream URLs in `configmap.yaml`:

```yaml
set $upstream_datastore <your-datastore-name>.<your-namespace>.svc.cluster.local:8000;
set $upstream_customizer <your-customizer-name>.<your-namespace>.svc.cluster.local:8000;
# ... etc
```

### Resource Limits

Default resource configuration:
- CPU: 100m request, 200m limit
- Memory: 128Mi request, 256Mi limit

To modify, edit the `resources` section in `deployment.yaml`.

## Troubleshooting

### Gateway Pod Not Starting

```bash
# Check pod status
oc get pods -n hacohen-flywheel -l app=nemo-gateway

# Check logs
oc logs -n hacohen-flywheel -l app=nemo-gateway
```

### Route Not Accessible

```bash
# Verify route exists
oc get route nemo-gateway -n hacohen-flywheel

# Check TLS configuration
oc describe route nemo-gateway -n hacohen-flywheel
```

### Service Routing Issues

```bash
# Test from inside the cluster
oc run test-curl --rm -it --image=curlimages/curl -n hacohen-flywheel -- \
  curl -s http://nemo-gateway/healthz

# Check NeMo service availability
oc get svc -n hacohen-flywheel | grep nemo
```

## Cleanup

```bash
# Using Kustomize
oc delete -k deploy/nemo-gateway/

# Or manually
oc delete deployment,service,configmap,route -l app=nemo-gateway -n hacohen-flywheel
```

## Integration with Data Flywheel

The data-flywheel Helm chart is configured to use this gateway via the `nemo_base_url` and `datastore_base_url` settings in `values-openshift-standalone.yaml`:

```yaml
config:
  nmp_config:
    nemo_base_url: "http://nemo-gateway"
    datastore_base_url: "http://nemo-gateway"
```

This ensures all Data Flywheel API calls to NeMo services route through the gateway.
