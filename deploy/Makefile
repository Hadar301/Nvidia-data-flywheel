.PHONY: help install-prereqs uninstall-prereqs update-prereqs upgrade-prereqs status verify clean

# Load environment variables from .env file
ifneq (,$(wildcard ../.env))
    include ../.env
    export
endif

# Configuration
NAMESPACE ?= hacohen-flywheel
RELEASE_NAME ?= flywheel-infra
CHART_DIR = flywheel-prerequisites

help:
	@echo "NVIDIA Data Flywheel - Deployment Automation"
	@echo ""
	@echo "Available targets:"
	@echo "  install-prereqs    - Install all prerequisite services (Elasticsearch, Redis, MongoDB, Gateway)"
	@echo "  uninstall-prereqs  - Uninstall prerequisite services"
	@echo "  update-prereqs     - Update Helm dependencies"
	@echo "  upgrade-prereqs    - Upgrade existing deployment"
	@echo "  status             - Check deployment status"
	@echo "  verify             - Run verification checks"
	@echo "  clean              - Clean Helm dependency artifacts"
	@echo ""
	@echo "Configuration:"
	@echo "  NAMESPACE=$(NAMESPACE)"
	@echo "  RELEASE_NAME=$(RELEASE_NAME)"

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
