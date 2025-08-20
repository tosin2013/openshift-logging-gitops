# ADR-0014: Cluster Observability Operator Integration Strategy

## Status
Proposed

## Date
2025-08-17

## Context

During OpenShift logging infrastructure implementation, we encountered a failed Cluster Observability Operator installation that impacts the overall observability strategy and user experience.

### Current State Analysis
```
Cluster Observability Operator Status: Failed
Reason: TooManyOperatorGroups
Message: csv created in namespace with multiple operatorgroups, can't pick one automatically
```

### Missing Components Identified
- ❌ **Cluster Observability Operator**: Failed installation due to OperatorGroup conflicts
- ❌ **Logging UIPlugins**: No logging console integration available
- ❌ **Console Integration**: Users cannot access logs from OpenShift console
- ✅ **Standalone Logging**: LokiStack and Vector working independently
- ✅ **Loki Route**: Direct access available at external route

### User Experience Impact
- **Current**: Users must access Loki directly via external route
- **Missing**: Integrated logging experience within OpenShift console
- **Available**: Monitoring and networking console plugins working
- **Gap**: No unified observability dashboard

## Decision

We will adopt a **Hybrid Observability Architecture** that prioritizes working logging infrastructure while planning for future observability integration.

### Strategic Approach

#### Phase 1: Standalone Logging (Current - Maintain)
- **Continue** with current LokiStack + Vector architecture
- **Maintain** direct Loki route access for immediate log access needs
- **Resolve** TLS certificate issues to ensure log delivery
- **Document** current architecture as baseline

#### Phase 2: OperatorGroup Conflict Resolution (Next)
- **Investigate** OperatorGroup conflicts in observability namespace
- **Implement** namespace isolation strategy for operators
- **Test** Cluster Observability Operator installation in clean environment
- **Validate** operator functionality before integration

#### Phase 3: UIPlugin Integration (Future)
- **Develop** logging UIPlugin using `uiplugins.observability.openshift.io` CRD
- **Integrate** with OpenShift console plugin framework
- **Provide** seamless log access within console interface
- **Maintain** backward compatibility with direct Loki access

### Architecture Decision Matrix

| Component | Current State | Target State | Priority |
|-----------|---------------|--------------|----------|
| **Log Collection** | ✅ Working (Vector) | ✅ Maintain | High |
| **Log Storage** | ✅ Working (LokiStack + S3) | ✅ Maintain | High |
| **Log Access** | ✅ Direct Route | ➕ Console Integration | Medium |
| **Observability Operator** | ❌ Failed | 🔄 Fix OperatorGroups | Medium |
| **UIPlugins** | ❌ Missing | ➕ Implement | Low |
| **Unified Dashboard** | ❌ Missing | ➕ Future Enhancement | Low |

## Consequences

### Positive
- ✅ **Operational Continuity**: Maintains working logging infrastructure
- ✅ **Risk Mitigation**: Avoids disrupting functional components
- ✅ **Incremental Improvement**: Allows phased enhancement approach
- ✅ **User Access**: Preserves current log access capabilities

### Negative
- ❌ **Fragmented Experience**: Users must use multiple interfaces
- ❌ **Delayed Integration**: Console integration postponed
- ❌ **Operational Overhead**: Multiple access methods to maintain
- ❌ **Technical Debt**: OperatorGroup conflicts remain unresolved

### Risks
- **Operator Conflicts**: May affect other observability components
- **Console Integration Complexity**: UIPlugin development may be complex
- **User Adoption**: Direct Loki access may have lower adoption
- **Maintenance Burden**: Multiple interfaces require separate maintenance

## Implementation

### Phase 1: Immediate Actions (Current Sprint)
```yaml
# Maintain current working configuration
# Focus on resolving TLS certificate issues
# Document direct Loki access procedures
```

### Phase 2: OperatorGroup Resolution (Next Sprint)
```bash
# Investigate OperatorGroup conflicts
oc get operatorgroups -A
oc describe csv cluster-observability-operator.v1.2.2 -n openshift-cluster-observability-operator

# Clean up conflicting OperatorGroups
# Reinstall Cluster Observability Operator
# Validate operator functionality
```

### Phase 3: UIPlugin Development (Future)
```yaml
# Create logging UIPlugin
apiVersion: observability.openshift.io/v1
kind: UIPlugin
metadata:
  name: logging-console-plugin
  namespace: openshift-logging
spec:
  type: console
  displayName: "Logging"
  backend:
    service:
      name: logging-console-plugin
      namespace: openshift-logging
      port: 9443
```

### Validation Criteria

#### Phase 1 Success Metrics
- ✅ Log collection continues without interruption
- ✅ TLS certificate issues resolved
- ✅ Direct Loki access functional
- ✅ Documentation updated

#### Phase 2 Success Metrics
- ✅ Cluster Observability Operator status: Succeeded
- ✅ No OperatorGroup conflicts
- ✅ Observability components healthy
- ✅ Integration with existing logging stack

#### Phase 3 Success Metrics
- ✅ UIPlugin deployed and functional
- ✅ Console integration working
- ✅ User can access logs from OpenShift console
- ✅ Backward compatibility maintained

## Alternatives Considered

### Alternative 1: Fix Observability Operator Immediately
**Rejected**: Risk of disrupting working logging infrastructure

### Alternative 2: Abandon Observability Operator
**Rejected**: Loses long-term observability integration benefits

### Alternative 3: Custom Console Integration
**Rejected**: Higher development effort than UIPlugin approach

## References
- [OpenShift Console Plugin Development](https://docs.openshift.com/container-platform/latest/web_console/creating-quick-start-tutorials.html)
- [Cluster Observability Operator Documentation](https://docs.openshift.com/container-platform/latest/observability/cluster_observability_operator/cluster-observability-operator-overview.html)
- [UIPlugin CRD Reference](https://docs.openshift.com/container-platform/latest/rest_api/extension_apis/uiplugin-observability-openshift-io-v1.html)

## Related ADRs
- ADR-0010: Log Collection TLS Certificate Management Strategy
- ADR-0011: GitOps Resource Ownership and Namespace Management
- ADR-0015: Logging Console Integration and UIPlugin Strategy (to be created)
