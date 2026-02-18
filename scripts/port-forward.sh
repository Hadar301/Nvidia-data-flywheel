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

echo "📡 Starting port-forwards for namespace: $NAMESPACE"


oc port-forward -n $NAMESPACE svc/df-elasticsearch-service 9200:9200 &
sleep 0.1
oc port-forward -n $NAMESPACE svc/nemo-gateway 8080:80 &
sleep 0.1
oc port-forward -n $NAMESPACE svc/meta-llama3-1b-instruct 9001:8000 &
sleep 0.1
oc port-forward -n $NAMESPACE svc/df-api-service 8000:8000 &
sleep 0.1
oc port-forward -n $NAMESPACE svc/df-mlflow-service 5000:5000 &
sleep 0.1

echo "All port-forwards started. Press Ctrl+C to stop all."

wait 

echo "All port-forwards stoped."