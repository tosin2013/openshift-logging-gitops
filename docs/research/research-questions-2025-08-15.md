# OpenShift Logging Architecture Research Questions
*Generated: August 15, 2025*
*OpenShift Version: 4.18.21*
*Cluster Type: AWS (3 masters, 3 workers)*

## Executive Summary

This research document outlines critical questions for implementing and validating the Loki-centric logging architecture defined in our ADRs. The questions are informed by actual cluster analysis and current implementation status.

## Current Cluster State (from `oc` commands)

- **OpenShift Version**: 4.18.21 ✅ (Meets ADR requirement for 4.18+)
- **Cluster Configuration**: 3 control-plane nodes, 3 worker nodes
- **Storage Classes**: gp2-csi, gp3-csi (default) - AWS EBS CSI driver
- **Logging Operators**: None currently installed
- **Platform**: AWS (us-east-2)

## Project File Structure

```
openshift-logging-gitops/
├── .gitignore                              # Git ignore file (includes PRD.md)
├── .vscode/                               # VS Code configuration
│   └── mcp.json                           # MCP server configuration
├── PRD.md                                 # Product Requirements Document
├── README.md                              # Project documentation
├── research.md                            # Research documentation
├── package.json                           # Node.js dependencies (mcp-adr-analysis-server)
├── package-lock.json                      # Dependency lock file
├── docs/                                  # Documentation directory
│   ├── adrs/                             # Architectural Decision Records
│   │   ├── adr-0001-adopt-a-loki-centric-logging-architecture.md
│   │   ├── adr-0001-operator-pattern-for-lifecycle-management.md
│   │   ├── adr-0002-declarative-gitops-driven-configuration-management.md
│   │   ├── adr-0003-object-storage-selection-for-log-retention.md
│   │   ├── adr-0004-secure-management-of-secrets-and-credentials.md
│   │   └── adr-0005-multi-environment-and-multi-cluster-scalability.md
│   └── research/                          # Research questions and findings
│       └── research-questions-2025-08-15.md
├── apps/                                  # ArgoCD Applications
│   └── applications/                      # Application definitions
│       ├── argocd-loki-operator.yaml
│       ├── argocd-logging-operator.yaml
│       ├── argocd-observability-operator.yaml
│       ├── argocd-external-secrets-operator.yaml
│       └── argocd-external-secrets-instance.yaml
├── base/                                  # Base Kustomize configurations
│   ├── external-secrets-operator/        # External Secrets Operator base
│   │   ├── instance/
│   │   └── operator/
│   ├── logging-operator/                  # Cluster Logging Operator base
│   │   ├── namespace.yaml
│   │   ├── subscription.yaml
│   │   └── operator-group.yaml
│   ├── loki-operator/                     # Loki Operator base
│   ├── observability-operator/           # Observability Operator base
│   │   ├── namespace.yaml
│   │   └── subscription.yaml
│   └── openshift-gitops/                  # OpenShift GitOps configuration
│       ├── argocd.yaml
│       ├── kustomization.yaml
│       ├── operator.yaml
│       └── rbac.yaml
└── overlays/                              # Environment-specific overlays
```

### Key File Structure Observations for Research:

**GitOps Architecture (ADR-0002):**
- ✅ ArgoCD applications defined in `apps/applications/`
- ✅ Base configurations in `base/` directory
- ✅ Overlay structure exists but needs population
- ✅ Kustomization files present

**Logging Components (ADR-0001):**
- ✅ Loki Operator application: `apps/applications/argocd-loki-operator.yaml`
- ✅ Logging Operator application: `apps/applications/argocd-logging-operator.yaml`
- ✅ Observability Operator application: `apps/applications/argocd-observability-operator.yaml`
- ✅ Base configurations: `base/logging-operator/`, `base/loki-operator/`, `base/observability-operator/`

**External Secrets (ADR-0004):**
- ✅ External Secrets Operator application: `apps/applications/argocd-external-secrets-operator.yaml`
- ✅ External Secrets instance: `apps/applications/argocd-external-secrets-instance.yaml`
- ✅ Base configuration: `base/external-secrets-operator/`

**Documentation Structure:**
- ✅ ADRs properly organized in `docs/adrs/`
- ✅ Research documentation in `docs/research/`
- ✅ Project documentation (PRD.md, README.md, research.md)

**Development Environment:**
- ✅ MCP ADR Analysis Server installed and configured
- ✅ VS Code configuration for MCP tools

## Current OpenShift GitOps Status

**ArgoCD Installation:**
- ✅ OpenShift GitOps installed and running in `openshift-gitops` namespace
- ✅ ArgoCD Server URL: `openshift-gitops-server-openshift-gitops.apps.cluster-rw9rh.rw9rh.sandbox1010.opentlc.com`
- ✅ All GitOps components healthy (8/8 pods running)

**Deployed Applications:**
- ✅ **external-secrets-operator**: Synced & Healthy
  - **Status**: Successfully deployed from `base/external-secrets-operator/operator/overlays/stable`
  - **Operator Version**: v0.11.0 (installed in openshift-operators namespace)
  - **Sync Policy**: Automated (auto-heal and prune enabled)
  - **Last Sync**: Successful at revision 7ecfdec4c

**Missing Applications (Ready to Deploy):**
- ⏳ loki-operator (ArgoCD app exists: `apps/applications/argocd-loki-operator.yaml`)
- ⏳ logging-operator (ArgoCD app exists: `apps/applications/argocd-logging-operator.yaml`) 
- ⏳ observability-operator (ArgoCD app exists: `apps/applications/argocd-observability-operator.yaml`)
- ⏳ external-secrets-instance (ArgoCD app exists: `apps/applications/argocd-external-secrets-instance.yaml`)

## Research Categories

### 1. ADR Implementation Validation

#### 1.1 Loki-Centric Architecture (ADR-0001)
**Priority: Critical**

**RQ-001**: How do we validate Loki performance vs. EFK on OpenShift 4.18.21?
- **oc Commands**: 
  ```bash
  # Before implementation - baseline metrics
  oc adm top nodes
  oc get events --field-selector type=Warning
  oc get pods --all-namespaces -o wide | grep -E "(fluentd|elasticsearch|kibana)"
  ```
- **Success Criteria**: 50% reduction in resource usage, 2x faster ingestion
- **Timeline**: 2 weeks

**RQ-002**: What is the migration path from existing logging to Loki without data loss?
- **oc Commands**:
  ```bash
  # Assess current logging data
  oc get pv | grep logging
  oc describe clusterlogging instance || echo "No ClusterLogging found"
  ```
- **Research Areas**: Data migration strategies, downtime minimization
- **Dependencies**: Object storage setup (ADR-0003)

#### 1.2 Operator Pattern Validation (ADR-0001 - Operator Pattern)
**Priority: High**

**RQ-003**: Which operator versions are compatible with OpenShift 4.18.21?
- **oc Commands**:
  ```bash
  # Check available operators
  oc get packagemanifests -n openshift-marketplace | grep -E "(loki|logging|observability)"
  oc describe packagemanifest cluster-logging -n openshift-marketplace
  oc describe packagemanifest loki-operator -n openshift-marketplace
  ```
- **Research Focus**: Version compatibility matrix, upgrade paths

**RQ-004**: How do we monitor operator health and dependencies?
- **oc Commands**:
  ```bash
  # Monitor operator status
  oc get csv -A
  oc get operators.operators.coreos.com
  oc get installplan -A
  ```
- **Success Criteria**: Zero failed operator reconciliations

### 2. Storage Implementation (ADR-0003)

#### 2.1 Object Storage Integration
**Priority: Critical**

**RQ-005**: How do we implement S3-compatible storage for Loki on AWS?
- **oc Commands**:
  ```bash
  # Check storage options
  oc get storageclass
  oc get pv
  # Test S3 connectivity from cluster
  oc run s3-test --image=amazon/aws-cli --rm -it -- aws s3 ls
  ```
- **Research Areas**: AWS S3 vs. in-cluster MinIO performance and cost
- **Dependencies**: Secret management (ADR-0004)

**RQ-006**: What are the storage performance benchmarks for different retention policies?
- **Testing Required**: 
  - Log ingestion rates with S3 backend
  - Query performance across different time ranges
  - Cost analysis for different storage tiers

### 3. Security and Secrets (ADR-0004)

#### 3.1 External Secrets Operator
**Priority: High**

**RQ-007**: How do we implement External Secrets Operator with AWS Secrets Manager?
- **oc Commands**:
  ```bash
  # Check current secret management
  oc get secrets -A | grep -E "(loki|logging|storage)"
  oc get sa -A | grep logging
  # Verify RBAC
  oc auth can-i create secrets --as=system:serviceaccount:openshift-logging:logcollector
  ```
- **Research Focus**: IAM roles, service account configuration, secret rotation

**RQ-008**: What are the security implications of cross-namespace secret sharing?
- **Security Areas**: Network policies, RBAC boundaries, audit logging

### 4. Multi-Environment Scalability (ADR-0005)

#### 4.1 GitOps Structure Validation
**Priority: Medium**

**RQ-009**: How do we validate remaining ArgoCD applications deploy correctly?
- **Current Status**: ✅ External Secrets Operator already deployed and healthy
- **oc Commands**:
  ```bash
  # Deploy remaining logging applications
  oc apply -f apps/applications/argocd-loki-operator.yaml
  oc apply -f apps/applications/argocd-logging-operator.yaml
  oc apply -f apps/applications/argocd-observability-operator.yaml
  oc apply -f apps/applications/argocd-external-secrets-instance.yaml
  
  # Monitor application deployment
  oc get applications -n openshift-gitops
  oc describe application <app-name> -n openshift-gitops
  
  # Test overlay generation (when overlays are created)
  oc kustomize overlays/dev/ || echo "Dev overlay not yet created"
  oc kustomize overlays/staging/ || echo "Staging overlay not yet created" 
  oc kustomize overlays/prod/ || echo "Prod overlay not yet created"
  ```
- **Testing Required**: Validate each application syncs and becomes healthy
- **Current ArgoCD**: Access at openshift-gitops-server-openshift-gitops.apps.cluster-rw9rh.rw9rh.sandbox1010.opentlc.com

**RQ-010**: What is the ArgoCD ApplicationSet configuration for multi-cluster deployment?
- **Research Areas**: ApplicationSet generators, cluster selection logic

### 5. Performance and Resource Planning

#### 5.1 Cluster Resource Assessment
**Priority: Medium**

**RQ-011**: What are the resource requirements for each logging component?
- **oc Commands**:
  ```bash
  # Current resource usage
  oc adm top nodes
  oc adm top pods -A
  # Available resources
  oc describe nodes | grep -E "(Capacity|Allocatable)"
  ```
- **Planning Required**: CPU, memory, storage allocation per component

**RQ-012**: How do we implement horizontal pod autoscaling for Loki components?
- **Research Areas**: HPA configuration, custom metrics, scaling triggers

### 6. Operational Readiness

#### 6.1 Monitoring and Alerting
**Priority: High**

**RQ-013**: What monitoring dashboards and alerts are needed for production?
- **oc Commands**:
  ```bash
  # Check monitoring stack
  oc get pods -n openshift-monitoring
  oc get servicemonitor -A
  oc get prometheusrule -A
  ```
- **Research Areas**: Grafana dashboard templates, alertmanager rules

**RQ-014**: How do we implement log retention and archival policies?
- **Policy Areas**: Compliance requirements, storage lifecycle management

### 7. Integration and Compatibility

#### 7.1 External System Integration
**Priority: Medium**

**RQ-015**: How do we integrate with existing SIEM and log analysis tools?
- **Integration Points**: API compatibility, data export formats
- **Research Required**: Third-party tool compatibility matrix

**RQ-016**: What is the impact on existing applications that depend on current logging?
- **Assessment Areas**: Application log formats, query patterns, dashboards

## Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)
1. **RQ-003**: Validate operator compatibility
2. **RQ-005**: Set up S3-compatible storage
3. **RQ-007**: Implement External Secrets Operator

### Phase 2: Core Implementation (Weeks 3-4)
1. **RQ-001**: Deploy and validate Loki architecture
2. **RQ-009**: Test GitOps overlays
3. **RQ-011**: Resource planning and allocation

### Phase 3: Production Readiness (Weeks 5-6)
1. **RQ-013**: Implement monitoring and alerting
2. **RQ-002**: Execute migration strategy
3. **RQ-014**: Implement retention policies

### Phase 4: Optimization (Weeks 7-8)
1. **RQ-006**: Performance benchmarking
2. **RQ-012**: Implement autoscaling
3. **RQ-015**: External integrations

## Success Metrics

- **Performance**: 50% reduction in logging infrastructure resource usage
- **Reliability**: 99.9% uptime for logging pipeline
- **Security**: Zero credential exposure incidents
- **Scalability**: Support for 3 environments without manual intervention
- **Compliance**: All audit requirements met

## Risk Mitigation

### High-Risk Areas
1. **Data Loss During Migration**: Implement parallel running and validation
2. **Performance Degradation**: Extensive testing before production cutover
3. **Security Vulnerabilities**: Regular security scanning and updates

### Contingency Plans
1. **Rollback Strategy**: Maintain EFK stack until Loki validation complete
2. **Data Recovery**: Implement backup and restore procedures
3. **Performance Issues**: Have scaling and optimization strategies ready

## Tools and Commands Reference

### Essential `oc` Commands for Research
```bash
# Cluster information
oc version
oc get clusterversion
oc get nodes -o wide

# Operator management
oc get packagemanifests -n openshift-marketplace
oc get csv -A
oc get operators.operators.coreos.com

# Resource monitoring
oc adm top nodes
oc adm top pods -A
oc get events --field-selector type=Warning

# Storage and secrets
oc get storageclass
oc get secrets -A
oc get pv

# Networking and security
oc get networkpolicies -A
oc auth can-i <verb> <resource> --as=<user>

# Application deployment
oc apply --dry-run=client -k <kustomization-dir>
oc kustomize <overlay-dir>
```

## Next Steps

1. **Immediate Actions**:
   - Execute RQ-003 to identify compatible operator versions
   - Begin RQ-005 storage implementation planning
   - Start RQ-007 External Secrets Operator research

2. **Research Assignments**:
   - Assign critical questions (RQ-001, RQ-005, RQ-007) to team leads
   - Schedule weekly research review meetings
   - Set up research tracking and documentation

3. **Validation Environment**:
   - Set up development environment for testing
   - Implement CI/CD pipeline for GitOps validation
   - Create monitoring dashboard for research progress

---

*This document should be updated weekly as research progresses and new questions emerge.*
