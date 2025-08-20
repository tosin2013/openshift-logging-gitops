# ADR-0013: Multi-Environment Log Forwarding Architecture

## Status
Accepted

## Date
2025-08-17

## Context

Development and production environments require different log retention, filtering, and compliance strategies. During implementation, we needed to design environment-specific log forwarding while maintaining consistent log collection.

### Requirements Analysis
- **Development**: Comprehensive log access for debugging, shorter retention
- **Production**: Compliance-focused with separate audit trails, longer retention
- **Consistency**: Shared log collection configuration across environments
- **Scalability**: Support for additional environments (staging, testing)

### Current Architecture
```
ClusterLogging (Shared) → ClusterLogForwarder (Environment-Specific) → LokiStack (Environment-Specific)
```

## Decision

We will implement environment-specific log forwarding using Kustomize overlays:

### Architecture Strategy
1. **Shared Collection**: Use common ClusterLogging instance across environments
2. **Environment-Specific Forwarding**: Use ClusterLogForwarder overlays for routing
3. **Compliance Separation**: Separate audit log pipelines in production
4. **Development Debugging**: Combined log streams for easier troubleshooting

### Environment Configurations

#### Development Environment
```yaml
# overlays/dev/cluster-log-forwarder-dev.yaml
spec:
  pipelines:
  - name: enable-default-log-store
    inputRefs: [application, infrastructure]
    outputRefs: [default-lokistack]
  - name: audit-logs-dev
    inputRefs: [audit]
    outputRefs: [default-lokistack]  # Combined with other logs
```

#### Production Environment
```yaml
# overlays/production/cluster-log-forwarder-production.yaml
spec:
  outputs:
  - name: default-lokistack      # Application & Infrastructure
  - name: audit-lokistack        # Separate audit output
  pipelines:
  - name: application-logs
    inputRefs: [application]
    outputRefs: [default-lokistack]
  - name: infrastructure-logs
    inputRefs: [infrastructure]
    outputRefs: [default-lokistack]
  - name: audit-logs-production  # Separate pipeline
    inputRefs: [audit]
    outputRefs: [audit-lokistack]
```

## Consequences

### Positive
- ✅ **Environment Isolation**: Appropriate log handling per environment
- ✅ **Compliance Ready**: Production audit logs properly separated
- ✅ **Development Friendly**: Comprehensive log access for debugging
- ✅ **Scalable**: Easy to add new environments with specific requirements

### Negative
- ❌ **Configuration Complexity**: Multiple overlays to maintain
- ❌ **Deployment Coordination**: Must ensure consistent base configuration
- ❌ **Testing Overhead**: Each environment requires separate validation

### Trade-offs
- **Consistency vs Flexibility**: Balanced approach with shared collection, specific forwarding
- **Simplicity vs Compliance**: Added complexity for production compliance requirements

## Implementation

### Directory Structure
```
base/
├── cluster-log-forwarder/
│   ├── cluster-log-forwarder-template.yaml
│   └── kustomization.yaml
overlays/
├── dev/
│   ├── cluster-log-forwarder-dev.yaml
│   └── kustomization.yaml
└── production/
    ├── cluster-log-forwarder-production.yaml
    └── kustomization.yaml
```

### Kustomize Configuration
```yaml
# overlays/dev/kustomization.yaml
resources:
- ../../base/cluster-log-forwarder
patchesStrategicMerge:
- cluster-log-forwarder-dev.yaml
configMapGenerator:
- name: logging-config
  literals:
  - environment=dev
  - retention_days=7
```

### Environment-Specific Features
| Feature | Development | Production |
|---------|-------------|------------|
| **Audit Logs** | Combined with other logs | Separate pipeline |
| **Retention** | 7 days | 90 days |
| **Log Level** | Debug | Info |
| **Compliance** | Basic | Full audit trail |

## Validation Criteria

### Success Metrics
- ✅ Dev environment: All log types accessible in single location
- ✅ Production environment: Audit logs separated for compliance
- ✅ Environment isolation: No cross-environment log leakage
- ✅ Consistent collection: Same log sources across environments

### Testing Strategy
- Validate log flow in each environment
- Verify audit log separation in production
- Test environment-specific retention policies
- Confirm compliance requirements met

## References
- [Kustomize Overlays Documentation](https://kustomize.io/docs/concepts/overlays/)
- [OpenShift Logging Multi-Environment Best Practices](https://docs.openshift.com/container-platform/latest/logging/)

## Related ADRs
- ADR-0011: GitOps Resource Ownership and Namespace Management
- ADR-0012: RBAC Strategy for Log Collection ServiceAccounts
- ADR-0015: Hybrid Storage Architecture for Log Data
