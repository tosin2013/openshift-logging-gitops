# ADR-0003: Object Storage Selection for Log Retention

## Status
Accepted

## Context
Persistent log storage is required for compliance, troubleshooting, and analytics. The Loki Operator supports various object storage backends, including AWS S3, Google Cloud Storage, and on-premises solutions like MinIO. The choice of backend impacts cost, scalability, and integration complexity.

## Decision
Standardize on S3-compatible object storage for Loki log retention. Prefer AWS S3 in cloud environments and MinIO for on-premises or disconnected clusters. Ensure all configurations use the S3 API for maximum portability.

**Implementation Details**: Create Kubernetes Secrets in the openshift-logging namespace with required keys: access_key_id, access_key_secret, bucketnames, endpoint, and region. Configure LokiStack CR with spec.storage section referencing the secret and appropriate storageClassName for ephemeral storage.

**Multi-Tiered Retention Strategy**: Implement a two-layer approach combining Loki's internal retention (managed by the Compactor with configurable retention_period and retention_stream policies) with S3 Lifecycle Policies for automated archival to cheaper storage classes (e.g., Glacier Deep Archive) and compliance-driven expiration.

## Storage Architecture

```mermaid
graph TB
    subgraph "Loki Components"
        I[Ingester] --> |writes chunks| S3
        C[Compactor] --> |manages retention| S3
        Q[Querier] --> |reads chunks| S3
    end
    
    subgraph "S3 Storage Tiers"
        S3[S3 Standard<br/>Hot Data<br/>0-90 days]
        IA[S3 Infrequent Access<br/>Warm Data<br/>90-365 days]
        GL[S3 Glacier<br/>Cold Archive<br/>1-7 years]
        GDA[S3 Glacier Deep Archive<br/>Compliance Archive<br/>7+ years]
    end
    
    subgraph "Retention Policies"
        subgraph "Layer 1: Loki Compactor"
            LP[retention_period: 90d<br/>Global retention]
            LS[retention_stream:<br/>Production: 90d<br/>Development: 7d<br/>Audit: 365d]
        end
        
        subgraph "Layer 2: S3 Lifecycle"
            T1[Transition Rule<br/>→ IA after 90d]
            T2[Transition Rule<br/>→ Glacier after 365d]
            T3[Transition Rule<br/>→ Deep Archive after 2y]
            E1[Expiration Rule<br/>Delete after 7y]
        end
    end
    
    S3 --> |after 90 days| IA
    IA --> |after 1 year| GL
    GL --> |after 2 years| GDA
    GDA --> |after 7 years| X[Deleted]
    
    C -.->|enforces| LP
    C -.->|enforces| LS
    S3 -.->|managed by| T1
    IA -.->|managed by| T2
    GL -.->|managed by| T3
    GDA -.->|managed by| E1
    
    style S3 fill:#e8f5e8
    style IA fill:#fff3e0
    style GL fill:#e3f2fd
    style GDA fill:#f3e5f5
    style X fill:#ffebee
```

## Consequences
- Enables scalable, cost-effective log retention
- Simplifies migration between cloud and on-premises
- Introduces dependency on S3 API compatibility
- Requires secure management of storage credentials

## Alternatives Considered
- Use block storage (PVCs) for log retention
- Use vendor-specific APIs

## Supporting Evidence
- Loki documentation: object storage backends
- OpenShift docs: storage best practices
- research.md: storage comparison and benchmarks

## References
- [Loki Storage Backends](https://grafana.com/docs/loki/latest/storage/)
- [MinIO Documentation](https://min.io/docs/minio/linux/index.html)
- [OpenShift Storage Docs](https://docs.openshift.com/container-platform/latest/storage/understanding-persistent-storage.html)
