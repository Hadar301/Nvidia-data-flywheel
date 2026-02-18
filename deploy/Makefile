.PHONY: help clone install-nemo install-flywheel status clean

# Load environment variables from .env file
ifneq (,$(wildcard ../.env))
    include ../.env
    export
endif

# Configuration
NAMESPACE ?= hacohen-flywheel
DATA_FLYWHEEL_CHART = ../data-flywheel/deploy/helm/data-flywheel

help:
	@echo "NVIDIA Data Flywheel - Deployment Commands"
	@echo ""
	@echo "Quick Start:"
	@echo "  make clone            - Clone required repositories (NeMo-Microservices, data-flywheel)"
	@echo "  make install-nemo     - Install NeMo Microservices infrastructure"
	@echo "  make install-flywheel - Install Data Flywheel with bundled infrastructure"
	@echo ""
	@echo "Utilities:"
	@echo "  make status           - Check deployment status"
	@echo "  make clean            - Clean up namespace (development only)"
	@echo ""
	@echo "Configuration:"
	@echo "  NAMESPACE=$(NAMESPACE)"
	@echo ""
	@echo "See ../INSTRUCTIONS.md for detailed installation guide."

clone:
	@echo "Cloning required repositories..."
	cd .. && ./scripts/clone.sh
	@echo ""
	@echo "✅ Repositories cloned successfully!"
	@echo "Next step: make install-nemo"

install-nemo:
	@echo "Installing NeMo Microservices..."
	@echo ""
	cd .. && ./scripts/install-nemo.sh
	@echo ""
	@echo "✅ NeMo Microservices installed!"
	@echo "Next step: make install-flywheel"

install-flywheel:
	@echo "Installing Data Flywheel with bundled infrastructure..."
	@echo ""
	@# Step 1: Configure OpenShift security
	@echo "=== Step 1/3: Configuring OpenShift Security ==="
	cd .. && ./scripts/configure-data-flywheel-security.sh
	@echo ""
	@# Step 2: Deploy NeMo Gateway
	@echo "=== Step 2/3: Deploying NeMo Gateway ==="
	oc apply -k nemo-gateway/
	@echo ""
	@# Step 3: Install Data Flywheel Helm chart
	@echo "=== Step 3/3: Installing Data Flywheel Helm Chart ==="
	@if [ -z "$(NGC_API_KEY)" ] || [ -z "$(NVIDIA_API_KEY)" ] || [ -z "$(HF_TOKEN)" ]; then \
		echo "ERROR: Required environment variables not set."; \
		echo "Please ensure .env file exists with NGC_API_KEY, NVIDIA_API_KEY, and HF_TOKEN"; \
		exit 1; \
	fi
	cd $(DATA_FLYWHEEL_CHART) && \
		helm dependency update && \
		helm install data-flywheel . \
			--values ../../../../deploy/flywheel-components/values-openshift-standalone.yaml \
			--set secrets.ngcApiKey="$(NGC_API_KEY)" \
			--set secrets.nvidiaApiKey="$(NVIDIA_API_KEY)" \
			--set secrets.hfToken="$(HF_TOKEN)" \
			--set secrets.llmJudgeApiKey="$(NVIDIA_API_KEY)" \
			--set secrets.embApiKey="$(NVIDIA_API_KEY)" \
			--set "imagePullSecrets[0].password=$(NGC_API_KEY)" \
			--namespace=$(NAMESPACE) \
			--timeout=10m
	@echo ""
	@echo "✅ Data Flywheel installation complete!"
	@echo ""
	@$(MAKE) status

status:
	@echo "=== Helm Releases ==="
	@helm list -n $(NAMESPACE) || echo "No releases found"
	@echo ""
	@echo "=== Pods ==="
	@oc get pods -n $(NAMESPACE) || echo "Namespace not found"
	@echo ""
	@echo "=== Services ==="
	@oc get svc -n $(NAMESPACE) || echo "Namespace not found"
	@echo ""
	@echo "=== Routes ==="
	@oc get routes -n $(NAMESPACE) 2>/dev/null || echo "No routes found (not on OpenShift?)"

clean:
	@echo "⚠️  WARNING: This will delete all resources in namespace $(NAMESPACE)"
	@echo "This action is intended for development/testing only."
	@echo ""
	cd .. && ./scripts/clear_namespace.sh
