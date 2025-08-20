# ADR-0012: RBAC Strategy for Log Collection ServiceAccounts

## Status
Accepted

## Date
2025-08-17

## Context

OpenShift Logging 6.3 introduced significant changes to RBAC requirements for log collection. During implementation, we encountered authorization failures:

### Problem Analysis
```
ClusterLogForwarder Status:
message: insufficient permissions on service account, not authorized to collect ["application" "audit" "infrastructure"] logs
reason: ClusterRoleMissing
status: "False"
type: observability.openshift.io/Authorized
```

### Investigation Findings
- **Custom ClusterRole Insufficient**: Our custom `logcollector` ClusterRole lacked proper permissions
- **Operator-Provided Roles**: OpenShift Logging 6.3 provides specific ClusterRoles for log collection
- **New Permission Model**: Uses `logs.collect` verb on specific log types

### Operator-Provided ClusterRoles
```yaml
# collect-application-logs
rules:
- apiGroups: [logging.openshift.io, observability.openshift.io]
  resourceNames: [application]
  resources: [logs]
  verbs: [collect]

# collect-audit-logs  
rules:
- apiGroups: [logging.openshift.io, observability.openshift.io]
  resourceNames: [audit]
  resources: [logs]
  verbs: [collect]

# collect-infrastructure-logs
rules:
- apiGroups: [logging.openshift.io, observability.openshift.io]
  resourceNames: [infrastructure]
  resources: [logs]
  verbs: [collect]
```

## Decision

We will adopt the operator-provided ClusterRoles for log collection authorization:

### RBAC Strategy
1. **Use Operator ClusterRoles**: Bind to `collect-application-logs`, `collect-audit-logs`, `collect-infrastructure-logs`
2. **Avoid Custom ClusterRoles**: Do not create custom ClusterRoles for log collection permissions
3. **ServiceAccount Binding**: Create multiple ClusterRoleBindings for comprehensive log access
4. **Operator Compatibility**: Ensure compatibility with OpenShift Logging operator expectations

## Consequences

### Positive
- ✅ **Proper Authorization**: ServiceAccount authorized for all log types
- ✅ **Operator Compatibility**: Uses permissions expected by OpenShift Logging operator
- ✅ **Future-Proof**: Automatic updates when operator changes permission requirements
- ✅ **Security Compliance**: Follows principle of least privilege

### Negative
- ❌ **External Dependency**: Relies on operator-provided ClusterRoles
- ❌ **Multiple Bindings**: Requires three separate ClusterRoleBindings
- ❌ **Operator Coupling**: Tightly coupled to OpenShift Logging operator RBAC model

## Implementation

### RBAC Configuration
```yaml
# base/cluster-log-forwarder/logcollector-serviceaccount.yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: logcollector-application-logs
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: collect-application-logs
subjects:
- kind: ServiceAccount
  name: logcollector
  namespace: openshift-logging
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: logcollector-audit-logs
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: collect-audit-logs
subjects:
- kind: ServiceAccount
  name: logcollector
  namespace: openshift-logging
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: logcollector-infrastructure-logs
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: collect-infrastructure-logs
subjects:
- kind: ServiceAccount
  name: logcollector
  namespace: openshift-logging
```

## Validation Criteria

### Success Metrics
- ✅ ClusterLogForwarder shows `Authorized: True`
- ✅ Vector collector pods start successfully
- ✅ Log collection flows from all sources
- ✅ No RBAC-related errors in logs

## References
- [OpenShift Logging 6.3 RBAC Documentation](https://docs.openshift.com/container-platform/latest/logging/cluster-logging-deploying.html)
- [Kubernetes RBAC Best Practices](https://kubernetes.io/docs/concepts/security/rbac-good-practices/)

## Related ADRs
- ADR-0011: GitOps Resource Ownership and Namespace Management
- ADR-0014: OpenShift Logging 6.3 API Migration Strategy
