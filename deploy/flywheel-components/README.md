# Data Flywheel Components - Values Files

This directory contains Helm values files for deploying Data Flywheel on OpenShift.

## Files

- **values-openshift-standalone.yaml** - OpenShift deployment with bundled infrastructure (Elasticsearch, Redis, MongoDB)

## Configuration

The `values-openshift-standalone.yaml` file configures:

- **Bundled infrastructure**: Enables Elasticsearch, Redis, MongoDB from the data-flywheel Helm chart
- **NeMo Gateway integration**: Routes NeMo service calls through `http://nemo-gateway`
- **Remote services**: Uses NVIDIA API for LLM judge and embeddings (conserves cluster GPU resources)
- **OpenShift compatibility**:
  - Full registry paths for MongoDB and Redis images (`docker.io/library/...`)
  - Sets `HOME=/tmp` for writable directories
  - Ephemeral storage (emptyDir) for development/testing

## Usage

This values file is used by the Makefile:

```bash
cd deploy
make install-flywheel
```

The Makefile automatically:
1. Configures OpenShift security (SCC grants, RBAC)
2. Deploys nemo-gateway
3. Installs data-flywheel with this values file

## Manual Installation

For manual installation using this values file:

```bash
# Ensure environment variables are set
source ../.env

# Install
cd ../data-flywheel/deploy/helm/data-flywheel
helm install data-flywheel . \
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

## Documentation

For complete installation instructions, see [INSTRUCTIONS.md](../../INSTRUCTIONS.md).
