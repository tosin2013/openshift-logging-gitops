# ADR-0002: Declarative GitOps-Driven Configuration Management

## Status
Accepted (Updated by ADR-0008)

## Context
The project requires consistent, auditable, and scalable management of infrastructure and application configuration across multiple environments. The Product Requirements Document (PRD.md) specifies GitOps and Kustomize as core strategies. The current structure uses ArgoCD and Kustomize overlays for declarative configuration, enabling version-controlled, repeatable deployments.

## Decision
Adopt GitOps as the primary configuration management approach, using ArgoCD for continuous delivery and Kustomize overlays for environment-specific configuration. All changes are managed via version control and applied declaratively, ensuring that the desired state is always reflected in the cluster.

**Advanced Deployment Patterns**: Implement ArgoCD Sync Waves and Hooks to solve operator race conditions. Use a three-stage deployment process: (1) Operator Subscription (wave 0), (2) Readiness Check Job (wave 1), (3) Custom Resources (wave 2). This ensures operators are fully installed before their CRDs are applied.

**Multi-Cluster Management**: Use ArgoCD ApplicationSets with Cluster generators for automated deployment across multiple clusters, enabling policy-driven rollouts based on cluster labels and placement policies.

## GitOps Workflow

```mermaid
graph TD
    subgraph "Git Repository"
        G[Git Repository<br/>openshift-logging-gitops]
        
        subgraph "Structure"
            B[base/<br/>Common Configs]
            O[overlays/<br/>Environment Specific]
            A[apps/<br/>ArgoCD Applications]
        end
        
        G --> B
        G --> O
        G --> A
    end
    
    subgraph "ArgoCD Deployment Process"
        AS[ApplicationSet<br/>Multi-Cluster Generator]
        APP[ArgoCD Application<br/>Per Environment]
        
        subgraph "Sync Waves"
            W0[Wave 0:<br/>Subscriptions]
            W1[Wave 1:<br/>Readiness Checks]
            W2[Wave 2:<br/>Custom Resources]
        end
    end
    
    subgraph "OpenShift Clusters"
        subgraph "Development"
            DEV[Dev Cluster<br/>Overlay: dev]
        end
        
        subgraph "Staging"
            STAGE[Staging Cluster<br/>Overlay: staging]
        end
        
        subgraph "Production"
            PROD[Production Cluster<br/>Overlay: production]
        end
    end
    
    G --> AS
    AS --> APP
    APP --> W0
    W0 --> W1
    W1 --> W2
    
    W2 --> DEV
    W2 --> STAGE
    W2 --> PROD
    
    style W0 fill:#ffebee
    style W1 fill:#fff3e0
    style W2 fill:#e8f5e8
    style DEV fill:#e3f2fd
    style STAGE fill:#fff8e1
    style PROD fill:#fce4ec
```

## Consequences
- Ensures configuration consistency and auditability
- Enables safe, repeatable multi-environment deployments
- Requires team discipline and GitOps expertise
- Increases reliance on Git and ArgoCD availability

## Alternatives Considered
- Manual or imperative configuration management
- Non-GitOps tools or ad-hoc scripts

## Evidence
- PRD.md: GitOps and Kustomize strategy
- apps/, overlays/, and kustomization.yaml files: implementation evidence
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/en/stable/)
- [Kustomize Documentation](https://kubectl.docs.kubernetes.io/references/kustomize/)
