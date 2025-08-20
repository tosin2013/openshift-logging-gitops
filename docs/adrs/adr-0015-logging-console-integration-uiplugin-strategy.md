# ADR-0015: Logging Console Integration and UIPlugin Strategy

## Status
Proposed

## Date
2025-08-17

## Context

OpenShift logging infrastructure is operational with LokiStack and Vector, but lacks integrated console access for users. Analysis reveals missing UIPlugin integration that would provide seamless log access within the OpenShift console.

### Current User Experience
- **Log Access**: Users must navigate to external Loki route
- **Route Available**: `https://logging-loki-openshift-logging.apps.cluster-rw9rh.rw9rh.sandbox1010.opentlc.com`
- **Console Integration**: Missing - no logging option in OpenShift console
- **Existing Plugins**: Monitoring and networking plugins working successfully

### Technical Assessment
```bash
# Available CRDs for console integration
consoleplugins.console.openshift.io     # Console plugin framework
uiplugins.observability.openshift.io    # Observability UI plugins

# Current console plugins enabled
["monitoring-plugin", "networking-console-plugin"]
# Missing: logging-plugin
```

### User Workflow Gap
```
Current: OpenShift Console → External Browser Tab → Loki UI
Desired: OpenShift Console → Logging Tab → Integrated Log View
```

## Decision

We will implement a **Logging Console Plugin** using the OpenShift console plugin framework to provide integrated log access within the OpenShift console.

### Implementation Strategy

#### Option 1: ConsolePlugin Integration (Chosen)
- **Use**: `consoleplugins.console.openshift.io` CRD
- **Approach**: Embed Loki UI within console iframe or custom component
- **Benefits**: Follows established OpenShift console patterns
- **Precedent**: Monitoring and networking plugins use this approach

#### Option 2: UIPlugin Integration (Future Enhancement)
- **Use**: `uiplugins.observability.openshift.io` CRD  
- **Approach**: Native observability dashboard integration
- **Dependency**: Requires working Cluster Observability Operator
- **Timeline**: After ADR-0014 OperatorGroup conflicts resolved

### Architecture Design

#### Console Plugin Architecture
```yaml
apiVersion: console.openshift.io/v1
kind: ConsolePlugin
metadata:
  name: logging-plugin
  namespace: openshift-logging
spec:
  displayName: "Logging"
  backend:
    service:
      name: logging-console-plugin
      namespace: openshift-logging
      port: 9443
    type: Service
  i18n:
    loadType: Preload
```

#### Service Implementation Options

##### Option A: Loki Proxy Service
```yaml
# Proxy service that forwards to Loki Gateway
apiVersion: v1
kind: Service
metadata:
  name: logging-console-plugin
  namespace: openshift-logging
spec:
  selector:
    app: loki-console-proxy
  ports:
  - port: 9443
    targetPort: 8080
```

##### Option B: Custom Console Plugin Service
```yaml
# Dedicated console plugin with custom UI
apiVersion: apps/v1
kind: Deployment
metadata:
  name: logging-console-plugin
  namespace: openshift-logging
spec:
  template:
    spec:
      containers:
      - name: console-plugin
        image: quay.io/openshift/logging-console-plugin:latest
        ports:
        - containerPort: 9443
```

## Consequences

### Positive
- ✅ **Integrated Experience**: Users access logs without leaving console
- ✅ **Consistent UI**: Follows OpenShift console design patterns
- ✅ **RBAC Integration**: Leverages OpenShift authentication and authorization
- ✅ **Discoverability**: Logging becomes visible in console navigation

### Negative
- ❌ **Development Effort**: Requires custom plugin development or configuration
- ❌ **Maintenance Overhead**: Additional component to maintain and update
- ❌ **Dependency Risk**: Console plugin framework changes could impact functionality
- ❌ **Performance Impact**: Additional service and network calls

### Trade-offs
- **Simplicity vs Integration**: Direct Loki access simpler but less integrated
- **Development vs User Experience**: Investment in development improves user adoption
- **Maintenance vs Functionality**: More components to maintain for better functionality

## Implementation

### Phase 1: Console Plugin Deployment
```yaml
# base/logging-console-plugin/
├── console-plugin.yaml          # ConsolePlugin CRD
├── service.yaml                 # Backend service
├── deployment.yaml              # Plugin service deployment
├── configmap.yaml              # Plugin configuration
└── kustomization.yaml          # Kustomize configuration
```

### Phase 2: Console Integration
```bash
# Enable logging plugin in console
oc patch console.operator.openshift.io cluster \
  --type='json' \
  -p='[{"op": "add", "path": "/spec/plugins/-", "value": "logging-plugin"}]'
```

### Phase 3: User Access Configuration
```yaml
# RBAC for console plugin access
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: logging-console-access
rules:
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "list"]
- apiGroups: ["observability.openshift.io"]
  resources: ["logs"]
  verbs: ["get", "list"]
```

### Validation Criteria

#### Success Metrics
- ✅ Console plugin appears in OpenShift console navigation
- ✅ Users can access logs without external navigation
- ✅ RBAC permissions properly enforced
- ✅ Plugin performance acceptable (< 2s load time)

#### User Acceptance Criteria
- ✅ Log search functionality available in console
- ✅ Time range selection working
- ✅ Log filtering and querying functional
- ✅ Export/download capabilities available

### Security Considerations
- **Authentication**: Plugin inherits OpenShift console authentication
- **Authorization**: RBAC controls access to log data
- **Network Security**: Internal service communication only
- **Data Privacy**: No log data cached in plugin service

## Alternatives Considered

### Alternative 1: Direct Loki Route Only
**Rejected**: Poor user experience, requires external navigation

### Alternative 2: Custom Console Tab
**Rejected**: Not following OpenShift console plugin patterns

### Alternative 3: Grafana Integration
**Rejected**: Additional complexity, not native to OpenShift

## References
- [OpenShift Console Plugin Development Guide](https://docs.openshift.com/container-platform/latest/web_console/dynamic-plugins/overview-dynamic-plugins.html)
- [Console Plugin Examples](https://github.com/openshift/console-plugin-template)
- [Loki HTTP API Documentation](https://grafana.com/docs/loki/latest/api/)

## Related ADRs
- ADR-0014: Cluster Observability Operator Integration Strategy
- ADR-0010: Log Collection TLS Certificate Management Strategy
- ADR-0012: RBAC Strategy for Log Collection ServiceAccounts
