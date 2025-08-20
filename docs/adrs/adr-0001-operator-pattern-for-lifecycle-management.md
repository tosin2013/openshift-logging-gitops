# ADR-0001: Operator Pattern for Lifecycle Management

## Status
Accepted

## Context
The project leverages Kubernetes Operators for managing the lifecycle of logging stack components. This includes the Loki Operator for log storage, the Cluster Logging Operator for log collection, and the Cluster Observability Operator for visualization. This modular approach is described in research.md and aligns with OpenShift best practices.

## Decision
Adopt the Operator pattern for all major logging stack components. Use the Loki Operator, Cluster Logging Operator, and Cluster Observability Operator to manage deployment, scaling, upgrades, and configuration via Custom Resources.

## Consequences
- Simplifies upgrades, scaling, and management
- Enables modular, independent evolution of stack components
- Increases dependency on operator health and compatibility
- Requires operator-specific knowledge and monitoring

## Alternatives Considered
- Manual management of components
- Helm charts or static manifests

## Supporting Evidence
- research.md: trio of operators and modular design
- YAML manifests: operator subscriptions and CRDs
- OpenShift documentation: operator best practices

## References
- [OpenShift Operator Framework](https://docs.openshift.com/container-platform/latest/operators/understanding/olm-what-operators-are.html)
- [Loki Operator GitHub](https://github.com/grafana/loki-operator)
- [Cluster Logging Operator](https://github.com/openshift/cluster-logging-operator)
- [Cluster Observability Operator](https://github.com/rhobs/observability-operator)
