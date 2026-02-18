#!/bin/bash

################################################################################
# OpenShift Security Configuration for Data Flywheel
# This script configures Security Context Constraints (SCC) and RBAC permissions
# required for Data Flywheel and NeMo services on OpenShift
################################################################################

set -e

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

# Load environment variables
NAMESPACE=${NAMESPACE:-hacohen-flywheel}

log_info "Configuring OpenShift security for Data Flywheel in namespace: $NAMESPACE"
echo ""

# Check if user is logged into OpenShift
if ! oc whoami &> /dev/null; then
    log_error "Not logged into OpenShift. Please run 'oc login' first."
    exit 1
fi

# Check if namespace exists
if ! oc get namespace "$NAMESPACE" &> /dev/null; then
    log_error "Namespace $NAMESPACE does not exist. Please create it first."
    exit 1
fi

log_success "Prerequisites check passed"
echo ""

# 1. Grant anyuid SCC for default service account (needed by infrastructure pods)
log_info "Granting anyuid SCC to default service account..."
oc adm policy add-scc-to-user anyuid -z default -n ${NAMESPACE} 2>/dev/null || log_warn "Failed to grant anyuid to default service account (may already exist)"

# 2. Create and configure data-flywheel service account
log_info "Creating data-flywheel service account..."
if oc get serviceaccount data-flywheel-sa -n ${NAMESPACE} &>/dev/null; then
    log_info "Service account data-flywheel-sa already exists"
else
    oc create serviceaccount data-flywheel-sa -n ${NAMESPACE}
    log_success "Created service account: data-flywheel-sa"
fi

log_info "Granting anyuid SCC to data-flywheel-sa..."
oc adm policy add-scc-to-user anyuid system:serviceaccount:${NAMESPACE}:data-flywheel-sa 2>/dev/null || log_warn "Failed to grant anyuid (may already exist)"

log_success "Data Flywheel service account configured"
echo ""

# 3. Configure NeMo Evaluator to use gateway (if NeMo is installed)
log_info "Checking for NeMo Evaluator deployment..."
if oc get deployment/nemoevaluator-sample -n ${NAMESPACE} &>/dev/null; then
    log_info "NeMo Evaluator found - configuring to use gateway..."

    # Set environment variable to use gateway
    if oc set env deployment/nemoevaluator-sample -n ${NAMESPACE} \
        ENTITY_STORE_URL="http://nemo-gateway" 2>/dev/null; then
        log_success "Configured NeMo Evaluator to use gateway"
    else
        log_warn "Failed to configure NeMo Evaluator (may already be configured)"
    fi

    # Wait for rollout
    log_info "Waiting for NeMo Evaluator to restart..."
    oc rollout status deployment/nemoevaluator-sample -n ${NAMESPACE} --timeout=120s 2>/dev/null || \
        log_warn "Timeout waiting for NeMo Evaluator rollout"

    echo ""

    # 4. Fix NeMo Evaluator RBAC for secret cleanup
    log_info "Fixing NeMo Evaluator RBAC permissions..."
    if oc get role nemoevaluator-sample -n ${NAMESPACE} &>/dev/null; then
        # Check if delete permission already exists
        if oc get role nemoevaluator-sample -n ${NAMESPACE} -o jsonpath='{.rules[1].verbs}' | grep -q "delete"; then
            log_info "Delete permission already exists for secrets"
        else
            if oc patch role nemoevaluator-sample -n ${NAMESPACE} --type=json \
                -p='[{"op": "add", "path": "/rules/1/verbs/-", "value": "delete"}]' 2>/dev/null; then
                log_success "Added delete permission for secrets"
            else
                log_warn "Failed to patch RBAC (may already be patched)"
            fi
        fi
    else
        log_warn "NeMo Evaluator role not found - skipping RBAC patch"
    fi
else
    log_warn "NeMo Evaluator not found - skipping NeMo-specific configuration"
    log_warn "This is expected if you haven't installed NeMo yet"
fi

# 5. Fix base model file permissions for customization jobs
echo ""
log_info "Fixing base model file permissions for customization..."
if oc get pvc finetuning-ms-models-pvc -n ${NAMESPACE} &>/dev/null; then
    OPENSHIFT_UID=$(oc get namespace ${NAMESPACE} -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.uid-range}' | cut -d'/' -f1)
    if [ -n "$OPENSHIFT_UID" ]; then
        log_info "Detected OpenShift UID range starting at: $OPENSHIFT_UID"
        log_info "Updating model file ownership..."
        oc run fix-model-perms --rm -i --restart=Never --image=busybox:latest -n ${NAMESPACE} \
            --overrides="{\"spec\":{\"securityContext\":{\"runAsUser\":0},\"containers\":[{\"name\":\"fix\",\"image\":\"busybox\",\"command\":[\"sh\",\"-c\",\"chown -R $OPENSHIFT_UID:1000 /mount/models/* 2>/dev/null || true\"],\"volumeMounts\":[{\"name\":\"models\",\"mountPath\":\"/mount/models\"}]}],\"volumes\":[{\"name\":\"models\",\"persistentVolumeClaim\":{\"claimName\":\"finetuning-ms-models-pvc\"}}],\"serviceAccountName\":\"default\"}}" \
            --timeout=60s 2>/dev/null || log_warn "Permission fix job may have already completed or failed"
        log_success "Model file permissions updated"
    else
        log_warn "Could not detect OpenShift UID range"
    fi
else
    log_warn "Model PVC (finetuning-ms-models-pvc) not found - skipping permission fix"
    log_warn "This is expected if you haven't installed NeMo yet"
fi

echo ""
log_success "===================================================================="
log_success "OpenShift Security Configuration Complete!"
log_success "===================================================================="
echo ""
log_info "Summary of configured resources:"
echo "  ✅ anyuid SCC granted to: default service account"
echo "  ✅ Service account created: data-flywheel-sa"
echo "  ✅ anyuid SCC granted to: data-flywheel-sa"

if oc get deployment/nemoevaluator-sample -n ${NAMESPACE} &>/dev/null; then
    echo "  ✅ NeMo Evaluator configured to use gateway"
    echo "  ✅ NeMo Evaluator RBAC updated for secret cleanup"
fi

if oc get pvc finetuning-ms-models-pvc -n ${NAMESPACE} &>/dev/null; then
    echo "  ✅ Model file permissions fixed for customization"
fi

echo ""
log_info "Next steps:"
echo "  1. Deploy nemo-gateway:"
echo "     oc apply -k deploy/nemo-gateway/"
echo ""
echo "  2. Install data-flywheel chart:"
echo "     cd data-flywheel/deploy/helm/data-flywheel"
echo "     helm dependency update"
echo "     helm install data-flywheel . \\"
echo "       --values ../../../../deploy/flywheel-components/values-openshift-standalone.yaml \\"
echo "       --set secrets.ngcApiKey=\"\${NGC_API_KEY}\" \\"
echo "       --set secrets.nvidiaApiKey=\"\${NVIDIA_API_KEY}\" \\"
echo "       --set secrets.hfToken=\"\${HF_TOKEN}\" \\"
echo "       --set secrets.llmJudgeApiKey=\"\${NVIDIA_API_KEY}\" \\"
echo "       --set secrets.embApiKey=\"\${NVIDIA_API_KEY}\" \\"
echo "       --set \"imagePullSecrets[0].password=\${NGC_API_KEY}\" \\"
echo "       --namespace=${NAMESPACE} \\"
echo "       --timeout=10m"
echo ""
