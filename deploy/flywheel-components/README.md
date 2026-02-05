# Data Flywheel Components - Makefile-Based Deployment

This directory organizes Data Flywheel deployment for OpenShift using Makefile automation.

## Overview

The Data Flywheel deployment is now integrated into the main Makefile at `deploy/Makefile` for streamlined installation.

## Quick Start

```bash
cd deploy
make install-flywheel
```

This command:
1. Ensures flywheel-prerequisites are installed (Elasticsearch, Redis, MongoDB, Gateway)
2. Deploys Data Flywheel services from the cloned data-flywheel repository
3. Configures OpenShift security (anyuid SCC, service accounts)
4. Patches deployments to use the correct security context

## Configuration

The deployment uses [values-openshift.yaml](values-openshift.yaml) (located in this directory) which configures:

- **Disabled embedded services**: Uses existing Elasticsearch, Redis, MongoDB from flywheel-prerequisites
- **NeMo service endpoints**: Routes through nemo-gateway for unified access
- **Remote LLM judge and embeddings**: Uses NVIDIA API to conserve cluster GPU resources
- **OpenShift compatibility**: Sets HOME=/tmp for writable directories

## Prerequisites

Before running `make install-flywheel`, ensure:

1. **.env file** configured in repository root with:
   - `NAMESPACE` - Your OpenShift namespace
   - `NVIDIA_API_KEY` - For remote LLM judge/embeddings
   - `NGC_API_KEY` - For pulling NVIDIA containers
   - `HF_TOKEN` - For HuggingFace datasets

2. **NeMo Microservices** deployed (via scripts/install-nemo.sh)

3. **data-flywheel repository** cloned (via scripts/clone.sh) to `../data-flywheel/`

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make install-flywheel` | Install Data Flywheel (includes prerequisites) |
| `make configure-flywheel-security` | Configure OpenShift security (service accounts, SCCs) |
| `make upgrade-flywheel` | Upgrade existing Data Flywheel deployment |
| `make uninstall-flywheel` | Remove Data Flywheel installation |
| `make status-flywheel` | Check Data Flywheel deployment status |

## Directory Structure

```
deploy/
├── Makefile                    # Main deployment automation
├── flywheel-prerequisites/     # Infrastructure Helm chart
└── flywheel-components/        # This directory
    ├── README.md               # This file
    └── values-openshift.yaml   # OpenShift-specific Helm values
```

## Manual Deployment

If you prefer manual deployment, see [demo/data-flywheel-bp-tutorial.md](../../demo/data-flywheel-bp-tutorial.md) for step-by-step instructions.

## Troubleshooting

- **Installation fails**: Check that prerequisites are running with `make status`
- **Permission errors**: Verify SCC permissions with `oc get scc data-flywheel-sa -o yaml`
- **Pod crashes**: Check logs with `oc logs -n $NAMESPACE deployment/df-api-deployment`

For detailed troubleshooting, see [knowledge/knowledge_dump_DataFlywheel.md](../../knowledge/knowledge_dump_DataFlywheel.md).
