#!/bin/bash

# OpenShift Logging S3 Storage Setup Script
# This script automates Step 2 of the getting-started tutorial
# 
# Usage: ./scripts/setup-s3-storage.sh [cluster-name] [aws-region]
# Example: ./scripts/setup-s3-storage.sh my-ocp-cluster us-east-1

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_CLUSTER_NAME="openshift-logging"
DEFAULT_REGION="us-east-1"
DEFAULT_RETENTION_DAYS="30"

# Parse arguments
CLUSTER_NAME="${1:-$DEFAULT_CLUSTER_NAME}"
AWS_REGION="${2:-$DEFAULT_REGION}"
RETENTION_DAYS="${3:-$DEFAULT_RETENTION_DAYS}"

# Generate unique names
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BUCKET_NAME="${CLUSTER_NAME}-loki-${TIMESTAMP}"
IAM_USER_NAME="${CLUSTER_NAME}-loki-user"
IAM_POLICY_NAME="${CLUSTER_NAME}-loki-policy"
SECRET_NAME="openshift-logging-s3-credentials"

# Logging function
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
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    log "✓ AWS CLI is available"
    
    # Check OpenShift CLI
    if ! command -v oc &> /dev/null; then
        error "OpenShift CLI (oc) is not installed. Please install it first."
    fi
    log "✓ OpenShift CLI is available"
    
    # Check if logged into OpenShift
    if ! oc whoami &> /dev/null; then
        error "Not logged into OpenShift. Please run 'oc login' first."
    fi
    log "✓ Logged into OpenShift cluster"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
    fi
    log "✓ AWS credentials are configured"
    
    # Display AWS identity
    AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    AWS_USER=$(aws sts get-caller-identity --query Arn --output text)
    log "AWS Account: $AWS_ACCOUNT"
    log "AWS Identity: $AWS_USER"
}

# Create S3 bucket with proper configuration
create_s3_bucket() {
    header "Creating S3 Bucket"
    
    log "Creating S3 bucket: $BUCKET_NAME in region: $AWS_REGION"
    
    # Create bucket
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$AWS_REGION"
    else
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    # Enable versioning
    log "Enabling versioning on bucket"
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    # Enable default encryption
    log "Enabling default encryption"
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }
            ]
        }'
    
    # Set lifecycle policy for cost optimization
    log "Setting lifecycle policy for cost optimization"
    
    # Create lifecycle policy based on retention days
    if [ "$RETENTION_DAYS" -le 30 ]; then
        # For short retention (≤30 days), only set expiration, no transitions
        cat > /tmp/lifecycle-policy.json << EOF
{
    "Rules": [
        {
            "ID": "LokiLogRetention",
            "Status": "Enabled",
            "Filter": {
                "Prefix": ""
            },
            "Expiration": {
                "Days": $RETENTION_DAYS
            }
        }
    ]
}
EOF
    elif [ "$RETENTION_DAYS" -le 90 ]; then
        # For medium retention (31-90 days), transition to IA, no Glacier
        cat > /tmp/lifecycle-policy.json << EOF
{
    "Rules": [
        {
            "ID": "LokiLogRetention",
            "Status": "Enabled",
            "Filter": {
                "Prefix": ""
            },
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                }
            ],
            "Expiration": {
                "Days": $RETENTION_DAYS
            }
        }
    ]
}
EOF
    else
        # For long retention (>90 days), full transition path
        cat > /tmp/lifecycle-policy.json << EOF
{
    "Rules": [
        {
            "ID": "LokiLogRetention",
            "Status": "Enabled",
            "Filter": {
                "Prefix": ""
            },
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                }
            ],
            "Expiration": {
                "Days": $RETENTION_DAYS
            }
        }
    ]
}
EOF
    fi
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$BUCKET_NAME" \
        --lifecycle-configuration file:///tmp/lifecycle-policy.json
    
    # Block public access
    log "Blocking public access"
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    log "✓ S3 bucket $BUCKET_NAME created successfully"
}

# Create IAM policy for Loki access
create_iam_policy() {
    header "Creating IAM Policy"
    
    log "Creating IAM policy: $IAM_POLICY_NAME"
    
    # Create policy document
    cat > /tmp/loki-policy.json << EOF
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
                "arn:aws:s3:::$BUCKET_NAME",
                "arn:aws:s3:::$BUCKET_NAME/*"
            ]
        }
    ]
}
EOF
    
    # Create the policy
    POLICY_ARN=$(aws iam create-policy \
        --policy-name "$IAM_POLICY_NAME" \
        --policy-document file:///tmp/loki-policy.json \
        --query 'Policy.Arn' \
        --output text)
    
    log "✓ IAM policy created: $POLICY_ARN"
    echo "$POLICY_ARN" > /tmp/policy-arn.txt
}

# Create IAM user for Loki
create_iam_user() {
    header "Creating IAM User"
    
    log "Creating IAM user: $IAM_USER_NAME"
    
    # Create user
    aws iam create-user --user-name "$IAM_USER_NAME" || true
    
    # Attach policy
    POLICY_ARN=$(cat /tmp/policy-arn.txt)
    aws iam attach-user-policy \
        --user-name "$IAM_USER_NAME" \
        --policy-arn "$POLICY_ARN"
    
    # Create access key
    log "Creating access keys"
    ACCESS_KEY_OUTPUT=$(aws iam create-access-key --user-name "$IAM_USER_NAME")
    
    ACCESS_KEY_ID=$(echo "$ACCESS_KEY_OUTPUT" | jq -r '.AccessKey.AccessKeyId')
    SECRET_ACCESS_KEY=$(echo "$ACCESS_KEY_OUTPUT" | jq -r '.AccessKey.SecretAccessKey')
    
    log "✓ IAM user created with access keys"
    
    # Save credentials for later use
    cat > /tmp/aws-credentials.json << EOF
{
    "access_key_id": "$ACCESS_KEY_ID",
    "access_key_secret": "$SECRET_ACCESS_KEY",
    "bucketnames": "$BUCKET_NAME",
    "endpoint": "https://s3.us-east-2.amazonaws.com",
    "region": "$AWS_REGION",
    "forcepathstyle": "false"
}
EOF
}

# Store credentials in AWS Secrets Manager
store_in_secrets_manager() {
    header "Storing Credentials in AWS Secrets Manager"
    
    log "Creating secret: $SECRET_NAME"
    
    # Create or update secret
    if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" &> /dev/null; then
        log "Secret exists, updating..."
        aws secretsmanager update-secret \
            --secret-id "$SECRET_NAME" \
            --secret-string file:///tmp/aws-credentials.json
    else
        log "Creating new secret..."
        aws secretsmanager create-secret \
            --name "$SECRET_NAME" \
            --description "S3 credentials for OpenShift Loki logging" \
            --secret-string file:///tmp/aws-credentials.json
    fi
    
    log "✓ Credentials stored in AWS Secrets Manager"
}


# Test S3 access
test_s3_access() {
    header "Testing S3 Access"
    
    log "Waiting for AWS access key propagation..."
    sleep 10
    
    log "Testing S3 bucket access with new credentials"
    
    # Create test file
    echo "OpenShift Logging S3 Test - $(date)" > /tmp/test-file.txt
    
    # Test upload
    AWS_ACCESS_KEY_ID=$(jq -r '.access_key_id' /tmp/aws-credentials.json) \
    AWS_SECRET_ACCESS_KEY=$(jq -r '.access_key_secret' /tmp/aws-credentials.json) \
    aws s3 cp /tmp/test-file.txt "s3://$BUCKET_NAME/test-file.txt"
    
    # Test list
    AWS_ACCESS_KEY_ID=$(jq -r '.access_key_id' /tmp/aws-credentials.json) \
    AWS_SECRET_ACCESS_KEY=$(jq -r '.access_key_secret' /tmp/aws-credentials.json) \
    aws s3 ls "s3://$BUCKET_NAME/"
    
    # Clean up test file
    AWS_ACCESS_KEY_ID=$(jq -r '.access_key_id' /tmp/aws-credentials.json) \
    AWS_SECRET_ACCESS_KEY=$(jq -r '.access_key_secret' /tmp/aws-credentials.json) \
    aws s3 rm "s3://$BUCKET_NAME/test-file.txt"
    
    log "✓ S3 access test successful"
}

# Generate configuration summary
generate_summary() {
    header "Configuration Summary"
    
    cat << EOF

${GREEN}✓ S3 Storage Setup Complete!${NC}

Configuration Details:
  S3 Bucket:           $BUCKET_NAME
  AWS Region:          $AWS_REGION
  IAM User:            $IAM_USER_NAME
  IAM Policy:          $IAM_POLICY_NAME
  Secrets Manager:     $SECRET_NAME

Next Steps:
  1. Continue with Step 3 in the tutorial: Deploy External Secrets Operator
  2. The AWS credentials are stored in AWS Secrets Manager
  3. External Secrets Operator will retrieve them automatically

Configuration saved to: /tmp/s3-config-summary.txt

${YELLOW}Important Security Notes:${NC}
  - Access keys are stored securely in AWS Secrets Manager
  - IAM user has minimal required permissions
  - S3 bucket has public access blocked
  - Lifecycle policies configured for cost optimization

EOF

    # Save summary to file
    cat > /tmp/s3-config-summary.txt << EOF
OpenShift Logging S3 Configuration
Generated: $(date)

S3 Bucket: $BUCKET_NAME
Region: $AWS_REGION
IAM User: $IAM_USER_NAME
Policy: $IAM_POLICY_NAME
Secret: $SECRET_NAME

Bucket Features:
- Versioning enabled
- Default encryption (AES256)
- Lifecycle policy (Standard → IA → Glacier → Delete)
- Public access blocked

IAM Permissions:
- s3:GetObject, s3:PutObject, s3:DeleteObject, s3:ListBucket
- Limited to specific bucket only

AWS Secrets Manager:
- Secret name: $SECRET_NAME
- Contains: access_key_id, access_key_secret, bucketnames, endpoint, region
EOF
}

# Cleanup temporary files
cleanup() {
    log "Cleaning up temporary files"
    rm -f /tmp/lifecycle-policy.json
    rm -f /tmp/loki-policy.json
    rm -f /tmp/aws-credentials.json
    rm -f /tmp/policy-arn.txt
    rm -f /tmp/test-file.txt
}

# Main execution
main() {
    header "OpenShift Logging S3 Storage Setup"
    
    cat << EOF
This script will set up S3 storage for OpenShift Logging with Loki.

Configuration:
  Cluster Name: $CLUSTER_NAME
  AWS Region:   $AWS_REGION
  Bucket Name:  $BUCKET_NAME
  Retention:    $RETENTION_DAYS days

EOF

    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Setup cancelled by user"
        exit 0
    fi

    verify_prerequisites
    create_s3_bucket
    create_iam_policy
    create_iam_user
    store_in_secrets_manager
    test_s3_access
    generate_summary
    cleanup
    
    log "S3 storage setup completed successfully!"
    log "You can now proceed to Step 3 in the tutorial."
}

# Handle script interruption
trap cleanup EXIT

# Check if jq is available
if ! command -v jq &> /dev/null; then
    error "jq is required but not installed. Please install jq first."
fi

# Run main function
main "$@"
