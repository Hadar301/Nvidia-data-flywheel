# NVIDIA Data Flywheel - OpenShift Installation Guide

This guide provides step-by-step instructions for deploying the NVIDIA Data Flywheel on an OpenShift cluster.

## Target Platform

**OpenShift Cluster Deployment** - This guide is specifically for OpenShift cluster installations, not local Docker deployments.

## Prerequisites

Before starting, ensure you have:

1. **OpenShift Cluster Access**
   - OpenShift cluster with GPU-enabled nodes
   - Permissions to create and manage resources in a namespace
   - Ability to grant SecurityContextConstraints (anyuid, privileged) - may require admin assistance for initial SCC setup
   - Access to install Custom Resource Definitions (CRDs) if not already present - may require admin assistance

2. **Required Tools**
   - `oc` CLI configured and authenticated to your cluster
   - `helm` CLI (version 3.8+)
   - `jq` for JSON processing
   - `git` for cloning repositories

3. **API Credentials**
   - **NVIDIA_API_KEY**: Remote LLM judge and embeddings ([Get from build.nvidia.com](https://build.nvidia.com/))
   - **NGC_API_KEY**: NVIDIA container registry access ([Get from ngc.nvidia.com](https://ngc.nvidia.com/setup/api-key))
   - **HF_TOKEN**: HuggingFace dataset access

## What This Guide Covers

This installation process deploys:
1. **NeMo Microservices** - Platform for model serving, customization, and evaluation
2. **Flywheel Prerequisites** - Infrastructure services (Elasticsearch, Redis, MongoDB, Gateway)
3. **Data Flywheel Components** - API, Celery workers, MLflow tracking
4. **Validation** - End-to-end testing via Jupyter notebook

---

## Step 0: Prepare Environment

### Create .env File

Create a `.env` file in the repository root with your credentials:

```bash
cd Nvidia-data-flywheel
cp .env.example .env
```

Edit `.env` and set your values:

```bash
NAMESPACE="your-namespace-name"
NVIDIA_API_KEY="nvapi-your-nvidia-api-key"
NGC_API_KEY="your-ngc-api-key"
HF_TOKEN="hf_your-huggingface-token"
```

### Load Environment Variables

```bash
source .env
```

---

## Step 1: Clone Required Repositories

Run the clone script to download NeMo-Microservices and data-flywheel repositories:

```bash
./scripts/clone.sh
```

This creates:
- `NeMo-Microservices/` - NeMo platform deployment charts
- `data-flywheel/` - Data Flywheel Helm chart

---

## Step 2: Deploy NeMo Microservices

### Pre-Installation: Check Your Cluster

#### 1. Find GPU Node Taints

Identify GPU node taints to configure pod scheduling:

```bash
# List all GPU nodes and their taints
oc get nodes -o json | jq -r '.items[] | select(.metadata.labels."nvidia.com/gpu.present"=="true") | {name: .metadata.name, taints: .spec.taints}'

# Or simpler output
oc describe nodes -l nvidia.com/gpu.present=true | grep Taints
```

**Common taint patterns:**
- `nvidia.com/gpu:NoSchedule`
- `g6e-gpu=true:NoSchedule`
- Custom cluster-specific taints

If your cluster has custom GPU taints, update tolerations in:
- `NeMo-Microservices/deploy/nemo-instances/values.yaml`

#### 2. Check Existing CRDs

Check if cluster already has Argo Workflows or Volcano CRDs:

```bash
# Check for Argo Workflows CRDs
oc get crds | grep argoproj.io

# Check for Volcano CRDs
oc get crds | grep volcano.sh

# Check ownership of existing CRDs (replace <crd-name>)
oc get crd <crd-name> -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-namespace}'
```

**Note**: If CRDs exist from previous installations, OpenDataHub, or Kubeflow, the installation script will handle adoption automatically.

#### 3. Pre-Installation Checklist

Verify your cluster meets these requirements:

| Requirement | Check Command | Expected Result | Action if Missing |
|------------|---------------|-----------------|-------------------|
| **GPU Node Taints** | `oc describe nodes -l nvidia.com/gpu.present=true \| grep Taints` | List of taints (e.g., `g6e-gpu=true:NoSchedule`) | Update `NeMo-Microservices/deploy/nemo-instances/values.yaml` with your taint keys |
| **Existing CRDs** | `oc get crds \| grep -E "argoproj\\.io\|volcano\\.sh"` | May show existing CRDs | Script handles adoption; see [knowledge/knowledge_dump_NeMo.md](knowledge/knowledge_dump_NeMo.md) if conflicts occur |
| **Storage Class** | `oc get storageclass` | Available storage class (e.g., `gp3-csi`) | Update `NeMo-Microservices/deploy/nemo-infra/values.yaml` with your storage class name |
| **Namespace UID Range** | `oc get namespace $NAMESPACE -o jsonpath='{.metadata.annotations.openshift\\.io/sa\\.scc\\.uid-range}'` | UID range (e.g., `1000790000/10000`) | Note for troubleshooting permission errors |
| **Available GPUs** | `oc get nodes -l nvidia.com/gpu.present=true -o json \| jq '.items[].status.allocatable."nvidia.com/gpu"'` | Total GPU count | Plan NIM deployments based on available resources |

### Installation Script Overview

The `scripts/install-nemo.sh` script automates NeMo deployment with:

- **Resource Adoption**: Adopts existing CRDs, ClusterRoles, Webhooks, and SCCs from previous installations
- **NGC Secret Creation**: Creates image pull and API secrets for NVIDIA registry
- **nemo-infra Installation**: Deploys PostgreSQL, MinIO, Milvus, Argo Workflows, Volcano scheduler
- **nemo-instances Installation**: Deploys NeMo services (Datastore, Entity Store, Customizer, Evaluator, Guardrails) and NIM pipelines
- **GPU Resource Management**: Scales down unused models to conserve GPU resources

### Run Installation

```bash
./scripts/install-nemo.sh
```

The script will:
1. Validate prerequisites (`oc` and `helm` CLIs)
2. Load configuration from `.env`
3. Create namespace and NGC secrets
4. Adopt existing cluster resources if needed
5. Install nemo-infra and nemo-instances
6. Verify installation

**Expected Duration**: 10-20 minutes depending on cluster resources

### Common Issues

If you encounter errors during installation, see [knowledge/knowledge_dump_NeMo.md](knowledge/knowledge_dump_NeMo.md) for detailed troubleshooting:

1. **Volcano/Argo CRD Conflicts**: Script attempts automatic adoption; manual intervention may be needed
2. **Field Manager Conflicts**: Automatically resolved by clearing `managedFields`
3. **SCC Ownership**: Script updates SecurityContextConstraints ownership
4. **MinIO Environment Variables**: Already fixed in values.yaml

---

## Step 3: Install Flywheel Prerequisites

Deploy infrastructure services (Elasticsearch, Redis, MongoDB, NeMo Gateway):

```bash
cd deploy
make install-prereqs
```

This command:
1. Grants `anyuid` SCC to Elasticsearch and default service accounts
2. Updates Helm chart dependencies
3. Installs all infrastructure services (10-minute timeout)
4. Configures NeMo Evaluator to use the gateway
5. Displays deployment status

### Components Installed

| Component | Version | Purpose | Storage |
|-----------|---------|---------|---------|
| **Elasticsearch** | 8.5.1 | Stores training/evaluation data and prompts | 30Gi PVC |
| **Redis** | 24.x | Celery task queue broker and results backend | 8Gi PVC |
| **MongoDB** | 18.x | API metadata and workflow state storage | 20Gi PVC |
| **NGINX Gateway** | 1.25-alpine | Unified routing to NeMo services + mock Entity Store endpoints | None |

### Gateway Routes

The gateway provides unified access to NeMo services:

- `/v1/datasets` → nemodatastore-sample (dataset management)
- `/v1/customization` → nemocustomizer-sample (fine-tuning jobs)
- `/v1/evaluation` → nemoevaluator-sample (model evaluation)
- `/v1/entity-store` → nemoentitystore-sample (model metadata for customized models)
- `/v1/namespaces` → nemoentitystore-sample (namespace management)
- `/v1/datastore` → nemodatastore-sample (datastore operations)
- `/v1/hf` → nemodatastore-sample (HuggingFace API)
- `/v1/models/{namespace}/{name}` → Mock endpoint (base NIM metadata)

**For detailed troubleshooting**, see [knowledge/knowledge_dump_flywheel_prereqs.md](knowledge/knowledge_dump_flywheel_prereqs.md).

---

## Step 4: Deploy Data Flywheel Components

Install Data Flywheel services using the integrated Makefile:

```bash
cd deploy
make install-flywheel
```

This command:
1. Ensures prerequisites are installed
2. Validates environment variables (NGC_API_KEY, NVIDIA_API_KEY, HF_TOKEN)
3. Configures NeMo Evaluator to use the gateway
4. Fixes RBAC permissions for NeMo Evaluator (adds delete permission for secrets)
5. Fixes model file permissions for customization jobs
6. Deploys Data Flywheel Helm chart with OpenShift values
7. Configures OpenShift security (service accounts, SCCs)
8. Displays deployment status

### Key Configuration

The deployment uses [deploy/flywheel-components/values-openshift.yaml](deploy/flywheel-components/values-openshift.yaml) with:

#### Service Endpoints
- **NeMo Gateway**: `http://nemo-gateway` (unified access to all NeMo services)
- **NIM for Inference**: `http://meta-llama3-1b-instruct:8000`
- **Infrastructure Services**: Elasticsearch, Redis, MongoDB (cluster-internal DNS)

#### Remote API Services (conserves cluster GPU resources)
- **LLM Judge**: NVIDIA API (`meta/llama-3.3-70b-instruct`)
- **Embeddings**: NVIDIA API (`nvidia/llama-3.2-nv-embedqa-1b-v2`)

#### Deployed Components
- **df-api**: Data Flywheel REST API (port 8000)
- **df-celery-worker**: Async job processor (evaluation, fine-tuning)
- **df-celery-parent-worker**: Parent job orchestrator
- **df-mlflow**: Experiment tracking server (port 5000)
- **df-flower**: Celery task monitoring UI (port 5555)

**For detailed troubleshooting**, see [knowledge/knowledge_dump_DataFlywheel.md](knowledge/knowledge_dump_DataFlywheel.md).

---

## Step 5: Validate Deployment

### Port-Forward Services

Use the automated port-forward script to access services locally:

```bash
cd ..
./scripts/port-forward.sh
```

This forwards:
- **Data Flywheel API**: localhost:8000
- **MLflow UI**: localhost:5000
- **Elasticsearch**: localhost:9200
- **MongoDB**: localhost:27017
- **Redis**: localhost:6379
- **NeMo Gateway**: localhost:8080
- **NIM (meta-llama3-1b-instruct)**: localhost:9001

Or manually forward specific services:

```bash
oc port-forward -n $NAMESPACE svc/df-api-service 8000:8000 &
oc port-forward -n $NAMESPACE svc/df-mlflow-service 5000:5000 &
oc port-forward -n $NAMESPACE svc/df-flower-service 5555:5555 &
```

### Run Validation Notebook

Run the comprehensive validation notebook to test the entire stack:

```bash
# Ensure port-forwards are running
jupyter notebook notebooks/data-flywheel-bp-tutorial.ipynb
```

The notebook validates:
- Infrastructure connectivity (Elasticsearch, Redis, MongoDB, NeMo Gateway)
- Data Flywheel API endpoints
- MLflow experiment tracking
- Celery job processing (via Flower UI)
- NeMo service integration (datasets, customization, evaluation)
- End-to-end workflows: base-eval, icl-eval, fine-tuning

**Expected Result**: No errors in notebook execution

**For comprehensive tutorial and troubleshooting**, see [demo/data-flywheel-bp-tutorial.md](demo/data-flywheel-bp-tutorial.md).

---

## Useful Commands

### Check Deployment Status

```bash
# Check all deployments
cd deploy
make status

# Check Data Flywheel specific status
make status-flywheel

# Check prerequisite services health
make verify
```

### View Logs

```bash
# Data Flywheel API logs
oc logs -n $NAMESPACE deployment/df-api-deployment --tail=100 -f

# Celery worker logs
oc logs -n $NAMESPACE deployment/df-celery-worker-deployment --tail=100 -f

# Infrastructure logs
make logs-elasticsearch
make logs-redis
make logs-mongodb
make logs-gateway
```

### Upgrade Deployments

```bash
# Upgrade flywheel prerequisites
make upgrade-prereqs

# Upgrade Data Flywheel
make upgrade-flywheel
```

### Cleanup

```bash
# Uninstall Data Flywheel (keeps prerequisites)
make uninstall-flywheel

# Uninstall prerequisites
make uninstall-prereqs

# Complete namespace cleanup (development only)
../scripts/clear_namespace.sh
```

---

## Troubleshooting

### Pods in CrashLoopBackOff

Check secrets and logs:

```bash
# Check if secrets are properly set
oc get secret nvidia-api hf-secret -n $NAMESPACE -o yaml

# Check pod logs
oc logs -n $NAMESPACE <pod-name>

# Verify service account has anyuid SCC
oc get scc anyuid -o yaml | grep -A 20 users:
```

### API Validation Failures

Verify NVIDIA API key:

```bash
# Test NVIDIA API connectivity
oc run test-curl --rm -it --image=curlimages/curl -- \
  curl https://integrate.api.nvidia.com/v1/models
```

### Base Model Evaluations Failing

If `base-eval` or `icl-eval` fail with 404 errors for base models:

```bash
# Ensure NeMo Evaluator is configured to use gateway
oc set env deployment/nemoevaluator-sample -n $NAMESPACE ENTITY_STORE_URL="http://nemo-gateway"

# Wait for restart
oc rollout status deployment/nemoevaluator-sample -n $NAMESPACE
```

### Customization Jobs Permission Denied

If fine-tuning jobs fail with permission errors:

```bash
# Fix model file ownership (run from deploy directory)
make install-flywheel
# The install-flywheel target includes permission fixes
```

### Infrastructure Services Not Ready

```bash
# Check individual service status
oc get pods -n $NAMESPACE | grep -E "elasticsearch|mongodb|redis|gateway"

# Check specific service logs
oc logs -n $NAMESPACE statefulset/elasticsearch-master --tail=50
oc logs -n $NAMESPACE deployment/flywheel-infra-mongodb --tail=50
oc logs -n $NAMESPACE deployment/flywheel-infra-redis-master --tail=50

# Manually verify services
make verify
```

---

## Additional Resources

### Configuration Files
- [.env.example](.env.example) - Environment variable template
- [deploy/flywheel-components/values-openshift.yaml](deploy/flywheel-components/values-openshift.yaml) - OpenShift-specific Helm values
- NeMo-Microservices/deploy/nemo-instances/values.yaml - GPU tolerations and resources
- NeMo-Microservices/deploy/nemo-infra/values.yaml - Storage classes

### Documentation
- [demo/data-flywheel-bp-tutorial.md](demo/data-flywheel-bp-tutorial.md) - Comprehensive deployment tutorial
- [knowledge/knowledge_dump_NeMo.md](knowledge/knowledge_dump_NeMo.md) - NeMo Microservices troubleshooting
- [knowledge/knowledge_dump_flywheel_prereqs.md](knowledge/knowledge_dump_flywheel_prereqs.md) - Prerequisites troubleshooting
- [knowledge/knowledge_dump_DataFlywheel.md](knowledge/knowledge_dump_DataFlywheel.md) - Data Flywheel troubleshooting

### Scripts
- [scripts/clone.sh](scripts/clone.sh) - Clone required repositories
- [scripts/install-nemo.sh](scripts/install-nemo.sh) - Automated NeMo Microservices installation
- [scripts/port-forward.sh](scripts/port-forward.sh) - Port-forward all services for local access
- [scripts/clear_namespace.sh](scripts/clear_namespace.sh) - Cleanup script for development/testing

### Makefile Targets
- [deploy/Makefile](deploy/Makefile) - All deployment automation
- [deploy/flywheel-components/README.md](deploy/flywheel-components/README.md) - Makefile deployment details

---

## Support

For issues, questions, or contributions:
- Review troubleshooting guides in the `knowledge/` directory
- Check existing issues and documentation
- Consult the comprehensive tutorial at [demo/data-flywheel-bp-tutorial.md](demo/data-flywheel-bp-tutorial.md)
