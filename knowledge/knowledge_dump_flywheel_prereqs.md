# Data Flywheel Prerequisites Installation - Knowledge Dump

This document captures all troubleshooting knowledge, design decisions, and error resolutions encountered during the deployment of Data Flywheel infrastructure prerequisites on OpenShift.

## Overview

**What This Chart Does:**
Deploys the infrastructure prerequisites for NVIDIA Data Flywheel on top of existing NeMo Microservices:
- Elasticsearch 8.5.1 (HTTPS with self-signed certificates)
- Redis 7.2.x (task queue for Celery)
- MongoDB 7.0.x (API metadata storage)
- NGINX Gateway (unified routing for NeMo + Data Flywheel)

**Environment:**
- Platform: OpenShift 4.12+
- Namespace: Configured via `.env` file
- Existing: NeMo Microservices already deployed
- Storage: Dynamic provisioning (gp3-csi)

---

## Error History and Resolutions

### 1. Elasticsearch Permission Errors (AccessDeniedException)

**Error:**
```
AccessDeniedException: /usr/share/elasticsearch/data/node.lock
java.nio.file.AccessDeniedException: /usr/share/elasticsearch/data/node.lock
failed to obtain node locks, tried [/usr/share/elasticsearch/data]
```

**Context:**
- Pod: `elasticsearch-master-0`
- Chart: Official Elastic Helm chart 8.5.1
- Platform: OpenShift with restricted-v2 SCC

**Root Cause Analysis:**
1. Elasticsearch container runs as UID 1000 by default
2. OpenShift restricted-v2 SCC assigns random UIDs (range: 1001050000-1001059999)
3. Volume mounted with random UID ownership
4. Container with UID 1000 can't write to volume owned by UID 1001050000+

**Failed Attempts:**
1. **Attempt 1:** Set only podSecurityContext
   ```yaml
   podSecurityContext:
     fsGroup: 1000
   ```
   **Result:** Pod still got random UID, fsGroup alone insufficient

2. **Attempt 2:** Set only container securityContext
   ```yaml
   securityContext:
     runAsUser: 1000
   ```
   **Result:** OpenShift SCC rejected due to UID outside allowed range

**Final Solution:**
Two-part fix:

**Part 1 - Grant anyuid SCC:**
```bash
oc adm policy add-scc-to-user anyuid -z elasticsearch-master -n $NAMESPACE
```

**Part 2 - Explicit UID configuration in values.yaml:**
```yaml
elasticsearch:
  podSecurityContext:
    fsGroup: 1000      # Volume files owned by group 1000
    runAsUser: 1000    # Pod-level UID
  securityContext:
    capabilities:
      drop:
        - ALL         # Drop all capabilities for security
    runAsNonRoot: true
    allowPrivilegeEscalation: false
    runAsUser: 1000   # Container-level UID
```

**Automation in Makefile:**
```makefile
install-prereqs: update-prereqs
	@echo "Granting anyuid SCC to Elasticsearch service account..."
	oc adm policy add-scc-to-user anyuid -z elasticsearch-master -n $(NAMESPACE) || true
	helm install ...
```

**Verification:**
```bash
# Check SCC assignment
oc get pod elasticsearch-master-0 -o jsonpath='{.metadata.annotations.openshift\.io/scc}'
# Should return: anyuid

# Check actual UID
kubectl exec elasticsearch-master-0 -- id
# Should return: uid=1000 gid=1000

# Check volume permissions
kubectl exec elasticsearch-master-0 -- ls -la /usr/share/elasticsearch/data
# Should show ownership: 1000:1000
```

---

### 2. Elasticsearch HTTPS/SSL Configuration Issues

**Error Sequence:**

**Error 1 - Plaintext on HTTPS channel:**
```
WARN received plaintext http traffic on an https channel, closing connection
Netty4HttpChannel{localAddress=/127.0.0.1:9200, remoteAddress=/127.0.0.1:57878}
curl: (52) Empty reply from server
```

**Error 2 - Readiness probe failures:**
```
Readiness probe failed: HTTP probe failed with statuscode: 502
Liveness probe failed: Get "http://10.129.2.167:9200": EOF
```

**Context:**
- Official Elastic chart defaults to HTTPS with self-signed certificates
- Health probes and verification scripts used HTTP
- Initial attempt: disable SSL completely
- User requirement: Actually, use HTTPS (encryption within cluster)

**Troubleshooting Journey:**

**Attempt 1 - Disable SSL via esConfig only:**
```yaml
esConfig:
  elasticsearch.yml: |
    xpack.security.enabled: false
    xpack.security.http.ssl.enabled: false
    xpack.security.transport.ssl.enabled: false
```
**Result:** SSL still enabled! Config didn't override chart's protocol setting.

**Attempt 2 - Set protocol to http:**
```yaml
protocol: http  # Added this
esConfig:
  elasticsearch.yml: |
    xpack.security.enabled: false
    xpack.security.http.ssl.enabled: false
    xpack.security.transport.ssl.enabled: false
```
**Result:** Worked, but user asked "why not use HTTPS?"

**Discussion - HTTP vs HTTPS:**
- Initially chose HTTP because:
  - Services only accessible within cluster (ClusterIP)
  - No external exposure
  - Development environment
- User pointed out: Still within cluster, so HTTPS doesn't add overhead concerns
- Decision: Use HTTPS for encryption, disable authentication

**Final Solution - HTTPS with no authentication:**
```yaml
elasticsearch:
  protocol: https  # Use HTTPS with self-signed certs
  esConfig:
    elasticsearch.yml: |
      xpack.security.enabled: false  # Disable auth, keep TLS
```

**Updated Verification Script:**
```makefile
verify:
	@kubectl exec elasticsearch-master-0 -n $(NAMESPACE) -- \
	  curl -k -s https://localhost:9200/_cluster/health | grep -q "status"
	#    ^^^ -k flag = insecure, accepts self-signed certs
```

**Configuration Trade-offs:**

| Configuration | Encryption | Authentication | Use Case |
|---------------|-----------|----------------|----------|
| `protocol: http`<br/>`xpack.security.enabled: false` | ❌ None | ❌ None | Local dev only |
| `protocol: https`<br/>`xpack.security.enabled: false` | ✅ TLS | ❌ None | Internal cluster (current) |
| `protocol: https`<br/>`xpack.security.enabled: true` | ✅ TLS | ✅ Basic/API Key | Production |

---

### 3. NGINX Gateway DNS Resolution Failures

**Error:**
```
2026/01/28 09:30:42 [emerg] 1#1: host not found in upstream
"data-flywheel-api.hacohen-flywheel.svc.cluster.local" in /etc/nginx/nginx.conf:45
nginx: [emerg] host not found in upstream "data-flywheel-api.hacohen-flywheel.svc.cluster.local"
nginx: configuration file /etc/nginx/nginx.conf test failed
```

**Context:**
- NGINX pod: `nemo-gateway-*`
- Issue: data-flywheel-api service doesn't exist yet (deployed separately)
- NGINX behavior: Resolves all upstreams at startup/reload
- Result: Pod crashes if any upstream missing

**Why This Happened:**
Gateway chart deployed before Data Flywheel application (intentional architecture):
```
Deployment Order:
1. NeMo Microservices (already exists)
2. Flywheel Prerequisites (this chart) ← includes gateway
3. Data Flywheel Application (deployed later)
```

**Failed Configuration:**
```nginx
# Static upstream - fails if service doesn't exist
upstream data_flywheel {
    server data-flywheel-api.hacohen-flywheel.svc.cluster.local:8000;
}

location / {
    proxy_pass http://data_flywheel;
}
```

**Working Solution - Runtime DNS Resolution:**
```nginx
http {
    # OpenShift DNS service
    resolver 172.30.0.10 valid=30s;

    server {
        listen 8080;

        # Health check (no upstream needed)
        location /healthz {
            return 200 "OK\n";
            add_header Content-Type text/plain;
        }

        # Data Flywheel API (may not exist yet)
        location / {
            # Variable forces runtime DNS resolution
            set $upstream_flywheel {{ .Values.dataFlywheel.name }}.{{ .Values.namespace.name }}.svc.cluster.local:8000;
            proxy_pass http://$upstream_flywheel;

            # If service doesn't exist: returns 502 Bad Gateway
            # Gateway pod stays running (no crash)
        }

        # NeMo services (should exist)
        location /v1/datasets {
            set $upstream_datastore {{ .Values.datastore.name }}.{{ .Values.namespace.name }}.svc.cluster.local:8000;
            proxy_pass http://$upstream_datastore;
        }

        # ... more routes
    }
}
```

**Key Pattern:**
```nginx
# DON'T: Static resolution (startup time)
proxy_pass http://service.namespace.svc.cluster.local:8000;

# DO: Variable resolution (request time)
set $upstream service.namespace.svc.cluster.local:8000;
proxy_pass http://$upstream;
```

**Benefits:**
1. Gateway starts successfully even if backends missing
2. Returns 502 for missing services (informative error)
3. Automatically works when backend deployed later
4. DNS cache TTL (30s) balances performance and updates

**Finding OpenShift DNS IP:**
```bash
kubectl get svc -n openshift-dns
# Look for dns-default service, typically 172.30.0.10
```

---

### 4. NGINX Image Compatibility (Red Hat S2I)

**Error:**
Pod running but showing S2I builder instructions instead of serving traffic.

**Symptoms:**
```bash
kubectl logs nemo-gateway-xxx
# Output: Source-to-Image (S2I) builder instructions
# Expected: NGINX access logs
```

**Original Configuration:**
```yaml
gateway:
  image:
    repository: registry.redhat.io/rhel8/nginx-120
    tag: latest
```

**Problem:**
- `rhel8/nginx-120` is a Source-to-Image (S2I) builder
- S2I expects source code to be injected at build time
- We're using ConfigMap to mount nginx.conf at runtime
- S2I workflow incompatible with ConfigMap mounting

**Solution:**
```yaml
gateway:
  image:
    repository: nginx
    tag: "1.25-alpine"  # Standard NGINX
```

**Why Alpine:**
- Small image size (~10MB vs ~200MB)
- Standard NGINX with no Red Hat customizations
- Well-tested with ConfigMap mounting
- Official Docker Hub image

**ConfigMap Mounting:**
```yaml
volumeMounts:
  - name: nginx-config
    mountPath: /etc/nginx/nginx.conf
    subPath: nginx.conf
volumes:
  - name: nginx-config
    configMap:
      name: nemo-gateway-config
```

---

### 5. Helm Chart Version Mismatches

**Error:**
```
Error: can't get a valid version for 1 subchart(s):
"elasticsearch" (repository "https://charts.bitnami.com/bitnami", version "21.10.x")
Error: failed to download "elasticsearch"
```

**Initial Chart.yaml:**
```yaml
dependencies:
  - name: elasticsearch
    version: 21.10.x
    repository: https://charts.bitnami.com/bitnami
  - name: redis
    version: 20.8.x
    repository: https://charts.bitnami.com/bitnami
  - name: mongodb
    version: 16.4.x
    repository: https://charts.bitnami.com/bitnami
```

**Problem:**
- Specified versions didn't exist in Bitnami repository
- Chart versions change over time
- Bitnami deprecated older versions

**Investigation:**
```bash
helm search repo bitnami/elasticsearch --versions | head
helm search repo bitnami/redis --versions | head
helm search repo bitnami/mongodb --versions | head
```

**Decision - Switch to Official Elastic Chart:**

Reasons:
1. Bitnami Elasticsearch had SCC compatibility issues
2. Official chart better maintained by Elastic
3. More control over protocol and security settings
4. Matches Data Flywheel documentation (Elasticsearch 8.12.2)

**Final Chart.yaml:**
```yaml
dependencies:
  - name: elasticsearch
    version: 8.5.1  # Official Elastic chart
    repository: https://helm.elastic.co
    condition: elasticsearch.enabled
  - name: redis
    version: 24.x.x  # Latest Bitnami 24.x
    repository: https://charts.bitnami.com/bitnami
    condition: redis.enabled
  - name: mongodb
    version: 18.x.x  # Latest Bitnami 18.x
    repository: https://charts.bitnami.com/bitnami
    condition: mongodb.enabled
```

**Version Strategy:**
- **Elasticsearch:** Pin to 8.5.1 (close to required 8.12.2, tested)
- **Redis/MongoDB:** Use `x.x.x` for latest patch versions
- **Flexibility:** Patch updates automatic, major/minor pinned

---

### 6. Namespace Hardcoding Issues

**Problem:**
Multiple files hardcoded `hacohen-flywheel` namespace:
- values.yaml: `namespace.name: hacohen-flywheel`
- README.md: All examples used `hacohen-flywheel`
- Manual find-replace required for different namespaces

**User Requirement:**
"remove hacohen-flywheel and use namespace in readme as well"

**Solution - .env File Integration:**

**1. Create .env file structure:**
```bash
# .env
NAMESPACE="hacohen-flywheel"
NVIDIA_API_KEY="nvapi-..."
NGC_API_KEY="..."
HF_TOKEN="hf_..."
```

**2. Load .env in Makefile:**
```makefile
# Load environment variables from .env file
ifneq (,$(wildcard ../.env))
    include ../.env
    export
endif

# Configuration with fallback
NAMESPACE ?= hacohen-flywheel
RELEASE_NAME ?= flywheel-infra
```

**3. Pass to Helm:**
```makefile
install-prereqs: update-prereqs
	helm install $(RELEASE_NAME) $(CHART_DIR) \
		--namespace $(NAMESPACE) \
		--set namespace.name=$(NAMESPACE) \
		--create-namespace
```

**4. Update README:**
```bash
# Find and replace all instances
hacohen-flywheel → $NAMESPACE
```

**Benefits:**
- Single source of truth (`.env` file)
- No hardcoded values in documentation
- Consistent with NeMo installation pattern
- Easy multi-namespace deployments

**Typo Fix:**
Original `.env` had: `NAMESAPCE="hacohen-flywheel"`
Fixed to: `NAMESPACE="hacohen-flywheel"`

---

### 7. Bitnami Image Tag Issues

**Error:**
```
ImagePullBackOff
Failed to pull image "bitnami/mongodb:7.0.4-debian-12-r0":
manifest unknown: manifest unknown
```

**Problem:**
Initial values.yaml specified exact image tags that became unavailable:
```yaml
redis:
  image:
    registry: docker.io
    repository: bitnami/redis
    tag: "7.2.4-debian-12-r0"  # Specific tag may not exist
```

**Solution - Use Chart Defaults:**
```yaml
redis:
  enabled: true
  architecture: standalone
  auth:
    enabled: false
  # No image section - rely on chart's default
```

**Why This Works:**
- Bitnami charts have well-tested default images
- Charts updated regularly with working image tags
- Reduces maintenance burden
- Automatic compatibility with chart version

**Chart Version Strategy:**
```yaml
dependencies:
  - name: redis
    version: 24.x.x  # Gets latest 24.x.y
  - name: mongodb
    version: 18.x.x  # Gets latest 18.x.y
```

---

## Design Decisions

### Architecture: Infrastructure vs Application

**Separation of Concerns:**

```
┌─────────────────────────────────────────────┐
│     Infrastructure (this chart)              │
│  - Elasticsearch (logs storage)              │
│  - Redis (task queue)                        │
│  - MongoDB (metadata)                        │
│  - Gateway (routing)                         │
└─────────────────────────────────────────────┘
               ▲
               │ Service endpoints
               │
┌─────────────────────────────────────────────┐
│     Application (separate deployment)        │
│  - FastAPI server                            │
│  - Celery workers                            │
│  - Data Flywheel logic                       │
└─────────────────────────────────────────────┘
```

**Rationale:**
1. **Stability:** Infrastructure changes less frequently than application
2. **Reusability:** Infrastructure can support multiple applications
3. **Operations:** Different upgrade/rollback strategies
4. **Separation:** Database failures don't require app redeployment

**Deployment Order:**
1. NeMo Microservices (prerequisite)
2. Flywheel Prerequisites (this chart)
3. Data Flywheel Application

### Gateway Routing Strategy

**Unified Gateway Approach:**

Single NGINX gateway routes to both:
- NeMo Microservices (`/v1/*` paths)
- Data Flywheel API (`/` catch-all)

**Alternative Approaches Considered:**

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Separate gateways | Isolation, independent scaling | Multiple routes, complexity | ❌ Rejected |
| Istio/Service Mesh | Advanced features, observability | Heavy, overkill for use case | ❌ Rejected |
| **Unified NGINX** | Simple, single route, low overhead | Single point of failure | ✅ **Chosen** |

**Route Priority (Order Matters):**
```nginx
# Order: Specific → General

location /healthz { }              # 1. Health check
location /v1/datasets { }          # 2. NeMo specific paths
location /v1/customization { }     # 3. NeMo specific paths
# ... more specific NeMo paths
location / { }                     # Last. Catch-all for Data Flywheel
```

### Security Configuration

**Development vs Production:**

**Current (Development):**
```yaml
elasticsearch:
  protocol: https              # ✅ Encrypted
  esConfig:
    elasticsearch.yml: |
      xpack.security.enabled: false  # ❌ No auth

redis:
  auth:
    enabled: false  # ❌ No password

mongodb:
  auth:
    enabled: false  # ❌ No password
```

**Recommended (Production):**
```yaml
elasticsearch:
  protocol: https
  esConfig:
    elasticsearch.yml: |
      xpack.security.enabled: true          # ✅ Auth required
      xpack.security.authc.api_key.enabled: true

redis:
  auth:
    enabled: true
    password: "{{ .Values.redis.password }}"  # From secret

mongodb:
  auth:
    enabled: true
    rootPassword: "{{ .Values.mongodb.password }}"  # From secret
```

**Rationale for Development Mode:**
- Faster development iteration
- No password management during testing
- Cluster network isolation sufficient
- HTTPS still encrypts data in transit

---

## Resource Sizing

### Current Allocations

| Service | CPU Request | CPU Limit | Memory Request | Memory Limit | Storage |
|---------|-------------|-----------|----------------|--------------|---------|
| Elasticsearch | 500m | 1000m | 1Gi | 2Gi | 30Gi |
| Redis | 250m | 500m | 256Mi | 512Mi | 8Gi |
| MongoDB | 500m | 1000m | 512Mi | 1Gi | 20Gi |
| Gateway | 100m | 200m | 128Mi | 256Mi | - |
| **Total** | **1.35 cores** | **2.7 cores** | **~2Gi** | **~4Gi** | **58Gi** |

### Sizing Rationale

**Elasticsearch (Largest):**
- Stores all prompt/completion logs
- Full-text search requires memory
- JVM heap typically 50% of memory (1Gi → 512Mi heap)
- Storage: Depends on log retention policy

**Redis (Smallest):**
- In-memory data structure
- Used only for task queue (transient data)
- Very efficient, rarely needs more resources

**MongoDB (Medium):**
- Stores API metadata (not full logs)
- WiredTiger cache uses ~50% memory
- Storage: Moderate (metadata, configurations)

**Gateway (Minimal):**
- Stateless proxy
- Low resource usage
- Horizontal scaling possible if needed

### Tuning Recommendations

**Monitor with:**
```bash
# CPU/Memory usage
kubectl top pods -n $NAMESPACE

# Storage usage
kubectl exec elasticsearch-master-0 -n $NAMESPACE -- df -h /usr/share/elasticsearch/data
kubectl exec flywheel-infra-mongodb-xxx -n $NAMESPACE -- df -h /bitnami/mongodb
kubectl exec flywheel-infra-redis-master-0 -n $NAMESPACE -- df -h /data
```

**When to Scale Up:**
- **Elasticsearch:** OOMKilled, slow queries, high GC
- **Redis:** Memory evictions, slow operations
- **MongoDB:** High CPU, slow queries
- **Gateway:** High latency, CPU throttling

---

## Makefile Automation

### Command Structure

```makefile
.PHONY: target-name

target-name: prerequisites
	@echo "User-friendly description"
	command-that-might-fail || true
	command-that-must-succeed
	@$(MAKE) next-target  # Chain to next step
```

### Error Handling Patterns

**Pattern 1 - Allow Failure:**
```makefile
oc adm policy add-scc-to-user anyuid -z elasticsearch-master -n $(NAMESPACE) || true
#                                                                              ^^^^^^
# Reason: SCC might already be granted, don't fail entire install
```

**Pattern 2 - User Feedback:**
```makefile
verify:
	@echo "1. Checking Elasticsearch..."
	@command && echo "✓ Success" || echo "✗ Failed"
#   ^                ^                    ^
#   Suppress command output  |            Show result only
```

**Pattern 3 - Sequential Dependencies:**
```makefile
install-prereqs: update-prereqs
#                ^^^^^^^^^^^^^^
# Runs update-prereqs first, then install
```

### Key Targets

**Installation Flow:**
```
update-prereqs (helm dependency update)
    ↓
install-prereqs (SCC + helm install)
    ↓
status (show deployment)
    ↓
verify (health checks)
```

**Troubleshooting Targets:**
```bash
make logs-elasticsearch     # Stream logs
make port-forward-elasticsearch  # localhost:9200
make clean                  # Remove Helm artifacts
```

---

## Verification and Testing

### Automated Verification (make verify)

**Script Logic:**
```makefile
verify:
	# 1. Find pod by label
	@kubectl get pods -n $(NAMESPACE) -l chart=elasticsearch \
	  -o jsonpath='{.items[0].metadata.name}' | \
	# 2. Execute health check in pod
	  xargs -I {} kubectl exec {} -n $(NAMESPACE) -- \
	    curl -k -s https://localhost:9200/_cluster/health | \
	# 3. Verify response
	  grep -q "status" && echo "✓ Elasticsearch is healthy" || echo "✗ Failed"
```

**Why This Pattern:**
- Uses labels (resilient to pod name changes)
- Executes from inside pod (no network policy issues)
- Silent curl output (`-s`)
- Insecure SSL (`-k`) for self-signed certs
- Grep for expected content
- User-friendly output

### Manual Verification

**1. Helm Release:**
```bash
helm list -n $NAMESPACE | grep flywheel-infra
# Should show: STATUS: deployed
```

**2. Pods Running:**
```bash
kubectl get pods -n $NAMESPACE | grep -E "(elasticsearch|redis|mongodb|gateway)"
# All should show: 1/1 Running
```

**3. Services Created:**
```bash
kubectl get svc -n $NAMESPACE | grep -E "(elasticsearch|redis|mongodb|gateway)"
# All ClusterIP services should exist
```

**4. Route Accessible:**
```bash
oc get route nemo-gateway -n $NAMESPACE -o jsonpath='{.spec.host}'
curl https://$(oc get route nemo-gateway -n $NAMESPACE -o jsonpath='{.spec.host}')/healthz
# Should return: OK
```

**5. Elasticsearch Queries:**
```bash
# Cluster health
kubectl exec elasticsearch-master-0 -n $NAMESPACE -- \
  curl -k -s https://localhost:9200/_cluster/health | jq

# List indices
kubectl exec elasticsearch-master-0 -n $NAMESPACE -- \
  curl -k -s https://localhost:9200/_cat/indices?v
```

**6. Redis Connectivity:**
```bash
kubectl exec -it flywheel-infra-redis-master-0 -n $NAMESPACE -- redis-cli ping
# Should return: PONG

kubectl exec -it flywheel-infra-redis-master-0 -n $NAMESPACE -- redis-cli info
# Should show Redis stats
```

**7. MongoDB Connectivity:**
```bash
kubectl exec -it flywheel-infra-mongodb-xxx -n $NAMESPACE -- \
  mongosh --eval "db.adminCommand('ping')"
# Should return: { ok: 1 }
```

---

## Integration Points

### Data Flywheel Application Configuration

**Environment Variables:**
```yaml
env:
  - name: ELASTICSEARCH_URL
    value: "https://elasticsearch-master:9200"
  - name: MONGODB_URL
    value: "mongodb://flywheel-infra-mongodb:27017"
  - name: MONGODB_DB
    value: "flywheel"
  - name: REDIS_URL
    value: "redis://flywheel-infra-redis-master:6379/0"
  - name: ES_COLLECTION_NAME
    value: "flywheel"
```

### SSL Certificate Handling in Applications

**Python (requests):**
```python
import requests
requests.get(
    'https://elasticsearch-master:9200/_cluster/health',
    verify=False  # Disable cert verification
)
```

**Python (elasticsearch library):**
```python
from elasticsearch import Elasticsearch
es = Elasticsearch(
    ['https://elasticsearch-master:9200'],
    verify_certs=False,
    ssl_show_warn=False
)
```

**Python (urllib3 warnings):**
```python
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
```

### Gateway Access Patterns

**From within cluster:**
```
http://nemo-gateway.$NAMESPACE.svc.cluster.local/v1/datasets
```

**From outside cluster (via Route):**
```
https://nemo-gateway-$NAMESPACE.apps.cluster.com/v1/datasets
```

**Health check:**
```bash
curl http://nemo-gateway:80/healthz
# Returns: OK
```

---

## Common Troubleshooting Patterns

### Pattern: Pod CrashLoopBackOff

**Diagnosis:**
```bash
# Check pod status
kubectl get pod <pod-name> -n $NAMESPACE

# Check recent events
kubectl describe pod <pod-name> -n $NAMESPACE | tail -50

# Check logs
kubectl logs <pod-name> -n $NAMESPACE --previous
```

**Common Causes:**
- Permission denied: Check SCC
- Config error: Check ConfigMap
- Missing dependencies: Check services exist
- Resource limits: Check OOMKilled

### Pattern: Service Connection Refused

**Diagnosis:**
```bash
# Verify service exists
kubectl get svc <service-name> -n $NAMESPACE

# Check endpoints
kubectl get endpoints <service-name> -n $NAMESPACE

# Test DNS
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup <service-name>.$NAMESPACE.svc.cluster.local

# Test connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl <service-name>:port
```

**Common Causes:**
- Service selector mismatch
- Pod not ready
- Network policy blocking
- Wrong port number

### Pattern: PVC Stuck in Pending

**Diagnosis:**
```bash
# Check PVC status
kubectl get pvc -n $NAMESPACE

# Describe PVC
kubectl describe pvc <pvc-name> -n $NAMESPACE

# Check storage classes
kubectl get storageclass

# Check events
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'
```

**Common Causes:**
- No storage class available
- Quota exceeded
- Access mode not supported
- Volume size too large

---

## References

### Files in This Repository
- [deploy/flywheel-prerequisites/Chart.yaml](../deploy/flywheel-prerequisites/Chart.yaml) - Helm chart definition
- [deploy/flywheel-prerequisites/values.yaml](../deploy/flywheel-prerequisites/values.yaml) - Configuration
- [deploy/flywheel-prerequisites/templates/nemo-gateway-configmap.yaml](../deploy/flywheel-prerequisites/templates/nemo-gateway-configmap.yaml) - NGINX config
- [deploy/flywheel-prerequisites/README.md](../deploy/flywheel-prerequisites/README.md) - User documentation
- [deploy/Makefile](../deploy/Makefile) - Automation
- [.env](../.env) - Environment configuration

### External Documentation
- [Official Elastic Helm Charts](https://github.com/elastic/helm-charts/tree/main/elasticsearch)
- [Bitnami Redis Chart](https://github.com/bitnami/charts/tree/main/bitnami/redis)
- [Bitnami MongoDB Chart](https://github.com/bitnami/charts/tree/main/bitnami/mongodb)
- [NGINX Runtime DNS Resolution](https://www.nginx.com/blog/dns-service-discovery-nginx-plus/)
- [OpenShift Security Context Constraints](https://docs.openshift.com/container-platform/latest/authentication/managing-security-context-constraints.html)
- [Data Flywheel Configuration](https://github.com/NVIDIA-AI-Blueprints/data-flywheel/blob/main/docs/03-configuration.md)
