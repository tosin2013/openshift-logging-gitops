#!/bin/bash

# OpenShift Logging Environment Cleanup Script
# Companion to bootstrap-environment.sh for complete infrastructure lifecycle management
# 
# Usage: ./scripts/cleanup-environment.sh [ENVIRONMENT] [OPTIONS]
# Example: ./scripts/cleanup-environment.sh dev --region us-east-2 --dry-run

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT=""
REGION=""
DRY_RUN=false
FORCE=false

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

# Show help
show_help() {
    cat << EOF
${BLUE}OpenShift Logging Environment Cleanup${NC}
Safely removes all resources created by bootstrap-environment.sh

${GREEN}USAGE:${NC}
  ./scripts/cleanup-environment.sh [ENVIRONMENT] [OPTIONS]

${GREEN}ENVIRONMENTS:${NC}
  dev         Development environment
  staging     Staging environment  
  production  Production environment

${GREEN}OPTIONS:${NC}
  --region=REGION     AWS region (e.g., us-east-2)
  --dry-run          Show what would be deleted without actually deleting
  --force            Skip confirmation prompts (DANGEROUS)
  --help, -h         Show this help message

${GREEN}EXAMPLES:${NC}
  # Safe cleanup with confirmation
  ./scripts/cleanup-environment.sh dev --region us-east-2
  
  # Preview what would be deleted
  ./scripts/cleanup-environment.sh dev --region us-east-2 --dry-run
  
  # Force cleanup without prompts (use with caution)
  ./scripts/cleanup-environment.sh dev --region us-east-2 --force

${YELLOW}SAFETY FEATURES:${NC}
  - Environment isolation (only cleans specified environment)
  - Dry-run mode for safe preview
  - Confirmation prompts for destructive operations
  - Graceful handling of already-deleted resources
  - Comprehensive logging of all operations

${RED}WARNING:${NC}
  This script will permanently delete AWS resources and data.
  Always run with --dry-run first to verify what will be deleted.

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        dev|staging|production)
            ENVIRONMENT="$1"
            shift
            ;;
        --region)
            REGION="$2"
            if [ -z "$REGION" ]; then
                error "--region requires a value"
            fi
            shift 2
            ;;
        --region=*)
            REGION="${1#*=}"
            if [ -z "$REGION" ]; then
                error "--region requires a value"
            fi
            shift
            ;;
        --dry-run|-n)
            DRY_RUN=true
            log "🧪 DRY RUN MODE: Will show what would be deleted without actually deleting"
            shift
            ;;
        --force)
            FORCE=true
            warn "⚠️  FORCE MODE: Will skip confirmation prompts"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1. Use --help for usage information"
            ;;
    esac
done

# Validate environment
if [ -z "$ENVIRONMENT" ]; then
    error "Environment is required. Valid environments: dev, staging, production"
fi

case $ENVIRONMENT in
    dev|staging|production)
        ;;
    *)
        error "Invalid environment: $ENVIRONMENT. Valid environments: dev, staging, production"
        ;;
esac

# Set environment-specific variables (will be set in main function)
BUCKET_PREFIX=""

# Validate region if provided
if [ -n "$REGION" ]; then
    log "Using specified region: $REGION"
else
    error "AWS region is required. Use --region to specify (e.g., --region us-east-2)"
fi

# Show banner
header "OpenShift Logging Environment Cleanup"
cat << EOF
╔═══════════════════════════════════════════════════╗
║          Environment Cleanup                     ║
║                                                   ║
║   Environment: ${ENVIRONMENT}                              ║
║   Region: ${REGION}                          ║
║   Mode: $([ "$DRY_RUN" = true ] && echo "DRY RUN" || echo "DESTRUCTIVE")                           ║
╚═══════════════════════════════════════════════════╝
EOF

# Verify prerequisites
verify_prerequisites() {
    header "Verifying Prerequisites"
    
    # Check required tools
    log "Checking required tools..."
    
    if ! command -v oc &> /dev/null; then
        error "OpenShift CLI (oc) is required but not installed"
    fi
    log "✓ OpenShift CLI: $(oc version --client -o json | jq -r '.clientVersion.gitVersion' 2>/dev/null || oc version --client --short 2>/dev/null || echo "available")"
    
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is required but not installed"
    fi
    log "✓ AWS CLI: $(aws --version)"
    
    if ! command -v jq &> /dev/null; then
        error "jq is required but not installed"
    fi
    log "✓ jq: $(jq --version)"
    
    # Check OpenShift access
    log "Checking OpenShift cluster access..."
    if ! oc whoami &> /dev/null; then
        error "Not logged into OpenShift cluster. Run 'oc login' first"
    fi
    log "✓ Connected as: $(oc whoami)"
    log "✓ Cluster: $(oc config current-context)"
    
    # Check AWS credentials
    log "Checking AWS credentials..."
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first"
    fi
    local aws_identity=$(aws sts get-caller-identity --query 'Arn' --output text)
    log "✓ AWS Identity: $aws_identity"
    
    log "✓ All prerequisites verified"
}

# Execute dry-run or actual command
execute_command() {
    local description="$1"
    local command="$2"

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $description:"
        echo -e "${BLUE}  $command${NC}"
    else
        log "$description"
        eval "$command"
    fi
}

# Phase 1: Delete ArgoCD applications
cleanup_argocd_applications() {
    header "Phase 1: Cleaning Up ArgoCD Applications"

    local applications=(
        "logging-stack-$ENVIRONMENT"
        "external-secrets-operator"
        "loki-operator"
        "logging-operator"
        "logging-infrastructure-$ENVIRONMENT"
        "logging-forwarder-$ENVIRONMENT"
        "observability-operator"
    )

    for app in "${applications[@]}"; do
        if oc get application "$app" -n openshift-gitops &> /dev/null; then
            execute_command "Deleting ArgoCD application: $app" \
                "oc delete application '$app' -n openshift-gitops --wait=true"
        else
            log "ArgoCD application $app not found (already deleted)"
        fi
    done

    log "✓ ArgoCD applications cleanup completed"
}

# Phase 2: Delete Kubernetes resources
cleanup_kubernetes_resources() {
    header "Phase 2: Cleaning Up Kubernetes Resources"

    # Delete ClusterLogForwarder
    if oc get clusterlogforwarder instance -n openshift-logging &> /dev/null; then
        execute_command "Deleting ClusterLogForwarder" \
            "oc delete clusterlogforwarder instance -n openshift-logging"
    else
        log "ClusterLogForwarder not found (already deleted)"
    fi

    # Delete LokiStack
    if oc get lokistack logging-loki -n openshift-logging &> /dev/null; then
        execute_command "Deleting LokiStack" \
            "oc delete lokistack logging-loki -n openshift-logging"
    else
        log "LokiStack not found (already deleted)"
    fi

    # Delete External Secrets
    local secret_name="${BUCKET_PREFIX}-openshift-logging-s3-credentials"
    if oc get externalsecret "$secret_name" -n openshift-logging &> /dev/null; then
        execute_command "Deleting ExternalSecret: $secret_name" \
            "oc delete externalsecret '$secret_name' -n openshift-logging"
    else
        log "ExternalSecret $secret_name not found (already deleted)"
    fi

    # Delete regular secrets
    if oc get secret logging-loki-s3 -n openshift-logging &> /dev/null; then
        execute_command "Deleting Kubernetes secret: logging-loki-s3" \
            "oc delete secret logging-loki-s3 -n openshift-logging"
    else
        log "Secret logging-loki-s3 not found (already deleted)"
    fi

    log "✓ Kubernetes resources cleanup completed"
}

# Phase 3: Delete TLS configuration
cleanup_tls_configuration() {
    header "Phase 3: Cleaning Up TLS Configuration"

    local overlay_file="overlays/$ENVIRONMENT/cluster-log-forwarder.yaml"

    if [ -f "$overlay_file" ]; then
        execute_command "Removing TLS configuration file: $overlay_file" \
            "rm -f '$overlay_file'"
    else
        log "TLS configuration file not found: $overlay_file (already deleted)"
    fi

    log "✓ TLS configuration cleanup completed"
}

# Phase 4: Delete AWS resources
cleanup_aws_resources() {
    header "Phase 4: Cleaning Up AWS Resources"

    local iam_policy_name="${BUCKET_PREFIX}-openshift-logging-s3-credentials-loki-policy"
    local iam_user_name="${BUCKET_PREFIX}-openshift-logging-s3-credentials-loki-user"
    local secret_name="openshift-logging-s3-credentials"

    # Find and delete S3 buckets with pattern matching
    log "Searching for S3 buckets with pattern: ${BUCKET_PREFIX}-openshift-logging-s3-credentials-loki-*"
    local buckets=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, '${BUCKET_PREFIX}-openshift-logging-s3-credentials-loki-')].Name" --output text --region "$REGION" 2>/dev/null || echo "")

    if [ -n "$buckets" ]; then
        for bucket in $buckets; do
            log "Found S3 bucket: $bucket"

            # Empty bucket first (required before deletion)
            # Handle both regular objects and versioned objects
            execute_command "Emptying S3 bucket (objects): $bucket" \
                "aws s3 rm s3://'$bucket' --recursive --region '$REGION'"
            execute_command "Emptying S3 bucket (versions): $bucket" \
                "aws s3api delete-objects --bucket '$bucket' --delete \"\$(aws s3api list-object-versions --bucket '$bucket' --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --region '$REGION' 2>/dev/null || echo '{\"Objects\":[]}')\" --region '$REGION' 2>/dev/null || true"
            execute_command "Emptying S3 bucket (delete markers): $bucket" \
                "aws s3api delete-objects --bucket '$bucket' --delete \"\$(aws s3api list-object-versions --bucket '$bucket' --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --region '$REGION' 2>/dev/null || echo '{\"Objects\":[]}')\" --region '$REGION' 2>/dev/null || true"

            # Delete bucket
            execute_command "Deleting S3 bucket: $bucket" \
                "aws s3api delete-bucket --bucket '$bucket' --region '$REGION'"
        done
    else
        log "No S3 buckets found matching pattern"
    fi

    # Delete IAM user (with access keys)
    if aws iam get-user --user-name "$iam_user_name" &> /dev/null; then
        log "Found IAM user: $iam_user_name"

        # Delete all access keys
        local access_keys=$(aws iam list-access-keys --user-name "$iam_user_name" --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null || echo "")
        if [ -n "$access_keys" ]; then
            for key in $access_keys; do
                execute_command "Deleting access key: $key" \
                    "aws iam delete-access-key --user-name '$iam_user_name' --access-key-id '$key'"
            done
        fi

        # Detach policies from user
        local attached_policies=$(aws iam list-attached-user-policies --user-name "$iam_user_name" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
        if [ -n "$attached_policies" ]; then
            for policy_arn in $attached_policies; do
                execute_command "Detaching policy from user: $policy_arn" \
                    "aws iam detach-user-policy --user-name '$iam_user_name' --policy-arn '$policy_arn'"
            done
        fi

        # Delete user
        execute_command "Deleting IAM user: $iam_user_name" \
            "aws iam delete-user --user-name '$iam_user_name'"
    else
        log "IAM user $iam_user_name not found (already deleted)"
    fi

    # Delete IAM policy
    local policy_arn="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/$iam_policy_name"
    if aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
        execute_command "Deleting IAM policy: $iam_policy_name" \
            "aws iam delete-policy --policy-arn '$policy_arn'"
    else
        log "IAM policy $iam_policy_name not found (already deleted)"
    fi

    # Delete AWS Secrets Manager secret
    if aws secretsmanager describe-secret --secret-id "$secret_name" --region "$REGION" &> /dev/null; then
        execute_command "Deleting AWS Secrets Manager secret: $secret_name" \
            "aws secretsmanager delete-secret --secret-id '$secret_name' --force-delete-without-recovery --region '$REGION'"
    else
        log "AWS Secrets Manager secret $secret_name not found (already deleted)"
    fi

    log "✓ AWS resources cleanup completed"
}

# Main execution
main() {
    # Set environment-specific variables
    case $ENVIRONMENT in
        dev)
            BUCKET_PREFIX="dev"
            ;;
        staging)
            BUCKET_PREFIX="staging"
            ;;
        production)
            BUCKET_PREFIX="prod"
            ;;
    esac

    verify_prerequisites

    if [ "$DRY_RUN" = false ] && [ "$FORCE" = false ]; then
        echo
        warn "This will permanently delete AWS resources and data for environment: $ENVIRONMENT"
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi

    log "Starting cleanup for environment: $ENVIRONMENT in region: $REGION"
    
    # Phase 1: Delete ArgoCD applications
    cleanup_argocd_applications

    # Phase 2: Delete Kubernetes resources
    cleanup_kubernetes_resources

    # Phase 3: Delete TLS configuration
    cleanup_tls_configuration

    # Phase 4: Delete AWS resources
    cleanup_aws_resources
    
    if [ "$DRY_RUN" = true ]; then
        log "🧪 DRY RUN COMPLETE: No resources were actually deleted"
        log "Run without --dry-run to perform actual cleanup"
    else
        log "✅ Cleanup completed successfully"
    fi
}

# Run main function
main "$@"
