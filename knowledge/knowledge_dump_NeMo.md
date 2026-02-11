# NeMo Microservices Installation - Troubleshooting Guide

This document provides troubleshooting guidance for NeMo Microservices installation on OpenShift. These issues were encountered during real-world deployments and the solutions have been integrated into the automated installation script ([scripts/install-nemo.sh](../scripts/install-nemo.sh)).

## When to Use This Guide

**Important**: Most issues described here are **automatically handled** by the installation script. Use this guide when:

1. **Script Fails**: The automated installation script encounters errors despite its built-in adoption logic
2. **Understanding Script Behavior**: You want to understand what the script is doing behind the scenes
3. **Manual Installation**: You're performing manual installation without using the automation
4. **Troubleshooting Clusters with Existing Resources**: You're installing in an environment with:
   - Previous NeMo Microservices installations in other namespaces
   - OpenDataHub, Kubeflow, or other platforms that installed Argo Workflows or Volcano
   - Existing CRDs, ClusterRoles, or Webhooks from other tools

## Common Scenario

Installing NeMo Microservices in a new namespace when cluster-wide resources (CRDs, ClusterRoles, Webhooks, SecurityContextConstraints) already exist from previous installations.

**Example Environment:**
- **Current Namespace**: `my-data-flywheel` (replace with your namespace)
- **Previous Installation**: Resources from old namespace (`previous-namespace`) or different platform (OpenDataHub, Kubeflow, etc.)
- **Cluster Type**: OpenShift with GPU nodes
- **GPU Node Taints**: Custom taints like `g6e-gpu=true:NoSchedule` or `nvidia.com/gpu:NoSchedule`

**What the Installation Script Does:**
The [scripts/install-nemo.sh](../scripts/install-nemo.sh) automatically:
- Adopts existing CRDs (Argo Workflows, Volcano) by updating ownership annotations
- Clears field manager conflicts (`managedFields`) to resolve server-side apply issues
- Updates ClusterRoles, ClusterRoleBindings, and Webhooks ownership
- Handles SecurityContextConstraints (OpenShift-specific) adoption
- Scales down unused GPU workloads to conserve resources

---

## Error Categories and Fixes

### 1. Volcano CRD Ownership Conflicts

**Error:**
```
Error: INSTALLATION FAILED: unable to continue with install: CustomResourceDefinition "jobtemplates.flow.volcano.sh"
in namespace "" exists and cannot be imported into the current release: invalid ownership metadata;
annotation validation error: key "meta.helm.sh/release-namespace" must equal "hacohen-flywheel":
current value is "anemo-rhoai"
```

**Root Cause:**
- Volcano CRDs were previously installed by Helm in the `anemo-rhoai` namespace
- CRDs are cluster-scoped but had Helm ownership annotations from the previous namespace
- Helm refused to import them into the new release

**Fix Applied:**
Created `adopt_volcano_crds()` function in [install-nemo.sh](install-nemo.sh#L174-L207) to:
1. Find all CRDs with `volcano.sh` in their group name
2. Update Helm ownership annotations to point to new namespace
3. Add `app.kubernetes.io/managed-by=Helm` label

```bash
adopt_volcano_crds() {
    volcano_crds=$(oc get crds -o json | \
        jq -r '.items[] | select(.spec.group | contains("volcano.sh")) | .metadata.name')

    for crd in $volcano_crds; do
        oc annotate crd "$crd" \
            meta.helm.sh/release-name=nemo-infra \
            meta.helm.sh/release-namespace="$NAMESPACE" \
            --overwrite
        oc label crd "$crd" \
            app.kubernetes.io/managed-by=Helm \
            --overwrite
    done
}
```

---

### 2. MinIO Duplicate Environment Variables

**Error:**
```
Error: INSTALLATION FAILED: failed to create resource: failed to create typed patch object
(hacohen-flywheel/nemo-infra-minio; apps/v1, Kind=Deployment): errors:
  .spec.template.spec.containers[name="minio"].env: duplicate entries for key [name="MINIO_ROOT_USER"]
  .spec.template.spec.containers[name="minio"].env: duplicate entries for key [name="MINIO_ROOT_PASSWORD"]
  .spec.template.spec.containers[name="minio"].env: duplicate entries for key [name="MINIO_DEFAULT_BUCKETS"]
```

**Root Cause:**
- MinIO configuration had both `auth` section and `extraEnvVars` section
- Bitnami MinIO chart automatically converts `auth.rootUser` and `auth.rootPassword` to environment variables
- Explicit `extraEnvVars` were duplicating these

**Fix Applied:**
Removed `extraEnvVars` section from [deploy/nemo-infra/values.yaml](deploy/nemo-infra/values.yaml#L140-L176):

```yaml
minio:
  enabled: true
  auth:
    rootUser: "minioadmin"
    rootPassword: "minioadmin"
  defaultBuckets: "mlflow"
  # Removed extraEnvVars section - auth handles these automatically
```

---

### 3. Argo Workflows CRD Field Manager Conflicts

**Error:**
```
Error: INSTALLATION FAILED: conflict occurred while applying object /workflowartifactgctasks.argoproj.io
apiextensions.k8s.io/v1, Kind=CustomResourceDefinition: Apply failed with 1 conflict:
conflict with "platform.opendatahub.io": .spec.versions
```

**Root Cause:**
- Argo Workflows CRDs were previously managed by OpenDataHub platform
- Server-Side Apply (SSA) field manager conflict - "platform.opendatahub.io" owned `.spec.versions` field
- Helm couldn't take ownership due to field-level tracking

**Fix Applied:**
Updated `adopt_argo_crds()` function in [install-nemo.sh](install-nemo.sh#L129-L172) to:
1. Remove `kubectl.kubernetes.io/last-applied-configuration` annotation
2. Clear `managedFields` to remove all field manager tracking
3. Then add Helm ownership annotations

```bash
adopt_argo_crds() {
    for crd in $argo_crds; do
        # Clear last-applied-configuration
        oc annotate crd "$crd" \
            kubectl.kubernetes.io/last-applied-configuration- \
            2>/dev/null || true

        # Clear managedFields to remove field manager conflicts
        oc patch crd "$crd" --type=json \
            -p='[{"op": "replace", "path": "/metadata/managedFields", "value": []}]'

        # Add Helm ownership
        oc annotate crd "$crd" \
            meta.helm.sh/release-name=nemo-infra \
            meta.helm.sh/release-namespace="$NAMESPACE" --overwrite
    done
}
```

**Alternative Fix:**
Disabled Argo CRD installation in [deploy/nemo-infra/values.yaml](deploy/nemo-infra/values.yaml#L296-L298):
```yaml
crds:
  install: false  # CRDs already exist from OpenDataHub
  keep: true
```

---

### 4. Volcano Webhook Configuration Conflicts

**Error:**
```
Error: INSTALLATION FAILED: conflict occurred while applying object
/volcano-admission-service-jobs-validate admissionregistration.k8s.io/v1, Kind=ValidatingWebhookConfiguration:
Apply failed with 2 conflicts:
conflicts with "kubectl-patch" using admissionregistration.k8s.io/v1:
- .webhooks[name="validatejob.volcano.sh"].failurePolicy
- .webhooks[name="validatejob.volcano.sh"].namespaceSelector
```

**Root Cause:**
- Volcano webhook configurations were previously patched (`kubectl-patch` manager)
- Field-level conflicts on `failurePolicy` and `namespaceSelector`
- Clearing managedFields created new "before-first-apply" manager conflicts

**Fix Applied:**
Two-part solution:

**Option 1 (Manual - Used for initial fix):**
```bash
kubectl delete mutatingwebhookconfiguration \
    volcano-admission-service-queues-mutate \
    volcano-admission-service-jobs-mutate

kubectl delete validatingwebhookconfiguration \
    volcano-admission-service-jobs-validate \
    volcano-admission-service-queues-validate \
    volcano-admission-service-hypernodes-validate
```

**Option 2 (Automated - Final solution):**
Disabled Volcano installation entirely in [deploy/nemo-infra/values.yaml](deploy/nemo-infra/values.yaml#L25):
```yaml
install:
  volcano: false  # Already exists from previous installation
```

**Rationale:** Since Volcano was already installed cluster-wide from the previous deployment, the new installation can simply use the existing Volcano scheduler rather than trying to adopt conflicting resources.

---

### 5. ClusterRole Ownership Conflicts (Multiple)

**Error Pattern:**
```
Error: INSTALLATION FAILED: unable to continue with install: ClusterRole "nemo-infra-admission"
in namespace "" exists and cannot be imported into the current release: invalid ownership metadata;
annotation validation error: key "meta.helm.sh/release-namespace" must equal "hacohen-flywheel":
current value is "anemo-rhoai"
```

**Affected Resources:**
- `nemo-infra-admission`
- `volcano-rbac-setup`
- `volcano-*` (various ClusterRoles)
- `k8s-nim-operator-role`
- `nemo-instances-nemo-operator-manager-role`

**Root Cause:**
- Cluster-scoped resources (ClusterRoles, ClusterRoleBindings) had ownership from previous namespace
- Resources needed for both nemo-infra and nemo-instances installations

**Fix Applied:**
Created `adopt_cluster_resources()` function in [install-nemo.sh](install-nemo.sh#L209-L325) to adopt:
- ClusterRoles (containing "nemo-infra", "volcano", or "nim-operator")
- ClusterRoleBindings
- ValidatingWebhookConfigurations (with managedFields clearing)
- MutatingWebhookConfigurations (with managedFields clearing)
- SecurityContextConstraints (OpenShift-specific)

Also created `adopt_instances_cluster_resources()` for nemo-instances in [install-nemo.sh](install-nemo.sh#L344-L431).

```bash
adopt_cluster_resources() {
    # Adopt ClusterRoles
    cluster_roles=$(oc get clusterroles -o json | \
        jq -r '.items[] | select(.metadata.name | contains("nemo-infra") or contains("volcano") or contains("nim-operator")) | .metadata.name')

    for resource in $cluster_roles; do
        oc annotate clusterrole "$resource" \
            meta.helm.sh/release-name=nemo-infra \
            meta.helm.sh/release-namespace="$NAMESPACE" --overwrite
        oc label clusterrole "$resource" \
            app.kubernetes.io/managed-by=Helm --overwrite
    done

    # Similar logic for ClusterRoleBindings, Webhooks, SCCs...
}
```

---

### 6. SecurityContextConstraints (SCC) Conflicts

**Error:**
```
Error: INSTALLATION FAILED: unable to continue with install:
SecurityContextConstraints "nemo-customizer-scc" in namespace "" exists and cannot be imported into
the current release: invalid ownership metadata; annotation validation error:
key "meta.helm.sh/release-namespace" must equal "hacohen-flywheel": current value is "anemo-rhoai"
```

**Root Cause:**
- OpenShift-specific SecurityContextConstraints from previous installation
- SCCs are cluster-scoped but had namespace-specific ownership metadata

**Fix Applied:**
Extended both `adopt_cluster_resources()` and `adopt_instances_cluster_resources()` to include SCC adoption:

```bash
# Check and adopt SecurityContextConstraints (OpenShift-specific)
sccs=$(oc get scc -o json | \
    jq -r '.items[] | select(.metadata.name | contains("nemo") or contains("nim")) | .metadata.name')

for resource in $sccs; do
    oc annotate scc "$resource" \
        meta.helm.sh/release-name=nemo-infra \
        meta.helm.sh/release-namespace="$NAMESPACE" --overwrite
    oc label scc "$resource" \
        app.kubernetes.io/managed-by=Helm --overwrite
done
```

---

## Installation Script Structure

The final [install-nemo.sh](install-nemo.sh) script includes these adoption functions:

1. **`adopt_argo_crds()`** - Adopts Argo Workflows CRDs with managedFields clearing
2. **`adopt_volcano_crds()`** - Adopts Volcano CRDs
3. **`adopt_cluster_resources()`** - Adopts nemo-infra cluster resources (ClusterRoles, ClusterRoleBindings, Webhooks, SCCs)
4. **`adopt_instances_cluster_resources()`** - Adopts nemo-instances cluster resources
5. **`install_nemo_infra()`** - Installs nemo-infra with all adoptions first
6. **`install_nemo_instances()`** - Installs nemo-instances with all adoptions first
7. **`downscale_unused()`** - Scales down embedding/reranking models to save GPU resources

---

## Key Learnings

### 1. Helm Ownership Metadata
- Helm tracks releases using `meta.helm.sh/release-name` and `meta.helm.sh/release-namespace` annotations
- Cluster-scoped resources (CRDs, ClusterRoles, etc.) can only belong to one Helm release
- Must update ownership annotations when moving resources between namespaces

### 2. Server-Side Apply (SSA) Field Managers
- Kubernetes tracks field ownership at a granular level via `managedFields`
- Multiple managers can conflict on the same fields
- Clearing `managedFields` removes all ownership tracking
- Some conflicts require manual resource deletion and recreation

### 3. Bitnami Chart Conventions
- Bitnami charts automatically convert certain config sections to environment variables
- Check chart documentation before using `extraEnvVars` to avoid duplicates

### 4. OpenShift-Specific Resources
- SecurityContextConstraints (SCCs) are OpenShift-specific cluster resources
- Must be adopted along with standard Kubernetes resources
- SCCs control pod security policies

### 5. Resource Sharing Strategies
When resources exist from previous installations:
- **Option A**: Adopt resources into new release (complex, many conflicts)
- **Option B**: Disable installation and reuse existing resources (simpler, chosen for Volcano)
- **Option C**: Delete and recreate (works but disrupts existing workloads)

### 6. GPU Node Taints
- Cluster has GPU nodes with taint `g6e-gpu=true:NoSchedule`
- Pods requiring GPUs must include matching tolerations
- NeMo instances values.yaml already includes proper GPU tolerations

---

## Configuration Changes

### nemo-infra/values.yaml
- Disabled Volcano installation (`install.volcano: false`)
- Disabled Argo CRD installation (`crds.install: false`)
- Removed duplicate MinIO environment variables
- Increased PostgreSQL storage sizes to 2Gi
- Increased Milvus storage to 100Gi
- Increased MLflow storage to 20Gi
- Added `global.security.allowInsecureImages: true`

### nemo-instances/values.yaml
- Increased customizer modelPVC to 100Gi
- Increased customizer workspacePVC to 50Gi
- Added GPU tolerations for all NIM components
- Upgraded evaluator image to 25.08
- Added master node tolerations

### install-nemo.sh
- Added comprehensive resource adoption functions
- Added `downscale_unused()` function to scale embedding/reranking models to 0
- Integrated adoption into installation workflow

---

## Final Installation Flow

1. **Prerequisites Check** - Verify `oc` and `helm` CLI tools
2. **Load Environment** - Load NGC API key and namespace from `.env`
3. **Create Namespace** - Create or verify target namespace
4. **Create NGC Secrets** - Create image pull and API secrets
5. **Install nemo-infra**:
   - Adopt Argo CRDs (clear managedFields)
   - Adopt Volcano CRDs
   - Adopt cluster resources (ClusterRoles, Webhooks, SCCs)
   - Install Helm chart (with Volcano and Argo CRDs disabled)
6. **Install nemo-instances**:
   - Adopt nemo-instances cluster resources
   - Install Helm chart
7. **Downscale Unused Resources**:
   - Scale `nv-embedqa-1b-v2` deployment to 0 replicas
   - Scale `nv-rerankqa-1b-v2` deployment to 0 replicas
8. **Verify Installation** - Check Helm releases, custom resources, services, pods

---

## Common Patterns for Similar Issues

If you encounter similar ownership/conflict errors in the future:

1. **Identify the resource type and scope**:
   - Cluster-scoped: CRDs, ClusterRoles, ClusterRoleBindings, Webhooks, SCCs
   - Namespace-scoped: Deployments, Services, ConfigMaps, Secrets

2. **Check current ownership**:
   ```bash
   oc get <resource-type> <name> -o jsonpath='{.metadata.annotations}'
   ```

3. **Determine the field manager causing conflicts**:
   ```bash
   oc get <resource-type> <name> -o jsonpath='{.metadata.managedFields}'
   ```

4. **Choose resolution strategy**:
   - **Adopt**: Update annotations and clear managedFields
   - **Disable**: Skip installation, use existing resource
   - **Delete**: Remove and recreate (disruptive)

5. **Implement in installation script**:
   - Create adoption function for the resource type
   - Call before Helm install
   - Handle errors gracefully with warnings

---

## GPU Resource Management

To save GPU resources, embedding and reranking models are scaled to 0 replicas after installation:

```bash
oc scale deployment nv-embedqa-1b-v2 -n hacohen-flywheel --replicas=0
oc scale deployment nv-rerankqa-1b-v2 -n hacohen-flywheel --replicas=0
```

To re-enable when needed:
```bash
oc scale deployment nv-embedqa-1b-v2 -n hacohen-flywheel --replicas=1
oc scale deployment nv-rerankqa-1b-v2 -n hacohen-flywheel --replicas=1
```

---

## References

- [install-nemo.sh](install-nemo.sh) - Main installation script with all adoption logic
- [deploy/nemo-infra/values.yaml](deploy/nemo-infra/values.yaml) - Infrastructure configuration
- [deploy/nemo-instances/values.yaml](deploy/nemo-instances/values.yaml) - Instance configuration
- [.env](.env) - Environment variables (NGC API key, namespace)
