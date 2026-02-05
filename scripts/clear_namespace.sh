#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load NAMESPACE from .env file
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
fi

# Use default if not set
NAMESPACE="${NAMESPACE:-hacohen-flywheel}"

# Check if namespace exists before proceeding
if ! oc get namespace $NAMESPACE &>/dev/null; then
  echo "Namespace '$NAMESPACE' does not exist. Exiting."
  exit 0
fi

oc project $NAMESPACE
# echo "Uninstalling NeMo Microservices Prerequisites..."
# cd k8s-nim-operator/test/e2e/nemo-dependencies
# ansible-playbook -c local -i localhost uninstall.yaml &
echo "DONE! Uninstalling NeMo Microservices Prerequisites"

echo "Starting cleanup of namespace: $NAMESPACE"

# Step 1: Delete webhooks that might block resource deletion
echo "Deleting webhooks..."
oc delete validatingwebhookconfiguration k8s-nim-operator-validating-webhook-configuration --ignore-not-found=true &
oc delete mutatingwebhookconfiguration k8s-nim-operator-mutating-webhook-configuration --ignore-not-found=true &

oc delete mutatingwebhookconfiguration volcano-admission-service-queues-mutate volcano-admission-service-jobs-mutate
oc delete validatingwebhookconfiguration volcano-admission-service-jobs-validate volcano-admission-service-queues-validate volcano-admission-service-hypernodes-validate


# Step 2: Delete custom resources FIRST (they may own other resources)
echo "Deleting custom resources..."
oc delete nemotrainingjobs --all -n $NAMESPACE --wait=false &
oc delete nimservice --all -n $NAMESPACE --wait=false &
oc delete nimcache --all -n $NAMESPACE --wait=false &
oc delete nimpipeline --all -n $NAMESPACE --wait=false &
oc delete nemodatastore --all -n $NAMESPACE --wait=false &
oc delete nemocustomizer --all -n $NAMESPACE --wait=false &
oc delete nemoentitystore --all -n $NAMESPACE --wait=false &
oc delete nemoguardrails --all -n $NAMESPACE --wait=false &
oc delete nemoevaluator --all -n $NAMESPACE --wait=false &

# Step 3: Delete deployments and wait for pods to terminate
echo "Deleting deployments..."
oc delete deployment --all -n $NAMESPACE --wait=false &
oc delete statefulsets --all -n $NAMESPACE --wait=false &

# Step 4: Delete jobs
echo "Deleting jobs..."
oc delete job --all -n $NAMESPACE --wait=false &

# Step 5: Force delete all pods to release PVC locks
echo "Force deleting all pods..."
oc delete pod --all -n $NAMESPACE --force --grace-period=0 &

# Step 6: Wait a moment for pods to release PVCs
echo "Waiting for pods to fully terminate..."
sleep 5

# Step 7: Delete PVCs (now that pods are gone)
echo "Deleting PVCs..."
oc delete pvc --all -n $NAMESPACE --wait=false &

# Step 8: Remove finalizers from stuck PVCs if any
echo "Checking for stuck PVCs and removing finalizers..."
for pvc in $(oc get pvc -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  echo "Removing finalizers from PVC: $pvc"
  oc patch pvc $pvc -n $NAMESPACE -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
done

# Step 9: Delete services
echo "Deleting services..."
oc delete service --all -n $NAMESPACE &

# Step 10: Delete configmaps
echo "Deleting configmaps..."
oc delete configmap --all -n $NAMESPACE &

# Step 11: Delete secrets (be careful with this one if you have important secrets)
echo "Deleting secrets..."
oc delete secret --all -n $NAMESPACE &

# Step 12: Remove finalizers from any stuck custom resources
echo "Checking for stuck custom resources and removing finalizers..."
for crd in nemotrainingjobs nimservice nimcache nimpipeline nemodatastore nemocustomizer nemoentitystore nemoguardrails nemoevaluator; do
  for resource in $(oc get $crd -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    echo "Removing finalizers from $crd: $resource"
    oc patch $crd $resource -n $NAMESPACE -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
  done
done

echo "Waiting for resources to be cleaned up..."
sleep 10

wait
# Step 13: Delete the namespace
echo "Deleting namespace: $NAMESPACE"
oc delete project $NAMESPACE --wait=false

# Step 14: Remove finalizers from namespace if it gets stuck
echo "Monitoring namespace deletion..."
sleep 5
if oc get namespace $NAMESPACE 2>/dev/null; then
  echo "Namespace stuck in Terminating, removing finalizers..."
  oc patch namespace $NAMESPACE -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
fi

echo "Cleanup completed!"