# ADR-0010: Log Collection TLS Certificate Management Strategy

## Status
Proposed

## Date
2025-08-17

## Context

OpenShift logging infrastructure requires secure communication between Vector log collectors and Loki Gateway components. During implementation, we encountered TLS certificate verification failures:

```
error:0A000086:SSL routines:tls_post_process_server_certificate:certificate verify failed:ssl/statem/statem_clnt.c:2102:: self-signed certificate in certificate chain
```

### Problem Analysis
- **Vector collectors** cannot verify Loki Gateway certificates
- **Loki Gateway** uses OpenShift service-serving-signer CA: `openshift-service-serving-signer@1755265534`
- **Certificate Subject**: `CN=logging-loki-gateway-http.openshift-logging.svc`
- **Issue**: Vector doesn't trust OpenShift internal CA by default

### Architecture Flow
```
Vector (Collector) --[TLS]-> Loki Gateway --[HTTPS]-> Amazon S3
                      ↑
                   FAILING HERE
```

## Decision

We will implement a comprehensive TLS certificate management strategy for OpenShift logging:

1. **Use OpenShift Service CA**: Leverage `openshift-service-serving-signer` for internal service certificates
2. **Configure CA Trust**: Configure Vector collectors to trust OpenShift internal CA bundle
3. **Separate Internal/External TLS**: Maintain distinction between internal service TLS and external storage HTTPS
4. **Automated CA Management**: Use OpenShift's automatic CA bundle injection via ConfigMaps

### Implementation Details
- Reference `openshift-service-ca.crt` ConfigMap in ClusterLogForwarder configuration
- Use `logging-loki-gateway-ca-bundle` ConfigMap for Loki-specific CA trust
- Configure Vector to validate certificates against OpenShift service CA

## Consequences

### Positive
- ✅ **Secure Communication**: Proper TLS validation for all internal logging traffic
- ✅ **OpenShift Integration**: Leverages built-in certificate management infrastructure
- ✅ **Automatic Rotation**: Benefits from OpenShift's automatic certificate rotation
- ✅ **Compliance**: Meets security requirements for encrypted log transmission

### Negative
- ❌ **Configuration Complexity**: Requires proper CA bundle configuration in ClusterLogForwarder
- ❌ **OpenShift Dependency**: Tightly coupled to OpenShift certificate infrastructure
- ❌ **Troubleshooting Complexity**: TLS issues require understanding of OpenShift CA hierarchy

### Risks
- **Certificate Expiration**: Must monitor OpenShift CA certificate lifecycle
- **CA Rotation**: Need to handle service CA rotation events
- **Cross-Cluster**: Strategy may not work for multi-cluster log forwarding

## Implementation

### Phase 1: CA Bundle Configuration
```yaml
# ClusterLogForwarder with CA bundle reference
spec:
  outputs:
  - name: default-lokistack
    type: lokiStack
    lokiStack:
      target:
        name: logging-loki
        namespace: openshift-logging
      authentication:
        token:
          from: serviceAccount
      tls:
        caCert:
          configMapName: logging-loki-gateway-ca-bundle
          key: service-ca.crt
```

### Phase 2: Validation
- Verify Vector can connect to Loki Gateway without TLS errors
- Monitor certificate validation in Vector logs
- Test log flow from collection to storage

## References
- [OpenShift Service CA Documentation](https://docs.openshift.com/container-platform/latest/security/certificates/service-serving-certificate.html)
- [Vector TLS Configuration](https://vector.dev/docs/reference/configuration/sinks/loki/#tls)
- OpenShift Logging 6.3 ClusterLogForwarder API Reference

## Related ADRs
- ADR-0011: GitOps Resource Ownership and Namespace Management
- ADR-0012: RBAC Strategy for Log Collection ServiceAccounts
- ADR-0014: OpenShift Logging 6.3 API Migration Strategy
