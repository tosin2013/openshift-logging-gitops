# OpenShift Logging Operator Reference

This reference provides complete configuration options, API specifications, and deployment parameters for the OpenShift logging operators used in this GitOps deployment.

## Supported Operators

| Operator | Version | Namespace | Purpose |
|----------|---------|-----------|---------|
| External Secrets Operator | v0.11.0 | `external-secrets-system` | Secure credential management |
| Loki Operator | v5.9.6 | `openshift-operators` | Loki deployment and management |
| Cluster Logging Operator | v6.1.1 | `openshift-operators` | Log collection and forwarding |
| Observability Operator | v1.0.0 | `openshift-operators` | Metrics and monitoring |

## External Secrets Operator

### ClusterSecretStore Configuration

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager | ParameterStore | SecretsManager
      region: string
      auth:
        secretRef:
          accessKeyIDSecretRef:
            name: string
            key: string
            namespace: string
          secretAccessKeySecretRef:
            name: string
            key: string
            namespace: string
```

**Parameters:**
- `service`: AWS service type (SecretsManager recommended)
- `region`: AWS region where secrets are stored
- `auth.secretRef`: Reference to Kubernetes secret containing AWS credentials

### ExternalSecret Configuration

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: string
  namespace: string
spec:
  refreshInterval: duration  # Default: 15s
  secretStoreRef:
    name: string
    kind: ClusterSecretStore | SecretStore
  target:
    name: string
    creationPolicy: Owner | Merge | None
    template:
      type: Opaque | kubernetes.io/tls | kubernetes.io/service-account-token
      metadata:
        labels: {}
        annotations: {}
      data: {}
  data:
  - secretKey: string
    remoteRef:
      key: string
      property: string
      version: string
```

**Parameters:**
- `refreshInterval`: How often to sync secrets (minimum: 15s)
- `target.creationPolicy`: How to handle existing secrets
- `data`: Array of secret mappings from external source to K8s secret

## Loki Operator

### LokiStack Configuration

```yaml
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: string
  namespace: string
spec:
  size: 1x.demo | 1x.extra-small | 1x.small | 1x.medium | 1x.large
  storage:
    secret:
      name: string
      type: s3 | azure | gcs | swift | alibabacloud
      credentialMode: static | token | token-cco
    storageClassName: string
    schemas:
    - version: v11 | v12 | v13
      effectiveDate: "YYYY-MM-DD"
      objectStorage:
        effectiveDateRetention: duration  # e.g., "30d", "1y"
  tenants:
    mode: static | dynamic | openshift-logging | openshift-network
    authentication:
    - tenantName: string
      tenantId: string
      oidc:
        secret:
          name: string
        issuerURL: string
        redirectURL: string
        groupClaim: string
        usernameClaim: string
  template:
    compactor:
      replicas: int
      nodeSelector: {}
      tolerations: []
      resources:
        limits:
          cpu: string
          memory: string
        requests:
          cpu: string
          memory: string
    distributor:
      replicas: int
      nodeSelector: {}
      tolerations: []
      resources: {}
    ingester:
      replicas: int
      nodeSelector: {}
      tolerations: []
      resources: {}
    querier:
      replicas: int
      nodeSelector: {}
      tolerations: []
      resources: {}
    queryFrontend:
      replicas: int
      nodeSelector: {}
      tolerations: []
      resources: {}
    gateway:
      replicas: int
      nodeSelector: {}
      tolerations: []
      resources: {}
    indexGateway:
      replicas: int
      nodeSelector: {}
      tolerations: []
      resources: {}
    ruler:
      replicas: int
      nodeSelector: {}
      tolerations: []
      resources: {}
  limits:
    global:
      retention:
        days: int
        streams:
        - days: int
          priority: int
          selector: string
      ingestion:
        ingestionRate: int  # MB/s
        ingestionBurstSize: int  # MB
        maxLineSize: int  # bytes
        maxLabelNameLength: int
        maxLabelValueLength: int
        maxLabelNamesPerSeries: int
        maxGlobalStreamsPerUser: int
        maxChunksPerQuery: int
        maxQueriesPerTenant: int
      queries:
        queryTimeout: duration
        cardinalityLimit: int
        maxConcurrent: int
        maxFetch: int
        maxQueryBytesRead: int
        maxQueryLength: duration
        maxEntriesLimitPerQuery: int
        maxStreamsMatchersPerQuery: int
        maxSamplesPerQuery: int
    tenants: {}
  managementState: Managed | Unmanaged
  proxy:
    sat:
      mode: static | dynamic
      tokenAudience: string
```

### Size Specifications

| Size | Use Case | Distributor | Ingester | Querier | Gateway | CPU Limit | Memory Limit |
|------|----------|-------------|----------|---------|---------|-----------|--------------|
| 1x.demo | Development/testing | 1 | 1 | 1 | 1 | 100m | 128Mi |
| 1x.extra-small | Low volume prod | 1 | 1 | 1 | 1 | 500m | 512Mi |
| 1x.small | Standard prod | 1 | 1 | 2 | 1 | 1 | 2Gi |
| 1x.medium | High volume prod | 2 | 3 | 3 | 2 | 2 | 4Gi |
| 1x.large | Enterprise scale | 3 | 3 | 6 | 3 | 4 | 8Gi |

### Storage Secret Format

For S3-compatible storage:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: logging-loki-s3
  namespace: openshift-logging
type: Opaque
data:
  access_key_id: base64(string)
  access_key_secret: base64(string)
  bucketnames: base64(string)
  endpoint: base64(string)  # s3.amazonaws.com
  region: base64(string)    # us-east-1
```

## Cluster Logging Operator

### ClusterLogging Configuration

```yaml
apiVersion: logging.coreos.com/v1
kind: ClusterLogging
metadata:
  name: instance
  namespace: openshift-logging
spec:
  managementState: Managed | Unmanaged
  collection:
    type: fluentd | vector
    fluentd:
      buffer:
        chunkLimitSize: string      # Default: "8m"
        flushInterval: duration     # Default: "1s"
        flushMode: string           # Default: "interval"
        flushThreadCount: int       # Default: 2
        overflowAction: string      # Default: "block"
        retryWait: duration         # Default: "1s"
        retryMaxInterval: duration  # Default: "60s"
        retryTimeout: duration      # Default: "60m"
        totalLimitSize: string      # Default: "32m"
      nodeSelector: {}
      tolerations: []
      resources:
        limits:
          cpu: string
          memory: string
        requests:
          cpu: string
          memory: string
    vector:
      nodeSelector: {}
      tolerations: []
      resources: {}
  logStore:
    type: lokistack
    lokistack:
      name: string  # LokiStack instance name
  visualization:
    type: ocp-console
    ocpConsole:
      logsLimit: int  # Default: 100
      timeout: duration  # Default: "30s"
  curation:
    type: lokistack
    lokistack:
      name: string
```

### ClusterLogForwarder Configuration

```yaml
apiVersion: logging.coreos.com/v1
kind: ClusterLogForwarder
metadata:
  name: instance
  namespace: openshift-logging
spec:
  serviceAccountName: string
  inputs:
  - name: string
    application:
      namespaces: []
      selector:
        matchLabels: {}
        matchExpressions: []
      includes:
      - namespace: string
        container: string
      excludes:
      - namespace: string
        container: string
    infrastructure:
      sources: []  # node, container, kubeAPIServer, openshiftAPIServer, ovn
    audit:
      sources: []  # kubeAPIServer, openshiftAPIServer, ovn
  outputs:
  - name: string
    type: loki | elasticsearch | fluentdForward | syslog | kafka | cloudwatch | splunk | http
    loki:
      url: string
      tenantKey: string
      labelKeys: []
    elasticsearch:
      url: string
      version: int
      index: string
      template:
        name: string
        pattern: string
      ilm:
        enabled: boolean
        policyName: string
    fluentdForward:
      url: string
    syslog:
      url: string
      facility: string
      severity: string
      appName: string
      msgID: string
      procID: string
      rfc: string
    kafka:
      url: string
      topic: string
    cloudwatch:
      groupBy: string
      groupPrefix: string
      region: string
    splunk:
      url: string
      index: string
    http:
      url: string
      headers: {}
      method: string
    secret:
      name: string
    tls:
      insecureSkipVerify: boolean
      caCert:
        key: string
        secretName: string
        configMapName: string
  filters:
  - name: string
    type: "json" | "multilineException" | "detectMultiline" | "drop" | "prune"
    json:
      javascript: string
    multilineException:
      sourceField: string
      pattern: string
      matchAny: []
    detectMultiline:
      sourceField: string
      pattern: string
      maxLines: int
      timeout: duration
    drop:
    - test:
      - field: string
        matches: string
        notMatches: string
    prune:
      in: []
      notIn: []
  pipelines:
  - name: string
    inputRefs: []
    filterRefs: []
    outputRefs: []
    labels: {}
    parse: json | regexp | logType
    detectMultilineErrors: boolean
```

### Input Types

| Type | Purpose | Sources |
|------|---------|---------|
| `application` | Application container logs | User workloads |
| `infrastructure` | OpenShift infrastructure | node, container, kubeAPIServer, openshiftAPIServer, ovn |
| `audit` | Audit logs | kubeAPIServer, openshiftAPIServer, ovn |

### Output Types

| Type | Purpose | Required Fields |
|------|---------|----------------|
| `loki` | Loki storage | `url`, `tenantKey` |
| `elasticsearch` | Elasticsearch storage | `url`, `index` |
| `fluentdForward` | Forward to Fluentd | `url` |
| `syslog` | Syslog server | `url`, `facility` |
| `kafka` | Kafka topic | `url`, `topic` |
| `cloudwatch` | AWS CloudWatch | `region`, `groupBy` |
| `splunk` | Splunk HEC | `url`, `index` |
| `http` | Generic HTTP endpoint | `url` |

## Resource Requirements

### Minimum Requirements

| Component | CPU Request | Memory Request | CPU Limit | Memory Limit |
|-----------|-------------|----------------|-----------|--------------|
| External Secrets Controller | 100m | 128Mi | 500m | 512Mi |
| Loki Distributor (1x.small) | 100m | 128Mi | 1 | 1Gi |
| Loki Ingester (1x.small) | 300m | 1Gi | 1 | 2Gi |
| Loki Querier (1x.small) | 100m | 128Mi | 1 | 1Gi |
| Loki Gateway (1x.small) | 100m | 64Mi | 200m | 256Mi |
| Vector Collector | 120m | 128Mi | 200m | 256Mi |

### Storage Requirements

| Component | Storage Class | Size | Purpose |
|-----------|---------------|------|---------|
| Loki WAL | gp3-csi | 10Gi per ingester | Write-ahead log |
| Loki Chunks | S3 | Unlimited | Long-term storage |
| Vector Buffer | emptyDir | 1Gi | Log buffering |

## API Versions

| Resource | API Version | Kind |
|----------|-------------|------|
| ClusterSecretStore | external-secrets.io/v1beta1 | ClusterSecretStore |
| ExternalSecret | external-secrets.io/v1beta1 | ExternalSecret |
| LokiStack | loki.grafana.com/v1 | LokiStack |
| ClusterLogging | logging.coreos.com/v1 | ClusterLogging |
| ClusterLogForwarder | logging.coreos.com/v1 | ClusterLogForwarder |

## Status Fields

### LokiStack Status

```yaml
status:
  conditions:
  - type: Ready | Degraded | Warning
    status: "True" | "False" | "Unknown"
    reason: string
    message: string
    lastTransitionTime: timestamp
  components:
    compactor: Ready | Pending | Failed
    distributor: Ready | Pending | Failed
    ingester: Ready | Pending | Failed
    querier: Ready | Pending | Failed
    queryFrontend: Ready | Pending | Failed
    gateway: Ready | Pending | Failed
    indexGateway: Ready | Pending | Failed
    ruler: Ready | Pending | Failed
  storage:
    credentialMode: static | token | token-cco
    schemas:
    - effectiveDate: "YYYY-MM-DD"
      version: v11 | v12 | v13
```

### ClusterLogging Status

```yaml
status:
  conditions:
  - type: Ready | Degraded
    status: "True" | "False" | "Unknown"
    reason: string
    message: string
  collection:
    status: Ready | Pending | Failed
    reason: string
  logStore:
    status: Ready | Pending | Failed
    reason: string
  visualization:
    status: Ready | Pending | Failed
    reason: string
```

## Environment Variables

### Loki Components

| Component | Environment Variable | Default | Purpose |
|-----------|---------------------|---------|---------|
| All | `GOMEMLIMIT` | Calculated | Go memory limit |
| Distributor | `JAEGER_AGENT_HOST` | - | Tracing endpoint |
| Ingester | `LOKI_WAL_DIR` | `/tmp/wal` | WAL directory |
| Querier | `LOKI_QUERY_TIMEOUT` | `1m` | Query timeout |

### Vector Collector

| Environment Variable | Default | Purpose |
|---------------------|---------|---------|
| `VECTOR_CONFIG` | `/etc/vector/vector.toml` | Configuration file |
| `VECTOR_LOG` | `info` | Log level |
| `VECTOR_REQUIRE_HEALTHY` | `true` | Health check requirement |

## Labels and Annotations

### Standard Labels

```yaml
metadata:
  labels:
    app.kubernetes.io/name: string
    app.kubernetes.io/instance: string
    app.kubernetes.io/version: string
    app.kubernetes.io/component: string
    app.kubernetes.io/part-of: openshift-logging
    app.kubernetes.io/managed-by: loki-operator
```

### ArgoCD Annotations

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"
    argocd.argoproj.io/sync-options: "SkipDryRunOnMissingResource=true"
    argocd.argoproj.io/compare-options: "ServerSideDiff=true"
```

This reference covers all major configuration options for the OpenShift logging operators used in this GitOps deployment. For the most up-to-date API specifications, consult the official operator documentation.
