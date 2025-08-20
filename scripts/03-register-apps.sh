#!/bin/bash

# OpenShift Logging ArgoCD Application Registration Script
# Implements ADR-0009: Hybrid Deployment Strategy - Phase 1d (Application Registration)
# Refactored from bootstrap-environment.sh for better modularity and reliability
#
# Usage: ./scripts/03-register-apps.sh [environment] [--dry-run]
# Example: ./scripts/03-register-apps.sh dev
# 
# This script extracts ArgoCD application registration from the monolithic bootstrap:
# 1. Registers separated logging infrastructure application (Wave 2)
# 2. Registers separated logging forwarder application (Wave 3)
# 3. Configures External Secrets Operator ClusterSecretStore
# 4. Verifies applications are registered but not synced
#
# This replaces the register_argocd_applications() function from bootstrap-environment.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_ENVIRONMENT="dev"
DRY_RUN=false

# Parse arguments
ENVIRONMENT="${1:-$DEFAULT_ENVIRONMENT}"
shift || true

while [[ $# -gt 0 ]]; do
    case $1 in
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
${BLUE}OpenShift Logging ArgoCD Application Registration Script${NC}

${GREEN}DESCRIPTION:${NC}
  Implements Phase 1d of ADR-0009: Hybrid Deployment Strategy
  Registers separated ArgoCD applications for logging infrastructure

${GREEN}USAGE:${NC}
  ./scripts/03-register-apps.sh [ENVIRONMENT] [OPTIONS]

${GREEN}ENVIRONMENTS:${NC}
  dev         Development environment
  staging     Staging environment
  production  Production environment

${GREEN}OPTIONS:${NC}
  --dry-run, -n   Show commands without executing them
  --help, -h      Show this help message

${GREEN}WHAT THIS SCRIPT DOES:${NC}
  1. 📋 Registers logging infrastructure application (Wave 2)
  2. 📋 Registers logging forwarder application (Wave 3)
  3. 🔐 Configures External Secrets Operator ClusterSecretStore
  4. ✅ Verifies applications are registered but not synced

${GREEN}PREREQUISITES:${NC}
  - Operators deployed (run 00-setup-operators.sh first)
  - AWS resources created (run 01-bootstrap-aws.sh first)
  - TLS configured (run 02-setup-tls.sh first)

${GREEN}NEXT STEPS:${NC}
  After applications are registered, run:
  ./scripts/04-trigger-sync.sh [environment]

${GREEN}DOCUMENTATION:${NC}
  See docs/adrs/adr-0009-hybrid-deployment-strategy.md
EOF
}

show_banner() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          OpenShift Logging App Registration      ║${NC}"
    echo -e "${BLUE}║         Phase 1d: ArgoCD Applications            ║${NC}"
    echo -e "${BLUE}║                                                   ║${NC}"
    echo -e "${BLUE}║   Environment: $(printf '%-10s' "$ENVIRONMENT")                       ║${NC}"
    echo -e "${BLUE}║   Strategy: Separated Applications               ║${NC}"
    echo -e "${BLUE}║   Step: 4 of 5 (App Registration)                ║${NC}"
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
    
    # Check OpenShift CLI
    if ! command -v oc &> /dev/null; then
        error "OpenShift CLI (oc) not found. Please install it first."
    fi
    
    # Check OpenShift login
    if ! oc whoami &> /dev/null; then
        error "Not logged into OpenShift cluster. Run 'oc login' first."
    fi
    log "✓ Logged into OpenShift as: $(oc whoami)"
    
    # Check if ArgoCD is available
    if ! oc get namespace openshift-gitops &> /dev/null; then
        error "OpenShift GitOps (ArgoCD) not found. Please install it first."
    fi
    log "✓ OpenShift GitOps namespace exists"
    
    # Check if operators are deployed and healthy
    local operators=("external-secrets-operator" "loki-operator" "observability-operator")
    for operator in "${operators[@]}"; do
        if ! oc get application "$operator" -n openshift-gitops &> /dev/null; then
            error "Operator $operator not found. Run 00-setup-operators.sh first."
        fi
        
        local health_status=$(oc get application "$operator" -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        if [ "$health_status" != "Healthy" ]; then
            warn "Operator $operator is not healthy (status: $health_status). This may cause issues."
        fi
    done
    log "✓ Required operators are deployed"
    
    log "✓ Prerequisites verified"
}

# Register separated ArgoCD applications
register_applications() {
    header "Registering Separated ArgoCD Applications"
    
    # Register infrastructure application (Wave 2): LokiStack + Health Check
    local infra_app_file="apps/applications/argocd-logging-infrastructure-${ENVIRONMENT}.yaml"
    # Register forwarder application (Wave 3): ClusterLogForwarder (depends on infrastructure)
    local forwarder_app_file="apps/applications/argocd-logging-forwarder-${ENVIRONMENT}.yaml"
    
    # Register infrastructure application first
    if [ -f "$infra_app_file" ]; then
        log "Registering ArgoCD infrastructure application: $infra_app_file"
        execute "oc apply -f $infra_app_file"
        
        if [ "$DRY_RUN" = false ]; then
            log "✓ ArgoCD infrastructure application registered: logging-infrastructure-${ENVIRONMENT}"
        fi
    else
        error "ArgoCD infrastructure application file not found: $infra_app_file"
    fi
    
    # Register forwarder application second
    if [ -f "$forwarder_app_file" ]; then
        log "Registering ArgoCD forwarder application: $forwarder_app_file"
        execute "oc apply -f $forwarder_app_file"
        
        if [ "$DRY_RUN" = false ]; then
            log "✓ ArgoCD forwarder application registered: logging-forwarder-${ENVIRONMENT}"
        fi
    else
        error "ArgoCD forwarder application file not found: $forwarder_app_file"
    fi
}


# Verify applications are registered
verify_registration() {
    if [ "$DRY_RUN" = true ]; then
        log "✓ [DRY-RUN] Would verify application registration"
        return 0
    fi
    
    header "Verifying Application Registration"
    
    local apps=("logging-infrastructure-${ENVIRONMENT}" "logging-forwarder-${ENVIRONMENT}")
    
    for app in "${apps[@]}"; do
        if oc get application "$app" -n openshift-gitops &> /dev/null; then
            local sync_status=$(oc get application "$app" -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
            log "✓ Application registered: $app (sync status: $sync_status)"
            
            if [ "$sync_status" = "Synced" ]; then
                warn "Application $app is already synced. This may indicate auto-sync is enabled."
            fi
        else
            error "Application $app was not registered successfully"
        fi
    done
}

# Show completion summary
show_completion_summary() {
    header "Application Registration Complete"
    
    cat << EOF

${GREEN}✅ Phase 1d Complete: ArgoCD Applications Registered${NC}

${BLUE}Registered Applications:${NC}
• logging-infrastructure-$ENVIRONMENT (Wave 2) - LokiStack + Health Check
• logging-forwarder-$ENVIRONMENT (Wave 3) - ClusterLogForwarder

${BLUE}Application Architecture:${NC}
• Infrastructure app deploys first with health check job (Wave 1.5)
• Forwarder app waits for infrastructure to be healthy before deploying
• Health check prevents Vector pods from starting before LokiStack is ready

${BLUE}Next Steps:${NC}
1. Trigger GitOps sync:
   ${YELLOW}./scripts/04-trigger-sync.sh $ENVIRONMENT${NC}

2. Monitor application status:
   ${YELLOW}oc get applications -n openshift-gitops${NC}

${BLUE}Manual Verification:${NC}
• Check applications are registered but not synced:
  ${YELLOW}oc get application logging-infrastructure-$ENVIRONMENT -n openshift-gitops${NC}
  ${YELLOW}oc get application logging-forwarder-$ENVIRONMENT -n openshift-gitops${NC}

${GREEN}Ready for Phase 2: Manual Verification & Phase 3: GitOps Sync! 🚀${NC}
EOF
}

# Main execution
main() {
    show_banner
    verify_prerequisites
    register_applications
    verify_registration
    show_completion_summary
}

# Run main function
main "$@"
