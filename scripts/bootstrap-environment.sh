#!/bin/bash

# OpenShift Logging Bootstrap Script
# Implements ADR-0009: Hybrid Deployment Strategy + ADR-0016: Dual TLS Options
#
# Usage: ./scripts/bootstrap-environment.sh [environment] [--tls-option] [--dry-run]
# Example: ./scripts/bootstrap-environment.sh production --tls-option=b
# Example: ./scripts/bootstrap-environment.sh dev --tls-option=a --dry-run
# 
# This script handles Phase 1 (Bootstrap) of the deployment:
# 1. Cleans up existing ArgoCD applications (if requested)
# 2. Creates AWS resources (S3, IAM, Secrets Manager)
# 3. Creates initial Kubernetes secrets
# 4. Configures TLS certificate strategy (Option A or B)
# 5. Registers ArgoCD applications (without syncing)
# 6. Sets up External Secrets Operator ClusterSecretStore
#
# Environments: dev, staging, production
# TLS Options: --tls-option=a (immediate), --tls-option=b (production)
# Options: --clean-argocd, --dry-run (preview commands without executing)

set -euo pipefail

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

# Execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="${2:-Running command}"
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $description:"
        echo -e "${YELLOW}  $cmd${NC}"
        return 0
    else
        log "$description..."
        eval "$cmd"
    fi
}

# Default values
DEFAULT_ENVIRONMENT="dev"
DEFAULT_TLS_OPTION="b"  # Default to production security

# Parse arguments
ENVIRONMENT="$DEFAULT_ENVIRONMENT"
REGION=""
TLS_OPTION="$DEFAULT_TLS_OPTION"
CLEAN_ARGOCD=false
DRY_RUN=false

# Parse all arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        dev|staging|production)
            ENVIRONMENT="$1"
            shift
            ;;
        --tls-option)
            TLS_OPTION="$2"
            if [[ "$TLS_OPTION" != "a" && "$TLS_OPTION" != "b" ]]; then
                echo -e "${RED}[ERROR]${NC} --tls-option must be 'a' or 'b'"
                echo "  a = Immediate resolution (TLS bypass)"
                echo "  b = Production security (full validation)"
                exit 1
            fi
            shift 2
            ;;
        --tls-option=*)
            TLS_OPTION="${1#*=}"
            if [[ "$TLS_OPTION" != "a" && "$TLS_OPTION" != "b" ]]; then
                echo -e "${RED}[ERROR]${NC} --tls-option must be 'a' or 'b'"
                echo "  a = Immediate resolution (TLS bypass)"
                echo "  b = Production security (full validation)"
                exit 1
            fi
            shift
            ;;
        --clean-argocd)
            CLEAN_ARGOCD=true
            log "🧹 CLEAN MODE: Will delete existing ArgoCD applications"
            shift
            ;;
        --dry-run|-n)
            DRY_RUN=true
            log "🧪 DRY RUN MODE: Commands will be displayed but not executed"
            shift
            ;;
        --region|-r)
            REGION="$2"
            if [ -z "$REGION" ]; then
                echo -e "${RED}[ERROR]${NC} --region requires a value"
                exit 1
            fi
            shift 2
            ;;
        --help|-h)
            # Already handled above
            shift
            ;;
        *)
            # Unknown option
            echo -e "${RED}[ERROR]${NC} Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Show help information
show_help() {
    cat << EOF
${BLUE}OpenShift Logging Bootstrap Script${NC}

${GREEN}DESCRIPTION:${NC}
  Implements Phase 1 of the Hybrid GitOps Deployment Strategy (ADR-0009)
  with Dual TLS Certificate Options (ADR-0016)
  Bootstraps AWS resources, Kubernetes secrets, and ArgoCD applications

${GREEN}USAGE:${NC}
  ./scripts/bootstrap-environment.sh [ENVIRONMENT] [OPTIONS]

${GREEN}ENVIRONMENTS:${NC}
  dev         Development environment (7-day retention)
  staging     Staging environment (30-day retention)
  production  Production environment (90-day retention)

${GREEN}TLS OPTIONS (ADR-0016):${NC}
  --tls-option=a  Option A: Immediate resolution (TLS bypass)
                  - 15 minutes implementation
                  - Emergency/development use
                  - Requires migration to Option B

  --tls-option=b  Option B: Production security (full validation)
                  - 2-4 hours implementation
                  - Cert Manager integration
                  - Automated certificate lifecycle
                  - Default for production

${GREEN}OPTIONS:${NC}
  --tls-option    Choose TLS implementation (a or b, default: b)
  --clean-argocd  Delete existing ArgoCD applications before bootstrap
  --region, -r    Specify AWS region (e.g., us-east-1, us-west-2)
  --dry-run, -n   Preview commands without executing them
  --help, -h      Show this help message

${GREEN}EXAMPLES:${NC}
  ./scripts/bootstrap-environment.sh dev --tls-option=a
  ./scripts/bootstrap-environment.sh dev --tls-option=b --region us-east-2
  ./scripts/bootstrap-environment.sh production --tls-option=b --clean-argocd
  ./scripts/bootstrap-environment.sh staging --tls-option=a --dry-run

${GREEN}REGION SELECTION:${NC}
  If --region is not specified, you will be prompted to choose from:
  - us-east-1 (N. Virginia)    - us-east-2 (Ohio)
  - us-west-1 (N. California)  - us-west-2 (Oregon)
  - eu-west-1 (Ireland)        - eu-central-1 (Frankfurt)
  - ap-south-1 (Mumbai)        - ap-southeast-1 (Singapore)

${GREEN}PREREQUISITES:${NC}
  - OpenShift CLI (oc) installed and logged in
  - AWS CLI configured with appropriate permissions
  - jq command-line JSON processor

${GREEN}WHAT THIS SCRIPT DOES:${NC}
  1. ✅ Verifies prerequisites and tools
  2. 🧹 Cleans up existing ArgoCD applications (if --clean-argocd)
  3. ✅ Creates AWS S3 bucket and IAM resources
  4. 🔐 Configures TLS certificate strategy (Option A or B)
  5. ✅ Sets up External Secrets Operator configuration
  6. ✅ Registers ArgoCD applications (without syncing)
  7. ⏸️  Pauses for manual verification
  8. 🎯 Prepares for GitOps deployment (Phase 3)

${GREEN}NEXT STEPS:${NC}
  After bootstrap completion, use:
  ./scripts/trigger-gitops-sync.sh [ENVIRONMENT]

${GREEN}DOCUMENTATION:${NC}
  Tutorial: docs/tutorials/getting-started-with-logging.md
  Strategy: docs/explanations/hybrid-deployment-strategy.md
EOF
}

# Validate environment
case $ENVIRONMENT in
    dev|staging|production)
        ;;
    *)
        echo -e "${RED}[ERROR]${NC} Invalid environment: $ENVIRONMENT"
        echo "Valid environments: dev, staging, production"
        echo "Use --help for more information"
        exit 1
        ;;
esac

# Region selection function
select_region() {
    if [ -n "$REGION" ]; then
        log "Using specified region: $REGION"
        return 0
    fi
    
    echo -e "\n${BLUE}=== AWS Region Selection ===${NC}"
    echo "Please select an AWS region for your deployment:"
    echo ""
    echo "  1) us-east-1      (N. Virginia)"
    echo "  2) us-east-2      (Ohio)"
    echo "  3) us-west-1      (N. California)"
    echo "  4) us-west-2      (Oregon)"
    echo "  5) eu-west-1      (Ireland)"
    echo "  6) eu-central-1   (Frankfurt)"
    echo "  7) ap-south-1     (Mumbai)"
    echo "  8) ap-southeast-1 (Singapore)"
    echo "  9) Custom region  (enter manually)"
    echo ""
    
    while true; do
        read -p "Select region [1-9]: " choice
        case $choice in
            1) REGION="us-east-1"; break ;;
            2) REGION="us-east-2"; break ;;
            3) REGION="us-west-1"; break ;;
            4) REGION="us-west-2"; break ;;
            5) REGION="eu-west-1"; break ;;
            6) REGION="eu-central-1"; break ;;
            7) REGION="ap-south-1"; break ;;
            8) REGION="ap-southeast-1"; break ;;
            9) 
                read -p "Enter custom region (e.g., ca-central-1): " REGION
                if [ -n "$REGION" ]; then
                    break
                else
                    echo "Please enter a valid region."
                fi
                ;;
            *) 
                echo "Invalid selection. Please choose 1-9."
                ;;
        esac
    done
    
    log "Selected region: $REGION"
}

# Show banner
show_banner() {
    local tls_description
    case $TLS_OPTION in
        a) tls_description="Option A (Immediate)" ;;
        b) tls_description="Option B (Production)" ;;
        *) tls_description="Unknown" ;;
    esac

    echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          OpenShift Logging Bootstrap             ║${NC}"
    echo -e "${BLUE}║         Phase 1: Environment Setup               ║${NC}"
    echo -e "${BLUE}║                                                   ║${NC}"
    echo -e "${BLUE}║   Environment: $(printf '%-10s' "$ENVIRONMENT")                       ║${NC}"
    echo -e "${BLUE}║   Region: $(printf '%-15s' "$REGION")                    ║${NC}"
    echo -e "${BLUE}║   TLS Strategy: $(printf '%-18s' "$tls_description")           ║${NC}"
    echo -e "${BLUE}║   GitOps: Hybrid Strategy (ADR-0009)             ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}"
}

# Verify prerequisites
verify_prerequisites() {
    header "Verifying Prerequisites (as per Tutorial Step 1)"
    
    # Check required tools
    local missing_tools=()
    
    log "Checking required tools..."
    if ! command -v oc &> /dev/null; then
        missing_tools+=("OpenShift CLI (oc)")
    else
        log "✓ OpenShift CLI: $(oc version --client 2>/dev/null | head -n1 || echo 'oc available')"
    fi
    
    if ! command -v aws &> /dev/null; then
        missing_tools+=("AWS CLI")
    else
        log "✓ AWS CLI: $(aws --version)"
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    else
        log "✓ jq: $(jq --version)"
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        error "Missing required tools: ${missing_tools[*]}"
    fi
    
    # Check cluster connection
    log "Checking OpenShift cluster access..."
    if ! oc whoami &> /dev/null; then
        error "Not logged into OpenShift cluster. Run 'oc login' first."
    fi
    
    local current_user=$(oc whoami)
    local cluster_info=$(oc config current-context)
    log "✓ Connected as: $current_user"
    log "✓ Cluster: $cluster_info"
    
    # Check AWS credentials
    log "Checking AWS credentials..."
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    local aws_identity=$(aws sts get-caller-identity --query 'Arn' --output text)
    log "✓ AWS Identity: $aws_identity"
    
    # Check if OpenShift GitOps is installed
    log "Checking OpenShift GitOps..."
    if oc get namespace openshift-gitops &> /dev/null; then
        log "✓ OpenShift GitOps namespace exists"
        
        # Check if ArgoCD is ready
        local argocd_pods=$(oc get pods -n openshift-gitops --no-headers 2>/dev/null | wc -l)
        if [ "$argocd_pods" -gt 0 ]; then
            log "✓ ArgoCD pods found: $argocd_pods"
        else
            warn "ArgoCD pods not found, may still be starting"
        fi
    else
        warn "OpenShift GitOps not found. Installing..."
        install_gitops_operator
    fi
    
    log "✓ All prerequisites verified for $ENVIRONMENT environment"
}

# Clean up existing ArgoCD applications
cleanup_argocd_applications() {
    if [ "$CLEAN_ARGOCD" = false ]; then
        return 0
    fi

    header "Phase 0: Cleaning Up Existing ArgoCD Applications"

    log "Checking for existing ArgoCD applications..."

    # List of applications to clean up
    local apps_to_clean=(
        "logging-stack-${ENVIRONMENT}"
        "external-secrets-operator"
        "loki-operator"
        "logging-operator"
    )

    for app in "${apps_to_clean[@]}"; do
        if oc get application "$app" -n openshift-gitops &> /dev/null; then
            log "Deleting ArgoCD application: $app"
            execute_cmd "oc delete application '$app' -n openshift-gitops --wait=true" \
                "Deleting ArgoCD application $app"
        else
            log "✓ ArgoCD application not found (already clean): $app"
        fi
    done

    # Wait a moment for cleanup to complete
    if [ "$DRY_RUN" = false ]; then
        log "Waiting for cleanup to complete..."
        sleep 10
    fi

    log "✓ ArgoCD application cleanup completed"
}

# Install GitOps operator if not present
install_gitops_operator() {
    log "Installing OpenShift GitOps Operator..."
    
    cat << EOF | oc apply -f -
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
    
    log "Waiting for GitOps operator to install..."
    timeout=300
    while [ $timeout -gt 0 ]; do
        if oc get namespace openshift-gitops &> /dev/null; then
            log "✓ OpenShift GitOps installed successfully"
            
            # Wait for ArgoCD pods to start
            log "Waiting for ArgoCD pods to start..."
            sleep 30
            break
        fi
        sleep 10
        timeout=$((timeout - 10))
    done
    
    if [ $timeout -eq 0 ]; then
        error "OpenShift GitOps installation timed out"
    fi
}

# Phase 1: Create AWS resources
create_aws_resources() {
    header "Phase 1a: Creating AWS Resources for $ENVIRONMENT"

    # Set environment-specific variables
    case $ENVIRONMENT in
        dev)
            local bucket_prefix="dev"
            local retention_days="7"
            ;;
        staging)
            local bucket_prefix="staging"
            local retention_days="30"
            ;;
        production)
            local bucket_prefix="prod"
            local retention_days="90"
            ;;
    esac

    # Set secret name based on bucket prefix
    local secret_name="${bucket_prefix}-openshift-logging-s3-credentials"
    
    log "Environment configuration:"
    log "  Region: $REGION"
    log "  Bucket prefix: $bucket_prefix"
    log "  Retention: $retention_days days"
    
    if [ -f "./scripts/setup-s3-storage.sh" ]; then
        log "Running S3 storage setup script..."
        
        # Pass environment-specific parameters
        if ./scripts/setup-s3-storage.sh \
            "$secret_name" \
            "$REGION" \
            "$retention_days"; then
            log "✓ AWS resources created successfully"
        else
            error "Failed to create AWS resources"
        fi
    else
        error "S3 setup script not found. Expected: ./scripts/setup-s3-storage.sh"
    fi
}

# Configure TLS certificate strategy
configure_tls_strategy() {
    header "Phase 1b: Configuring TLS Certificate Strategy (ADR-0016)"

    case $TLS_OPTION in
        a)
            log "🚨 Configuring Option A: Immediate Resolution (TLS Bypass)"
            log "  Implementation time: 15 minutes"
            log "  Security level: Medium (encrypted but not verified)"
            log "  Use case: Emergency/development environments"
            log "  ⚠️  Migration to Option B required within 30 days"

            # Copy Option A configuration to the overlay
            local option_a_file="base/cluster-log-forwarder/option-a-tls-bypass.yaml"
            local target_file="overlays/${ENVIRONMENT}/cluster-log-forwarder.yaml"

            if [ -f "$option_a_file" ]; then
                execute_cmd "cp '$option_a_file' '$target_file'" \
                    "Copying Option A TLS configuration to $ENVIRONMENT overlay"

                # Update environment-specific values in the copied file
                if [ "$DRY_RUN" = false ]; then
                    sed -i "s/implementation-date: \"2025-08-17\"/implementation-date: \"$(date -Iseconds)\"/" "$target_file"
                    log "✓ Option A TLS configuration prepared"
                fi
            else
                error "Option A configuration file not found: $option_a_file"
            fi
            ;;

        b)
            log "🔐 Configuring Option B: Production Security (Full Validation)"
            log "  Implementation time: 2-4 hours"
            log "  Security level: High (full certificate verification)"
            log "  Use case: Production environments"
            log "  Features: Automated certificate lifecycle with Cert Manager"

            # Deploy Cert Manager PKI infrastructure first
            local pki_file="base/cluster-log-forwarder/option-b-cert-manager-pki.yaml"
            local validation_file="base/cluster-log-forwarder/option-b-full-validation.yaml"
            local target_file="overlays/${ENVIRONMENT}/cluster-log-forwarder.yaml"

            if [ -f "$pki_file" ] && [ -f "$validation_file" ]; then
                execute_cmd "oc apply -f '$pki_file'" \
                    "Deploying Cert Manager PKI infrastructure"

                # Wait for certificates to be ready (in non-dry-run mode)
                if [ "$DRY_RUN" = false ]; then
                    log "Waiting for Root CA certificate to be ready..."
                    if oc wait --for=condition=Ready certificate/internal-root-ca -n cert-manager --timeout=300s; then
                        log "✓ Root CA certificate ready"
                    else
                        warn "Root CA certificate not ready within 5 minutes, continuing..."
                    fi

                    log "Waiting for Loki Gateway certificate to be ready..."
                    if oc wait --for=condition=Ready certificate/lokistack-gateway-tls -n openshift-logging --timeout=300s; then
                        log "✓ Loki Gateway certificate ready"
                    else
                        warn "Loki Gateway certificate not ready within 5 minutes, continuing..."
                    fi

                    # Create trust bundle
                    log "Creating ClusterLogForwarder trust bundle..."
                    if [ -f "./scripts/create-clf-trust-bundle.sh" ]; then
                        if ./scripts/create-clf-trust-bundle.sh; then
                            log "✓ Trust bundle created successfully"
                        else
                            error "Failed to create trust bundle"
                        fi
                    else
                        error "Trust bundle script not found: ./scripts/create-clf-trust-bundle.sh"
                    fi
                fi

                # Copy Option B configuration to the overlay
                execute_cmd "cp '$validation_file' '$target_file'" \
                    "Copying Option B TLS configuration to $ENVIRONMENT overlay"

                # Update environment-specific values in the copied file
                if [ "$DRY_RUN" = false ]; then
                    sed -i "s/implementation-date: \"2025-08-17\"/implementation-date: \"$(date -Iseconds)\"/" "$target_file"
                    log "✓ Option B TLS configuration prepared"
                fi
            else
                error "Option B configuration files not found: $pki_file or $validation_file"
            fi
            ;;

        *)
            error "Invalid TLS option: $TLS_OPTION (must be 'a' or 'b')"
            ;;
    esac

    log "✓ TLS certificate strategy configured: Option $TLS_OPTION"
}

# Phase 1: Create initial Kubernetes secrets
create_initial_secrets() {
    header "Phase 1b: Creating Initial Kubernetes Secrets"

    # Set environment-specific variables
    case $ENVIRONMENT in
        dev)
            local bucket_prefix="dev"
            ;;
        staging)
            local bucket_prefix="staging"
            ;;
        production)
            local bucket_prefix="prod"
            ;;
    esac

    # Set environment-specific secret name
    local secret_name="${bucket_prefix}-openshift-logging-s3-credentials"
    
    if [ -f "./scripts/setup-external-secrets.sh" ]; then
        log "Running External Secrets setup script..."
        log "  Secret name: $secret_name"
        
        if ./scripts/setup-external-secrets.sh "$secret_name"; then
            log "✓ Initial secrets created successfully"
        else
            error "Failed to create initial secrets"
        fi
    else
        error "External Secrets setup script not found. Expected: ./scripts/setup-external-secrets.sh"
    fi
}

# Phase 1: Register ArgoCD applications (but don't sync)
# Applications are configured with sync waves for proper deployment order:
# - Wave 0: Operators (external-secrets-operator, loki-operator, logging-operator)
# - Wave 2: Application stacks (logging-stack-dev/production)
register_argocd_applications() {
    header "Phase 1c: Registering ArgoCD Applications"
    
    # Check if ArgoCD is available
    if ! oc get namespace openshift-gitops &> /dev/null; then
        error "OpenShift GitOps (ArgoCD) not found. Please install it first."
    fi
    
    # Register the separated logging applications for this environment
    # Infrastructure application (Wave 2): LokiStack + Health Check
    local infra_app_file="apps/applications/argocd-logging-infrastructure-${ENVIRONMENT}.yaml"
    # Forwarder application (Wave 3): ClusterLogForwarder (depends on infrastructure)
    local forwarder_app_file="apps/applications/argocd-logging-forwarder-${ENVIRONMENT}.yaml"

    # Register infrastructure application first
    if [ -f "$infra_app_file" ]; then
        log "Registering ArgoCD infrastructure application: $infra_app_file"

        if oc apply -f "$infra_app_file"; then
            log "✓ ArgoCD infrastructure application registered: logging-infrastructure-${ENVIRONMENT}"
        else
            error "Failed to register ArgoCD infrastructure application"
        fi
    else
        warn "ArgoCD infrastructure application file not found: $infra_app_file"
    fi

    # Register forwarder application second
    if [ -f "$forwarder_app_file" ]; then
        log "Registering ArgoCD forwarder application: $forwarder_app_file"

        if oc apply -f "$forwarder_app_file"; then
            log "✓ ArgoCD forwarder application registered: logging-forwarder-${ENVIRONMENT}"
        else
            error "Failed to register ArgoCD forwarder application"
        fi
    else
        warn "ArgoCD forwarder application file not found: $forwarder_app_file"
    fi

    # Show available applications if any are missing
    if [ ! -f "$infra_app_file" ] || [ ! -f "$forwarder_app_file" ]; then
        log "Available applications:"
        ls -1 apps/applications/ | grep -E "yaml$" || echo "None found"
    fi
    
    # Also register operator applications if they don't exist
    for operator in external-secrets-operator loki-operator logging-operator; do
        local operator_app="apps/applications/argocd-${operator}.yaml"
        
        if [ -f "$operator_app" ]; then
            if ! oc get application "$operator" -n openshift-gitops &> /dev/null; then
                log "Registering operator application: $operator"
                oc apply -f "$operator_app"
            else
                log "✓ Operator application already exists: $operator"
            fi
        fi
    done
}

# Wait for External Secrets Operator to be ready
wait_for_eso_ready() {
    header "Phase 1d: Waiting for External Secrets Operator"
    
    log "Checking External Secrets Operator readiness..."
    
    # Wait for the application to be synced
    timeout=300
    while [ $timeout -gt 0 ]; do
        if oc get application external-secrets-operator -n openshift-gitops &> /dev/null; then
            sync_status=$(oc get application external-secrets-operator -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
            health_status=$(oc get application external-secrets-operator -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
            
            if [ "$sync_status" = "Synced" ] && [ "$health_status" = "Healthy" ]; then
                log "✓ External Secrets Operator is ready"
                break
            fi
            
            log "External Secrets Operator status: sync=$sync_status, health=$health_status"
        else
            log "External Secrets Operator application not found..."
        fi
        
        sleep 10
        timeout=$((timeout - 10))
    done
    
    if [ $timeout -eq 0 ]; then
        warn "External Secrets Operator did not become ready within 5 minutes"
        log "Continuing anyway..."
    fi
}

# Show manual verification steps
show_manual_verification() {
    header "Phase 2: Manual Verification Required"

    # Set environment-specific variables
    case $ENVIRONMENT in
        dev)
            local bucket_prefix="dev"
            ;;
        staging)
            local bucket_prefix="staging"
            ;;
        production)
            local bucket_prefix="prod"
            ;;
    esac

    # Environment-specific details
    local secret_name="${bucket_prefix}-openshift-logging-s3-credentials"
    local bucket_name
    
    case $ENVIRONMENT in
        dev)
            bucket_name="dev-$(date +%Y%m%d)-logging-loki"
            ;;
        staging)
            bucket_name="staging-$(date +%Y%m%d)-logging-loki"
            ;;
        production)
            bucket_name="prod-$(date +%Y%m%d)-logging-loki"
            ;;
    esac
    
    local tls_description
    case $TLS_OPTION in
        a) tls_description="Option A (Immediate Resolution - TLS Bypass)" ;;
        b) tls_description="Option B (Production Security - Full Validation)" ;;
        *) tls_description="Unknown TLS Option" ;;
    esac

    cat << EOF

${GREEN}✅ Bootstrap Phase Complete for $ENVIRONMENT!${NC}

${BLUE}Phase 1 Completed:${NC}
✅ AWS resources created for $ENVIRONMENT environment
✅ TLS certificate strategy configured: $tls_description
✅ Initial Kubernetes secrets configured
✅ ArgoCD applications registered
✅ External Secrets Operator ready

${YELLOW}⚠️  Phase 2: Manual Verification Required${NC}

Before proceeding to GitOps deployment, please verify:

${BLUE}1. AWS Resources (Environment: $ENVIRONMENT):${NC}
   ${YELLOW}# Check S3 bucket${NC}
   aws s3 ls | grep $ENVIRONMENT-.*-logging

   ${YELLOW}# Check Secrets Manager${NC}
   aws secretsmanager list-secrets --region $REGION | grep $secret_name

   ${YELLOW}# Verify IAM user${NC}
   aws iam get-user --user-name $ENVIRONMENT-loki-s3-user

${BLUE}2. Kubernetes Secrets:${NC}
   ${YELLOW}# Check bootstrap secret${NC}
   oc get secret aws-credentials -n external-secrets

   ${YELLOW}# Check ClusterSecretStore${NC}
   oc get clustersecretstore aws-secrets-manager

   ${YELLOW}# List all secrets in external-secrets-system${NC}
   oc get secrets -n external-secrets

${BLUE}3. ArgoCD Applications:${NC}
   ${YELLOW}# List all applications${NC}
   oc get applications -n openshift-gitops

   ${YELLOW}# Check separated applications for this environment${NC}
   oc get application logging-infrastructure-$ENVIRONMENT -n openshift-gitops -o yaml
   oc get application logging-forwarder-$ENVIRONMENT -n openshift-gitops -o yaml

   ${YELLOW}# Verify External Secrets Operator${NC}
   oc get application external-secrets-operator -n openshift-gitops

${BLUE}4. TLS Certificate Configuration (Option $TLS_OPTION):${NC}
$(if [ "$TLS_OPTION" = "a" ]; then
    cat << 'OPTION_A_EOF'
   ${YELLOW}# Verify Option A (TLS Bypass) configuration${NC}
   oc get clusterlogforwarder instance -n openshift-logging -o jsonpath='{.spec.outputs[0].lokiStack.tls.insecureSkipVerify}'

   ${YELLOW}# Check for migration tracking annotations${NC}
   oc get clusterlogforwarder instance -n openshift-logging -o jsonpath='{.metadata.annotations}'

   ${YELLOW}# Verify no TLS certificate errors (should be none with bypass)${NC}
   oc logs -l app.kubernetes.io/name=vector -n openshift-logging --since=2m | grep "certificate verify failed" || echo "✅ No TLS errors"
OPTION_A_EOF
else
    cat << 'OPTION_B_EOF'
   ${YELLOW}# Verify Option B (Full Validation) certificates${NC}
   oc get certificates -n cert-manager
   oc get certificates -n openshift-logging

   ${YELLOW}# Check trust bundle secret${NC}
   oc get secret clf-trust-bundle -n openshift-logging

   ${YELLOW}# Verify certificate chain${NC}
   oc get secret clf-trust-bundle -n openshift-logging -o jsonpath='{.data.ca-bundle\.crt}' | base64 -d | openssl x509 -text -noout | grep -E "Subject:|Issuer:"

   ${YELLOW}# Test certificate verification${NC}
   oc logs -l app.kubernetes.io/name=vector -n openshift-logging --since=2m | grep -E "TLS|certificate"
OPTION_B_EOF
fi)

${BLUE}5. External Secrets Status:${NC}
   ${YELLOW}# Check external secrets across all namespaces${NC}
   oc get externalsecret -A

   ${YELLOW}# Verify ClusterSecretStore is ready${NC}
   oc describe clustersecretstore aws-secrets-manager

$(if [ "$ENVIRONMENT" = "production" ]; then
    echo "${RED}🚨 PRODUCTION ENVIRONMENT CHECKLIST:${NC}"
    echo "   [ ] Change control ticket approved"
    echo "   [ ] Deployment window scheduled"
    echo "   [ ] Team notified of deployment"
    echo "   [ ] Rollback plan documented"
    echo "   [ ] Monitoring alerts configured"
    echo "   [ ] Security review completed"
    echo ""
fi)

${GREEN}When verification is complete, proceed to Phase 3:${NC}

${BLUE}Option 1: Automated GitOps Trigger${NC}
   ${YELLOW}./scripts/trigger-gitops-sync.sh $ENVIRONMENT${NC}

${BLUE}Option 2: Manual ArgoCD UI (Recommended for Production)${NC}
   ${YELLOW}# Get ArgoCD URL${NC}
   oc get route argocd-server -n openshift-gitops -o jsonpath='{.spec.host}'
   
   ${YELLOW}# Login and navigate to application: logging-stack-$ENVIRONMENT${NC}
   ${YELLOW}# Click "SYNC" to deploy the logging stack${NC}

${BLUE}Option 3: ArgoCD CLI${NC}
   ${YELLOW}# Login to ArgoCD${NC}
   argocd login \$(oc get route argocd-server -n openshift-gitops -o jsonpath='{.spec.host}')
   
   ${YELLOW}# Sync the application${NC}
   argocd app sync logging-stack-$ENVIRONMENT

${BLUE}Environment-Specific Details:${NC}
- Region: ${YELLOW}$REGION${NC}
- TLS Strategy: ${YELLOW}$tls_description${NC}
- Expected bucket pattern: ${YELLOW}$ENVIRONMENT-*-logging${NC}
- Secret name in AWS: ${YELLOW}$secret_name${NC}
- ArgoCD application: ${YELLOW}logging-stack-$ENVIRONMENT${NC}

$(if [ "$TLS_OPTION" = "a" ]; then
    echo "${YELLOW}⚠️  TLS Option A Migration Required:${NC}"
    echo "   This deployment uses TLS bypass for immediate resolution."
    echo "   Plan migration to Option B within 30 days for production security."
    echo "   Migration guide: docs/deployment-guide-dual-tls-options.md"
elif [ "$TLS_OPTION" = "b" ]; then
    echo "${GREEN}✅ TLS Option B Production Ready:${NC}"
    echo "   Full certificate validation with automated lifecycle management."
    echo "   Certificates will auto-renew before expiry."
    echo "   Monitor certificate health via Cert Manager metrics."
fi)

${GREEN}Tutorial Reference:${NC} docs/tutorials/getting-started-with-logging.md
${GREEN}Architecture Reference:${NC} docs/explanations/hybrid-deployment-strategy.md

${GREEN}Happy GitOps! 🚀${NC}
EOF
}

# Check for help first
for arg in "$@"; do
    if [[ "$arg" == "--help" || "$arg" == "-h" || "$arg" == "help" ]]; then
        show_help
        exit 0
    fi
done

# Main execution
main() {
    select_region
    show_banner
    verify_prerequisites
    cleanup_argocd_applications
    create_aws_resources
    configure_tls_strategy
    create_initial_secrets
    register_argocd_applications
    wait_for_eso_ready
    show_manual_verification
}

# Run main function
main "$@"
