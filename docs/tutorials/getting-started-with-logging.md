# Deploying OpenShift Logging with GitOps

Welcome to the OpenShift Logging GitOps deployment guide! This tutorial will walk you through deploying a complete Loki-based logging infrastructure on OpenShift 4.18+ using our **Hybrid GitOps Strategy** (ADR-0009).

## What you'll accomplish

By the end of this tutorial, you'll have:
- A fully functional Loki-based logging stack deployed via ArgoCD
- External Secrets Operator managing S3 credentials securely
- Multi-environment configuration ready for dev/staging/production
- A production-ready deployment process with manual approval gates

## Prerequisites

- **OpenShift 4.18+ cluster** with cluster-admin access
- **AWS account** with permissions to create S3 buckets and IAM resources
- **Git repository access** (this repository)
- **Tools installed locally**:
  - OpenShift CLI (`oc`)
  - AWS CLI (`aws`)
  - JSON processor (`jq`)

## Architecture Overview

This deployment implements our Hybrid GitOps Strategy documented in ADR-0009:
- **Phase 1**: Scripts bootstrap AWS resources and initial secrets
- **Phase 2**: Manual verification and approval gates
- **Phase 3**: GitOps manages declarative infrastructure

Supporting ADRs:
- **ADR-0001**: Loki-centric architecture replacing EFK stack
- **ADR-0002**: GitOps-driven configuration management
- **ADR-0004**: External Secrets Operator for credential management
- **ADR-0009**: Hybrid deployment strategy for production
- **ADR-0018**: ClusterLogForwarder bearer token authentication

## 🚀 Quick Start (Recommended)

### Option 1: Stepped Deployment (Recommended for Production)

Our new stepped deployment approach provides better control and visibility:

```bash
# Phase 1a: Deploy operators
./scripts/00-setup-operators.sh

# Phase 1b: Create AWS resources  
./scripts/01-bootstrap-aws.sh dev --region us-east-2

# Phase 1c: SKIP TLS setup (deprecated - handled in templates)
# ./scripts/02-setup-tls.sh  ← NOT NEEDED

# Phase 1d: Register ArgoCD applications
./scripts/03-register-apps.sh dev

# Phase 3: Trigger GitOps sync
./scripts/04-trigger-sync.sh dev
```

### Option 2: Monolithic Bootstrap (Legacy)

For users preferring the original approach:

```bash
# Bootstrap development environment with preview
./scripts/bootstrap-environment.sh dev --dry-run

# Run actual bootstrap
./scripts/bootstrap-environment.sh dev

# After manual verification, deploy via GitOps
./scripts/trigger-gitops-sync.sh dev
```

### Production Environment
```bash
# Bootstrap production environment with preview
./scripts/bootstrap-environment.sh production --dry-run

# Run actual bootstrap
./scripts/bootstrap-environment.sh production

# Manual verification and approval (required)
# Then controlled GitOps deployment
./scripts/trigger-gitops-sync.sh production
```

### Get Help
```bash
# See all available options and environments
./scripts/bootstrap-environment.sh --help
```

**Bootstrap Script Features**:
- ✅ **Prerequisite validation**: Checks tools and credentials
- ✅ **Environment awareness**: dev, staging, production configurations
- ✅ **Dry-run mode**: Preview all commands before execution
- ✅ **AWS resource creation**: S3 buckets and IAM policies
- ✅ **ArgoCD integration**: Registers applications without auto-sync
- ⏸️ **Manual verification gates**: Pauses for security review
- 🎯 **GitOps preparation**: Ready for Phase 3 deployment

---

## 📋 Detailed Step-by-Step Guide

If you prefer to understand each step or need to customize the deployment, follow this detailed guide. The bootstrap script automates most of these steps, but understanding them helps with troubleshooting and customization.

## Step 1: Verify Prerequisites

The bootstrap script validates these automatically, but you can verify manually:

### Required Tools
```bash
# Check OpenShift CLI (4.x required)
oc version --client

# Check AWS CLI (2.x recommended)  
aws --version

# Check JSON processor
jq --version
```

### Cluster Access
```bash
# Login to OpenShift cluster
oc login --token=<your-token> --server=<your-server>

# Verify cluster access and permissions
oc whoami
oc auth can-i create namespace
```

### AWS Access
```bash
# Configure AWS credentials (if not using instance profiles)
aws configure

# Verify AWS access and permissions
aws sts get-caller-identity
aws s3 ls  # Should not error (empty list OK)
```

## Step 2: Environment Configuration

Our deployment supports three environments with different configurations:

| Environment | Region | Retention | S3 Bucket Suffix | Use Case |
|-------------|--------|-----------|------------------|----------|
| **dev** | us-east-1 | 7 days | `-dev-logging-loki` | Development/testing |
| **staging** | us-east-1 | 30 days | `-staging-logging-loki` | Pre-production validation |
| **production** | us-west-2 | 90 days | `-prod-logging-loki` | Production workloads |

### Understanding the Bootstrap Process

The bootstrap script follows our Hybrid GitOps Strategy (ADR-0009):

**Phase 1: Bootstrap (Automated)**
- Creates AWS S3 bucket with proper naming
- Sets up IAM user and policies for Loki access  
- Stores credentials in AWS Secrets Manager
- Configures External Secrets Operator
- Registers ArgoCD applications (without auto-sync)

**Phase 2: Manual Verification (Required)**
- Review AWS resources created
- Validate External Secrets synchronization
- Verify ArgoCD application registration
- Security and compliance checks

**Phase 3: GitOps Deployment (Controlled)**
- Trigger ArgoCD synchronization
- Monitor deployment progress
- Validate logging stack health
```

### Verify OpenShift GitOps
```bash
# Check if GitOps is already installed
oc get operators | grep gitops

# If not installed, install it:
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# Wait for installation
oc get pods -n openshift-gitops
```

## Step 2: Choose Your Deployment Path

## Step 3: Run Bootstrap Script

### Using the Bootstrap Script

The recommended approach is to use our bootstrap script, which automates the entire Phase 1 setup:

```bash
# See all available options
./scripts/bootstrap-environment.sh --help

# Preview what will be done (highly recommended)
./scripts/bootstrap-environment.sh dev --dry-run

# Execute the bootstrap for development
./scripts/bootstrap-environment.sh dev
```

**What the script does for you**:
1. ✅ Validates all prerequisites and tools
2. ✅ Creates environment-specific AWS S3 bucket
3. ✅ Sets up IAM user and policies for Loki access
4. ✅ Stores credentials in AWS Secrets Manager  
5. ✅ Configures External Secrets Operator
6. ✅ Registers ArgoCD applications (without auto-sync)
7. ⏸️ Pauses for your manual verification
8. 🎯 Prepares for GitOps deployment

### Manual Verification Phase

After the bootstrap script completes, it will pause and prompt you to verify:

1. **AWS Resources Created**
   ```bash
   # Verify S3 bucket exists
   aws s3 ls | grep logging-loki
   
   # Check IAM user
   aws iam get-user --user-name loki-s3-user
   
   # Verify secret in Secrets Manager
   aws secretsmanager describe-secret --secret-id openshift-logging-s3-credentials
   ```

2. **External Secrets Synchronization**
   ```bash
   # Check External Secret status
   oc get externalsecret -n openshift-logging
   
   # Verify the secret was created
   oc get secret loki-s3-credentials -n openshift-logging
   ```

3. **ArgoCD Application Registration**
   ```bash
   # List ArgoCD applications
   oc get application -n openshift-gitops
   
   # Check specific application status
   oc get application logging-stack-dev -n openshift-gitops -o yaml
   ```

---

## 🎯 Phase 3: GitOps Deployment

After bootstrap and manual verification, deploy the logging stack via GitOps:

### Automated Deployment
```bash
# Trigger GitOps sync for your environment
./scripts/trigger-gitops-sync.sh dev        # Development
./scripts/trigger-gitops-sync.sh staging    # Staging  
./scripts/trigger-gitops-sync.sh production # Production
```

### Manual ArgoCD Deployment (Production Recommended)

1. **Access ArgoCD UI**
   ```bash
   # Get ArgoCD URL
   oc get route argocd-server -n openshift-gitops -o jsonpath='{.spec.host}'
   
   # Get admin password
   oc get secret argocd-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d
   ```

2. **Navigate to your application**
   - Find application: `logging-stack-{environment}`
   - Review configuration differences
   - Click **SYNC** to deploy

3. **Monitor deployment progress**
   - Watch sync status in ArgoCD UI
   - Monitor resource creation
   - Verify health status

### Validation Steps

After deployment, verify the logging stack:

```bash
# Check ArgoCD application status
oc get application logging-stack-dev -n openshift-gitops

# Verify External Secrets are synced
oc get externalsecret -n openshift-logging

# Check LokiStack deployment
oc get lokistack -n openshift-logging

# Verify Loki pods are running
oc get pods -n openshift-logging -l app.kubernetes.io/name=loki

# Test log collection (if ClusterLogging deployed)
oc get pods -n openshift-logging -l app.kubernetes.io/name=vector
```

---

## 🔧 Manual Step-by-Step (Alternative)

If you prefer full control over each step, follow this detailed manual process:

## Step 3: Create AWS Resources (Manual)

Configure object storage for Loki as defined in ADR-0003.

1. **Create S3 bucket** (via AWS Console or CLI)
   - Bucket name: `my-cluster-logging-loki`
   - Region: `us-east-1` (or your preferred region)
   - Enable versioning and encryption

2. **Create IAM user for Loki access**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "s3:GetObject",
           "s3:PutObject",
           "s3:DeleteObject",
           "s3:ListBucket"
         ],
         "Resource": [
           "arn:aws:s3:::my-cluster-logging-loki",
           "arn:aws:s3:::my-cluster-logging-loki/*"
         ]
       }
     ]
   }
   ```

3. **Store credentials in AWS Secrets Manager**
   ```bash
   aws secretsmanager create-secret \
     --name openshift-logging-s3-credentials \
     --description "S3 credentials for OpenShift Loki" \
     --secret-string '{
       "access_key_id": "YOUR_ACCESS_KEY",
       "access_key_secret": "YOUR_SECRET_KEY",
       "bucketnames": "my-cluster-logging-loki",
       "endpoint": "s3.amazonaws.com",
       "region": "us-east-1"
     }'
   ```

## Step 3: Deploy External Secrets Operator

Implement secure credential management as defined in ADR-0004.

1. **Deploy External Secrets Operator**
   ```bash
   oc apply -f apps/applications/argocd-external-secrets-operator.yaml
   ```

2. **Wait for operator to be ready**
   ```bash
   oc get csv -n openshift-operators | grep external-secrets
   # Should show "Succeeded" phase
   ```

3. **Verify operator installation**
   ```bash
   oc get pods -n external-secrets-system
   # All pods should be Running
   ```

## Step 4: Configure Secret Management

Set up the External Secrets integration with AWS.

1. **Create AWS credentials secret for ESO**
   ```bash
   oc create secret generic aws-credentials \
     --from-literal=access-key-id=YOUR_ESO_ACCESS_KEY \
     --from-literal=secret-access-key=YOUR_ESO_SECRET_KEY \
     -n external-secrets-system
   ```

2. **Deploy SecretStore configuration**
   ```bash
   oc apply -f - <<EOF
   apiVersion: external-secrets.io/v1beta1
   kind: ClusterSecretStore
   metadata:
     name: aws-secrets-manager
   spec:
     provider:
       aws:
         service: SecretsManager
         region: us-east-1
         auth:
           secretRef:
             accessKeyIDSecretRef:
               name: aws-credentials
               key: access-key-id
               namespace: external-secrets-system
             secretAccessKeySecretRef:
               name: aws-credentials
               key: secret-access-key
               namespace: external-secrets-system
   EOF
   ```

3. **Deploy External Secrets instance**
   ```bash
   oc apply -f apps/applications/argocd-external-secrets-instance.yaml
   ```

## Step 5: Deploy Logging Operators

Deploy the core logging operators as defined in ADR-0001.

1. **Deploy Loki Operator**
   ```bash
   oc apply -f apps/applications/argocd-loki-operator.yaml
   ```

2. **Deploy Observability Operator** (for ClusterLogForwarder v1)
   ```bash
   oc apply -f apps/applications/argocd-observability-operator.yaml
   ```

4. **Monitor deployment progress**
   ```bash
   oc get applications -n openshift-gitops
   # All applications should show "Synced" and "Healthy"
   ```

## Step 6: Configure Loki Storage Integration

Set up S3 integration for Loki storage.

1. **Create ExternalSecret for S3 credentials**
   ```bash
   oc apply -f - <<EOF
   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   metadata:
     name: logging-loki-s3
     namespace: openshift-logging
   spec:
     refreshInterval: 15s
     secretStoreRef:
       name: aws-secrets-manager
       kind: ClusterSecretStore
     target:
       name: logging-loki-s3
       creationPolicy: Owner
     data:
     - secretKey: access_key_id
       remoteRef:
         key: openshift-logging-s3-credentials
         property: access_key_id
     - secretKey: access_key_secret
       remoteRef:
         key: openshift-logging-s3-credentials
         property: access_key_secret
     - secretKey: bucketnames
       remoteRef:
         key: openshift-logging-s3-credentials
         property: bucketnames
     - secretKey: endpoint
       remoteRef:
         key: openshift-logging-s3-credentials
         property: endpoint
     - secretKey: region
       remoteRef:
         key: openshift-logging-s3-credentials
         property: region
   EOF
   ```

2. **Verify secret creation**
   ```bash
   oc get secret logging-loki-s3 -n openshift-logging -o yaml
   ```

## Step 7: Deploy LokiStack

Create the Loki storage backend.

1. **Deploy LokiStack instance**
   ```bash
   oc apply -f - <<EOF
   apiVersion: loki.grafana.com/v1
   kind: LokiStack
   metadata:
     name: logging-loki
     namespace: openshift-logging
   spec:
     size: 1x.small
     storage:
       secret:
         name: logging-loki-s3
         type: s3
       storageClassName: gp3-csi
     tenants:
       mode: application
   EOF
   ```

2. **Monitor LokiStack deployment**
   ```bash
   oc get lokistack -n openshift-logging
   oc get pods -n openshift-logging
   ```

## Step 8: Configure Log Collection

Set up Vector log collection and forwarding.

1. **Deploy ClusterLogging instance**
   ```bash
   oc apply -f - <<EOF
   apiVersion: logging.coreos.com/v1
   kind: ClusterLogging
   metadata:
     name: instance
     namespace: openshift-logging
   spec:
     collection:
       type: vector
   EOF
   ```

2. **Deploy ClusterLogForwarder** (with bearer token authentication)
   ```bash
   oc apply -f - <<EOF
   apiVersion: observability.openshift.io/v1
   kind: ClusterLogForwarder
   metadata:
     name: instance
     namespace: openshift-logging
   spec:
     serviceAccount:
       name: logcollector
     outputs:
     - name: loki-app
       type: loki
       loki:
         url: https://logging-loki-gateway-http.openshift-logging.svc:8080/api/logs/v1/application
         authentication:
           token:
             from: secret
             secret:
               name: lokistack-gateway-bearer-token
               key: token
       tls:
         ca:
           key: ca-bundle.crt
           secretName: lokistack-gateway-bearer-token
         insecureSkipVerify: true  # For demo environments
     - name: loki-infra
       type: loki
       loki:
         url: https://logging-loki-gateway-http.openshift-logging.svc:8080/api/logs/v1/infrastructure
         authentication:
           token:
             from: secret
             secret:
               name: lokistack-gateway-bearer-token
               key: token
       tls:
         ca:
           key: ca-bundle.crt
           secretName: lokistack-gateway-bearer-token
         insecureSkipVerify: true  # For demo environments
     pipelines:
     - name: application-logs
       inputRefs:
       - application
       outputRefs:
       - loki-app
     - name: infrastructure-logs
       inputRefs:
       - infrastructure
       outputRefs:
       - loki-infra
   EOF
   ```

## Step 9: Verification and Testing

Verify the complete logging stack is operational.

1. **Check all components are running**
   ```bash
   # ArgoCD Applications
   oc get applications -n openshift-gitops
   
   # Loki components
   oc get pods -n openshift-logging
   
   # Log collection
   oc get pods -n openshift-logging | grep collector
   ```

2. **Test log ingestion**
   ```bash
   # Generate test logs
   oc run test-logger --image=busybox --restart=Never -- sh -c 'for i in $(seq 1 10); do echo "Test log message $i"; sleep 1; done'
   
   # Wait a few minutes, then check ArgoCD logs interface
   ```

3. **Access logging interface**
   - Open OpenShift Console
   - Navigate to Observe → Logs
   - Query logs with LogQL syntax

---

## 🎯 Complete Workflow Summary

Here's the complete workflow for reference:

### For Development Environment (Stepped Approach)
```bash
# 1. Deploy operators
./scripts/00-setup-operators.sh

# 2. Create AWS resources
./scripts/01-bootstrap-aws.sh dev --region us-east-2

# 3. SKIP TLS setup (deprecated - handled in ClusterLogForwarder templates)
# ./scripts/02-setup-tls.sh  ← NOT NEEDED

# 4. Register ArgoCD applications
./scripts/03-register-apps.sh dev

# 5. Deploy via GitOps
./scripts/04-trigger-sync.sh dev

# 6. Validate deployment
oc get pods -n openshift-logging
oc get application logging-forwarder-dev -n openshift-gitops
```

### For Production Environment (Stepped Approach)
```bash
# 1. Deploy operators
./scripts/00-setup-operators.sh

# 2. Create AWS resources
./scripts/01-bootstrap-aws.sh production --region us-west-2

# 3. SKIP TLS setup (deprecated - handled in ClusterLogForwarder templates)
# ./scripts/02-setup-tls.sh  ← NOT NEEDED

# 4. Register ArgoCD applications
./scripts/03-register-apps.sh production

# 5. Extended manual verification (required for production)
# - Security review of all created resources
# - Compliance validation 
# - Change approval process

# 6. Controlled GitOps deployment (manual ArgoCD preferred)
# Use ArgoCD UI for production deployments or:
./scripts/04-trigger-sync.sh production
```

## 🚀 Next Steps

After completing this tutorial, you'll have:
- ✅ A production-ready Loki-based logging infrastructure
- ✅ GitOps-managed configuration with environment separation
- ✅ Secure credential management via External Secrets
- ✅ Automated bootstrap process for new environments

### Recommended Follow-up Actions

1. **Configure Log Collection**
   - Deploy ClusterLogging operator
   - Configure log forwarding rules
   - Set up retention policies

2. **Set up Monitoring**
   - Create Loki alerts for storage/ingestion
   - Monitor S3 costs and usage
   - Set up ArgoCD sync alerts

3. **Document Your Customizations**
   - Update overlay configurations for your specific needs
   - Document any environment-specific changes
   - Create new ADRs for significant architectural decisions

## 📖 Additional Resources

- **Architecture Decisions**: [docs/adrs/](../adrs/)
- **Hybrid Strategy Deep Dive**: [docs/explanations/hybrid-deployment-strategy.md](../explanations/hybrid-deployment-strategy.md)
- **GitOps Architecture**: [docs/explanations/gitops-architecture.md](../explanations/gitops-architecture.md)
- **Troubleshooting Guide**: [docs/runbooks/troubleshooting.md](../runbooks/troubleshooting.md)

## 🤝 Contributing

Found an issue or have an improvement? Please see our [contributing guidelines](../../CONTRIBUTING.md) and submit a pull request!

---

*This tutorial implements the Hybrid GitOps Deployment Strategy documented in ADR-0009. For questions or support, please open an issue in this repository.*
   - Navigate to Observe → Logs
   - Query: `{namespace="default"} |= "Test log message"`

## What You've Accomplished

✅ **Infrastructure Deployment**: Complete Loki-based logging stack via GitOps  
✅ **Secure Credential Management**: External Secrets Operator with AWS integration  
✅ **Object Storage Integration**: S3-backed log retention and storage  
✅ **Multi-Component Architecture**: Loki, Vector, and Observability operators  
✅ **GitOps Workflow**: All configurations managed through ArgoCD  

## Next Steps

- **Multi-Environment Setup**: Configure dev/staging/production overlays
- **Performance Tuning**: Implement resource sizing from ADR-0006
- **Monitoring Setup**: Deploy operational monitoring from ADR-0007
- **SIEM Integration**: Configure external log forwarding

## Troubleshooting

**ArgoCD sync issues?**
- Check operator installation status: `oc get csv -A`
- Verify sync wave timing in ArgoCD UI
- Review application events: `oc describe application <app-name> -n openshift-gitops`

**Secret not created?**
- Verify External Secrets Operator is running
- Check SecretStore connection: `oc describe clustersecretstore aws-secrets-manager`
- Validate AWS credentials and permissions

**Loki pods not starting?**
- Check S3 secret exists: `oc get secret logging-loki-s3 -n openshift-logging`
- Verify S3 bucket permissions and connectivity
- Review LokiStack status: `oc describe lokistack logging-loki -n openshift-logging`

This deployment follows GitOps principles and the architectural decisions documented in our ADRs, ensuring a maintainable and scalable logging infrastructure.
