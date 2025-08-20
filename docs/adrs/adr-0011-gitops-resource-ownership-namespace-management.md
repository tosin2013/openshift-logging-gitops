# ADR-0011: GitOps Resource Ownership and Namespace Management

## Status
Accepted

## Date
2025-08-17

## Context

During implementation of OpenShift logging infrastructure with ArgoCD, we encountered critical namespace management issues:

### Problem Identified
```yaml
# DANGEROUS: Application-level ArgoCD managing namespace
syncPolicy:
  automated:
    prune: true      # ⚠️ Could delete namespace
managedNamespaceMetadata:  # ⚠️ ArgoCD thinks it owns namespace
```

### Risk Analysis
- **Namespace Deletion Risk**: ArgoCD applications with `prune: true` could delete `openshift-logging` namespace
- **Resource Loss**: Complete loss of LokiStack data, secrets, and configurations
- **Service Disruption**: Total logging outage across the cluster
- **Shared Resource Conflicts**: Multiple ArgoCD applications claiming namespace ownership

### Current Architecture Issues
```
logging-stack-dev (ArgoCD) ──┐
                             ├── openshift-logging namespace
logging-operator (ArgoCD) ───┘
```

## Decision

We will implement a hierarchical resource ownership model with strict namespace management rules:

### Resource Ownership Hierarchy

#### 1. **Operator-Level** (`argocd-logging-operator.yaml`)
- **Manages**: `openshift-logging` namespace creation
- **Manages**: Operator subscription and installation
- **Scope**: Infrastructure lifecycle management
- **Namespace Policy**: `CreateNamespace=true`

#### 2. **Instance-Level** (`argocd-logging-instance.yaml`)
- **Manages**: ClusterLogging instance (defines **WHAT** logs to collect)
- **Scope**: Cluster-wide, environment-agnostic log collection configuration
- **Namespace Policy**: `CreateNamespace=false`

#### 3. **Application-Level** (`logging-stack-dev/prod`)
- **Manages**: ClusterLogForwarder (defines **WHERE** logs go)
- **Manages**: LokiStack, ExternalSecrets (environment-specific resources)
- **Scope**: Environment-specific routing and destinations
- **Namespace Policy**: `CreateNamespace=false`
- **PROHIBITION**: MUST NOT manage namespaces

### Architectural Separation
```
Operator Level:    Namespace + Operator Installation
     ↓
Instance Level:    ClusterLogging (What to collect)
     ↓
Application Level: ClusterLogForwarder + Storage (Where to send)
```

## Consequences

### Positive
- ✅ **Namespace Protection**: Eliminates risk of accidental namespace deletion
- ✅ **Clear Ownership**: Unambiguous resource ownership and responsibility
- ✅ **Proper Dependencies**: Correct deployment order and dependency management
- ✅ **GitOps Best Practices**: Follows established patterns for operator vs application management

### Negative
- ❌ **Multiple Applications**: Requires coordination between multiple ArgoCD applications
- ❌ **Deployment Complexity**: More complex deployment orchestration
- ❌ **Dependency Management**: Must ensure proper sync order between applications

### Risks Mitigated
- **Data Loss Prevention**: Cannot accidentally delete logging data
- **Service Continuity**: Prevents logging service disruption
- **Resource Conflicts**: Eliminates shared resource ownership conflicts

## Implementation

### Phase 1: Update ArgoCD Application Configurations
```yaml
# Application-level apps MUST include:
spec:
  syncPolicy:
    syncOptions:
      - CreateNamespace=false  # Never create namespaces
  # Remove managedNamespaceMetadata completely
```

### Phase 2: Resource Separation
```yaml
# Operator Level: base/logging-operator/
resources:
- namespace.yaml
- subscription.yaml

# Instance Level: base/logging-instance/
resources:
- cluster-logging.yaml

# Application Level: base/cluster-log-forwarder/
resources:
- cluster-log-forwarder-template.yaml
- logcollector-serviceaccount.yaml
```

### Phase 3: Deployment Order
1. **First**: `argocd-logging-operator.yaml` (creates namespace, installs operator)
2. **Second**: `argocd-logging-instance.yaml` (creates ClusterLogging)
3. **Third**: `logging-stack-dev/prod` (creates environment-specific forwarding)

## Validation

### Safety Checks
- ✅ No application-level ArgoCD app has `managedNamespaceMetadata`
- ✅ All application-level apps use `CreateNamespace=false`
- ✅ Only operator-level app can create/manage namespaces
- ✅ Resource ownership is clearly documented and enforced

### Testing
- Verify namespace cannot be deleted by application-level ArgoCD sync
- Test ArgoCD application deletion does not affect namespace
- Validate proper resource cleanup without namespace impact

## References
- [ArgoCD Best Practices for Namespace Management](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [OpenShift GitOps Operator Documentation](https://docs.openshift.com/container-platform/latest/cicd/gitops/understanding-openshift-gitops.html)

## Related ADRs
- ADR-0010: Log Collection TLS Certificate Management Strategy
- ADR-0012: RBAC Strategy for Log Collection ServiceAccounts
- ADR-0013: Multi-Environment Log Forwarding Architecture
