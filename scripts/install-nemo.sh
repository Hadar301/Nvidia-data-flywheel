#!/bin/bash

################################################################################
# NeMo Microservices Installation Script
# This script automates the installation of NeMo infrastructure and instances
# Based on commands.md and includes the restored chat model (meta-llama3-1b-instruct)
################################################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if oc CLI is installed
    if ! command -v oc &> /dev/null; then
        log_error "oc CLI not found. Please install OpenShift CLI."
        exit 1
    fi

    # Check if helm CLI is installed
    if ! command -v helm &> /dev/null; then
        log_error "helm CLI not found. Please install Helm."
        exit 1
    fi

    # Check if logged into OpenShift
    if ! oc whoami &> /dev/null; then
        log_error "Not logged into OpenShift. Please run 'oc login' first."
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Function to load variables from .env file
load_env_variables() {
    log_info "Loading configuration from .env file..."

    # Look for .env file in parent directory (Nvidia-data-flywheel/)
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    ENV_FILE="$PROJECT_ROOT/.env"

    # Check if .env file exists
    if [ ! -f "$ENV_FILE" ]; then
        log_error ".env file not found at $ENV_FILE"
        log_error "Please create a .env file in the repository root with the following variables:"
        log_error "  NGC_API_KEY=\"your-api-key\""
        log_error "  NAMESPACE=\"your-namespace\""
        exit 1
    fi

    # Source the .env file
    set -a  # automatically export all variables
    source "$ENV_FILE"
    set +a

    # Validate required variables
    if [ -z "$NGC_API_KEY" ]; then
        log_error "NGC_API_KEY is not set in .env file"
        exit 1
    fi

    if [ -z "$NAMESPACE" ]; then
        log_error "NAMESPACE is not set in .env file"
        exit 1
    fi

    log_success "Configuration loaded from .env"
}

# Function to create or verify namespace
create_namespace() {
    log_info "Creating/verifying namespace: $NAMESPACE"

    if oc get namespace "$NAMESPACE" &> /dev/null; then
        log_info "Namespace $NAMESPACE already exists"
    else
        oc new-project "$NAMESPACE"
        log_success "Namespace $NAMESPACE created"
    fi

    # Switch to namespace
    oc project "$NAMESPACE"
}

# Function to create NGC secrets
create_ngc_secrets() {
    log_info "Creating NGC secrets..."

    # Delete existing secrets if they exist
    oc delete secret ngc-secret ngc-api-secret -n "$NAMESPACE" --ignore-not-found=true

    # Create NGC Image Pull Secret
    oc create secret docker-registry ngc-secret \
        --docker-server=nvcr.io \
        --docker-username='$oauthtoken' \
        --docker-password="$NGC_API_KEY" \
        -n "$NAMESPACE"

    # Create NGC API Secret
    oc create secret generic ngc-api-secret \
        --from-literal=NGC_API_KEY="$NGC_API_KEY" \
        -n "$NAMESPACE"

    log_success "NGC secrets created"
}

# Function to adopt existing Argo Workflows CRDs
adopt_argo_crds() {
    log_info "Checking for existing Argo Workflows CRDs..."

    # Dynamically find all CRDs with argoproj.io in the name
    local argo_crds
    argo_crds=$(oc get crds -o jsonpath='{.items[?(@.spec.group=="argoproj.io")].metadata.name}' 2>/dev/null)

    if [ -z "$argo_crds" ]; then
        log_info "No existing Argo Workflows CRDs found"
        return 0
    fi

    local found_crds=false

    for crd in $argo_crds; do
        found_crds=true
        log_info "Found existing CRD: $crd - adopting into Helm release..."

        # Remove the last-applied-configuration annotation to clear previous manager conflicts
        oc annotate crd "$crd" \
            kubectl.kubernetes.io/last-applied-configuration- \
            2>/dev/null || true

        # Clear managedFields to remove field manager conflicts
        # This is necessary when the CRD was previously managed by another tool (e.g., platform.opendatahub.io)
        log_info "Clearing managedFields for $crd to resolve field manager conflicts..."
        oc patch crd "$crd" --type=json -p='[{"op": "replace", "path": "/metadata/managedFields", "value": []}]' \
            2>/dev/null || log_warn "Failed to clear managedFields for $crd"

        oc annotate crd "$crd" \
            meta.helm.sh/release-name=nemo-infra \
            meta.helm.sh/release-namespace="$NAMESPACE" \
            --overwrite 2>/dev/null || log_warn "Failed to annotate $crd"

        oc label crd "$crd" \
            app.kubernetes.io/managed-by=Helm \
            --overwrite 2>/dev/null || log_warn "Failed to label $crd"
    done

    if [ "$found_crds" = true ]; then
        log_success "Existing Argo Workflows CRDs adopted into Helm"
    fi
}

# Function to adopt existing Volcano CRDs
adopt_volcano_crds() {
    log_info "Checking for existing Volcano CRDs..."

    # Dynamically find all CRDs with volcano.sh groups
    local volcano_crds
    volcano_crds=$(oc get crds -o json 2>/dev/null | \
        jq -r '.items[] | select(.spec.group | contains("volcano.sh")) | .metadata.name' 2>/dev/null)

    if [ -z "$volcano_crds" ]; then
        log_info "No existing Volcano CRDs found"
        return 0
    fi

    local found_crds=false

    for crd in $volcano_crds; do
        found_crds=true
        log_info "Found existing CRD: $crd - adopting into Helm release..."

        oc annotate crd "$crd" \
            meta.helm.sh/release-name=nemo-infra \
            meta.helm.sh/release-namespace="$NAMESPACE" \
            --overwrite 2>/dev/null || log_warn "Failed to annotate $crd"

        oc label crd "$crd" \
            app.kubernetes.io/managed-by=Helm \
            --overwrite 2>/dev/null || log_warn "Failed to label $crd"
    done

    if [ "$found_crds" = true ]; then
        log_success "Existing Volcano CRDs adopted into Helm"
    fi
}

# Function to adopt existing nemo-infra cluster resources
adopt_cluster_resources() {
    log_info "Checking for existing nemo-infra cluster resources..."

    local found_resources=false

    # Check and adopt ClusterRoles
    local cluster_roles
    cluster_roles=$(oc get clusterroles -o json 2>/dev/null | \
        jq -r '.items[] | select(.metadata.name | contains("nemo-infra") or contains("volcano") or contains("nim-operator")) | .metadata.name' 2>/dev/null)

    for resource in $cluster_roles; do
        found_resources=true
        log_info "Found existing ClusterRole: $resource - adopting into Helm release..."

        oc annotate clusterrole "$resource" \
            meta.helm.sh/release-name=nemo-infra \
            meta.helm.sh/release-namespace="$NAMESPACE" \
            --overwrite 2>/dev/null || log_warn "Failed to annotate $resource"

        oc label clusterrole "$resource" \
            app.kubernetes.io/managed-by=Helm \
            --overwrite 2>/dev/null || log_warn "Failed to label $resource"
    done

    # Check and adopt ClusterRoleBindings
    local cluster_role_bindings
    cluster_role_bindings=$(oc get clusterrolebindings -o json 2>/dev/null | \
        jq -r '.items[] | select(.metadata.name | contains("nemo-infra") or contains("volcano") or contains("nim-operator")) | .metadata.name' 2>/dev/null)

    for resource in $cluster_role_bindings; do
        found_resources=true
        log_info "Found existing ClusterRoleBinding: $resource - adopting into Helm release..."

        oc annotate clusterrolebinding "$resource" \
            meta.helm.sh/release-name=nemo-infra \
            meta.helm.sh/release-namespace="$NAMESPACE" \
            --overwrite 2>/dev/null || log_warn "Failed to annotate $resource"

        oc label clusterrolebinding "$resource" \
            app.kubernetes.io/managed-by=Helm \
            --overwrite 2>/dev/null || log_warn "Failed to label $resource"
    done

    # Check and adopt ValidatingWebhookConfigurations
    local webhooks
    webhooks=$(oc get validatingwebhookconfigurations -o json 2>/dev/null | \
        jq -r '.items[] | select(.metadata.name | contains("nemo-infra") or contains("volcano") or contains("nim-operator")) | .metadata.name' 2>/dev/null)

    for resource in $webhooks; do
        found_resources=true
        log_info "Found existing ValidatingWebhookConfiguration: $resource - adopting into Helm release..."

        # Clear managedFields to remove field manager conflicts
        log_info "Clearing managedFields for $resource to resolve field manager conflicts..."
        oc patch validatingwebhookconfiguration "$resource" --type=json -p='[{"op": "replace", "path": "/metadata/managedFields", "value": []}]' \
            2>/dev/null || log_warn "Failed to clear managedFields for $resource"

        oc annotate validatingwebhookconfiguration "$resource" \
            meta.helm.sh/release-name=nemo-infra \
            meta.helm.sh/release-namespace="$NAMESPACE" \
            --overwrite 2>/dev/null || log_warn "Failed to annotate $resource"

        oc label validatingwebhookconfiguration "$resource" \
            app.kubernetes.io/managed-by=Helm \
            --overwrite 2>/dev/null || log_warn "Failed to label $resource"
    done

    # Check and adopt MutatingWebhookConfigurations
    local mutating_webhooks
    mutating_webhooks=$(oc get mutatingwebhookconfigurations -o json 2>/dev/null | \
        jq -r '.items[] | select(.metadata.name | contains("nemo-infra") or contains("volcano") or contains("nim-operator")) | .metadata.name' 2>/dev/null)

    for resource in $mutating_webhooks; do
        found_resources=true
        log_info "Found existing MutatingWebhookConfiguration: $resource - adopting into Helm release..."

        # Clear managedFields to remove field manager conflicts
        log_info "Clearing managedFields for $resource to resolve field manager conflicts..."
        oc patch mutatingwebhookconfiguration "$resource" --type=json -p='[{"op": "replace", "path": "/metadata/managedFields", "value": []}]' \
            2>/dev/null || log_warn "Failed to clear managedFields for $resource"

        oc annotate mutatingwebhookconfiguration "$resource" \
            meta.helm.sh/release-name=nemo-infra \
            meta.helm.sh/release-namespace="$NAMESPACE" \
            --overwrite 2>/dev/null || log_warn "Failed to annotate $resource"

        oc label mutatingwebhookconfiguration "$resource" \
            app.kubernetes.io/managed-by=Helm \
            --overwrite 2>/dev/null || log_warn "Failed to label $resource"
    done

    # Check and adopt SecurityContextConstraints (OpenShift-specific)
    local sccs
    sccs=$(oc get scc -o json 2>/dev/null | \
        jq -r '.items[] | select(.metadata.name | contains("nemo") or contains("nim")) | .metadata.name' 2>/dev/null)

    for resource in $sccs; do
        found_resources=true
        log_info "Found existing SecurityContextConstraints: $resource - adopting into Helm release..."

        oc annotate scc "$resource" \
            meta.helm.sh/release-name=nemo-infra \
            meta.helm.sh/release-namespace="$NAMESPACE" \
            --overwrite 2>/dev/null || log_warn "Failed to annotate $resource"

        oc label scc "$resource" \
            app.kubernetes.io/managed-by=Helm \
            --overwrite 2>/dev/null || log_warn "Failed to label $resource"
    done

    if [ "$found_resources" = true ]; then
        log_success "Existing cluster resources adopted into Helm"
    else
        log_info "No existing nemo-infra cluster resources found"
    fi
}

# Function to install nemo-infra
install_nemo_infra() {
    log_info "Installing nemo-infra..."

    # Adopt any existing Argo Workflows CRDs
    adopt_argo_crds

    # Adopt any existing Volcano CRDs
    adopt_volcano_crds

    # Adopt any existing cluster resources
    adopt_cluster_resources

    # Navigate to NeMo-Microservices deploy directory
    NEMO_MS_DIR="$PROJECT_ROOT/NeMo-Microservices"

    if [ ! -d "$NEMO_MS_DIR/deploy/nemo-infra" ]; then
        log_error "NeMo-Microservices repository not found at $NEMO_MS_DIR"
        log_error "Please run: ./scripts/clone.sh"
        exit 1
    fi

    cd "$NEMO_MS_DIR/deploy/nemo-infra"

    # Check if nemo-infra release already exists with failed status
    if helm list -n "$NAMESPACE" | grep "nemo-infra" | grep -q "failed"; then
        log_warn "Existing nemo-infra release found in failed state. Uninstalling..."
        helm uninstall nemo-infra -n "$NAMESPACE" || log_warn "Failed to uninstall nemo-infra"
        sleep 5  # Give time for resources to clean up
    elif helm list -n "$NAMESPACE" | grep -q "nemo-infra"; then
        log_info "nemo-infra release already exists and is deployed. Skipping installation."
        return 0
    fi

    # Update Helm dependencies (force rebuild to pick up values changes)
    log_info "Updating Helm dependencies for nemo-infra..."
    rm -rf charts/*.tgz Chart.lock 2>/dev/null || true
    helm dependency update

    # Install nemo-infra
    log_info "Installing nemo-infra Helm chart..."
    helm install nemo-infra . -n "$NAMESPACE" \
        --create-namespace \
        --set namespace.name="$NAMESPACE" \

    log_success "nemo-infra installed"

    # Wait for infrastructure to be ready
    log_info "Waiting for nemo-infra pods to be ready (this may take a few minutes)..."
    oc wait --for=condition=ready pod -l app.kubernetes.io/instance=nemo-infra \
        -n "$NAMESPACE" --timeout=300s || log_warn "Some infrastructure pods may still be starting"

    log_success "nemo-infra is ready"
}

# Function to adopt existing nemo-instances cluster resources
adopt_instances_cluster_resources() {
    log_info "Checking for existing nemo-instances cluster resources..."

    local found_resources=false

    # Check and adopt ClusterRoles for nemo-instances
    local cluster_roles
    cluster_roles=$(oc get clusterroles -o json 2>/dev/null | \
        jq -r '.items[] | select(.metadata.name | contains("nemo-instances") or contains("nemo-operator") or contains("nim-operator")) | .metadata.name' 2>/dev/null)

    for resource in $cluster_roles; do
        found_resources=true
        log_info "Found existing ClusterRole: $resource - adopting into Helm release..."

        oc annotate clusterrole "$resource" \
            meta.helm.sh/release-name=nemo-instances \
            meta.helm.sh/release-namespace="$NAMESPACE" \
            --overwrite 2>/dev/null || log_warn "Failed to annotate $resource"

        oc label clusterrole "$resource" \
            app.kubernetes.io/managed-by=Helm \
            --overwrite 2>/dev/null || log_warn "Failed to label $resource"
    done

    # Check and adopt ClusterRoleBindings for nemo-instances
    local cluster_role_bindings
    cluster_role_bindings=$(oc get clusterrolebindings -o json 2>/dev/null | \
        jq -r '.items[] | select(.metadata.name | contains("nemo-instances") or contains("nemo-operator") or contains("nim-operator")) | .metadata.name' 2>/dev/null)

    for resource in $cluster_role_bindings; do
        found_resources=true
        log_info "Found existing ClusterRoleBinding: $resource - adopting into Helm release..."

        oc annotate clusterrolebinding "$resource" \
            meta.helm.sh/release-name=nemo-instances \
            meta.helm.sh/release-namespace="$NAMESPACE" \
            --overwrite 2>/dev/null || log_warn "Failed to annotate $resource"

        oc label clusterrolebinding "$resource" \
            app.kubernetes.io/managed-by=Helm \
            --overwrite 2>/dev/null || log_warn "Failed to label $resource"
    done

    # Check and adopt ValidatingWebhookConfigurations for nemo-instances
    local webhooks
    webhooks=$(oc get validatingwebhookconfigurations -o json 2>/dev/null | \
        jq -r '.items[] | select(.metadata.name | contains("nemo-instances") or contains("nemo-operator") or contains("nim-operator")) | .metadata.name' 2>/dev/null)

    for resource in $webhooks; do
        found_resources=true
        log_info "Found existing ValidatingWebhookConfiguration: $resource - adopting into Helm release..."

        oc annotate validatingwebhookconfiguration "$resource" \
            meta.helm.sh/release-name=nemo-instances \
            meta.helm.sh/release-namespace="$NAMESPACE" \
            --overwrite 2>/dev/null || log_warn "Failed to annotate $resource"

        oc label validatingwebhookconfiguration "$resource" \
            app.kubernetes.io/managed-by=Helm \
            --overwrite 2>/dev/null || log_warn "Failed to label $resource"
    done

    # Check and adopt MutatingWebhookConfigurations for nemo-instances
    local mutating_webhooks
    mutating_webhooks=$(oc get mutatingwebhookconfigurations -o json 2>/dev/null | \
        jq -r '.items[] | select(.metadata.name | contains("nemo-instances") or contains("nemo-operator") or contains("nim-operator")) | .metadata.name' 2>/dev/null)

    for resource in $mutating_webhooks; do
        found_resources=true
        log_info "Found existing MutatingWebhookConfiguration: $resource - adopting into Helm release..."

        oc annotate mutatingwebhookconfiguration "$resource" \
            meta.helm.sh/release-name=nemo-instances \
            meta.helm.sh/release-namespace="$NAMESPACE" \
            --overwrite 2>/dev/null || log_warn "Failed to annotate $resource"

        oc label mutatingwebhookconfiguration "$resource" \
            app.kubernetes.io/managed-by=Helm \
            --overwrite 2>/dev/null || log_warn "Failed to label $resource"
    done

    # Check and adopt SecurityContextConstraints (OpenShift-specific) for nemo-instances
    local sccs
    sccs=$(oc get scc -o json 2>/dev/null | \
        jq -r '.items[] | select(.metadata.name | contains("nemo") or contains("nim")) | .metadata.name' 2>/dev/null)

    for resource in $sccs; do
        found_resources=true
        log_info "Found existing SecurityContextConstraints: $resource - adopting into Helm release..."

        oc annotate scc "$resource" \
            meta.helm.sh/release-name=nemo-instances \
            meta.helm.sh/release-namespace="$NAMESPACE" \
            --overwrite 2>/dev/null || log_warn "Failed to annotate $resource"

        oc label scc "$resource" \
            app.kubernetes.io/managed-by=Helm \
            --overwrite 2>/dev/null || log_warn "Failed to label $resource"
    done

    if [ "$found_resources" = true ]; then
        log_success "Existing nemo-instances cluster resources adopted into Helm"
    else
        log_info "No existing nemo-instances cluster resources found"
    fi
}

# Function to install nemo-instances
install_nemo_instances() {
    log_info "Installing nemo-instances with chat model..."

    # Adopt any existing nemo-instances cluster resources
    adopt_instances_cluster_resources

    # Navigate to NeMo-Microservices deploy directory
    if [ ! -d "$NEMO_MS_DIR/deploy/nemo-instances" ]; then
        log_error "NeMo-Microservices repository not found at $NEMO_MS_DIR"
        log_error "Please run: ./scripts/clone.sh"
        exit 1
    fi

    cd "$NEMO_MS_DIR/deploy/nemo-instances"

    # Check if nemo-instances release already exists with failed status
    if helm list -n "$NAMESPACE" | grep "nemo-instances" | grep -q "failed"; then
        log_warn "Existing nemo-instances release found in failed state. Uninstalling..."
        helm uninstall nemo-instances -n "$NAMESPACE" || log_warn "Failed to uninstall nemo-instances"
        sleep 5  # Give time for resources to clean up
    elif helm list -n "$NAMESPACE" | grep -q "nemo-instances"; then
        log_info "nemo-instances release already exists and is deployed. Skipping installation."
        return 0
    fi

    # Install nemo-instances (LlamaStack disabled initially)
    log_info "Installing nemo-instances Helm chart..."
    helm install nemo-instances . -n "$NAMESPACE" \
        --set namespace.name="$NAMESPACE" \
        --set llamastack.enabled=false

    log_success "nemo-instances installed"

    # Wait for services to be ready
    log_info "Waiting for NeMo services to be ready (this may take several minutes)..."
    sleep 30  # Give pods time to start

    log_info "Checking NeMo service status..."
    oc get pods -n "$NAMESPACE" | grep -E "nemo(datastore|entitystore|customizer|evaluator|guardrail)|llama3-1b|embedqa"

    log_success "nemo-instances is ready"
}

# Function to verify installation
verify_installation() {
    log_info "Verifying installation..."

    echo ""
    log_info "=== Helm Releases ==="
    helm list -n "$NAMESPACE"

    echo ""
    log_info "=== Custom Resources ==="
    oc get nemodatastore,nemoentitystore,nemocustomizer,nemoevaluator,nemoguardrail,nimcache,nimpipeline -n "$NAMESPACE"

    echo ""
    log_info "=== Services ==="
    oc get svc -n "$NAMESPACE" | grep -E "nemo|llama|embedqa"

    echo ""
    log_info "=== Pods ==="
    oc get pods -n "$NAMESPACE"

    log_success "Installation verification complete"
}

downscale_unused() {
    # Scale down embedding and reranking models to save GPU resources
    log_info "Scaling down embedding and reranking models to save GPU resources..."
    oc scale deployment nv-embedqa-1b-v2 -n "$NAMESPACE" --replicas=0 2>/dev/null || log_warn "Failed to scale nv-embedqa-1b-v2"
    oc scale deployment nv-rerankqa-1b-v2 -n "$NAMESPACE" --replicas=0 2>/dev/null || log_warn "Failed to scale nv-rerankqa-1b-v2"
    log_success "Embedding and reranking models scaled to 0"
}

# Function to display next steps
display_next_steps() {
    echo ""
    log_success "==================================================================="
    log_success "NeMo Microservices Installation Complete!"
    log_success "==================================================================="
    echo ""
    log_info "Installed components:"
    echo "  ✅ NeMo Infrastructure (nemo-infra)"
    echo "  ✅ NeMo Services (customizer, datastore, entitystore, evaluator, guardrails)"
    echo "  ✅ Chat Model NIM: meta-llama3-1b-instruct"
    echo "  ✅ Embedding NIM: nv-embedqa-1b-v2"
    echo ""
    log_info "Service URLs (cluster-internal):"
    echo "  • Chat Model:     http://meta-llama3-1b-instruct.$NAMESPACE.svc.cluster.local:8000"
    echo "  • Embedding:      http://nv-embedqa-1b-v2.$NAMESPACE.svc.cluster.local:8000"
    echo "  • Data Store:     http://nemodatastore-sample.$NAMESPACE.svc.cluster.local:8000"
    echo "  • Entity Store:   http://nemoentitystore-sample.$NAMESPACE.svc.cluster.local:8000"
    echo "  • Customizer:     http://nemocustomizer-sample.$NAMESPACE.svc.cluster.local:8000"
    echo "  • Evaluator:      http://nemoevaluator-sample.$NAMESPACE.svc.cluster.local:8000"
    echo "  • Guardrails:     http://nemoguardrails-sample.$NAMESPACE.svc.cluster.local:8000"
    echo ""
    log_info "Next Steps:"
    echo ""
    echo "  1. Install Data Flywheel Prerequisites and Components:"
    echo "     cd $PROJECT_ROOT/deploy"
    echo "     make install-flywheel"
    echo ""
    echo "  2. Validate the installation with the tutorial notebook:"
    echo "     cd $PROJECT_ROOT"
    echo "     ./scripts/port-forward.sh"
    echo "     jupyter notebook notebooks/data-flywheel-bp-tutorial.ipynb"
    echo ""
    log_info "For detailed instructions, see: $PROJECT_ROOT/INSTRUCTIONS.md"
}

################################################################################
# Main Script
################################################################################

main() {
    # Get script directory and project root
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

    log_info "Starting NeMo Microservices Installation"
    log_info "Script directory: $SCRIPT_DIR"
    log_info "Project root: $PROJECT_ROOT"
    echo ""

    # Check prerequisites
    check_prerequisites

    # Load variables from .env
    load_env_variables

    # Set NeMo-Microservices directory path
    NEMO_MS_DIR="$PROJECT_ROOT/NeMo-Microservices"

    # Check if NeMo-Microservices is cloned
    if [ ! -d "$NEMO_MS_DIR" ]; then
        log_error "NeMo-Microservices repository not found at $NEMO_MS_DIR"
        log_error "Please run: cd $PROJECT_ROOT && ./scripts/clone.sh"
        exit 1
    fi

    echo ""
    log_info "Installation Configuration:"
    log_info "  Namespace: $NAMESPACE"
    log_info "  NGC API Key: ${NGC_API_KEY:0:10}... (hidden)"
    log_info "  NeMo-Microservices path: $NEMO_MS_DIR"
    echo ""

    read -p "Proceed with installation? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled"
        exit 0
    fi

    echo ""
    log_info "Starting installation..."
    echo ""

    # Execute installation steps
    create_namespace
    create_ngc_secrets
    install_nemo_infra
    install_nemo_instances
    verify_installation
    downscale_unused
    # Display next steps
    display_next_steps
}

# Run main function
main "$@"
