# ADR-0017: Stepped Deployment Scripts Architecture

## Status
Accepted

## Context

The original `bootstrap-environment.sh` script was monolithic and prone to failure at various points, making it difficult to debug and recover from issues. The script attempted to handle:

1. Operator deployment
2. AWS resource creation
3. External Secrets configuration
4. ArgoCD application registration
5. Initial secret creation

When any step failed, the entire process would halt, requiring manual intervention and making it difficult to resume from the failure point.

Additionally, our implementation of separated ArgoCD applications (logging-infrastructure-dev and logging-forwarder-dev) with health check integration required more sophisticated orchestration than the monolithic script could provide.

## Decision

We will refactor the monolithic bootstrap script into a stepped approach with focused, single-responsibility scripts:

### Phase 1: Bootstrap Scripts (Stepped Approach)

1. **00-setup-operators.sh** - Operator Deployment
   - Deploys External Secrets, Loki, and Logging operators
   - Waits for operators to be ready
   - Extracted from `bootstrap-environment.sh` lines 640-651

2. **01-bootstrap-aws.sh** - AWS Resource Creation
   - Creates S3 bucket, IAM user, and policies
   - Stores credentials in AWS Secrets Manager
   - Delegates to existing `setup-s3-storage.sh`
   - Extracted from `bootstrap-environment.sh` create_aws_resources()

3. **02-setup-tls.sh** - TLS Configuration (Future)
   - Implements ADR-0016 TLS options A and B
   - Configures certificate management
   - Prepares TLS configuration for overlays

4. **03-register-apps.sh** - ArgoCD Application Registration
   - Registers separated infrastructure and forwarder applications
   - Configures External Secrets Operator ClusterSecretStore
   - Extracted from `bootstrap-environment.sh` register_argocd_applications()

5. **04-trigger-sync.sh** - Enhanced GitOps Sync
   - Replaces and enhances existing `trigger-gitops-sync.sh`
   - Handles separated applications with health check integration
   - Orchestrates Wave 2 → Health Check → Wave 3 deployment

### Integration with Existing Scripts

The stepped approach reuses and integrates with existing specialized scripts:
- `setup-s3-storage.sh` - Called by 01-bootstrap-aws.sh
- `setup-external-secrets.sh` - Called by 03-register-apps.sh
- `create-clf-trust-bundle.sh` - Called by 02-setup-tls.sh (Option B)

### Backward Compatibility

The original `bootstrap-environment.sh` and `trigger-gitops-sync.sh` scripts remain available but are deprecated in favor of the stepped approach.

## Consequences

### Positive

1. **Improved Reliability**: Each script has a single responsibility and can be run independently
2. **Better Error Recovery**: Failed steps can be retried without rerunning the entire process
3. **Enhanced Debugging**: Issues can be isolated to specific phases
4. **Modular Testing**: Each script can be tested independently
5. **Clear Progress Tracking**: Users can see exactly which phase they're in
6. **Health Check Integration**: Proper orchestration of separated applications with health validation

### Negative

1. **More Scripts to Maintain**: Five scripts instead of one monolithic script
2. **Learning Curve**: Users need to understand the stepped approach
3. **Coordination Required**: Scripts must be run in the correct order

### Neutral

1. **Documentation Update Required**: ADR-0009 needs updates to reflect the stepped approach
2. **CI/CD Pipeline Updates**: Automation scripts may need updates to use the stepped approach

## Implementation

### Phase 1: Core Scripts (Completed)
- ✅ 00-setup-operators.sh
- ✅ 01-bootstrap-aws.sh  
- ⏳ 02-setup-tls.sh (planned)
- ✅ 03-register-apps.sh
- ✅ 04-trigger-sync.sh

### Phase 2: Integration Testing
- Test each script independently
- Test full workflow end-to-end
- Validate health check integration

### Phase 3: Documentation Updates
- Update ADR-0009 to reference stepped approach
- Create workflow documentation
- Update README with new process

## Usage

### Complete Workflow
```bash
# Phase 1a: Deploy operators
./scripts/00-setup-operators.sh

# Phase 1b: Create AWS resources  
./scripts/01-bootstrap-aws.sh dev --region us-east-2

# Phase 1c: Configure TLS (when available)
./scripts/02-setup-tls.sh dev --tls-option b

# Phase 1d: Register ArgoCD applications
./scripts/03-register-apps.sh dev

# Phase 2: Manual verification (per ADR-0009)
oc get applications -n openshift-gitops

# Phase 3: Trigger GitOps sync
./scripts/04-trigger-sync.sh dev
```

### Individual Script Recovery
```bash
# If operators fail, retry just that step
./scripts/00-setup-operators.sh

# If AWS resources fail, retry just that step
./scripts/01-bootstrap-aws.sh dev --region us-east-2
```

## Relationship to Other ADRs

- **ADR-0009**: Enhanced implementation of the 3-phase hybrid deployment strategy
- **ADR-0016**: TLS configuration integrated into 02-setup-tls.sh
- **Health Check Implementation**: Proper orchestration of separated applications

## Future Considerations

1. **CI/CD Integration**: Scripts designed for automation pipeline integration
2. **Multi-Environment Support**: Each script supports dev/staging/production
3. **Dry-Run Mode**: All scripts support --dry-run for testing
4. **Monitoring Integration**: Enhanced logging and progress tracking
