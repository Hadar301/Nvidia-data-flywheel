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

## Installation

**For complete installation instructions, configuration options, and troubleshooting, see [INSTRUCTIONS.md](INSTRUCTIONS.md).**

## Repository Structure

```
Nvidia-data-flywheel/
├── deploy/
│   ├── flywheel-components/       # Data Flywheel values files
│   │   ├── README.md
│   │   └── values-openshift-standalone.yaml  # OpenShift values with bundled infrastructure
│   ├── nemo-gateway/              # NGINX gateway for unified NeMo access
│   │   ├── configmap.yaml         # NGINX routing configuration
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── route.yaml             # OpenShift route
│   │   ├── kustomization.yaml
│   │   └── README.md
│   └── Makefile                   # Deployment automation (clone, install-nemo, install-flywheel, status, clean)
├── knowledge/                     # Troubleshooting documentation
│   ├── knowledge_dump_DataFlywheel.md
│   ├── knowledge_dump_NeMo.md
│   └── knowledge_dump_demo_workflow.md
├── openshift-ai/                  # OpenShift AI workbench configuration
│   ├── README.md                  # Instructions for running on OpenShift AI
│   ├── config.py                  # In-cluster service endpoints
│   ├── data-flywheel-bp-tutorial-RHOAI.ipynb
│   ├── demo.ipynb
│   └── requirements.txt           # Python dependencies
├── scripts/
│   ├── clear_namespace.sh         # Cleanup script
│   ├── clone.sh                   # Clone required repositories
│   ├── configure-data-flywheel-security.sh  # OpenShift SCC and RBAC configuration
│   ├── install-nemo.sh            # Install NeMo Microservices
│   └── port-forward.sh            # Port-forward cluster services
├── .env.example                   # Environment variable template
├── INSTRUCTIONS.md                # Detailed installation guide
├── LICENSE
└── README.md                      # This file

After running make clone:
├── NeMo-Microservices/            # Cloned: NeMo platform charts
│   └── deploy/
│       ├── nemo-infra/            # PostgreSQL, MinIO, Milvus, Argo, Volcano
│       └── nemo-instances/        # NeMo services (Datastore, Evaluator, Customizer, etc.)
└── data-flywheel/                 # Cloned: Data Flywheel Helm chart and application code
    ├── deploy/
    │   └── helm/
    │       └── data-flywheel/     # Helm chart with bundled infrastructure
    │           ├── templates/     # Elasticsearch, Redis, MongoDB, API, Celery, MLflow
    │           ├── Chart.yaml
    │           └── values.yaml
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
