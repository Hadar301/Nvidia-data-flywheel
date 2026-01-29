# Data Flywheel Blueprint Tutorial Setup - Summary

## Objective
Set up and run the NVIDIA Data Flywheel Blueprint tutorial to demonstrate continuous model improvement using production data, fine-tuning smaller models (1B parameters) to replace larger models while maintaining accuracy.

## Environment
- **Hardware**: L40s GPU (48GB VRAM)
- **Platform**: OpenShift cluster (ai-dev05.kni.syseng.devcluster.openshift.com)
- **Namespace**: `$NAMESPACE` (hacohen-flywheel)
- **Local Machine**: macOS with Docker Desktop

## What We Accomplished

### 1. Infrastructure Deployment on OpenShift

**NeMo Microservices Platform** (already deployed):
- `nemodatastore-sample` - Dataset management
- `nemocustomizer-sample` - Fine-tuning service
- `nemoevaluator-sample` - Model evaluation
- `nemoguardrails-sample` - Safety filters
- `nemoentitystore-sample` - Model metadata
- Supporting PostgreSQL instances for each service
- MLflow tracking server
- MinIO object storage
- Milvus vector database
- Argo Workflows for orchestration

**Data Flywheel Prerequisites** (deployed via Helm):
- Elasticsearch 8.5.1 - Log storage (30GB PVC)
- MongoDB 7.0.x - API metadata (20GB PVC)
- Redis 7.2.x - Task queue (8GB PVC)
- NGINX Gateway - Unified routing

**Model Deployment**:
- `meta-llama3-1b-instruct` NIM - Running on OpenShift
- Embedding/reranking NIMs (nv-embedqa-1b-v2, nv-rerankqa-1b-v2) - Pending (not required for core demo)

### 2. Local Data Flywheel Application Setup

**Architecture Decision**: Run the Data Flywheel application locally on laptop, connecting to OpenShift-hosted infrastructure via port-forwards.

**Clone the Data Flywheel Repository**:
```bash
git clone https://github.com/NVIDIA-AI-Blueprints/data-flywheel.git
cd data-flywheel
```

**Key Configuration Changes**:

#### config.yaml
- **NeMo base URL**: `http://localhost:8080/v1` (NGINX gateway)
- **NIM base URL**: `http://localhost:9001` (1B model)
- **Datastore URL**: `http://localhost:8001`
- **Namespace**: `$NAMESPACE`
- **LLM Judge**: Remote deployment via NVIDIA API (to avoid 70B model GPU requirements)
  - URL: `https://integrate.api.nvidia.com/v1/chat/completions`
  - Model: `meta/llama-3.3-70b-instruct`
- **Embeddings**: Remote deployment via NVIDIA API
  - URL: `https://integrate.api.nvidia.com/v1/embeddings`
  - Model: `nvidia/llama-3.2-nv-embedqa-1b-v2`

#### docker-compose.yaml (macOS-specific changes for local execution)
**Objective**: Enable running the Data Flywheel application locally on a macOS laptop while connecting to infrastructure on OpenShift.

**Problem**: The original `docker-compose.yaml` uses `network_mode: host`, which works on Linux but **not on macOS Docker Desktop**. On macOS, Docker runs in a VM, so host networking doesn't bind to the actual host's localhost. This prevents local services from accessing port-forwarded OpenShift services.

**Changes Made** (to enable local execution on macOS):
- **Removed** `network_mode: host` from all service definitions (api, celery_worker, celery_parent_worker)
- **Changed** service URLs from `localhost` to Docker service names:
  - Elasticsearch: `http://elasticsearch:9200` (instead of `http://localhost:9200`)
  - MongoDB: `mongodb://mongodb:27017` (instead of `mongodb://localhost:27017`)
  - Redis: `redis://redis:6379/0` (instead of `redis://localhost:6379/0`)
- **Port mappings**: Using standard Docker port publishing (8000:8000)

**Why This Works**:
- OpenShift infrastructure services (Elasticsearch, MongoDB, Redis) are port-forwarded to `localhost` on the Mac
- Docker Compose creates a bridge network where containers can talk to each other via service names
- However, since these are local standalone containers (not from port-forwards), we keep the infrastructure running on OpenShift and use Docker service names only for containers that need to talk to each other

**For Linux Users**:
If running on a Linux machine, you can keep the original `network_mode: host` configuration and use `localhost` URLs. The host network mode works properly on native Linux Docker installations and allows containers to directly access `localhost` port-forwards.

#### Port Forwarding Configuration
Created `local_scripts/port-forward.sh`:
```bash
oc port-forward -n $NAMESPACE svc/elasticsearch-master 9200:9200
oc port-forward -n $NAMESPACE svc/flywheel-infra-mongodb 27017:27017
oc port-forward -n $NAMESPACE svc/flywheel-infra-redis-master 6379:6379
oc port-forward -n $NAMESPACE svc/nemo-gateway 8080:80
oc port-forward -n $NAMESPACE svc/meta-llama3-1b-instruct 9001:8000
oc port-forward -n $NAMESPACE svc/nemodatastore-sample 8001:8000
```

**Note**: Changed 1B NIM port from 8000 → 9001 to avoid conflict with Data Flywheel API.

#### scripts/run.sh
Modified the startup script to fix `docker-compose` command compatibility:

**Original**:
```bash
docker compose -f ./deploy/docker-compose.yaml down && \
docker compose -f ./deploy/docker-compose.yaml up -d --build --no-attach mongodb
```

**Changed to**:
```bash
docker-compose -f ./deploy/docker-compose.yaml down && \
docker-compose -f ./deploy/docker-compose.yaml up -d --build --no-attach mongodb
```

**Reason**: The system has `docker-compose` v2.36.0 installed as a standalone command rather than the Docker CLI plugin syntax (`docker compose`). Using `docker-compose` (with hyphen) ensures compatibility with the installed version.

### 3. Docker Services Running Locally

**Services Started**:
- `deploy-api-1` - FastAPI server on port 8000
- `deploy-celery_worker-1` - Main Celery worker (concurrency=50)
- `deploy-celery_parent_worker-1` - Parent queue worker (concurrency=1)
- `deploy-elasticsearch-1` - Elasticsearch 8.12.2
- `deploy-mongodb-1` - MongoDB 7.0
- `deploy-redis-1` - Redis 7.2

**Verification**:
```bash
curl http://localhost:8000/api/jobs
# Returns: {"jobs":[]}
```

### 4. Hardware Constraints & Adaptations

**Original Blueprint Requirements**:
- 6× H100/A100 GPUs (for self-hosted LLM judge)
- 70B parameter models for production

**Our Constraints**:
- L40s GPU (48GB VRAM) - cannot run 70B models

**Solutions Applied**:
1. Use NVIDIA hosted API for 70B LLM judge (remote deployment)
2. Use NVIDIA hosted API for embeddings (remote deployment)
3. Focus demo on 1B → fine-tuned 1B comparison (smaller delta but demonstrates the concept)
4. Fine-tuning happens on OpenShift cluster

### 5. Demo Approach

**Skipping**:
- Section 1 (Setup) - Already completed manually
- Section 2 (AIVA deployment) - Using pre-generated dataset instead

**Running**:
- Section 3: Load pre-generated AIVA dataset (`data/aiva_primary_assistant_dataset.jsonl`)
- Section 4: Launch flywheel job targeting `primary_assistant` workload
- Section 5: Monitor evaluation and fine-tuning
- Section 6 (Optional): Show continuous improvement with more data

**Pre-generated Dataset**:
- Contains 1000+ customer service queries
- Multiple data sizes: 300, 500, 1000 records (client_id: aiva-1, aiva-2, aiva-3)
- Demonstrates progressive improvement

## Required API Keys

1. **NGC API Key** - Already configured on OpenShift for container pulls
2. **NVIDIA API Key** - Required for remote LLM judge and embeddings
   - Set via: `export NVIDIA_API_KEY="your-key-here"`
   - Used by Data Flywheel containers

## Next Steps

1. Ensure port-forwards are running: `./local_scripts/port-forward.sh`
2. Verify NVIDIA_API_KEY is set in environment
3. Open notebook: `notebooks/data-flywheel-bp-tutorial.ipynb`
4. Jump to Section 3 (cell 30+)
5. Load sample data and launch flywheel job

## Key Files Modified

- `/Users/hacohen/Desktop/repos/data-flywheel/config/config.yaml`
- `/Users/hacohen/Desktop/repos/data-flywheel/deploy/docker-compose.yaml`
- `/Users/hacohen/Desktop/repos/Nvidia-data-flywheel/local_scripts/port-forward.sh`
- `/Users/hacohen/Desktop/repos/data-flywheel/scripts/run.sh`

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     Local Laptop (macOS)                        │
│                                                                 │
│  ┌───────────────────────────────────────────────────────┐    │
│  │           Docker Compose Services                      │    │
│  │  - FastAPI (localhost:8000)                           │    │
│  │  - Celery Workers                                     │    │
│  │  - Elasticsearch (via port-forward from OpenShift)   │    │
│  │  - MongoDB (via port-forward from OpenShift)         │    │
│  │  - Redis (via port-forward from OpenShift)           │    │
│  └───────────────────────────────────────────────────────┘    │
│                           │                                     │
│                           │ Port Forwards                       │
│                           ▼                                     │
└─────────────────────────────────────────────────────────────────┘
                            │
                            │ oc port-forward
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│          OpenShift Cluster (ai-dev05)                           │
│          Namespace: $NAMESPACE                                  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐     │
│  │  NeMo Microservices Platform                         │     │
│  │  - nemodatastore-sample :8001                        │     │
│  │  - nemocustomizer-sample (fine-tuning)               │     │
│  │  - nemoevaluator-sample (evaluation)                 │     │
│  │  - nemoentitystore-sample (model metadata)           │     │
│  │  - nemoguardrails-sample (safety)                    │     │
│  │  - nemo-gateway :8080 (NGINX routing)                │     │
│  └──────────────────────────────────────────────────────┘     │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐     │
│  │  Model Deployments (NIMs)                            │     │
│  │  - meta-llama3-1b-instruct :9001                     │     │
│  └──────────────────────────────────────────────────────┘     │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐     │
│  │  Infrastructure (via Helm)                           │     │
│  │  - Elasticsearch :9200                               │     │
│  │  - MongoDB :27017                                    │     │
│  │  - Redis :6379                                       │     │
│  └──────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────┘
                            │
                            │ HTTPS
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│          NVIDIA Cloud (Remote APIs)                             │
│                                                                 │
│  - LLM Judge: meta/llama-3.3-70b-instruct                      │
│  - Embeddings: nvidia/llama-3.2-nv-embedqa-1b-v2               │
│                                                                 │
│  URL: https://integrate.api.nvidia.com/v1                      │
└─────────────────────────────────────────────────────────────────┘
```

## Lessons Learned

1. **macOS Docker Limitations**: `network_mode: host` doesn't work on macOS; use service names instead
2. **Port Conflicts**: When using port-forwards, avoid port collisions (8000 conflict resolved by moving NIM to 9001)
3. **Hardware Adaptation**: Remote API endpoints allow running demos on hardware that can't support full model sizes
4. **Hybrid Architecture**: Local application + remote infrastructure works well for demos
5. **Configuration is Key**: Proper service discovery URLs are critical for Docker Compose on macOS

## Status
✅ **Setup Complete** - Ready to run tutorial notebook
