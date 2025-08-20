# ADR-0018: ClusterLogForwarder Bearer Token Authentication and TLS Configuration

## Status
Accepted

## Context

During the implementation of OpenShift logging with LokiStack, we encountered authentication and TLS certificate verification issues when using the standard `lokiStack` output type with service account token authentication. The initial approach using `lokiStack` output type resulted in persistent 403 Forbidden errors and TLS certificate verification failures.

After extensive troubleshooting and referencing the Loki Operator documentation, we discovered that LokiStack in `openshift-logging` tenant mode requires a specific authentication approach using bearer tokens and the `loki` output type with direct gateway endpoints.

## Decision

We have decided to implement ClusterLogForwarder using:

1. **Bearer Token Authentication**: Use the `loki` output type with bearer token authentication from a dedicated secret
2. **Direct Gateway Endpoints**: Connect directly to LokiStack gateway endpoints for each log type
3. **TLS Configuration with Skip Verification**: Use `insecureSkipVerify: true` for demonstration environments

### Implementation Details

#### Authentication Method
```yaml
authentication:
  token:
    from: secret
    secret:
      name: lokistack-gateway-bearer-token
      key: token
```

#### Output Configuration
- **Application Logs**: `https://logging-loki-gateway-http.openshift-logging.svc:8080/api/logs/v1/application`
- **Infrastructure Logs**: `https://logging-loki-gateway-http.openshift-logging.svc:8080/api/logs/v1/infrastructure`
- **Audit Logs**: `https://logging-loki-gateway-http.openshift-logging.svc:8080/api/logs/v1/audit`

#### TLS Configuration for Demo Environment
```yaml
tls:
  ca:
    key: ca-bundle.crt
    secretName: lokistack-gateway-bearer-token
  insecureSkipVerify: true  # For demonstration purposes
```

#### Required RBAC
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: lokistack-dev-tenant-logs
rules:
- apiGroups:
  - 'loki.grafana.com'
  resources:
  - application
  - infrastructure
  - audit
  resourceNames:
  - logs
  verbs:
  - 'create'
```

## Consequences

### Positive
- **Functional Log Forwarding**: Eliminates 403 Forbidden and TLS certificate verification errors
- **Proper Authentication**: Uses the correct authentication method for LokiStack `openshift-logging` tenant mode
- **Separate Log Streams**: Each log type (application, infrastructure, audit) has dedicated outputs for better organization
- **GitOps Ready**: Configuration is templated and ready for multi-environment deployment

### Negative
- **TLS Security Trade-off**: Using `insecureSkipVerify: true` reduces security in demonstration environments
- **Complexity**: Requires additional secret management and RBAC configuration
- **Maintenance**: Bearer token secret needs to be populated and maintained

## TLS Security Considerations

### Current Demo Configuration (`insecureSkipVerify: true`)
The demonstration environment uses `insecureSkipVerify: true` to bypass TLS certificate verification. This approach:
- **Pros**: Eliminates certificate chain issues and enables immediate functionality
- **Cons**: Reduces security by not validating server certificates
- **Use Case**: Suitable for development, testing, and demonstration environments

### Production Configuration (`insecureSkipVerify: false`)
For production environments, `insecureSkipVerify: false` should be used with proper certificate management:

#### Requirements for Production TLS
1. **Valid CA Certificate**: Ensure the CA bundle in the secret contains the correct certificate authority
2. **Certificate Chain Validation**: Verify the complete certificate chain from LokiStack gateway to root CA
3. **Certificate Rotation**: Implement automated certificate rotation and secret updates
4. **Monitoring**: Monitor certificate expiration and TLS handshake failures

#### Implementation Steps for Production TLS
```yaml
# Production TLS configuration
tls:
  ca:
    key: ca-bundle.crt
    secretName: lokistack-gateway-bearer-token
  insecureSkipVerify: false  # Enable full TLS validation
```

**Required Actions:**
1. Obtain the correct CA certificate from OpenShift Service CA or LokiStack
2. Update the bearer token secret with the proper CA bundle:
   ```bash
   oc patch secret lokistack-gateway-bearer-token -n openshift-logging \
     --patch='{"data":{"ca-bundle.crt":"<base64-encoded-ca-cert>"}}'
   ```
3. Verify certificate chain: `openssl verify -CAfile ca-bundle.crt server-cert.crt`
4. Test TLS connectivity: `openssl s_client -connect logging-loki-gateway-http.openshift-logging.svc:8080`

## Alternatives Considered

1. **lokiStack Output Type**: Initial approach that failed due to authentication issues in `openshift-logging` tenant mode
2. **Service Account Token Authentication**: Attempted but resulted in 403 Forbidden errors
3. **Direct Secret Reference**: Considered but bearer token approach provides better security and flexibility

## Implementation

The implementation includes:
- Base ClusterLogForwarder template with bearer token authentication
- Bearer token secret template with placeholders
- RBAC resources for LokiStack tenant permissions
- Environment-specific overlays for dev and production
- Production overlay uses `insecureSkipVerify: false` for enhanced security

## References
- [Loki Operator Documentation - Forwarding Logs to Gateway](https://loki-operator.dev/docs/forwarding_logs_to_gateway.md/)
- [OpenShift Logging Documentation](https://docs.openshift.com/container-platform/latest/logging/cluster-logging.html)
- ADR-0010: Log Collection TLS Certificate Management
- ADR-0012: RBAC Strategy Log Collection ServiceAccounts
