# Data Flywheel Prerequisites for OpenShift

Infrastructure prerequisites Helm chart for deploying [NVIDIA Data Flywheel](https://github.com/NVIDIA-AI-Blueprints/data-flywheel) on top of [NeMo Microservices](https://github.com/RHEcosystemAppEng/NeMo-Microservices) on OpenShift.

## Overview

This Helm chart deploys the backend infrastructure services required by the NVIDIA Data Flywheel application:

- **Elasticsearch 8.5.1** - Logging and storage for prompt/completion data
- **Redis 7.2.x** - Task queue broker and results backend for Celery
- **MongoDB 7.0.x** - API metadata and application data storage
- **NGINX Gateway** - Unified API gateway routing both NeMo services and Data Flywheel API

## Prerequisites

### Required: NeMo Microservices Deployment

This chart assumes you have already deployed the [NeMo Microservices](https://github.com/RHEcosystemAppEng/NeMo-Microservices) infrastructure on your OpenShift cluster. The following NeMo services should be running:

- `nemodatastore-sample` - Dataset management and HuggingFace API
- `nemocustomizer-sample` - Fine-tuning jobs and LoRA configurations
- `nemoevaluator-sample` - Model evaluation jobs
- `nemoguardrails-sample` - Safety filters and content moderation
- `nemoentitystore-sample` - Model metadata and PEFT models

The NGINX gateway deployed by this chart will provide unified routing to both NeMo services and the Data Flywheel API.

### OpenShift Requirements

- OpenShift 4.12+ cluster
- Cluster admin access for SCC configuration
- Storage class with dynamic provisioning (for persistent volumes)
- Namespace with sufficient resource quotas:
  - CPU: ~2.5 cores minimum
  - Memory: ~3-4 GB minimum
  - Storage: ~60 GB minimum (Elasticsearch: 30GB, Redis: 8GB, MongoDB: 20GB)

### Required Tools

- `helm` 3.x
- `kubectl` or `oc` CLI
- `make` (optional, for automation)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│            OpenShift Route (HTTPS - TLS Edge)                │
│              nemo-gateway.apps.cluster.com                   │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │   NGINX Gateway      │
              │    (nemo-gateway)    │
              └──────────┬───────────┘
                         │
        ┌────────────────┼────────────────┬──────────────┐
        ▼                ▼                ▼              ▼
  ┌──────────┐    ┌──────────┐    ┌──────────┐   ┌──────────┐
  │   NeMo   │    │   Data   │    │Backend Infrastructure  │
  │ Services │    │ Flywheel │    │                        │
  │          │    │   API    │    │  - Elasticsearch       │
  │ /v1/*    │    │   /      │    │  - Redis               │
  │          │    │          │    │  - MongoDB             │
  └──────────┘    └──────────┘    └──────────────────────┘
```

### Gateway Routing

The NGINX gateway routes requests as follows:

| Path                  | Target Service           | Purpose                           |
|-----------------------|--------------------------|-----------------------------------|
| `/healthz`            | Gateway itself           | Health check endpoint             |
| `/v1/datasets`        | `nemodatastore-sample`   | Dataset management, HuggingFace   |
| `/v1/customization`   | `nemocustomizer-sample`  | Fine-tuning jobs, LoRA configs    |
| `/v1/evaluation`      | `nemoevaluator-sample`   | Model evaluation                  |
| `/v1/guardrails`      | `nemoguardrails-sample`  | Safety filters                    |
| `/v1/entity-store`    | `nemoentitystore-sample` | Model metadata, PEFT models       |
| `/` (all other paths) | `data-flywheel-api`      | Data Flywheel API (to be deployed)|

## Quick Start

### 1. Configure Namespace

Create a `.env` file in the repository root with your target namespace:

```bash
# .env
NAMESPACE="your-namespace-name"
```

The Makefile will automatically read this file and use the configured namespace.

### 2. Install Prerequisites

```bash
cd deploy
make install-prereqs
```

This single command will:
1. Grant `anyuid` SCC to the Elasticsearch service account (required for UID 1000)
2. Update Helm chart dependencies
3. Install Elasticsearch, Redis, MongoDB, and the NGINX gateway
4. Wait for all services to be ready
5. Display deployment status

### 3. Verify Installation

```bash
make verify
```

Expected output:
```
=== Running Verification Checks ===

1. Checking Elasticsearch...
✓ Elasticsearch is healthy

2. Checking Redis...
✓ Redis is responding

3. Checking MongoDB...
✓ MongoDB is responding

4. Checking Gateway...
✓ Gateway health check passed

=== Gateway URL ===
https://nemo-gateway-$NAMESPACE.apps.cluster.com
```

## Configuration

### Service Endpoints

The Data Flywheel application should use these internal service endpoints:

```yaml
ELASTICSEARCH_URL: https://elasticsearch-master:9200
MONGODB_URL: mongodb://flywheel-infra-mongodb:27017
MONGODB_DB: flywheel
REDIS_URL: redis://flywheel-infra-redis-master:6379/0
ES_COLLECTION_NAME: flywheel
```

**Note**: Elasticsearch uses HTTPS with self-signed certificates. Applications should disable certificate verification for internal cluster communication.

### Customizing the Deployment

Edit [values.yaml](values.yaml) to customize:

- **Namespace**: Override via `.env` file or pass `--set namespace.name=your-namespace` to Helm
- **Resource limits**: Adjust CPU/memory under `elasticsearch`, `redis`, `mongodb`
- **Storage sizes**: Modify `volumeClaimTemplate.resources.requests.storage`
- **Gateway settings**: Update `gateway.image`, `gateway.replicas`, etc.
- **NeMo service names**: If your NeMo services use different names, update the `datastore`, `customizer`, `evaluator`, `guardrail`, and `entitystore` sections

### Security Configuration

**Development mode (current configuration):**
- Elasticsearch: HTTPS enabled, authentication disabled
- Redis: No authentication
- MongoDB: No authentication

**Production mode (recommended):**

Enable authentication by updating `values.yaml`:

```yaml
elasticsearch:
  esConfig:
    elasticsearch.yml: |
      xpack.security.enabled: true
      xpack.security.http.ssl.enabled: true

redis:
  auth:
    enabled: true
    password: "your-secure-password"

mongodb:
  auth:
    enabled: true
    rootPassword: "your-secure-password"
```

## Makefile Commands

The included Makefile provides convenient automation:

```bash
# Show all available commands
make help

# Install prerequisites
make install-prereqs

# Upgrade existing deployment
make upgrade-prereqs

# Check deployment status
make status

# Verify all services are healthy
make verify

# Uninstall everything
make uninstall-prereqs

# View service logs
make logs-elasticsearch
make logs-redis
make logs-mongodb
make logs-gateway

# Port-forward for local access
make port-forward-elasticsearch  # Access on localhost:9200
make port-forward-redis          # Access on localhost:6379
make port-forward-mongodb        # Access on localhost:27017

# Clean Helm artifacts
make clean
```

## Manual Deployment

If you prefer not to use the Makefile:

```bash
# Update Helm dependencies
cd deploy/flywheel-prerequisites
helm dependency update

# Install the chart
helm install flywheel-infra . \
  --namespace $NAMESPACE \
  --create-namespace \
  --wait \
  --timeout 10m

# Verify deployment
kubectl get pods -n $NAMESPACE
kubectl get svc -n $NAMESPACE
oc get routes -n $NAMESPACE

# Uninstall
helm uninstall flywheel-infra --namespace $NAMESPACE
```

## Troubleshooting

### Elasticsearch Pod Not Starting

**Issue**: Elasticsearch pod shows `CrashLoopBackOff` or permission errors.

**Solution**: Ensure the `anyuid` SCC is granted:
```bash
oc adm policy add-scc-to-user anyuid -z elasticsearch-master -n $NAMESPACE
kubectl delete pod elasticsearch-master-0 -n $NAMESPACE
```

### Gateway Returns 502 Bad Gateway

**Issue**: Gateway responds with 502 when accessing NeMo services or Data Flywheel API.

**Cause**: Backend service doesn't exist or isn't ready.

**Solution**:
1. Verify NeMo services are running: `kubectl get pods -n $NAMESPACE | grep nemo`
2. The Data Flywheel API will show 502 until deployed (this is expected)
3. Check gateway logs: `make logs-gateway`

### Storage Issues

**Issue**: PVCs stuck in `Pending` state.

**Solution**:
1. Check available storage classes: `kubectl get storageclass`
2. Verify cluster has sufficient storage quota
3. Update `values.yaml` to specify a different storage class if needed

### Redis Connection Refused

**Issue**: Applications can't connect to Redis.

**Solution**: Verify Redis is running and accessible:
```bash
kubectl exec -it flywheel-infra-redis-master-0 -n $NAMESPACE -- redis-cli ping
# Should return: PONG
```

## Next Steps

After deploying these prerequisites:

1. **Deploy the Data Flywheel API**: Follow the instructions in the [Data Flywheel repository](https://github.com/NVIDIA-AI-Blueprints/data-flywheel) to deploy the FastAPI application and Celery workers

2. **Configure environment variables**: Use the service endpoints listed in the [Configuration](#configuration) section

3. **Test the integration**: Access the gateway URL and verify routing to both NeMo services and Data Flywheel API

## Resource Requirements Summary

| Service       | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage |
|---------------|-------------|-----------|----------------|--------------|---------|
| Elasticsearch | 500m        | 1000m     | 1Gi            | 2Gi          | 30Gi    |
| Redis         | 250m        | 500m      | 256Mi          | 512Mi        | 8Gi     |
| MongoDB       | 500m        | 1000m     | 512Mi          | 1Gi          | 20Gi    |
| NGINX Gateway | 100m        | 200m      | 128Mi          | 256Mi        | -       |
| **Total**     | **1.35**    | **2.7**   | **~2Gi**       | **~4Gi**     | **58Gi**|

## Chart Information

- **Chart Version**: 0.1.0
- **App Version**: 1.0
- **Dependencies**:
  - Elasticsearch 8.5.1 (from https://helm.elastic.co)
  - Redis 24.1.2 (from https://charts.bitnami.com/bitnami)
  - MongoDB 18.3.0 (from https://charts.bitnami.com/bitnami)

## Support and Contributing

For issues related to:
- **NeMo Microservices deployment**: See [RHEcosystemAppEng/NeMo-Microservices](https://github.com/RHEcosystemAppEng/NeMo-Microservices)
- **Data Flywheel application**: See [NVIDIA-AI-Blueprints/data-flywheel](https://github.com/NVIDIA-AI-Blueprints/data-flywheel)
- **This infrastructure chart**: Open an issue in this repository

## License

See the parent repository for license information.
