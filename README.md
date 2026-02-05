# NVIDIA Data Flywheel for OpenShift

This project provides a complete deployment solution for running the [NVIDIA Data Flywheel](https://github.com/NVIDIA-AI-Blueprints/data-flywheel) on OpenShift clusters. The Data Flywheel is an AI development framework that enables continuous model improvement through automated evaluation, fine-tuning, and deployment workflows.

## Purpose

This repository integrates:
- **NVIDIA Data Flywheel**: Automated AI model improvement pipeline with evaluation, fine-tuning, and experiment tracking
- **NeMo Microservices**: NVIDIA's platform for model serving, customization, and evaluation on Kubernetes
- **OpenShift Integration**: Production-ready deployment configurations, security policies, and operational tooling

The deployment provides a complete MLOps platform for iterative model development with built-in support for:
- Base model evaluation and in-context learning (ICL) evaluation
- Automated fine-tuning workflows with NVIDIA NIM
- Experiment tracking with MLflow
- Task orchestration with Celery
- Persistent storage for datasets, models, and evaluation results

**For detailed installation instructions, configuration options, and troubleshooting, refer to [INSTRUCTIONS.md](INSTRUCTIONS.md).**

## Quick Start

### Prerequisites
- OpenShift cluster with GPU-enabled nodes
- `oc`, `helm`, `jq`, and `git` CLI tools installed
- NVIDIA API key, NGC API key, and HuggingFace token

### Installation

```bash
# 1. Prepare environment
cd Nvidia-data-flywheel
cp .env.example .env
# Edit .env with your credentials (NAMESPACE, NVIDIA_API_KEY, NGC_API_KEY, HF_TOKEN)
source .env

# 2. Clone repositories
./scripts/clone.sh

# 3. Install NeMo Microservices
./scripts/install-nemo.sh

# 4. Install Data Flywheel (prerequisites + components)
cd deploy
make install-flywheel

# 5. Validate deployment
cd ..
./scripts/port-forward.sh
# In another terminal:
cd data-flywheel
sudo apt-get update && sudo apt-get install -y git-lfs
git lfs install
git lfs pull
cd ..
jupyter notebook notebooks/data-flywheel-bp-tutorial.ipynb
```

For detailed installation instructions, troubleshooting, and configuration options, see [INSTRUCTIONS.md](INSTRUCTIONS.md).

## Repository Structure

After running `./scripts/clone.sh`, your directory structure will look like this:

```
Nvidia-data-flywheel/
├── .env                           # Environment configuration (created from .env.example)
├── .env.example                   # Template for environment variables
├── README.md                      # This file
├── INSTRUCTIONS.md                # Detailed installation guide
├── scripts/
│   ├── clone.sh                   # Clone required repositories
│   ├── install-nemo.sh            # Install NeMo Microservices
│   ├── port-forward.sh            # Port-forward cluster services
│   └── clear_namespace.sh         # Cleanup script
├── deploy/
│   ├── Makefile                   # Deployment automation
│   ├── flywheel-prerequisites/    # Infrastructure Helm chart (Elasticsearch, Redis, MongoDB, Gateway)
│   └── flywheel-components/       # Data Flywheel configuration
│       ├── README.md
│       └── values-openshift.yaml  # OpenShift-specific values
├── knowledge/                     # Troubleshooting documentation
│   ├── knowledge_dump_NeMo.md
│   ├── knowledge_dump_flywheel_prereqs.md
│   ├── knowledge_dump_DataFlywheel.md
│   └── knowledge_dump_demo_workflow.md
├── NeMo-Microservices/            # Cloned: NeMo platform charts
│   └── deploy/
│       ├── nemo-infra/            # PostgreSQL, MinIO, Milvus, Argo, Volcano
│       └── nemo-instances/        # NeMo services (Datastore, Evaluator, Customizer, etc.)
└── data-flywheel/                 # Cloned: Data Flywheel Helm chart and application code
    ├── deploy/
    │   └── helm/
    │       └── data-flywheel/     # Helm chart for Data Flywheel services
    ├── src/                       # Data Flywheel Python application
    └── notebooks/                 # Demo and validation notebooks
        └── data-flywheel-bp-tutorial.ipynb
```

## References

This project builds upon:
- **NVIDIA Data Flywheel**: [https://github.com/NVIDIA-AI-Blueprints/data-flywheel](https://github.com/NVIDIA-AI-Blueprints/data-flywheel)
- **NeMo Microservices for OpenShift**: [https://github.com/RHEcosystemAppEng/NeMo-Microservices](https://github.com/RHEcosystemAppEng/NeMo-Microservices)

## Documentation

- [INSTRUCTIONS.md](INSTRUCTIONS.md) - Complete installation and configuration guide
- [knowledge/knowledge_dump_demo_workflow.md](knowledge/knowledge_dump_demo_workflow.md) - Demo workflow guide and validation
- [knowledge/](knowledge/) - Troubleshooting guides for each component
