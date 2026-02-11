# Data Flywheel Blueprint - Demo Workflow Guide

This document provides step-by-step instructions for running the Data Flywheel Blueprint demonstration on an OpenShift cluster with existing NeMo Microservices infrastructure. This guide is based on real-world deployment experience and follows the official tutorial notebook.

## When to Use This Guide

Use this guide if:
- You have completed the deployment of Data Flywheel on OpenShift following [INSTRUCTIONS.md](../INSTRUCTIONS.md)
- You want to run the Data Flywheel workflow demonstration
- You're running on a cluster (not local Docker) and want to adapt the tutorial for OpenShift
- You need troubleshooting guidance for common demo execution issues

## Prerequisites

Before running the demo, ensure:
1. **Data Flywheel deployed** - All services running in OpenShift cluster
2. **NeMo Microservices v25.08 deployed** - Including Entity Store, Evaluator, Customizer, Data Store, Guardrails
3. **At least one NIM deployed** - Base model accessible (e.g., `meta/llama-3.2-1b-instruct`)
4. **Post-deployment configuration completed** - Evaluator configured, RBAC fixed, model permissions set
5. **Port-forwarding active** - Services accessible from localhost
6. **Python environment set up** - Dependencies installed via `uv sync`

---

## Setup: Environment and Port-Forwarding

### 1. Install Python Dependencies

From the `data-flywheel` repository root:

```bash
# Navigate to data-flywheel repository
cd /path/to/data-flywheel

# Sync dependencies using uv
uv sync

# Activate virtual environment
source .venv/bin/activate
```

### 2. Port-Forward Cluster Services

From the `Nvidia-data-flywheel` repository:

```bash
# Navigate to Nvidia-data-flywheel repository
cd /path/to/Nvidia-data-flywheel

# Run port-forward script
./local_scripts/port-forward.sh
```

This script forwards all necessary services:
- Data Flywheel API: `localhost:8000`
- MLflow UI: `localhost:5000`
- Flower UI: `localhost:5555`
- Elasticsearch: `localhost:9200`
- MongoDB: `localhost:27017`
- Redis: `localhost:6379`
- NeMo Gateway: `localhost:8080`
- NIM (meta-llama3-1b-instruct): `localhost:9001`

**Verification:**
```bash
# Test Data Flywheel API
curl http://localhost:8000/health

# Expected output: {"status":"healthy"}
```

---

## Demo Execution: Step-by-Step

### Section 1-2: Setup (Adapt for Cluster Deployment)

The notebook's Sections 1 and 2 are designed for local Docker deployment. When running on OpenShift, adapt as follows:

**Section 1: Data Flywheel Blueprint Setup**
- Skip Docker deployment steps
- Skip NGC API key setup (already configured in `.env`)
- Skip `deploy-nmp.sh` script (NeMo Microservices already deployed)

**Section 2: AI Virtual Assistant Setup**
- Skip AI Virtual Assistant deployment (optional for demo)
- The demo can run without AIVA by using sample data directly

**Start from:** Section 3 - Load Sample Dataset

---

### Section 3: Load Sample Dataset

**Purpose:** Load sample training data into Elasticsearch to simulate production traffic logs.

**Note:** The sample dataset (`data/aiva_primary_assistant_dataset.jsonl`) contains pre-generated logs from the AI Virtual Assistant with tool-calling examples.

**Steps:**

1. **Import Libraries and Configure:**
   ```python
   import sys
   from pathlib import Path
   import requests
   import time
   from datetime import datetime
   import json
   import pandas as pd
   from IPython.display import display, clear_output

   # Configure pandas display
   pd.set_option('display.max_columns', None)
   pd.set_option('display.width', None)
   pd.set_option('display.max_colwidth', None)
   ```

2. **Inspect Dataset Schema:**
   ```python
   DATA_PATH = "/Users/hacohen/Desktop/repos/data-flywheel/data/aiva_primary_assistant_dataset.jsonl"

   # View first record
   !head -n1 {DATA_PATH} | jq
   ```

   **Expected Schema:**
   - `timestamp`: Epoch seconds when request was issued
   - `workload_id`: Identifier for logical task/route/agent node (e.g., "primary_assistant")
   - `client_id`: Application or deployment identifier (e.g., "aiva-1", "aiva-2", "aiva-3")
   - `request`: OpenAI ChatCompletion request payload with model, messages, tools
   - `response`: ChatCompletion response from the model

3. **Load Data to Elasticsearch:**
   ```python
   sys.path.insert(0, str(Path.cwd().parent))
   from src.scripts.load_test_data import load_data_to_elasticsearch

   load_data_to_elasticsearch(file_path=DATA_PATH)
   ```

   **Expected Output:**
   ```
   Elasticsearch is ready! Status: green
   Creating primary index: flywheel...
   Document is already in the log format. Loading with overrides.
   Data loaded successfully.
   ```

**Verification:**
```bash
# Check Elasticsearch index document count
curl -k -u elastic:$ELASTIC_PASSWORD https://localhost:9200/flywheel/_count

# Expected: {"count":1800,...} (300 + 500 + 1000 from aiva-1, aiva-2, aiva-3)
```

**Troubleshooting:**

**Error: Connection refused to Elasticsearch**
- **Cause:** Port-forwarding not active for Elasticsearch
- **Fix:**
  ```bash
  oc port-forward -n $NAMESPACE svc/elasticsearch-master 9200:9200 &
  ```

**Error: Authentication failed**
- **Cause:** Missing Elasticsearch credentials
- **Fix:** Get Elasticsearch password:
  ```bash
  export ELASTIC_PASSWORD=$(oc get secret elasticsearch-master-credentials \
    -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d)
  ```

---

### Section 4: Launch and Monitor Flywheel Job

**Purpose:** Create a Flywheel job to evaluate candidate models and optionally fine-tune them.

**Steps:**

1. **Launch Flywheel Job:**
   ```python
   # Flywheel Service URL (port-forwarded)
   API_BASE_URL = "http://localhost:8000"

   # Create job for primary_assistant workload with 300 data points (aiva-1)
   response = requests.post(
       f"{API_BASE_URL}/api/jobs",
       json={"workload_id": "primary_assistant", "client_id": "aiva-1"}
   )

   response.raise_for_status()
   job_id = response.json()["id"]

   print(f"Created job with ID: {job_id}")
   ```

   **Expected Output:**
   ```
   Created job with ID: 69849182fc3fedc35519db1f
   ```

2. **Check Job Status:**
   ```python
   def get_job_status(job_id):
       """Get the current status of a job."""
       response = requests.get(f"{API_BASE_URL}/api/jobs/{job_id}")
       response.raise_for_status()
       return response.json()

   status = get_job_status(job_id)
   print(status)
   ```

   **Status Fields:**
   - `status`: Current job state (pending, running, completed, failed)
   - `num_records`: Number of training examples (300 for aiva-1)
   - `llm_judge`: Remote LLM judge configuration and deployment status
   - `nims`: List of candidate models with evaluation/customization status
   - `error`: Error message if job failed

3. **Monitor Job Continuously:**
   ```python
   from notebooks.utils.job_monitor_helper import monitor_job

   monitor_job(
       api_base_url=API_BASE_URL,
       job_id=job_id,
       poll_interval=10
   )
   ```

   **What This Does:**
   - Polls job status every 10 seconds
   - Displays results in a formatted table
   - Uploads completed evaluation results to MLflow
   - Continues until all evaluations and customizations complete

**Expected Workflow:**
1. **base-eval** - Evaluate base NIM performance
2. **icl-eval** - Evaluate with in-context learning (few-shot examples)
3. **customization** - Fine-tune model on training data (if enabled)
4. **customized-eval** - Evaluate fine-tuned model

**Evaluation Metrics:**
- **Function name accuracy**: Exact match of predicted function name
- **Function name + args accuracy (exact-match)**: Exact match of function name and all arguments
- **Function name + args accuracy (LLM-judge)**: Function name exact match + semantically equivalent arguments

**Expected Results (300 data points):**
- `meta/llama-3.2-1b-instruct` base-eval: function_name ≈ 0.20-0.30
- `meta/llama-3.2-1b-instruct` icl-eval: function_name ≈ 0.30-0.40
- `meta/llama-3.2-1b-instruct` customized-eval: function_name ≈ 0.40-0.50

**MLflow Dashboard:**
```bash
# Port-forward MLflow (if not already done)
oc port-forward -n $NAMESPACE svc/df-mlflow-service 5000:5000 &

# Open in browser
open http://localhost:5000
```

**Troubleshooting:**

**Error: Job stuck in "pending" state**
- **Cause:** Celery worker not processing tasks
- **Investigation:**
  ```bash
  # Check Celery worker logs
  oc logs -n $NAMESPACE deployment/df-celery-worker-deployment --tail=100

  # Monitor Flower UI
  oc port-forward -n $NAMESPACE svc/df-flower-service 5555:5555 &
  open http://localhost:5555
  ```
- **Fix:** Restart Celery workers:
  ```bash
  oc rollout restart deployment/df-celery-worker-deployment -n $NAMESPACE
  oc rollout restart deployment/df-celery-parent-worker-deployment -n $NAMESPACE
  ```

**Error: base-eval fails with 404 Not Found**
- **Cause:** NeMo Evaluator not configured to use gateway
- **Fix:** See [knowledge_dump_DataFlywheel.md](knowledge_dump_DataFlywheel.md) Section 1:
  ```bash
  oc set env deployment/nemoevaluator-sample -n $NAMESPACE ENTITY_STORE_URL="http://nemo-gateway"
  ```

**Error: Customization fails with permission denied**
- **Cause:** Model file ownership mismatch with OpenShift UID
- **Fix:** See [knowledge_dump_DataFlywheel.md](knowledge_dump_DataFlywheel.md) Section 3:
  ```bash
  # Get OpenShift UID range
  OPENSHIFT_UID=$(oc get namespace $NAMESPACE \
    -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.uid-range}' | cut -d'/' -f1)

  # Fix ownership
  oc run fix-model-perms --rm -i --restart=Never --image=busybox:latest -n $NAMESPACE \
    --overrides="{\"spec\":{\"securityContext\":{\"runAsUser\":0},\"containers\":[{\"name\":\"fix\",\"image\":\"busybox\",\"command\":[\"chown\",\"-R\",\"$OPENSHIFT_UID:1000\",\"/mount/models\"],\"volumeMounts\":[{\"name\":\"models\",\"mountPath\":\"/mount/models\"}]}],\"volumes\":[{\"name\":\"models\",\"persistentVolumeClaim\":{\"claimName\":\"finetuning-ms-models-pvc\"}}],\"serviceAccountName\":\"default\"}}"
  ```

---

### Section 5: Show Continuous Improvement (Optional)

**Purpose:** Demonstrate how model performance improves with more training data.

**Steps:**

1. **Run Job with 500 Data Points:**
   ```python
   # Launch job with aiva-2 (500 data points)
   response = requests.post(
       f"{API_BASE_URL}/api/jobs",
       json={"workload_id": "primary_assistant", "client_id": "aiva-2"}
   )

   response.raise_for_status()
   job_id = response.json()["id"]

   print(f"Created job with ID: {job_id}")

   # Monitor job
   monitor_job(
       api_base_url=API_BASE_URL,
       job_id=job_id,
       poll_interval=10
   )
   ```

   **Expected Results:**
   - Customized model function_name accuracy ≈ 0.60-0.70

2. **Run Job with 1,000 Data Points:**
   ```python
   # Launch job with aiva-3 (1,000 data points)
   response = requests.post(
       f"{API_BASE_URL}/api/jobs",
       json={"workload_id": "primary_assistant", "client_id": "aiva-3"}
   )

   response.raise_for_status()
   job_id = response.json()["id"]

   print(f"Created job with ID: {job_id}")

   # Monitor job
   monitor_job(
       api_base_url=API_BASE_URL,
       job_id=job_id,
       poll_interval=10
   )
   ```

   **Expected Results:**
   - Customized model function_name accuracy ≈ 0.90-1.0
   - Demonstrates that smaller model (llama-3.2-1b-instruct) can match larger model (llama-3.3-70b-instruct) accuracy with sufficient training data

**Key Observation:** The Data Flywheel demonstrates continuous improvement - as more production data is collected, the customized smaller models improve and can eventually match the accuracy of much larger base models while offering significantly lower latency and cost.

---

### Section 6: Deploy Customized Model (Optional - Cluster Adaptation)

**Purpose:** Deploy the fine-tuned model for inference testing.

**Note:** Section 6 in the notebook is designed for local Docker deployment. On OpenShift, customized models are automatically registered in Entity Store and available for evaluation, but not automatically deployed as separate NIMs.

**What You Can Do:**

1. **List Available Models:**
   ```python
   from nemo_microservices import NeMoMicroservices

   # Configure client (port-forwarded)
   NEMO_BASE_URL = "http://localhost:8080"  # NeMo Gateway
   NIM_BASE_URL = "http://localhost:9001"   # Base NIM

   nemo_client = NeMoMicroservices(
       base_url=NEMO_BASE_URL,
       inference_base_url=NIM_BASE_URL
   )

   # List available models
   available_nims = nemo_client.inference.models.list()
   for nim in available_nims.data:
       print(nim.id)
   ```

   **Expected Output:**
   ```
   meta/llama-3.2-1b-instruct
   hacohen-flywheel/customized-meta-llama-3.2-1b-instruct@cust-KpXGmM8hN2g4kg33tjJfxK
   hacohen-flywheel/customized-meta-llama-3.2-1b-instruct@cust-MBwhJ3rRdBDKMuoxeSPxkC
   ```

2. **Get Best Customized Model from Job Results:**
   ```python
   # Get job status to find customized model ID
   job_status = get_job_status(job_id)

   # Extract customized model ID
   customized_model = job_status['nims'][0]['customizations'][0]['customized_model']
   print(f"Best customized model: {customized_model}")
   ```

3. **Test Inference (Cluster Limitation):**
   - On OpenShift, customized models are **metadata entries in Entity Store**, not deployed inference endpoints
   - To test inference with a customized model, you would need to deploy it via NeMo Deployment Management
   - For the demo, the evaluation results are sufficient to demonstrate improvement

**Why Customized Models Aren't Auto-Deployed:**
- Customization creates LoRA adapters stored in PVC
- Model artifacts are registered in Entity Store for evaluation
- Deploying as a new NIM would require:
  1. Merging LoRA weights with base model
  2. Creating new NIM deployment via NeMo Deployment Management
  3. Additional GPU resources for the deployment

**For Production Deployment:**
- Use NeMo Deployment Management API to deploy the best-performing customized model
- See official NeMo Microservices documentation for deployment procedures

---

## Success Criteria

A successful demo execution should demonstrate:

✅ **Data Loading:**
- Sample dataset loaded to Elasticsearch
- Data accessible via Elasticsearch API

✅ **Job Execution:**
- Flywheel job created successfully
- Job progresses through all stages (base-eval → icl-eval → customization → customized-eval)

✅ **Evaluation Results:**
- base-eval completes with baseline metrics
- icl-eval shows improvement over base
- customized-eval shows significant improvement

✅ **Continuous Improvement:**
- More data (300 → 500 → 1,000) results in better performance
- Customized smaller model approaches larger model accuracy

✅ **Observability:**
- MLflow shows experiment runs and metrics
- Flower shows completed tasks
- All services healthy and accessible

---

## Common Issues and Solutions

### Issue: Different model namespaces than notebook

**Symptoms:**
- Models show as `hacohen-flywheel/customized-...` instead of `dfwbp/...`

**Explanation:**
- Model namespace comes from your OpenShift namespace configuration
- This is expected and correct for cluster deployments

**Solution:**
- No action needed - this is normal behavior
- Model IDs follow pattern: `{namespace}/customized-{base-model}@{job-id}`

### Issue: Job takes very long to complete

**Symptoms:**
- First customization run takes 10+ minutes to start
- Total job time exceeds 60 minutes

**Explanation:**
- First run downloads training container (10-15 minutes)
- Subsequent runs are faster
- Training time depends on GPU type and data size
- LLM-judge evaluations depend on remote API responsiveness

**Solution:**
- This is expected behavior
- Monitor progress via Flower UI or MLflow
- Check Celery worker logs if job seems stuck

### Issue: Cannot access MLflow or Flower UI

**Symptoms:**
- Browser cannot connect to localhost:5000 or localhost:5555

**Solution:**
1. Verify port-forwarding is active:
   ```bash
   ps aux | grep port-forward
   ```
2. Restart port-forward script:
   ```bash
   ./local_scripts/port-forward.sh
   ```
3. Check service names match your deployment:
   ```bash
   oc get svc -n $NAMESPACE | grep -E "mlflow|flower"
   ```

---

## References

- [knowledge_dump_DataFlywheel.md](knowledge_dump_DataFlywheel.md) - Deployment and troubleshooting guide
- [INSTRUCTIONS.md](../INSTRUCTIONS.md) - Deployment instructions
- [local_scripts/port-forward.sh](../local_scripts/port-forward.sh) - Automated port-forwarding scrip
- [data-flywheel/notebooks/data-flywheel-bp-tutorial.ipynb](../../data-flywheel/notebooks/data-flywheel-bp-tutorial.ipynb) - Official tutorial notebook

---

## Summary

The Data Flywheel demo on OpenShift demonstrates:

1. **Load Sample Data** → Production traffic logs to Elasticsearch
2. **Launch Flywheel Job** → Evaluate and customize candidate models
3. **Monitor Progress** → Track evaluations via API and MLflow
4. **Continuous Improvement** → More data leads to better performance

Key differences from notebook tutorial:
- Skip Docker deployment sections (use OpenShift services)
- Use `uv sync` to install dependencies in data-flywheel repo
- Use port-forwarding to access cluster services
- Model namespaces match cluster namespace
- Customized models are metadata entries, not auto-deployed NIMs
- Post-deployment configuration required (evaluator, RBAC, permissions)

Common issues are addressed by automated deployment script and documented in [knowledge_dump_DataFlywheel.md](knowledge_dump_DataFlywheel.md).
