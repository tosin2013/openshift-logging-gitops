# OpenShift Logging Documentation

Welcome to the comprehensive documentation for deploying OpenShift logging infrastructure using Loki and GitOps principles. This documentation follows the [Diátaxis framework](https://diataxis.fr/) to provide clear, audience-specific guidance.

## Documentation Structure

### 📚 For End Users
Learn how to deploy and use the OpenShift logging system.

#### Tutorials
- **[Getting Started with OpenShift Logging Deployment](tutorials/getting-started-with-logging.md)** - Complete walkthrough for deploying Loki-based logging on OpenShift 4.18+ using ArgoCD

#### How-To Guides
- **[Troubleshooting Deployment Issues](how-to-guides/debug-application-issues.md)** - Diagnose and resolve common deployment problems

### 🔧 For Developers  
Technical guides for developing and maintaining the logging infrastructure.

#### How-To Guides
- **[Deploy with GitOps](how-to-guides/developer/deploy-with-gitops.md)** - Deploy and manage logging components using ArgoCD and GitOps workflows

#### Reference
- **[Operator Configuration Reference](reference/operators.md)** - Complete API specifications and configuration options for all logging operators

### 🏗️ For Architects
Understand the design principles and architectural decisions.

#### Explanations
- **[Architecture Overview](explanations/architecture-overview.md)** - Comprehensive explanation of the Loki-based logging architecture and design decisions

## Quick Start

1. **For Platform Administrators**: Start with the [Getting Started tutorial](tutorials/getting-started-with-logging.md)
2. **For Developers**: Jump to [GitOps deployment guide](how-to-guides/developer/deploy-with-gitops.md)  
3. **For Troubleshooting**: Use the [troubleshooting guide](how-to-guides/debug-application-issues.md)

## Architecture at a Glance

This deployment implements a modern, cloud-native logging stack:

- **Loki**: Cloud-native log aggregation with object storage
- **Vector**: High-performance log collection
- **ArgoCD**: GitOps-driven deployment and management
- **External Secrets Operator**: Secure credential management
- **S3**: Cost-effective log storage backend

## Key Benefits

✅ **Cost-Effective**: S3 object storage reduces operational costs by 60-80%  
✅ **Scalable**: Horizontally scalable architecture handles enterprise workloads  
✅ **Secure**: External Secrets Operator manages credentials securely  
✅ **GitOps-Native**: All configurations managed through Git workflows  
✅ **OpenShift-Integrated**: Native integration with OpenShift Console  

## Documentation Standards

This documentation follows strict audience separation:

- **End Users**: Focus on using and deploying the system
- **Developers**: Technical implementation and maintenance
- **Architects**: Design principles and architectural understanding

Each section is self-contained while linking to related information in other sections.

## Architecture Decision Records (ADRs)

The design decisions for this logging infrastructure are documented in our ADRs:

- **[ADR-0001](../docs/adrs/0001-adopt-loki-for-log-aggregation.md)**: Adopt Loki for Log Aggregation
- **[ADR-0002](../docs/adrs/0002-gitops-configuration-management.md)**: GitOps Configuration Management  
- **[ADR-0003](../docs/adrs/0003-s3-object-storage-for-logs.md)**: S3 Object Storage for Logs
- **[ADR-0004](../docs/adrs/0004-external-secrets-for-credential-management.md)**: External Secrets for Credential Management
- **[ADR-0005](../docs/adrs/0005-multi-environment-deployment-strategy.md)**: Multi-Environment Deployment Strategy
- **[ADR-0006](../docs/adrs/0006-resource-sizing-and-scaling-strategy.md)**: Resource Sizing and Scaling Strategy
- **[ADR-0007](../docs/adrs/0007-monitoring-and-alerting-strategy.md)**: Monitoring and Alerting Strategy

## Implementation Tasks

The deployment is guided by a comprehensive [TODO list](../TODO.md) with 57 tasks organized by priority and dependencies. This ensures systematic implementation following the architectural decisions.

## Getting Help

- **General Questions**: Refer to the appropriate documentation section above
- **Deployment Issues**: Use the [troubleshooting guide](how-to-guides/debug-application-issues.md)
- **Architecture Questions**: Review the [ADRs](../docs/adrs/) and [architecture overview](explanations/architecture-overview.md)
- **Configuration Reference**: Check the [operator reference](reference/operators.md)

## Contributing

All infrastructure changes follow GitOps principles:

1. Create feature branch
2. Update configurations 
3. Submit pull request
4. ArgoCD automatically deploys approved changes

See the [GitOps deployment guide](how-to-guides/developer/deploy-with-gitops.md) for detailed contribution workflows.

---

**Last Updated**: August 2025  
**OpenShift Version**: 4.18+  
**Loki Operator Version**: v5.9.6  
**Documentation Framework**: [Diátaxis](https://diataxis.fr/)
