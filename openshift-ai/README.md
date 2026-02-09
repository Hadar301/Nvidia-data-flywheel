# Running Data Flywheel on OpenShift AI

This directory contains configuration and dependencies for running the Data Flywheel Blueprint notebook on OpenShift AI workbenches.

## Prerequisites

- Data Flywheel deployed on OpenShift cluster (see [../INSTRUCTIONS.md](../INSTRUCTIONS.md))
- NeMo Microservices and at least one NIM deployed
- Sample data loaded to Elasticsearch

## Setup Instructions

### 1. Create an OpenShift AI Workbench

Create a workbench in your OpenShift AI environment. For detailed instructions, see [Red Hat OpenShift AI documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_cloud_service/1/html/getting_started_with_red_hat_openshift_ai_cloud_service/index).

### 2. Clone the Data Flywheel Repository

In your workbench terminal:

```bash
git clone https://github.com/NVIDIA-AI-Blueprints/data-flywheel
cd data-flywheel
```

**Important:** The repository uses Git LFS for the `data/` directory. Install Git LFS and pull the data files:

```bash
# Install git-lfs (if you have sudo permissions)
sudo apt-get update && sudo apt-get install -y git-lfs
git lfs install
git lfs pull
```

**If you cannot install git-lfs due to lack of permissions:**

Upload the `data/` directory manually to the `data-flywheel` repository root. You can download the data files from the repository's releases or obtain them separately.

**Alternative (without git):** Upload the following directories manually:
- `data/`
- `notebooks/`
- `src/`

### 3. Upload OpenShift AI Configuration Files

Upload these files from this directory to your workbench:
- [config.py](config.py) - Service endpoint configuration for in-cluster access
- [requirements.txt](requirements.txt) - Python dependencies

Place them in the `data-flywheel` repository root.

### 4. Install Dependencies

In your workbench terminal:

```bash
pip install -r requirements.txt
```

### 5. Run the Notebook

Open `notebooks/data-flywheel-bp-tutorial.ipynb` in your workbench.

**Important modifications:**

In the cell where you import libraries (Section 3), add this import at the top:

```python
from config import *

import sys
from pathlib import Path
import requests
import time
from datetime import datetime
import json
import pandas as pd
from IPython.display import display, clear_output
import random

pd.set_option('display.max_columns', None)
pd.set_option('display.width', None)
pd.set_option('display.max_colwidth', None)
```

**Start from Section 3: "Load Sample Dataset"** and follow the workflow as described in [knowledge_dump_demo_workflow.md](../knowledge/knowledge_dump_demo_workflow.md).

## Key Differences from Port-Forward Setup

- **No port-forwarding needed** - Configuration uses in-cluster service URLs
- **Direct cluster access** - Services communicate via internal Kubernetes DNS
- **Simplified setup** - Import configuration automatically sets environment variables

## Configuration Details

The [config.py](config.py) file configures these service endpoints:

- Data Flywheel API
- Elasticsearch
- MongoDB
- Redis
- MLflow
- NeMo Gateway
- NeMo Datastore

All URLs use the format: `http://<service-name>.<namespace>.svc.cluster.local:<port>`

Update the `NAMESPACE` variable in [config.py](config.py) if your services are deployed in a different namespace (default: `hacohen-flywheel`).

## Troubleshooting

If you encounter connection issues:

1. Verify the namespace in [config.py](config.py) matches your deployment
2. Ensure all Data Flywheel services are running:
   ```bash
   oc get pods -n <your-namespace>
   ```
3. Check service endpoints:
   ```bash
   oc get svc -n <your-namespace>
   ```

For deployment and workflow troubleshooting, see [knowledge_dump_demo_workflow.md](../knowledge/knowledge_dump_demo_workflow.md).
