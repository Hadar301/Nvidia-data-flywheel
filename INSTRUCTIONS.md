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
2. **NeMo Gateway** - NGINX proxy for unified NeMo service access
3. **Data Flywheel with Bundled Infrastructure** - Complete stack including Elasticsearch, Redis, MongoDB, API, Celery workers, MLflow tracking
4. **Validation** - End-to-end testing via Jupyter notebook

---

## Step 0: Prepare Environment

### Create .env File

Create a `.env` file in the repository root with your credentials:

```bash
cd Nvidia-data-flywheel
cp .env.example .env
```

Edit `.env` and set your values (without quotes):

```bash
NAMESPACE=your-namespace-name
NVIDIA_API_KEY=nvapi-your-nvidia-api-key
NGC_API_KEY=your-ngc-api-key
HF_TOKEN=hf_your-huggingface-token
```

**Important**: Do not use quotes around the values in the `.env` file.

### Load Environment Variables

```bash
source .env
```

---

## Quick Start with Makefile

For a streamlined installation, use the provided Makefile targets:

```bash
cd deploy

# Step 1: Clone repositories
make clone

# Step 2: Install NeMo Microservices
make install-nemo

# Step 3: Install Data Flywheel with bundled infrastructure
make install-flywheel

# Check deployment status
make status
```

The Makefile automates all installation steps. Continue reading for detailed manual installation instructions.

---

## Step 1: Clone Required Repositories

### Option A: Using Makefile (Recommended)

```bash
cd deploy
make clone
```

### Option B: Manual

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

### Option A: Using Makefile (Recommended)

```bash
cd deploy
make install-nemo
```

### Option B: Manual

```bash
./scripts/install-nemo.sh
```

The installation will:
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

## Step 3: Deploy Data Flywheel with Bundled Infrastructure

The Data Flywheel installation includes three automated steps:
1. Configure OpenShift security (SCC grants, RBAC, file permissions)
2. Deploy NeMo Gateway (NGINX proxy for unified NeMo service access)
3. Install Data Flywheel Helm chart (with Elasticsearch, Redis, MongoDB)

### Option A: Using Makefile (Recommended)

```bash
cd deploy
make install-flywheel
```

The Makefile will automatically:
- Run the security configuration script
- Deploy the nemo-gateway
- Install the data-flywheel Helm chart with all required secrets
- Display deployment status

### Option B: Manual Installation

If you prefer manual steps, follow these commands:

#### 3a. Configure OpenShift Security

```bash
cd scripts
./configure-data-flywheel-security.sh
```

This script:
1. Grants `anyuid` SCC to default and data-flywheel-sa service accounts
2. Configures NeMo Evaluator to use the gateway
3. Fixes RBAC permissions for NeMo Evaluator (adds delete permission for secrets)
4. Fixes base model file permissions for customization jobs
5. Verifies all security configurations

#### 3b. Deploy NeMo Gateway

```bash
cd ../deploy
oc apply -k nemo-gateway/
```

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

#### 3c. Install Data Flywheel Helm Chart

```bash
# Ensure environment variables are loaded
source ../.env

# Navigate to data-flywheel Helm chart
cd ../data-flywheel/deploy/helm/data-flywheel

# Update Helm dependencies
helm dependency update

# Install data-flywheel with bundled infrastructure
helm install data-flywheel . \
    --values ../../../../deploy/flywheel-components/values-openshift-standalone.yaml \
    --set secrets.ngcApiKey="${NGC_API_KEY}" \
    --set secrets.nvidiaApiKey="${NVIDIA_API_KEY}" \
    --set secrets.hfToken="${HF_TOKEN}" \
    --set secrets.llmJudgeApiKey="${NVIDIA_API_KEY}" \
    --set secrets.embApiKey="${NVIDIA_API_KEY}" \
    --set "imagePullSecrets[0].password=${NGC_API_KEY}" \
    --namespace=${NAMESPACE} \
    --timeout=10m
```

---

### Components Deployed

| Component | Version | Purpose | Storage |
|-----------|---------|---------|---------|
| **df-elasticsearch** | 8.12.2 | Stores training/evaluation data and prompts | Ephemeral (emptyDir) |
| **df-redis** | 7.2-alpine | Celery task queue broker and results backend | Ephemeral (emptyDir) |
| **df-mongodb** | 7.0 | API metadata and workflow state storage | Ephemeral (emptyDir) |
| **df-api** | 0.3.0 | Data Flywheel REST API | - |
| **df-celery-worker** | 0.3.0 | Async job processor (evaluation, fine-tuning) | - |
| **df-celery-parent-worker** | 0.3.0 | Parent job orchestrator | - |
| **df-mlflow** | 2.22.0 | Experiment tracking server | - |
| **df-flower** | 0.3.0 | Celery task monitoring UI | - |
| **nemo-gateway** | 1.25-alpine | Unified routing to NeMo services | - |

**Note**: Infrastructure uses ephemeral storage - data is lost on pod restart. For production use with persistence, consider using the traditional flywheel-prerequisites approach with Bitnami charts.

### Key Configuration

The deployment uses [deploy/flywheel-components/values-openshift-standalone.yaml](deploy/flywheel-components/values-openshift-standalone.yaml) with:

#### Service Endpoints
- **NeMo Gateway**: `http://nemo-gateway` (unified access to all NeMo services)
- **NIM for Inference**: `http://meta-llama3-1b-instruct:8000`
- **Infrastructure Services**:
  - Elasticsearch: `http://df-elasticsearch-service:9200`
  - Redis: `redis://df-redis-service:6379/0`
  - MongoDB: `mongodb://df-mongodb-service:27017`

#### Remote API Services (conserves cluster GPU resources)
- **LLM Judge**: NVIDIA API (`meta/llama-3.3-70b-instruct`)
- **Embeddings**: NVIDIA API (`nvidia/llama-3.2-nv-embedqa-1b-v2`)

Verify all pods are running:

```bash
cd ../../../../
oc get pods -n $NAMESPACE | grep "^df-"
```

**Expected**: All df-* pods should show `1/1 Running`

**For detailed troubleshooting**, see [knowledge/knowledge_dump_DataFlywheel.md](knowledge/knowledge_dump_DataFlywheel.md).

## Step 4: Validate Deployment

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

### Prepare Data Flywheel Repository

Before running the validation notebook, set up Git LFS to download required model files:

```bash
cd data-flywheel
sudo apt-get update && sudo apt-get install -y git-lfs
git lfs install
git lfs pull
cd ..
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

**For comprehensive tutorial and troubleshooting**, see [knowledge/knowledge_dump_demo_workflow.md](knowledge/knowledge_dump_demo_workflow.md).

---

## Useful Commands

### Makefile Commands

The `deploy/Makefile` provides convenient automation for common tasks:

```bash
cd deploy

# Installation workflow
make clone            # Clone required repositories
make install-nemo     # Install NeMo Microservices
make install-flywheel # Install Data Flywheel with bundled infrastructure

# Monitoring and utilities
make status           # Check deployment status (pods, services, routes)
make clean            # Clean up namespace (development only)
make help             # Show all available commands
```

### Check Deployment Status

#### Using Makefile (Recommended)

```bash
cd deploy
make status
```

This displays Helm releases, pods, services, and routes in the namespace.

#### Manual Commands

```bash
# Check all pods
oc get pods -n $NAMESPACE

# Check Data Flywheel pods
oc get pods -n $NAMESPACE | grep "^df-"

# Check NeMo Gateway
oc get pods,svc,route -n $NAMESPACE -l app=nemo-gateway

# Check Helm releases
helm list -n $NAMESPACE
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
# Upgrade Data Flywheel
source .env
cd data-flywheel/deploy/helm/data-flywheel
helm dependency update
helm upgrade data-flywheel . \
    --values ../../../../deploy/flywheel-components/values-openshift-standalone.yaml \
    --set secrets.ngcApiKey="${NGC_API_KEY}" \
    --set secrets.nvidiaApiKey="${NVIDIA_API_KEY}" \
    --set secrets.hfToken="${HF_TOKEN}" \
    --set secrets.llmJudgeApiKey="${NVIDIA_API_KEY}" \
    --set secrets.embApiKey="${NVIDIA_API_KEY}" \
    --set "imagePullSecrets[0].password=${NGC_API_KEY}" \
    --namespace ${NAMESPACE} \
    --timeout=10m
```

### Cleanup

#### Using Makefile (Recommended)

```bash
cd deploy
make clean
```

This runs the automated cleanup script that removes all resources from the namespace.

#### Manual Cleanup

```bash
# Uninstall Data Flywheel
helm uninstall data-flywheel -n $NAMESPACE

# Uninstall NeMo Gateway
oc delete -k deploy/nemo-gateway/

# Uninstall NeMo
helm uninstall nemo-instances -n $NAMESPACE
helm uninstall nemo-infra -n $NAMESPACE

# Complete namespace cleanup (development only)
./scripts/clear_namespace.sh
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

If fine-tuning jobs fail with permission errors (`Permission denied: '/mount/models/llama32_1b-instruct_2_0'`):

```bash
# Re-run the security configuration script to fix permissions
./scripts/configure-data-flywheel-security.sh
```

### Infrastructure Services Not Ready

```bash
# Check individual service status
oc get pods -n $NAMESPACE | grep -E "^df-"

# Check specific service logs
oc logs -n $NAMESPACE deployment/df-elasticsearch-deployment --tail=50
oc logs -n $NAMESPACE deployment/df-mongodb-deployment --tail=50
oc logs -n $NAMESPACE deployment/df-redis-deployment --tail=50
oc logs -n $NAMESPACE deployment/nemo-gateway --tail=50
```

### Image Pull Errors

If you see `ImagePullBackOff` errors with unauthorized errors from `bds-docker-release.jfrog.io`:

Your cluster redirects Docker Hub pulls to a JFrog registry. The `values-openshift-standalone.yaml` file already includes the fix with `docker.io/library/` prefixes for MongoDB and Redis images.

---

## Additional Resources

### Configuration Files
- [.env.example](.env.example) - Environment variable template
- [deploy/flywheel-components/values-openshift-standalone.yaml](deploy/flywheel-components/values-openshift-standalone.yaml) - Standalone deployment with bundled infrastructure
- [deploy/nemo-gateway/](deploy/nemo-gateway/) - NeMo Gateway Kubernetes manifests
- NeMo-Microservices/deploy/nemo-instances/values.yaml - GPU tolerations and resources
- NeMo-Microservices/deploy/nemo-infra/values.yaml - Storage classes

### Documentation
- [knowledge/knowledge_dump_demo_workflow.md](knowledge/knowledge_dump_demo_workflow.md) - Demo workflow guide and validation
- [knowledge/knowledge_dump_NeMo.md](knowledge/knowledge_dump_NeMo.md) - NeMo Microservices troubleshooting
- [knowledge/knowledge_dump_flywheel_prereqs.md](knowledge/knowledge_dump_flywheel_prereqs.md) - Prerequisites troubleshooting
- [knowledge/knowledge_dump_DataFlywheel.md](knowledge/knowledge_dump_DataFlywheel.md) - Data Flywheel troubleshooting

### Scripts
- [scripts/clone.sh](scripts/clone.sh) - Clone required repositories
- [scripts/install-nemo.sh](scripts/install-nemo.sh) - Automated NeMo Microservices installation
- [scripts/configure-data-flywheel-security.sh](scripts/configure-data-flywheel-security.sh) - OpenShift security configuration
- [scripts/port-forward.sh](scripts/port-forward.sh) - Port-forward all services for local access
- [scripts/clear_namespace.sh](scripts/clear_namespace.sh) - Cleanup script for development/testing

---

## Support

For issues, questions, or contributions:
- Review troubleshooting guides in the `knowledge/` directory
- Check existing issues and documentation
- Consult the demo workflow guide at [knowledge/knowledge_dump_demo_workflow.md](knowledge/knowledge_dump_demo_workflow.md)
