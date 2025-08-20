# Contributing Scripts to OpenShift Logging GitOps

This guide helps contributors create new scripts that follow the established patterns and conventions in this project.

## Overview

This project uses modular scripts to implement the [Hybrid Deployment Strategy (ADR-0009)](../../adrs/adr-0009-hybrid-deployment-strategy.md). Each script handles a specific phase of the deployment process and follows consistent patterns for reliability and maintainability.

## Script Structure and Conventions

### 1. File Naming Convention

Scripts should follow the pattern: `[phase]-[purpose].sh`

Examples:
- `01-bootstrap-aws.sh` - Phase 1b: AWS resource creation
- `02-setup-tls.sh` - Phase 1c: TLS configuration
- `03-register-apps.sh` - Phase 2: Application registration

### 2. Script Header Template

Every script should start with this header structure:

```bash
#!/bin/bash

# [Script Title]
# Implements [ADR Reference] - [Phase Description]
# [Brief description of what this script replaces or improves]
#
# Usage: ./scripts/[script-name].sh [arguments] [options]
# Example: ./scripts/[script-name].sh dev --region us-east-2
#
# This script [high-level description]:
# 1. [Step 1 description]
# 2. [Step 2 description]
# 3. [Step 3 description]
#
# [Reference to what this replaces, if applicable]

set -euo pipefail
```

### 3. Standard Variables and Functions

Include these standard elements in every script:

```bash
# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}
```

### 4. Argument Parsing Pattern

Use consistent argument parsing:

```bash
# Default values
DEFAULT_ENVIRONMENT="dev"
DEFAULT_REGION="us-east-1"
DRY_RUN=false

# Parse arguments
ENVIRONMENT="${1:-$DEFAULT_ENVIRONMENT}"
REGION="$DEFAULT_REGION"

shift || true  # Remove first argument if it exists

while [[ $# -gt 0 ]]; do
    case $1 in
        --region|-r)
            REGION="$2"
            if [ -z "$REGION" ]; then
                echo -e "${RED}[ERROR]${NC} --region requires a value"
                exit 1
            fi
            shift 2
            ;;
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done
```

### 5. Help Function

Include a comprehensive help function:

```bash
show_help() {
    cat << EOF
${BLUE}[Script Title]${NC}

${GREEN}DESCRIPTION:${NC}
  [Detailed description of what the script does]

${GREEN}USAGE:${NC}
  ./scripts/[script-name].sh [ENVIRONMENT] [OPTIONS]

${GREEN}ENVIRONMENTS:${NC}
  dev         Development environment
  staging     Staging environment  
  production  Production environment

${GREEN}OPTIONS:${NC}
  --region, -r    AWS region (default: us-east-1)
  --dry-run, -n   Show commands without executing them
  --help, -h      Show this help message

${GREEN}WHAT THIS SCRIPT DOES:${NC}
  1. [Step 1 with emoji] Description
  2. [Step 2 with emoji] Description
  3. [Step 3 with emoji] Description

${GREEN}PREREQUISITES:${NC}
  - [Prerequisite 1]
  - [Prerequisite 2]

${GREEN}NEXT STEPS:${NC}
  After this script completes, run:
  ./scripts/[next-script].sh [environment] [options]

${GREEN}DOCUMENTATION:${NC}
  See docs/adrs/[relevant-adr].md
EOF
}
```

### 6. Banner Function

Create an informative banner:

```bash
show_banner() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          [Script Purpose]                        ║${NC}"
    echo -e "${BLUE}║         Phase [X]: [Description]                 ║${NC}"
    echo -e "${BLUE}║                                                   ║${NC}"
    echo -e "${BLUE}║   Environment: $(printf '%-10s' "$ENVIRONMENT")                       ║${NC}"
    echo -e "${BLUE}║   Region: $(printf '%-15s' "$REGION")                    ║${NC}"
    echo -e "${BLUE}║   Step: [X] of [Y] ([Phase Description])         ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}"
}
```

## LokiStack Storage Configuration

When creating scripts that configure LokiStack storage, reference the official Red Hat documentation:

**📚 Reference Documentation:**
[Configuring LokiStack Storage - Red Hat OpenShift Logging 6.3](https://docs.redhat.com/en/documentation/red_hat_openshift_logging/6.3/html/configuring_logging/configuring-lokistack-storage)

### Secret Creation Standards

When creating storage secrets for LokiStack, use this exact format:

```bash
oc create secret generic logging-loki-aws \
    --from-literal=bucketnames="<bucket_name>" \
    --from-literal=endpoint="<aws_bucket_endpoint>" \
    --from-literal=access_key_id="<aws_access_key_id>" \
    --from-literal=access_key_secret="<aws_access_key_secret>" \
    --from-literal=region="<aws_region_of_your_bucket>" \
    --from-literal=forcepathstyle="false" \
    -n openshift-logging
```

**Important Notes:**
- Secret name must be `logging-loki-aws`
- For AWS endpoints (`.amazonaws.com`), set `forcepathstyle="false"`
- For non-AWS S3 services, set `forcepathstyle="true"`
- Always create in `openshift-logging` namespace

### LokiStack Configuration

Ensure your script creates secrets that match the LokiStack configuration:

```yaml
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: logging-loki
  namespace: openshift-logging
spec:
  storage:
    secret:
      name: logging-loki-aws  # Must match secret name
      type: s3
```

## Script Development Checklist

### ✅ Before You Start
- [ ] Read the relevant ADR documentation
- [ ] Understand the phase this script implements
- [ ] Review existing scripts for patterns
- [ ] Check Red Hat documentation for configuration requirements

### ✅ Script Implementation
- [ ] Follow the file naming convention
- [ ] Include proper script header with ADR reference
- [ ] Implement standard logging functions
- [ ] Add comprehensive argument parsing
- [ ] Include help function with examples
- [ ] Add prerequisite verification
- [ ] Implement dry-run support
- [ ] Add progress banners and status messages
- [ ] Include error handling and cleanup

### ✅ Secret and Configuration Management
- [ ] Use consistent secret naming (`logging-loki-aws`)
- [ ] Include all required secret fields
- [ ] Set correct `forcepathstyle` value
- [ ] Update corresponding YAML manifests
- [ ] Test with both direct secrets and External Secrets

### ✅ Integration and Testing
- [ ] Ensure script works with existing bootstrap flow
- [ ] Test dry-run functionality
- [ ] Verify prerequisite checks work correctly
- [ ] Test error scenarios and cleanup
- [ ] Update main bootstrap script if needed

### ✅ Documentation
- [ ] Update this guide if adding new patterns
- [ ] Add script to README.md
- [ ] Reference relevant ADRs
- [ ] Include usage examples

## Supported Storage Provider Scripts

Since we already have AWS S3 support (`01-bootstrap-aws.sh`), contributors can create scripts for these other supported storage providers:

### Google Cloud Storage (GCS)
**Script**: `scripts/01-bootstrap-gcs.sh`
**Secret Format**:
```bash
oc create secret generic logging-loki-gcs \
    --from-literal=bucketname="<bucket_name>" \
    --from-literal=key.json="<service_account_json>" \
    -n openshift-logging
```
**LokiStack Type**: `gcs`

### Microsoft Azure Blob Storage
**Script**: `scripts/01-bootstrap-azure.sh`
**Secret Format**:
```bash
oc create secret generic logging-loki-azure \
    --from-literal=container="<container_name>" \
    --from-literal=account_name="<storage_account_name>" \
    --from-literal=account_key="<storage_account_key>" \
    -n openshift-logging
```
**LokiStack Type**: `azure`

### OpenStack Swift
**Script**: `scripts/01-bootstrap-swift.sh`
**Secret Format**:
```bash
oc create secret generic logging-loki-swift \
    --from-literal=auth_url="<keystone_auth_url>" \
    --from-literal=username="<username>" \
    --from-literal=user_domain_name="<user_domain_name>" \
    --from-literal=user_domain_id="<user_domain_id>" \
    --from-literal=user_id="<user_id>" \
    --from-literal=password="<password>" \
    --from-literal=domain_id="<domain_id>" \
    --from-literal=domain_name="<domain_name>" \
    --from-literal=container_name="<container_name>" \
    -n openshift-logging
```
**LokiStack Type**: `swift`

### Alibaba Cloud OSS
**Script**: `scripts/01-bootstrap-alibabacloud.sh`
**Secret Format**:
```bash
oc create secret generic logging-loki-alibabacloud \
    --from-literal=bucket="<bucket_name>" \
    --from-literal=endpoint="<oss_endpoint>" \
    --from-literal=access_key_id="<access_key_id>" \
    --from-literal=secret_access_key="<secret_access_key>" \
    -n openshift-logging
```
**LokiStack Type**: `alibabacloud`

### Example: Creating a Google Cloud Storage Script

1. **Create the script**: `scripts/01-bootstrap-gcs.sh`
2. **Follow the header template** with GCS-specific information
3. **Implement GCS bucket creation and service account setup**
4. **Create the secret** with GCS-specific parameters (see format above)
5. **Update LokiStack configuration** to reference the new secret:
   ```yaml
   spec:
     storage:
       secret:
         name: logging-loki-gcs
         type: gcs
   ```
6. **Update External Secrets templates** if using External Secrets Operator

## Common Pitfalls to Avoid

### ❌ Don't Do This
- Hard-code values that should be configurable
- Skip prerequisite verification
- Forget to implement dry-run support
- Use inconsistent secret naming
- Miss the `forcepathstyle` parameter
- Create secrets in wrong namespace

### ✅ Do This Instead
- Use environment variables and arguments
- Verify all prerequisites before starting
- Support `--dry-run` flag for testing
- Use standard secret name `logging-loki-aws`
- Always include `forcepathstyle` with correct value
- Create secrets in `openshift-logging` namespace

## Getting Help

- **ADR Documentation**: See `docs/adrs/` for architectural decisions
- **Red Hat Docs**: [LokiStack Configuration Guide](https://docs.redhat.com/en/documentation/red_hat_openshift_logging/6.3/html/configuring_logging/configuring-lokistack-storage)
- **Existing Scripts**: Review `scripts/01-bootstrap-aws.sh` as a reference
- **Issues**: Open a GitHub issue for questions or problems

## Contributing Your Script

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/add-[provider]-support`
3. **Follow this guide** to create your script
4. **Test thoroughly** in dev environment
5. **Update documentation** as needed
6. **Submit a pull request** with detailed description

Remember: Every script should be production-ready, well-documented, and follow the established patterns for consistency and maintainability.
