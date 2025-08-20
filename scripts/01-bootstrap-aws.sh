#!/bin/bash

# OpenShift Logging AWS Bootstrap Script
# Implements ADR-0009: Hybrid Deployment Strategy - Phase 1b (AWS Resources)
# Refactored from bootstrap-environment.sh for better modularity and reliability
#
# Usage: ./scripts/01-bootstrap-aws.sh [environment] --region [region] [--dry-run]
# Example: ./scripts/01-bootstrap-aws.sh dev --region us-east-2
#
# This script extracts AWS resource creation from the monolithic bootstrap:
# 1. Creates S3 bucket for Loki storage (delegates to setup-s3-storage.sh)
# 2. Creates IAM user and policy for S3 access
# 3. Stores credentials in AWS Secrets Manager
# 4. Tests S3 access with new credentials
#
# This replaces the create_aws_resources() function from bootstrap-environment.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_ENVIRONMENT="dev"
DEFAULT_REGION="us-east-2"
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

# Validate environment
case $ENVIRONMENT in
    dev|staging|production)
        ;;
    *)
        echo -e "${RED}[ERROR]${NC} Invalid environment: $ENVIRONMENT. Must be one of: dev, staging, production"
        exit 1
        ;;
esac

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

show_help() {
    cat << EOF
${BLUE}OpenShift Logging AWS Bootstrap Script${NC}

${GREEN}DESCRIPTION:${NC}
  Implements Phase 1b of ADR-0009: Hybrid Deployment Strategy
  Creates AWS resources for OpenShift Logging with Loki

${GREEN}USAGE:${NC}
  ./scripts/01-bootstrap-aws.sh [ENVIRONMENT] [OPTIONS]

${GREEN}ENVIRONMENTS:${NC}
  dev         Development environment (7-day retention)
  staging     Staging environment (30-day retention)
  production  Production environment (90-day retention)

${GREEN}OPTIONS:${NC}
  --region, -r    AWS region (default: us-east-1)
  --dry-run, -n   Show commands without executing them
  --help, -h      Show this help message

${GREEN}WHAT THIS SCRIPT DOES:${NC}
  1. 🪣 Creates S3 bucket for Loki log storage
  2. 👤 Creates IAM user and policy for S3 access
  3. 🔐 Stores credentials in AWS Secrets Manager
  4. ✅ Tests S3 access with new credentials

${GREEN}PREREQUISITES:${NC}
  - AWS CLI configured with appropriate permissions
  - OpenShift CLI logged into cluster
  - Operators deployed (run 00-setup-operators.sh first)

${GREEN}NEXT STEPS:${NC}
  After AWS resources are ready, run:
  ./scripts/02-setup-tls.sh [environment] --tls-option [a|b]

${GREEN}DOCUMENTATION:${NC}
  See docs/adrs/adr-0009-hybrid-deployment-strategy.md
EOF
}

show_banner() {
    local retention_days
    case $ENVIRONMENT in
        dev) retention_days="7" ;;
        staging) retention_days="30" ;;
        production) retention_days="90" ;;
    esac

    echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          OpenShift Logging AWS Setup             ║${NC}"
    echo -e "${BLUE}║         Phase 1b: AWS Resources                  ║${NC}"
    echo -e "${BLUE}║                                                   ║${NC}"
    echo -e "${BLUE}║   Environment: $(printf '%-10s' "$ENVIRONMENT")                       ║${NC}"
    echo -e "${BLUE}║   Region: $(printf '%-15s' "$REGION")                    ║${NC}"
    echo -e "${BLUE}║   Retention: $(printf '%-12s' "${retention_days} days")                   ║${NC}"
    echo -e "${BLUE}║   Step: 2 of 5 (AWS Bootstrap)                   ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}"
}

# Execute command with dry-run support
execute() {
    local cmd="$1"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $cmd"
    else
        eval "$cmd"
    fi
}

# Verify prerequisites
verify_prerequisites() {
    header "Verifying Prerequisites"
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found. Please install it first."
    fi
    log "✓ AWS CLI available"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    local aws_identity=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null || echo "Unknown")
    log "✓ AWS Identity: $aws_identity"
    
    # Check OpenShift CLI
    if ! command -v oc &> /dev/null; then
        error "OpenShift CLI (oc) not found. Please install it first."
    fi
    
    # Check OpenShift login
    if ! oc whoami &> /dev/null; then
        error "Not logged into OpenShift cluster. Run 'oc login' first."
    fi
    log "✓ Logged into OpenShift as: $(oc whoami)"
    
    # Check if operators are deployed
    local operators=("external-secrets-operator" "loki-operator" "logging-operator" "observability-operator")
    for operator in "${operators[@]}"; do
        if ! oc get application "$operator" -n openshift-gitops &> /dev/null; then
            error "Operator $operator not found. Run 00-setup-operators.sh first."
        fi
    done
    log "✓ Required operators are deployed"
    
    log "✓ All prerequisites verified"
}

# Create AWS resources
create_aws_resources() {
    header "Creating AWS Resources for $ENVIRONMENT"
    
    local retention_days
    case $ENVIRONMENT in
        dev) retention_days="7" ;;
        staging) retention_days="30" ;;
        production) retention_days="90" ;;
    esac
    
    log "Environment configuration:"
    log "  Region: $REGION"
    log "  Bucket prefix: $ENVIRONMENT"
    log "  Retention: $retention_days days"
    
    if [ "$DRY_RUN" = true ]; then
        log "✓ [DRY-RUN] Would create AWS resources"
        return 0
    fi
    
    # Call the existing S3 setup script
    local s3_script="./scripts/setup-s3-storage.sh"
    if [ ! -f "$s3_script" ]; then
        error "S3 setup script not found: $s3_script"
    fi
    
    log "Running S3 storage setup script..."
    
    # Set environment variables for the S3 script
    export AWS_REGION="$REGION"
    export CLUSTER_NAME="${ENVIRONMENT}-openshift-logging-s3-credentials"
    export RETENTION_DAYS="$retention_days"

    # Run the S3 setup script with proper arguments
    # setup-s3-storage.sh expects: [cluster-name] [aws-region] [retention-days]
    if ! "$s3_script" "${ENVIRONMENT}-openshift-logging-s3-credentials" "$REGION" "$retention_days"; then
        error "Failed to create AWS resources"
    fi
    
    log "✓ AWS resources created successfully"
}

# Create initial Kubernetes secrets for External Secrets Operator
create_initial_secrets() {
    header "Creating Initial Kubernetes Secrets"

    if [ "$DRY_RUN" = true ]; then
        log "✓ [DRY-RUN] Would create initial aws-credentials secret"
        return 0
    fi

    # Use the existing setup-external-secrets.sh script
    local eso_script="./scripts/setup-external-secrets.sh"
    if [ ! -f "$eso_script" ]; then
        error "External Secrets setup script not found: $eso_script"
    fi

    log "Running External Secrets setup script..."
    log "  Secret name: openshift-logging-s3-credentials"
    log "  Region: $REGION"

    # The setup-external-secrets.sh script expects [secret-name] [aws-region]
    if ! "$eso_script" "openshift-logging-s3-credentials" "$REGION"; then
        warn "External Secrets setup failed. This may be expected if operators are not fully ready yet."
        log "You can run this manually later: $eso_script openshift-logging-s3-credentials $REGION"
    else
        log "✓ Initial secrets created successfully"
    fi
}

# Show completion summary
show_completion_summary() {
    header "AWS Bootstrap Complete"
    
    cat << EOF

${GREEN}✅ Phase 1b Complete: AWS Resources Created${NC}

${BLUE}Created Resources:${NC}
• S3 bucket for Loki log storage
• IAM user with minimal required permissions
• IAM policy for S3 access
• AWS Secrets Manager secret with credentials

${BLUE}Next Steps:${NC}
1. ${RED}SKIP${NC} TLS setup script (deprecated with bearer token implementation):
   ${YELLOW}# ./scripts/02-setup-tls.sh${NC} ${RED}← NOT NEEDED${NC}

2. Register ArgoCD applications:
   ${YELLOW}./scripts/03-register-apps.sh $ENVIRONMENT${NC}

3. Verify AWS resources:
   ${YELLOW}aws s3 ls | grep $ENVIRONMENT-openshift-logging${NC}
   ${YELLOW}aws secretsmanager list-secrets --region $REGION${NC}

${BLUE}Security Notes:${NC}
• Access keys are stored securely in AWS Secrets Manager
• IAM user has minimal required permissions
• S3 bucket has public access blocked

${GREEN}Ready for Phase 1d: ArgoCD Application Registration! 🚀${NC}
EOF
}

# Main execution
main() {
    show_banner
    verify_prerequisites
    create_aws_resources
    create_initial_secrets
    show_completion_summary
}

# Run main function
main "$@"
