# ADR-0008: Hybrid GitOps Architecture for Bootstrap and Runtime Management

## Status
Proposed

## Context
The current implementation uses a hybrid approach where scripts handle secret bootstrapping and ArgoCD+Kustomize manage operators. While functional, this creates an inconsistent operational model. The community is moving toward more GitOps-native approaches using External Secrets Operator patterns and Kustomize overlays for environment-specific configurations.

Analysis of current approach reveals:
- **Scripts**: Handle AWS resource creation, secret bootstrapping, and instance deployment
- **ArgoCD+Kustomize**: Manage only operator subscriptions and basic RBAC
- **Inconsistency**: Some resources in Git, others imperative

## Decision
Adopt a **Progressive GitOps Architecture** that maximizes declarative management while maintaining practical bootstrapping needs.

### Phase 1: Enhanced Kustomize Structure (Immediate)
Restructure to use proper Kustomize overlays for all environments:

```
base/
├── operators/           # All operator subscriptions
├── external-secrets/    # External Secrets configuration templates  
├── loki-stack/         # LokiStack templates
└── logging/            # ClusterLogging templates

overlays/
├── bootstrap/          # One-time setup resources
├── dev/               # Development environment
├── staging/           # Staging environment  
└── production/        # Production environment
```

### Phase 2: External Secrets Pattern (Near-term)
Move all secret management to GitOps using External Secrets Operator:

```yaml
# In Git (safe) - overlays/production/external-secret-loki.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: loki-s3-credentials
spec:
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: loki-s3-credentials
    creationPolicy: Owner
  data:
  - secretKey: access_key_id
    remoteRef:
      key: prod-loki-s3-credentials
      property: access_key_id
  - secretKey: secret_access_key
    remoteRef:
      key: prod-loki-s3-credentials  
      property: secret_access_key
  - secretKey: bucket_name
    remoteRef:
      key: prod-loki-s3-credentials
      property: bucket_name
```

### Phase 3: ArgoCD Application-of-Applications (Long-term)
Use App-of-Apps pattern for complete lifecycle management:

```yaml
# apps/root-application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: logging-stack
spec:
  source:
    path: apps/application-sets/
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

## Implementation Strategy

### 🚀 **Immediate Actions** (This Sprint)

1. **Restructure Kustomize**:
   ```bash
   # Move current base/* to base/operators/*
   # Create proper overlay structure
   # Update ArgoCD applications to use overlays
   ```

2. **Update Scripts** to be environment-aware:
   ```bash
   ./scripts/deploy-logging-stack.sh --environment production
   # Uses overlays/production/ instead of hardcoded values
   ```

3. **Create Bootstrap Overlay**:
   ```bash
   overlays/bootstrap/
   ├── kustomization.yaml
   ├── aws-secret-store.yaml      # Initial ClusterSecretStore
   └── bootstrap-external-secret.yaml  # Bootstraps other secrets
   ```

### 🎯 **Near-term Improvements** (Next Sprint)

1. **Eliminate Scripts** for instance creation:
   - Move LokiStack, ClusterLogging to overlays/
   - Use ExternalSecret pattern for all credentials
   - Scripts only handle AWS resource creation

2. **Environment Parity**:
   ```bash
   # Same command, different overlay:
   oc apply -k overlays/dev/
   oc apply -k overlays/staging/  
   oc apply -k overlays/production/
   ```

### 🔮 **Long-term Vision** (Future Sprints)

1. **Terraform/Crossplane** for AWS resources
2. **ArgoCD ApplicationSets** for multi-cluster
3. **Complete GitOps** - zero manual intervention

## Benefits

### ✅ **Improved Consistency**
- Single deployment method across environments
- All configurations version-controlled
- Consistent overlay patterns

### ✅ **Better Security**
- External Secrets Operator handles all credentials
- No secrets in Git ever
- Proper RBAC and audit trails

### ✅ **Enhanced Operations**
- Easier environment promotion
- Better diff/rollback capabilities
- Standard Kustomize patterns

### ✅ **Team Productivity**
- Familiar kubectl/kustomize workflows
- Self-service environment deployment
- Reduced script maintenance

## Migration Path

### Week 1: Restructure
```bash
git checkout -b restructure-kustomize
# Move and reorganize base/ structure
# Create initial overlays/
# Update ArgoCD applications
```

### Week 2: Test & Validate
```bash
# Deploy to dev using new overlays
oc apply -k overlays/dev/
# Validate all components work
```

### Week 3: Production Migration
```bash
# Apply to production with zero downtime
oc apply -k overlays/production/
```

## Consequences

### ✅ **Positive**
- More GitOps-native approach
- Better environment management
- Easier team onboarding
- Industry standard patterns

### ⚠️ **Considerations**
- Requires restructuring existing code
- Team needs Kustomize overlay training
- More complex initial setup

### 🔄 **Mitigation**
- Gradual migration approach
- Comprehensive documentation
- Training sessions for team

## Alternatives Considered

1. **Keep Current Approach**: Functional but inconsistent
2. **Pure Scripts**: Fast but not scalable
3. **Helm**: Considered but Kustomize is OpenShift standard

## Decision Criteria

1. **GitOps Alignment**: Maximize declarative management
2. **Team Productivity**: Use familiar OpenShift patterns  
3. **Security**: External Secrets Operator best practices
4. **Maintainability**: Reduce custom script complexity

## Next Steps

1. Create feature branch for restructuring
2. Implement new overlay structure
3. Update documentation and ADRs
4. Test in development environment
5. Plan production migration

---

**Note**: This ADR represents a natural evolution of our GitOps approach based on lessons learned and community best practices. The hybrid approach served well for initial development but can now be improved for production operations.
