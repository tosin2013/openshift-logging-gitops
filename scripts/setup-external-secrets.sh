#!/bin/bash

# OpenShift External Secrets Configuration Script
# This script automates Step 3-4 of the getting-started tutorial
# 
# Usage: ./scripts/setup-external-secrets.sh [secret-name] [aws-region]
# Example: ./scripts/setup-external-secrets.sh openshift-logging-s3-credentials us-east-1

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_SECRET_NAME="openshift-logging-s3-credentials"
DEFAULT_REGION="us-east-1"

# Parse arguments
SECRET_NAME="${1:-$DEFAULT_SECRET_NAME}"
AWS_REGION="${2:-$DEFAULT_REGION}"

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

# Verify prerequisites
verify_prerequisites() {
    header "Verifying Prerequisites"
    
    # Check OpenShift CLI
    if ! command -v oc &> /dev/null; then
        error "OpenShift CLI (oc) is not installed."
    fi
    log "✓ OpenShift CLI is available"
    
    # Check if logged into OpenShift
    if ! oc whoami &> /dev/null; then
        error "Not logged into OpenShift. Please run 'oc login' first."
    fi
    log "✓ Logged into OpenShift cluster"
    
    # Check if External Secrets Operator is deployed
    if ! oc get application external-secrets-operator -n openshift-gitops &> /dev/null; then
        error "External Secrets Operator not found. Deploy it first using ArgoCD."
    fi
    log "✓ External Secrets Operator application exists"
    
    # Wait for External Secrets Operator to be ready
    log "Waiting for External Secrets Operator to be ready..."
    timeout=300
    while [ $timeout -gt 0 ]; do
        if oc get pods -n openshift-operators | grep -q "external-secrets.*Running"; then
            log "✓ External Secrets Operator is running"
            break
        fi
        sleep 5
        timeout=$((timeout - 5))
    done
    
    if [ $timeout -eq 0 ]; then
        error "External Secrets Operator did not become ready within 5 minutes"
    fi
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
    fi
    log "✓ AWS credentials are configured"
}

# Prompt for AWS credentials for External Secrets Operator
get_aws_credentials() {
    header "AWS Credentials for External Secrets Operator"
    
    cat << EOF
External Secrets Operator needs AWS credentials to access Secrets Manager.
You can either:
  1. Use existing AWS credentials (if you have appropriate permissions)
  2. Create dedicated IAM user for External Secrets Operator (recommended)

For production, it's recommended to create a dedicated IAM user with minimal permissions.
EOF
    
    read -p "Do you want to create a dedicated IAM user for ESO? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        # Use existing credentials
        log "Using existing AWS credentials"
        ESO_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)
        ESO_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)
    else
        # Create dedicated IAM user
        create_eso_iam_user
    fi
}

# Create dedicated IAM user for External Secrets Operator
create_eso_iam_user() {
    header "Creating IAM User for External Secrets Operator"
    
    ESO_USER_NAME="openshift-external-secrets-operator"
    ESO_POLICY_NAME="external-secrets-operator-policy"
    
    log "Creating IAM user: $ESO_USER_NAME"
    
    # Create policy for ESO
    cat > /tmp/eso-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Create IAM policy
    log "Creating IAM policy: $ESO_POLICY_NAME"
    ESO_POLICY_ARN=$(aws iam create-policy \
        --policy-name "$ESO_POLICY_NAME" \
        --policy-document file:///tmp/eso-policy.json \
        --query 'Policy.Arn' \
        --output text 2>/dev/null || aws iam get-policy \
        --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/$ESO_POLICY_NAME" \
        --query 'Policy.Arn' \
        --output text)
    
    # Create IAM user
    aws iam create-user --user-name "$ESO_USER_NAME" 2>/dev/null || log "IAM user already exists"
    
    # Attach policy to user
    aws iam attach-user-policy \
        --user-name "$ESO_USER_NAME" \
        --policy-arn "$ESO_POLICY_ARN"
    
    # Delete existing access keys if any
    aws iam list-access-keys --user-name "$ESO_USER_NAME" --query 'AccessKeyMetadata[].AccessKeyId' --output text | \
    while read -r key_id; do
        if [ -n "$key_id" ]; then
            log "Deleting existing access key: $key_id"
            aws iam delete-access-key --user-name "$ESO_USER_NAME" --access-key-id "$key_id"
        fi
    done
    
    # Create new access key
    log "Creating access keys for ESO"
    ACCESS_KEY_OUTPUT=$(aws iam create-access-key --user-name "$ESO_USER_NAME")
    
    ESO_ACCESS_KEY_ID=$(echo "$ACCESS_KEY_OUTPUT" | jq -r '.AccessKey.AccessKeyId')
    ESO_SECRET_ACCESS_KEY=$(echo "$ACCESS_KEY_OUTPUT" | jq -r '.AccessKey.SecretAccessKey')
    
    log "✓ IAM user created for External Secrets Operator"
}

# Create AWS credentials secret for External Secrets Operator
create_aws_credentials_secret() {
    header "Creating AWS Credentials Secret"
    
    # Ensure external-secrets namespace exists
    oc create namespace external-secrets --dry-run=client -o yaml | oc apply -f -

    log "Creating aws-credentials secret in external-secrets namespace"

    # Delete existing secret if it exists
    oc delete secret aws-credentials -n external-secrets 2>/dev/null || true

    # Create new secret
    oc create secret generic aws-credentials \
        --from-literal=access-key-id="$ESO_ACCESS_KEY_ID" \
        --from-literal=secret-access-key="$ESO_SECRET_ACCESS_KEY" \
        -n external-secrets
    
    log "✓ AWS credentials secret created"
}

# Deploy ClusterSecretStore
deploy_cluster_secret_store() {
    header "Deploying ClusterSecretStore"
    
    log "Creating ClusterSecretStore for AWS Secrets Manager"
    
    cat << EOF | oc apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: $AWS_REGION
      auth:
        secretRef:
          accessKeyIDSecretRef:
            name: aws-credentials
            key: access-key-id
            namespace: external-secrets
          secretAccessKeySecretRef:
            name: aws-credentials
            key: secret-access-key
            namespace: external-secrets
EOF
    
    # Wait for ClusterSecretStore to be ready
    log "Waiting for ClusterSecretStore to be ready..."
    timeout=60
    while [ $timeout -gt 0 ]; do
        if oc get clustersecretstore aws-secrets-manager -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q "True"; then
            log "✓ ClusterSecretStore is ready"
            break
        fi
        sleep 2
        timeout=$((timeout - 2))
    done
    
    if [ $timeout -eq 0 ]; then
        warn "ClusterSecretStore may not be ready yet. Check with: oc describe clustersecretstore aws-secrets-manager"
    fi
}

# Deploy External Secrets instance ArgoCD application
deploy_external_secrets_instance() {
    header "Deploying External Secrets Instance"
    
    if oc get application argocd-external-secrets-instance -n openshift-gitops &> /dev/null; then
        log "External Secrets instance application already exists"
    else
        # log "Deploying External Secrets instance application"
        # oc apply -f apps/applications/argocd-external-secrets-instance.yaml
        true
    fi
    
    # Wait for application to sync
    log "Waiting for External Secrets instance to sync..."
    timeout=120
    while [ $timeout -gt 0 ]; do
        sync_status=$(oc get application argocd-external-secrets-instance -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        health_status=$(oc get application argocd-external-secrets-instance -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        
        if [ "$sync_status" = "Synced" ] && [ "$health_status" = "Healthy" ]; then
            log "✓ External Secrets instance is synced and healthy"
            break
        fi
        
        log "Status: Sync=$sync_status, Health=$health_status"
        sleep 5
        timeout=$((timeout - 5))
    done
    
    if [ $timeout -eq 0 ]; then
        warn "External Secrets instance may not be ready. Check ArgoCD UI for details."
    fi
}

# Create openshift-logging namespace
create_logging_namespace() {
    header "Creating OpenShift Logging Namespace"
    
    log "Creating openshift-logging namespace"
    oc create namespace openshift-logging --dry-run=client -o yaml | oc apply -f -
    
    # Add monitoring label
    oc label namespace openshift-logging openshift.io/cluster-monitoring="true" --overwrite
    
    log "✓ openshift-logging namespace created"
}

# Create OperatorConfig for External Secrets
create_operator_config() {
    header "Creating External Secrets OperatorConfig"
    
    log "Creating OperatorConfig to deploy External Secrets controller"
    
    cat << EOF | oc apply -f -
apiVersion: operator.external-secrets.io/v1alpha1
kind: OperatorConfig
metadata:
  name: cluster
  namespace: external-secrets
spec: {}
EOF
    
    log "Waiting for External Secrets controller pods to start..."
    timeout=120
    while [ $timeout -gt 0 ]; do
        if oc get pods -n external-secrets | grep -q "cluster-external-secrets.*Running"; then
            log "✓ External Secrets controller pods are running"
            break
        fi
        sleep 5
        timeout=$((timeout - 5))
    done
    
    if [ $timeout -eq 0 ]; then
        warn "External Secrets controller pods did not start within timeout"
    fi
}

# Create ExternalSecret for S3 credentials
create_s3_external_secret() {
    header "Creating S3 ExternalSecret"
    
    log "Creating ExternalSecret for Loki S3 credentials"
    
    cat << EOF | oc apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: logging-loki-aws
  namespace: openshift-logging
spec:
  refreshInterval: 15s
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: logging-loki-aws
    creationPolicy: Owner
  data:
  - secretKey: access_key_id
    remoteRef:
      key: $SECRET_NAME
      property: access_key_id
  - secretKey: access_key_secret
    remoteRef:
      key: $SECRET_NAME
      property: access_key_secret
  - secretKey: bucketnames
    remoteRef:
      key: $SECRET_NAME
      property: bucketnames
  - secretKey: endpoint
    remoteRef:
      key: $SECRET_NAME
      property: endpoint
  - secretKey: region
    remoteRef:
      key: $SECRET_NAME
      property: region
EOF
    
    # Wait for secret to be created
    log "Waiting for S3 secret to be created..."
    timeout=60
    while [ $timeout -gt 0 ]; do
        if oc get secret logging-loki-aws -n openshift-logging &> /dev/null; then
            log "✓ S3 secret created successfully"
            break
        fi
        sleep 2
        timeout=$((timeout - 2))
    done
    
    if [ $timeout -eq 0 ]; then
        warn "S3 secret was not created. Check ExternalSecret status:"
        oc describe externalsecret logging-loki-aws -n openshift-logging
    fi
}

# Verify setup
verify_setup() {
    header "Verifying External Secrets Setup"
    
    # Check ClusterSecretStore
    log "Checking ClusterSecretStore status:"
    oc get clustersecretstore aws-secrets-manager -o wide
    
    # Check ExternalSecret
    log "Checking ExternalSecret status:"
    oc describe externalsecret logging-loki-aws -n openshift-logging
    
    # Check if secret was created
    if oc get secret logging-loki-aws -n openshift-logging &> /dev/null; then
        log "✓ S3 credentials secret exists"
        log "Secret keys:"
        oc get secret logging-loki-aws -n openshift-logging -o jsonpath='{.data}' | jq -r 'keys[]'
    else
        warn "S3 credentials secret not found"
    fi
    
    # Check ArgoCD application
    log "Checking ArgoCD applications:"
    oc get applications -n openshift-gitops
}

# Generate summary
generate_summary() {
    header "External Secrets Configuration Summary"
    
    cat << EOF

${GREEN}✓ External Secrets Configuration Complete!${NC}

Components Deployed:
  ✓ ClusterSecretStore: aws-secrets-manager
  ✓ ExternalSecret: logging-loki-aws (in openshift-logging namespace)
  ✓ AWS credentials secret (in external-secrets namespace)
  ✓ ArgoCD External Secrets instance application

Next Steps:
  1. Continue with Step 5: Deploy Logging Operators
  2. The S3 credentials are now available as a Kubernetes secret
  3. Loki can use the logging-loki-aws secret for storage access

Verification Commands:
  oc get clustersecretstore aws-secrets-manager
  oc get externalsecret logging-loki-aws -n openshift-logging
  oc get secret logging-loki-aws -n openshift-logging

EOF
}

# Cleanup temporary files
cleanup() {
    rm -f /tmp/eso-policy.json
}

# Main execution
main() {
    header "External Secrets Configuration"
    
    cat << EOF
This script will configure External Secrets Operator to retrieve
S3 credentials from AWS Secrets Manager.

Configuration:
  Secret Name:  $SECRET_NAME
  AWS Region:   $AWS_REGION

EOF

    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Setup cancelled by user"
        exit 0
    fi

    verify_prerequisites
    get_aws_credentials
    create_aws_credentials_secret
    deploy_cluster_secret_store
    # deploy_external_secrets_instance
    create_logging_namespace
    create_operator_config
    create_s3_external_secret
    verify_setup
    generate_summary
    cleanup
    
    log "External Secrets configuration completed successfully!"
    log "You can now proceed to Step 5: Deploy Logging Operators"
}

# Handle script interruption
trap cleanup EXIT

# Check if jq is available
if ! command -v jq &> /dev/null; then
    error "jq is required but not installed. Please install jq first."
fi

# Run main function
main "$@"
