#!/bin/bash

# OpenShift Logging Operators Setup Script
# Implements ADR-0009: Hybrid Deployment Strategy - Phase 1a (Operator Setup)
# Refactored from bootstrap-environment.sh for better modularity and reliability
#
# Usage: ./scripts/00-setup-operators.sh [--dry-run]
#
# This script extracts and focuses on operator deployment from the monolithic bootstrap:
# 1. Verifies prerequisites (OpenShift access, ArgoCD)
# 2. Deploys External Secrets Operator
# 3. Deploys Loki Operator
# 4. Deploys Observability Operator (for ClusterLogForwarder v1)
# 5. Waits for operators to be ready
#
# This replaces the operator registration logic from bootstrap-environment.sh lines 640-651

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DRY_RUN=false

# Parse arguments
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
${BLUE}OpenShift Logging Operators Setup Script${NC}

${GREEN}DESCRIPTION:${NC}
  Implements Phase 1a of ADR-0009: Hybrid Deployment Strategy
  Deploys required operators for OpenShift Logging stack

${GREEN}USAGE:${NC}
  ./scripts/00-setup-operators.sh [OPTIONS]

${GREEN}OPTIONS:${NC}
  --dry-run, -n   Show commands without executing them
  --help, -h      Show this help message

${GREEN}WHAT THIS SCRIPT DOES:${NC}
  1. 🔍 Verifies OpenShift and ArgoCD prerequisites
  2. 📦 Deploys External Secrets Operator
  3. 📦 Deploys Loki Operator
  4. 📦 Deploys Observability Operator (ClusterLogForwarder v1)
  5. ⏳ Waits for all operators to be ready

${GREEN}NEXT STEPS:${NC}
  After operators are ready, run:
  ./scripts/01-bootstrap-aws.sh [environment] --region [region]

${GREEN}DOCUMENTATION:${NC}
  See docs/adrs/adr-0009-hybrid-deployment-strategy.md
EOF
}

show_banner() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          OpenShift Logging Operators             ║${NC}"
    echo -e "${BLUE}║         Phase 1a: Operator Setup                 ║${NC}"
    echo -e "${BLUE}║                                                   ║${NC}"
    echo -e "${BLUE}║   Strategy: Hybrid GitOps (ADR-0009)             ║${NC}"
    echo -e "${BLUE}║   Step: 1 of 5 (Operator Deployment)             ║${NC}"
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
    
    # Check if oc is available
    if ! command -v oc &> /dev/null; then
        error "OpenShift CLI (oc) not found. Please install it first."
    fi
    log "✓ OpenShift CLI available"
    
    # Check if logged into OpenShift
    if ! oc whoami &> /dev/null; then
        error "Not logged into OpenShift cluster. Run 'oc login' first."
    fi
    log "✓ Logged into OpenShift as: $(oc whoami)"
    
    # Check if ArgoCD namespace exists
    if ! oc get namespace openshift-gitops &> /dev/null; then
        error "OpenShift GitOps (ArgoCD) not found. Please install it first."
    fi
    log "✓ OpenShift GitOps namespace exists"
    
    # Check ArgoCD pods
    local argocd_pods=$(oc get pods -n openshift-gitops --no-headers 2>/dev/null | wc -l)
    if [ "$argocd_pods" -eq 0 ]; then
        error "No ArgoCD pods found. OpenShift GitOps may not be properly installed."
    fi
    log "✓ ArgoCD pods found: $argocd_pods"
    
    log "✓ All prerequisites verified"
}

# Deploy operator applications
deploy_operators() {
    header "Deploying Operator Applications"
    
    local operators=("external-secrets-operator" "loki-operator" "observability-operator")
    
    for operator in "${operators[@]}"; do
        local app_file="apps/applications/argocd-${operator}.yaml"
        
        if [ ! -f "$app_file" ]; then
            error "Operator application file not found: $app_file"
        fi
        
        log "Deploying operator: $operator"
        execute "oc apply -f $app_file"
        
        if [ "$DRY_RUN" = false ]; then
            log "✓ Operator application registered: $operator"
        fi
    done
}

# Wait for operators to be ready
wait_for_operators() {
    if [ "$DRY_RUN" = true ]; then
        log "✓ [DRY-RUN] Would wait for operators to be ready"
        return 0
    fi
    
    header "Waiting for Operators to be Ready"
    
    local operators=("external-secrets-operator" "loki-operator" "observability-operator")
    local timeout=300  # 5 minutes
    local check_interval=15
    
    for operator in "${operators[@]}"; do
        log "Waiting for $operator to be ready..."
        
        local elapsed=0
        while [ $elapsed -lt $timeout ]; do
            local sync_status=$(oc get application "$operator" -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
            local health_status=$(oc get application "$operator" -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
            
            log "$operator status: sync=$sync_status, health=$health_status"
            
            if [ "$sync_status" = "Synced" ] && [ "$health_status" = "Healthy" ]; then
                log "✓ $operator is ready"
                break
            fi
            
            if [ "$health_status" = "Degraded" ]; then
                warn "$operator is degraded. This may be expected during initial deployment."
            fi
            
            sleep $check_interval
            elapsed=$((elapsed + check_interval))
        done
        
        if [ $elapsed -ge $timeout ]; then
            warn "$operator did not become healthy within timeout. Check ArgoCD for details."
        fi
    done
}

# Show completion summary
show_completion_summary() {
    header "Operator Setup Complete"
    
    cat << EOF

${GREEN}✅ Phase 1a Complete: Operators Deployed${NC}

${BLUE}Deployed Operators:${NC}
• External Secrets Operator - Manages secrets from AWS Secrets Manager
• Loki Operator - Manages LokiStack instances
• Observability Operator - Manages ClusterLogForwarder (observability.openshift.io/v1)

${BLUE}Next Steps:${NC}
1. Run AWS resource setup:
   ${YELLOW}./scripts/01-bootstrap-aws.sh dev --region us-east-2${NC}

2. ${RED}SKIP${NC} TLS setup script (deprecated with bearer token implementation):
   ${YELLOW}# ./scripts/02-setup-tls.sh${NC} ${RED}← NOT NEEDED${NC}

3. Register ArgoCD applications:
   ${YELLOW}./scripts/03-register-apps.sh dev${NC}

4. Monitor operator status:
   ${YELLOW}oc get applications -n openshift-gitops${NC}

${BLUE}Troubleshooting:${NC}
If operators show as Degraded:
   ${YELLOW}oc describe application [operator-name] -n openshift-gitops${NC}

${GREEN}Ready for Phase 1b: AWS Resource Setup! 🚀${NC}
EOF
}

# Main execution
main() {
    show_banner
    verify_prerequisites
    deploy_operators
    wait_for_operators
    show_completion_summary
}

# Run main function
main "$@"
