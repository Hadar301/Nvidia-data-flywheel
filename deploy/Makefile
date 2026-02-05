.PHONY: help install-prereqs uninstall-prereqs update-prereqs upgrade-prereqs status verify clean \
	install-flywheel configure-flywheel-security uninstall-flywheel upgrade-flywheel status-flywheel

# Load environment variables from .env file
ifneq (,$(wildcard ../.env))
    include ../.env
    export
endif

# Configuration
NAMESPACE ?= hacohen-flywheel
RELEASE_NAME ?= flywheel-infra
CHART_DIR = flywheel-prerequisites

# Data Flywheel configuration
DATA_FLYWHEEL_CHART ?= ../data-flywheel/deploy/helm/data-flywheel
DATA_FLYWHEEL_RELEASE ?= data-flywheel
VALUES_OPENSHIFT = flywheel-components/values-openshift.yaml

help:
	@echo "NVIDIA Data Flywheel - Deployment Automation"
	@echo ""
	@echo "Prerequisites:"
	@echo "  install-prereqs    - Install all prerequisite services (Elasticsearch, Redis, MongoDB, Gateway)"
	@echo "  uninstall-prereqs  - Uninstall prerequisite services"
	@echo "  update-prereqs     - Update Helm dependencies"
	@echo "  upgrade-prereqs    - Upgrade existing deployment"
	@echo ""
	@echo "Data Flywheel:"
	@echo "  install-flywheel   - Install Data Flywheel services (includes prerequisites)"
	@echo "  upgrade-flywheel   - Upgrade existing Data Flywheel deployment"
	@echo "  uninstall-flywheel - Uninstall Data Flywheel services"
	@echo "  status-flywheel    - Check Data Flywheel deployment status"
	@echo ""
	@echo "Utilities:"
	@echo "  status             - Check all deployment status"
	@echo "  verify             - Run verification checks on prerequisites"
	@echo "  clean              - Clean Helm dependency artifacts"
	@echo ""
	@echo "Configuration:"
	@echo "  NAMESPACE=$(NAMESPACE)"
	@echo "  RELEASE_NAME=$(RELEASE_NAME)"
	@echo "  DATA_FLYWHEEL_CHART=$(DATA_FLYWHEEL_CHART)"

install-prereqs: update-prereqs
	@echo "Installing Data Flywheel prerequisites..."
	@echo "Granting anyuid SCC to Elasticsearch service account..."
	oc adm policy add-scc-to-user anyuid -z elasticsearch-master -n $(NAMESPACE) || true
	@echo "Granting anyuid SCC to default service account (for customization jobs)..."
	oc adm policy add-scc-to-user anyuid -z default -n $(NAMESPACE) || true
	helm install $(RELEASE_NAME) $(CHART_DIR) \
		--namespace $(NAMESPACE) \
		--create-namespace \
		--set namespace.name=$(NAMESPACE) \
		--wait \
		--timeout 10m
	@echo "Configuring NeMo Evaluator to use gateway for Entity Store calls..."
	oc set env deployment/nemoevaluator-sample -n $(NAMESPACE) ENTITY_STORE_URL="http://nemo-gateway" || true
	@echo "Installation complete!"
	@$(MAKE) status

uninstall-prereqs:
	@echo "Uninstalling Data Flywheel prerequisites..."
	helm uninstall $(RELEASE_NAME) --namespace $(NAMESPACE)
	@echo "Uninstallation complete!"

update-prereqs:
	@echo "Updating Helm chart dependencies..."
	cd $(CHART_DIR) && helm dependency update
	@echo "Dependencies updated!"

upgrade-prereqs: update-prereqs
	@echo "Upgrading Data Flywheel prerequisites..."
	helm upgrade $(RELEASE_NAME) $(CHART_DIR) \
		--namespace $(NAMESPACE) \
		--set namespace.name=$(NAMESPACE) \
		--wait \
		--timeout 10m
	@echo "Upgrade complete!"
	@$(MAKE) status

status:
	@echo "=== Helm Release Status ==="
	helm status $(RELEASE_NAME) -n $(NAMESPACE) || echo "Release not found"
	@echo ""
	@echo "=== Pods Status ==="
	kubectl get pods -n $(NAMESPACE) -o wide
	@echo ""
	@echo "=== Services ==="
	kubectl get svc -n $(NAMESPACE)
	@echo ""
	@echo "=== Routes ==="
	oc get routes -n $(NAMESPACE) 2>/dev/null || echo "No routes found (not on OpenShift?)"

verify:
	@echo "=== Running Verification Checks ==="
	@echo ""
	@echo "1. Checking Elasticsearch..."
	@kubectl get pods -n $(NAMESPACE) -l chart=elasticsearch -o jsonpath='{.items[0].metadata.name}' | \
		xargs -I {} kubectl exec {} -n $(NAMESPACE) -- curl -k -s https://localhost:9200/_cluster/health | grep -q "status" && \
		echo "✓ Elasticsearch is healthy" || echo "✗ Elasticsearch check failed"
	@echo ""
	@echo "2. Checking Redis..."
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=redis -o jsonpath='{.items[0].metadata.name}' | \
		xargs -I {} kubectl exec {} -n $(NAMESPACE) -- redis-cli ping | grep -q "PONG" && \
		echo "✓ Redis is responding" || echo "✗ Redis check failed"
	@echo ""
	@echo "3. Checking MongoDB..."
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/name=mongodb -o jsonpath='{.items[0].metadata.name}' | \
		xargs -I {} kubectl exec {} -n $(NAMESPACE) -- mongosh --quiet --eval "db.adminCommand('ping')" | grep -q "ok" && \
		echo "✓ MongoDB is responding" || echo "✗ MongoDB check failed"
	@echo ""
	@echo "4. Checking Gateway..."
	@kubectl get pods -n $(NAMESPACE) -l app=nemo-gateway -o jsonpath='{.items[0].metadata.name}' | \
		xargs -I {} kubectl exec {} -n $(NAMESPACE) -- curl -s http://localhost:8080/healthz | grep -q "OK" && \
		echo "✓ Gateway health check passed" || echo "✗ Gateway check failed"
	@echo ""
	@echo "=== Gateway URL ==="
	@oc get route nemo-gateway -n $(NAMESPACE) -o jsonpath='https://{.spec.host}' 2>/dev/null && echo "" || echo "Route not available"

clean:
	@echo "Cleaning Helm dependency artifacts..."
	rm -rf $(CHART_DIR)/charts/
	rm -f $(CHART_DIR)/Chart.lock
	@echo "Clean complete!"

# Advanced targets
logs-elasticsearch:
	@kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=elasticsearch --tail=100 -f

logs-redis:
	@kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=redis --tail=100 -f

logs-mongodb:
	@kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=mongodb --tail=100 -f

logs-gateway:
	@kubectl logs -n $(NAMESPACE) -l app=nemo-gateway --tail=100 -f

port-forward-elasticsearch:
	@echo "Forwarding Elasticsearch to localhost:9200..."
	kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-elasticsearch 9200:9200

port-forward-redis:
	@echo "Forwarding Redis to localhost:6379..."
	kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-redis-master 6379:6379

port-forward-mongodb:
	@echo "Forwarding MongoDB to localhost:27017..."
	kubectl port-forward -n $(NAMESPACE) svc/$(RELEASE_NAME)-mongodb 27017:27017

# ============================================================================
# Data Flywheel Targets
# ============================================================================

install-flywheel: install-prereqs
	@echo "=== Installing Data Flywheel Components ==="
	@echo ""
	@# Check that data-flywheel chart directory exists
	@if [ ! -d "$(DATA_FLYWHEEL_CHART)" ]; then \
		echo "ERROR: Data Flywheel Helm chart not found at $(DATA_FLYWHEEL_CHART)"; \
		echo "Please run: ./scripts/clone.sh"; \
		exit 1; \
	fi
	@# Check required environment variables
	@if [ -z "$(NGC_API_KEY)" ]; then \
		echo "ERROR: NGC_API_KEY not set. Please configure .env file"; \
		exit 1; \
	fi
	@if [ -z "$(NVIDIA_API_KEY)" ]; then \
		echo "ERROR: NVIDIA_API_KEY not set. Please configure .env file"; \
		exit 1; \
	fi
	@if [ -z "$(HF_TOKEN)" ]; then \
		echo "ERROR: HF_TOKEN not set. Please configure .env file"; \
		exit 1; \
	fi
	@echo "Configuring NeMo Evaluator to use gateway..."
	oc set env deployment/nemoevaluator-sample -n $(NAMESPACE) ENTITY_STORE_URL="http://nemo-gateway" || true
	@echo "Waiting for NeMo Evaluator to restart..."
	oc rollout status deployment/nemoevaluator-sample -n $(NAMESPACE) --timeout=120s || true
	@echo ""
	@echo "Fixing NeMo Evaluator RBAC permissions for secret cleanup..."
	@if oc get role nemoevaluator-sample -n $(NAMESPACE) &>/dev/null; then \
		if ! oc get role nemoevaluator-sample -n $(NAMESPACE) -o jsonpath='{.rules[1].verbs}' | grep -q "delete"; then \
			oc patch role nemoevaluator-sample -n $(NAMESPACE) --type=json \
				-p='[{"op": "add", "path": "/rules/1/verbs/-", "value": "delete"}]'; \
			echo "✓ Added delete permission for secrets"; \
		else \
			echo "✓ Delete permission already exists"; \
		fi \
	fi
	@echo ""
	@echo "Fixing base model file permissions for customization..."
	@if oc get pvc finetuning-ms-models-pvc -n $(NAMESPACE) &>/dev/null; then \
		OPENSHIFT_UID=$$(oc get namespace $(NAMESPACE) -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.uid-range}' | cut -d'/' -f1); \
		if [ -n "$$OPENSHIFT_UID" ]; then \
			echo "  Detected OpenShift UID range starting at: $$OPENSHIFT_UID"; \
			echo "  Updating model file ownership..."; \
			oc run fix-model-perms --rm -i --restart=Never --image=busybox:latest -n $(NAMESPACE) \
				--overrides="{\"spec\":{\"securityContext\":{\"runAsUser\":0},\"containers\":[{\"name\":\"fix\",\"image\":\"busybox\",\"command\":[\"sh\",\"-c\",\"chown -R $$OPENSHIFT_UID:1000 /mount/models/* 2>/dev/null || true\"],\"volumeMounts\":[{\"name\":\"models\",\"mountPath\":\"/mount/models\"}]}],\"volumes\":[{\"name\":\"models\",\"persistentVolumeClaim\":{\"claimName\":\"finetuning-ms-models-pvc\"}}],\"serviceAccountName\":\"default\"}}" \
				--timeout=60s 2>/dev/null || true; \
			echo "  ✓ Model file permissions updated"; \
		fi \
	fi
	@echo ""
	@echo "Navigating to Data Flywheel Helm chart..."
	cd $(DATA_FLYWHEEL_CHART) && \
	echo "Updating Helm dependencies..." && \
	helm dependency update && \
	echo "" && \
	echo "Installing Data Flywheel..." && \
	helm install $(DATA_FLYWHEEL_RELEASE) . \
		--values $(CURDIR)/$(VALUES_OPENSHIFT) \
		--set secrets.ngcApiKey="$(NGC_API_KEY)" \
		--set secrets.nvidiaApiKey="$(NVIDIA_API_KEY)" \
		--set secrets.hfToken="$(HF_TOKEN)" \
		--set secrets.llmJudgeApiKey="$(NVIDIA_API_KEY)" \
		--set secrets.embApiKey="$(NVIDIA_API_KEY)" \
		--set 'imagePullSecrets[0].password=$(NGC_API_KEY)' \
		--namespace $(NAMESPACE) \
		--timeout 10m
	@echo ""
	@$(MAKE) configure-flywheel-security
	@echo ""
	@echo "✅ Data Flywheel installation complete!"
	@$(MAKE) status-flywheel

configure-flywheel-security:
	@echo "=== Configuring OpenShift Security for Data Flywheel ==="
	@# Create service account if it doesn't exist
	@if ! oc get serviceaccount data-flywheel-sa -n $(NAMESPACE) &>/dev/null; then \
		oc create serviceaccount data-flywheel-sa -n $(NAMESPACE); \
		echo "  ✓ Created service account: data-flywheel-sa"; \
	else \
		echo "  ✓ Service account data-flywheel-sa already exists"; \
	fi
	@# Grant anyuid SCC
	oc adm policy add-scc-to-user anyuid system:serviceaccount:$(NAMESPACE):data-flywheel-sa
	@echo "  ✓ Granted anyuid SCC to service account"
	@# Patch deployments to use the service account
	@echo "  Patching deployments to use service account..."
	@for deployment in df-api-deployment df-celery-worker-deployment \
			df-celery-parent-worker-deployment df-flower-deployment \
			df-mlflow-deployment; do \
		oc patch deployment $$deployment -n $(NAMESPACE) \
			-p '{"spec":{"template":{"spec":{"serviceAccountName":"data-flywheel-sa"}}}}' 2>/dev/null || true; \
	done
	@echo "  ✓ Security configuration complete"

upgrade-flywheel:
	@echo "=== Upgrading Data Flywheel Components ==="
	@# Check that data-flywheel chart directory exists
	@if [ ! -d "$(DATA_FLYWHEEL_CHART)" ]; then \
		echo "ERROR: Data Flywheel Helm chart not found at $(DATA_FLYWHEEL_CHART)"; \
		exit 1; \
	fi
	@echo "Navigating to Data Flywheel Helm chart..."
	cd $(DATA_FLYWHEEL_CHART) && \
	echo "Updating Helm dependencies..." && \
	helm dependency update && \
	echo "" && \
	echo "Upgrading Data Flywheel..." && \
	helm upgrade $(DATA_FLYWHEEL_RELEASE) . \
		--values $(CURDIR)/$(VALUES_OPENSHIFT) \
		--set secrets.ngcApiKey="$(NGC_API_KEY)" \
		--set secrets.nvidiaApiKey="$(NVIDIA_API_KEY)" \
		--set secrets.hfToken="$(HF_TOKEN)" \
		--set secrets.llmJudgeApiKey="$(NVIDIA_API_KEY)" \
		--set secrets.embApiKey="$(NVIDIA_API_KEY)" \
		--set 'imagePullSecrets[0].password=$(NGC_API_KEY)' \
		--namespace $(NAMESPACE) \
		--timeout 10m
	@echo ""
	@echo "✅ Data Flywheel upgrade complete!"
	@$(MAKE) status-flywheel

uninstall-flywheel:
	@echo "=== Uninstalling Data Flywheel ==="
	helm uninstall $(DATA_FLYWHEEL_RELEASE) --namespace $(NAMESPACE) || echo "Release not found"
	@echo "✅ Data Flywheel uninstalled"

status-flywheel:
	@echo "=== Data Flywheel Deployment Status ==="
	@echo ""
	@echo "--- Helm Release ---"
	helm status $(DATA_FLYWHEEL_RELEASE) -n $(NAMESPACE) 2>/dev/null || echo "Release not found"
	@echo ""
	@echo "--- Data Flywheel Pods ---"
	oc get pods -n $(NAMESPACE) | grep "^df-" || echo "No Data Flywheel pods found"
	@echo ""
	@echo "--- Data Flywheel Services ---"
	oc get svc -n $(NAMESPACE) | grep "^df-" || echo "No Data Flywheel services found"
