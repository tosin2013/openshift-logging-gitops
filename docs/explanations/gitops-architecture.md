# GitOps Architecture: ArgoCD vs Manual Operations

## 🏗️ **GitOps-Managed Resources (ArgoCD + Kustomize)**

These are stored in Git and managed declaratively by ArgoCD:

### ✅ **Operators** (via `apps/applications/*.yaml`)
```bash
# These use Kustomize from base/ directory:
apps/applications/argocd-external-secrets-operator.yaml  → base/external-secrets-operator/
apps/applications/argocd-loki-operator.yaml             → base/loki-operator/
apps/applications/argocd-logging-operator.yaml          → base/logging-operator/
apps/applications/argocd-observability-operator.yaml    → base/observability-operator/
```

### ✅ **Base Kustomize Configurations**
```bash
base/external-secrets-operator/
├── operator/
│   ├── base/kustomization.yaml              # Subscription, OperatorGroup
│   └── overlays/stable/kustomization.yaml   # Channel patches
└── instance/
    ├── base/kustomization.yaml              # OperatorConfig
    └── overlays/default/kustomization.yaml  # Instance configuration
```

### ✅ **What ArgoCD Manages**
- **Operator Subscriptions**: Channel, approval policies
- **OperatorGroups**: Namespace targeting
- **Namespace Definitions**: Core namespaces
- **RBAC**: ClusterRoles, RoleBindings
- **Instance Configurations**: OperatorConfig CRDs

---

## 🔧 **Manual Script Operations (Bootstrap & Secrets)**

These **cannot** be stored in Git for security/bootstrapping reasons:

### 🔐 **AWS Credentials & Secrets**
```bash
# Created by setup-s3-storage.sh:
AWS Access Keys → AWS Secrets Manager
IAM Users & Policies → AWS IAM

# Created by setup-external-secrets.sh:
Secret: aws-credentials (external-secrets)
Secret: loki-s3-credentials (openshift-logging)
```

### 🎯 **Runtime Instance Resources**
```bash
# Created by scripts with environment-specific values:
ClusterSecretStore    # References AWS credentials secret
ExternalSecret        # Links Secrets Manager → K8s secrets
LokiStack            # References generated secret names
ClusterLogging       # Instance configuration
ClusterLogForwarder  # Log routing configuration
```

---

## 🔄 **How They Work Together**

### **Phase 1: ArgoCD Deploys Operators**
```bash
# ArgoCD applies Kustomize from Git:
oc apply -k base/external-secrets-operator/operator/overlays/stable/
oc apply -k base/loki-operator/operator/overlays/stable/
oc apply -k base/logging-operator/operator/overlays/stable/

# Result: Operators installed, waiting for instances
```

### **Phase 2: Scripts Bootstrap Security**
```bash
# Scripts create secrets that can't be in Git:
./setup-s3-storage.sh        # Creates AWS resources
./setup-external-secrets.sh  # Creates secret management
```

### **Phase 3: Scripts Deploy Instances**
```bash
# Scripts create instances using secrets from Phase 2:
./deploy-logging-stack.sh    # Creates LokiStack, ClusterLogging, etc.
```

---

## 📋 **Summary: Who Does What**

| Component | Manager | Storage | Reason |
|-----------|---------|---------|---------|
| **Operators** | ArgoCD + Kustomize | Git (`base/*/`) | Declarative, version-controlled |
| **RBAC & Namespaces** | ArgoCD + Kustomize | Git (`base/*/`) | Standard configurations |
| **AWS Resources** | Scripts | AWS | External to Kubernetes |
| **K8s Secrets** | Scripts | Cluster (from AWS) | Security - no secrets in Git |
| **Instance Resources** | Scripts | Cluster | Reference runtime secrets |

---

## 🎯 **Why This Hybrid Approach?**

### ✅ **ArgoCD/Kustomize Benefits**
- **Declarative**: Infrastructure as Code
- **Version Controlled**: All changes tracked in Git
- **Consistent**: Same config across environments
- **Auditable**: GitOps workflow with PR reviews

### ✅ **Script Benefits**
- **Security**: Secrets never touch Git
- **Bootstrap**: Creates foundation for GitOps
- **Dynamic**: Uses runtime values (bucket names, etc.)
- **External Integration**: Manages AWS resources

---

## 🚀 **Future State: More GitOps**

Eventually, we can move more to GitOps using:

### **Option 1: External Secrets Pattern**
```yaml
# In Git (safe):
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: loki-s3-secret
spec:
  secretStoreRef:
    name: aws-secret-store
    kind: ClusterSecretStore
  target:
    name: loki-s3-credentials
    creationPolicy: Owner
  data:
  - secretKey: bucketName
    remoteRef:
      key: loki-s3-config
      property: bucket_name
```

### **Option 2: Overlays Pattern**
```bash
overlays/
├── dev/
│   ├── kustomization.yaml
│   └── loki-stack-dev.yaml     # Dev-specific config
├── staging/
│   ├── kustomization.yaml  
│   └── loki-stack-staging.yaml # Staging-specific config
└── production/
    ├── kustomization.yaml
    └── loki-stack-prod.yaml    # Prod-specific config
```

This approach gives you the best of both worlds: **secure secrets management** with **GitOps declarative configuration**.
