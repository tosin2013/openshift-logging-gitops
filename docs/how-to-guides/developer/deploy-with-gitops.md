# How to Deploy OpenShift Logging Components via GitOps

This guide walks developers through deploying and managing OpenShift logging infrastructure using ArgoCD and GitOps principles.

## When to Use This Guide

Use this guide when you need to:
- Deploy new logging operators to an OpenShift cluster
- Update existing logging configurations
- Manage multi-environment logging deployments
- Troubleshoot GitOps synchronization issues
- Implement infrastructure as code practices

## Prerequisites

- OpenShift cluster with ArgoCD/OpenShift GitOps installed
- Git repository access (this repository)
- OpenShift CLI (`oc`) configured and authenticated
- Understanding of Kustomize and GitOps concepts

## Understanding the Repository Structure

This repository follows GitOps best practices as defined in ADR-0002:

```
openshift-logging-gitops/
├── apps/
│   └── applications/          # ArgoCD Application definitions
├── base/                     # Base Kustomize configurations
│   ├── external-secrets-operator/
│   ├── loki-operator/
│   ├── logging-operator/
│   └── observability-operator/
├── overlays/                 # Environment-specific overlays
└── docs/adrs/               # Architectural Decision Records
```

## Step 1: Prepare Your Environment

1. **Clone the repository:**
   ```bash
   git clone https://github.com/tosin2013/openshift-logging-gitops.git
   cd openshift-logging-gitops
   ```

2. **Verify cluster connectivity:**
   ```bash
   oc whoami
   oc cluster-info
   ```

3. **Check ArgoCD installation:**
   ```bash
   oc get pods -n openshift-gitops
   oc get route openshift-gitops-server -n openshift-gitops
   ```

## Step 2: Deploy Foundation Components

Deploy components in the correct order based on dependencies defined in ADR-0002.

### Deploy External Secrets Operator

This provides secure credential management for S3 storage (ADR-0004).

```bash
# Deploy the ArgoCD application
oc apply -f apps/applications/argocd-external-secrets-operator.yaml

# Monitor deployment status
oc get application argocd-external-secrets-operator -n openshift-gitops -w

# Verify operator installation
oc get csv -n openshift-operators | grep external-secrets
oc get pods -n external-secrets-system
```

### Configure AWS Secret Management

Set up the External Secrets integration:

```bash
# Create AWS credentials secret
oc create secret generic aws-credentials \
  --from-literal=access-key-id=$AWS_ACCESS_KEY_ID \
  --from-literal=secret-access-key=$AWS_SECRET_ACCESS_KEY \
  -n external-secrets-system

# Deploy ClusterSecretStore
cat <<EOF | oc apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        secretRef:
          accessKeyIDSecretRef:
            name: aws-credentials
            key: access-key-id
            namespace: external-secrets-system
          secretAccessKeySecretRef:
            name: aws-credentials
            key: secret-access-key
            namespace: external-secrets-system
EOF
```

### Deploy External Secrets Instance

```bash
oc apply -f apps/applications/argocd-external-secrets-instance.yaml
```

## Step 3: Deploy Logging Operators

Deploy the core logging operators following ADR-0001 (Loki-centric architecture).

### Deploy Loki Operator

```bash
# Deploy via ArgoCD
oc apply -f apps/applications/argocd-loki-operator.yaml

# Monitor installation
oc get application argocd-loki-operator -n openshift-gitops -w

# Verify operator readiness
oc get csv -n openshift-operators | grep loki-operator
oc get pods -n openshift-operators | grep loki
```

### Deploy OpenShift Logging Operator

```bash
# Deploy cluster logging operator
oc apply -f apps/applications/argocd-logging-operator.yaml

# Monitor deployment
oc get application argocd-logging-operator -n openshift-gitops -w

# Verify installation
oc get csv -n openshift-operators | grep cluster-logging
```

### Deploy Observability Operator

```bash
# Deploy observability stack
oc apply -f apps/applications/argocd-observability-operator.yaml

# Monitor deployment
oc get application argocd-observability-operator -n openshift-gitops -w
```

## Step 4: Configure Loki Storage

Set up S3-backed storage as defined in ADR-0003.

### Create External Secret for S3 Credentials

```bash
cat <<EOF | oc apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: logging-loki-s3
  namespace: openshift-logging
spec:
  refreshInterval: 15s
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: logging-loki-s3
    creationPolicy: Owner
  data:
  - secretKey: access_key_id
    remoteRef:
      key: openshift-logging-s3-credentials
      property: access_key_id
  - secretKey: access_key_secret
    remoteRef:
      key: openshift-logging-s3-credentials
      property: access_key_secret
  - secretKey: bucketnames
    remoteRef:
      key: openshift-logging-s3-credentials
      property: bucketnames
  - secretKey: endpoint
    remoteRef:
      key: openshift-logging-s3-credentials
      property: endpoint
  - secretKey: region
    remoteRef:
      key: openshift-logging-s3-credentials
      property: region
EOF
```

## Step 5: Deploy LokiStack Instance

Create the Loki storage backend:

```bash
cat <<EOF | oc apply -f -
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: logging-loki
  namespace: openshift-logging
spec:
  size: 1x.small  # See ADR-0006 for sizing guidance
  storage:
    secret:
      name: logging-loki-s3
      type: s3
    storageClassName: gp3-csi
  tenants:
    mode: application
  template:
    distributor:
      replicas: 1
    ingester:
      replicas: 1
    querier:
      replicas: 1
    queryFrontend:
      replicas: 1
    gateway:
      replicas: 1
    indexGateway:
      replicas: 1
    ruler:
      replicas: 1
EOF
```

## Step 6: Configure Log Collection

Set up Vector-based log collection:

```bash
# Deploy ClusterLogging instance
cat <<EOF | oc apply -f -
apiVersion: logging.coreos.com/v1
kind: ClusterLogging
metadata:
  name: instance
  namespace: openshift-logging
spec:
  collection:
    type: vector
    vector: {}
  managementState: Managed
EOF

# Deploy ClusterLogForwarder
cat <<EOF | oc apply -f -
apiVersion: logging.coreos.com/v1
kind: ClusterLogForwarder
metadata:
  name: instance
  namespace: openshift-logging
spec:
  outputs:
  - name: loki-app
    type: loki
    loki:
      tenantKey: kubernetes.namespace_name
    url: https://logging-loki-gateway-http.openshift-logging.svc:8080/api/logs/v1/application
  - name: loki-infra
    type: loki
    loki:
      tenantKey: log_type
    url: https://logging-loki-gateway-http.openshift-logging.svc:8080/api/logs/v1/infrastructure
  pipelines:
  - name: application-logs
    inputRefs:
    - application
    outputRefs:
    - loki-app
  - name: infrastructure-logs
    inputRefs:
    - infrastructure
    outputRefs:
    - loki-infra
EOF
```

## Step 7: Verify Deployment

Validate the complete logging stack:

```bash
# Check all ArgoCD applications
oc get applications -n openshift-gitops

# Verify all pods are running
oc get pods -n openshift-logging
oc get pods -n external-secrets-system

# Check LokiStack status
oc get lokistack -n openshift-logging
oc describe lokistack logging-loki -n openshift-logging

# Test log ingestion
oc run test-logger --image=busybox --restart=Never -- \
  sh -c 'for i in $(seq 1 10); do echo "GitOps test log $i"; sleep 1; done'
```

## Step 8: Monitor and Validate

Ensure the deployment is working correctly:

```bash
# Check ArgoCD sync status
oc get applications -n openshift-gitops -o wide

# Monitor resource health
oc get events -n openshift-logging --sort-by='.lastTimestamp'

# Verify log flow (wait 2-3 minutes after test-logger)
# Access OpenShift Console → Observe → Logs
# Query: {namespace="default"} |= "GitOps test log"
```

## Working with Multiple Environments

### Environment Overlays

Create environment-specific configurations using Kustomize overlays:

```bash
# Create development overlay
mkdir -p overlays/dev

cat <<EOF > overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- ../../base/loki-operator

patchesStrategicMerge:
- lokistack-dev.yaml
EOF

cat <<EOF > overlays/dev/lokistack-dev.yaml
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: logging-loki
  namespace: openshift-logging
spec:
  size: 1x.demo  # Smaller size for dev
  storage:
    storageClassName: gp2  # Different storage class
EOF
```

### ArgoCD Application for Environment

```bash
cat <<EOF | oc apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: loki-dev
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/tosin2013/openshift-logging-gitops.git
    targetRevision: HEAD
    path: overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-logging
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

## Troubleshooting GitOps Deployments

### Application Not Syncing

```bash
# Check application status
oc describe application argocd-loki-operator -n openshift-gitops

# Check sync operation
oc get application argocd-loki-operator -n openshift-gitops -o yaml | yq '.status.operationState'

# Force sync if needed
oc patch application argocd-loki-operator -n openshift-gitops --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

### Resource Conflicts

```bash
# Check for existing resources
oc get crd | grep loki
oc get operatorgroups -A

# Delete conflicting resources if safe
oc delete csv old-loki-operator -n openshift-operators
```

### Operator Installation Issues

```bash
# Check CSV status
oc get csv -A | grep -E "(external-secrets|loki|logging)"

# Check operator logs
oc logs deployment/external-secrets -n external-secrets-system
oc logs deployment/loki-operator-controller-manager -n openshift-operators
```

## Best Practices for GitOps

1. **Use Sync Waves**: Order deployments with `argocd.argoproj.io/sync-wave` annotations
2. **Health Checks**: Implement proper health checks for custom resources
3. **Prune Policy**: Enable automated pruning for removed resources
4. **Self-Heal**: Enable self-healing for configuration drift
5. **Branch Strategy**: Use separate branches for different environments
6. **Secret Management**: Never commit secrets; use External Secrets Operator

## Making Changes

### Updating Configurations

1. **Make changes in Git:**
   ```bash
   git checkout -b update-loki-config
   # Edit configurations
   git add .
   git commit -m "Update Loki resource limits"
   git push origin update-loki-config
   ```

2. **Create pull request and merge**

3. **ArgoCD will automatically sync changes**

### Rolling Back

```bash
# Via ArgoCD
oc patch application argocd-loki-operator -n openshift-gitops --type merge \
  -p '{"operation":{"sync":{"revision":"previous-commit-hash"}}}'

# Or via Git revert
git revert <commit-hash>
git push origin main
```

This guide follows the GitOps principles and architectural decisions documented in our ADRs, ensuring consistent and maintainable deployments of the OpenShift logging infrastructure.
