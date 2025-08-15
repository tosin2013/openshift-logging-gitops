#!/bin/bash

# OpenShift Logging GitOps Trigger Script
# Implements ADR-0009: Hybrid Deployment Strategy Phase 3
# 
# Usage: ./scripts/trigger-gitops-sync.sh [environment]
# Example: ./scripts/trigger-gitops-sync.sh production
# 
# This script handles Phase 3 (GitOps Sync) of the deployment:
# 1. Triggers ArgoCD application sync
# 2. Monitors deployment progress
# 3. Validates successful deployment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_ENVIRONMENT="dev"

# Parse arguments
ENVIRONMENT="${1:-$DEFAULT_ENVIRONMENT}"

# Handle help flag
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat << EOF
${BLUE}OpenShift Logging GitOps Trigger Script${NC}

${GREEN}DESCRIPTION:${NC}
  Implements Phase 3 of the Hybrid GitOps Deployment Strategy (ADR-0009)
  Triggers ArgoCD synchronization and monitors deployment progress

${GREEN}USAGE:${NC}
  ./scripts/trigger-gitops-sync.sh [ENVIRONMENT]

${GREEN}ENVIRONMENTS:${NC}
  dev         Development environment
  staging     Staging environment  
  production  Production environment

${GREEN}OPTIONS:${NC}
  --help, -h  Show this help message

${GREEN}EXAMPLES:${NC}
  ./scripts/trigger-gitops-sync.sh dev
  ./scripts/trigger-gitops-sync.sh production

${GREEN}PREREQUISITES:${NC}
  - Bootstrap script must have been run successfully
  - ArgoCD applications must be registered
  - OpenShift CLI (oc) logged in with appropriate permissions

${GREEN}WHAT THIS SCRIPT DOES:${NC}
  1. 🔍 Validates ArgoCD application exists
  2. 🚀 Triggers application synchronization
  3. 📊 Monitors sync progress
  4. ✅ Validates deployment health
  5. 🎯 Reports deployment status

${GREEN}DOCUMENTATION:${NC}
  Tutorial: docs/tutorials/getting-started-with-logging.md
  Strategy: docs/explanations/hybrid-deployment-strategy.md
EOF
    exit 0
fi

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

# Show banner
show_banner() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          OpenShift Logging GitOps                ║${NC}"
    echo -e "${BLUE}║         Phase 3: GitOps Deployment               ║${NC}"
    echo -e "${BLUE}║                                                   ║${NC}"
    echo -e "${BLUE}║   Environment: $(printf '%-10s' "$ENVIRONMENT")                       ║${NC}"
    echo -e "${BLUE}║   Strategy: Hybrid GitOps (ADR-0009)             ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}"
}

# Verify prerequisites
verify_prerequisites() {
    header "Verifying Prerequisites"
    
    # Check OpenShift CLI
    if ! command -v oc &> /dev/null; then
        error "OpenShift CLI (oc) is not installed."
    fi
    
    # Check cluster connection
    if ! oc whoami &> /dev/null; then
        error "Not logged into OpenShift cluster. Run 'oc login' first."
    fi
    
    # Check if ArgoCD application exists
    if ! oc get application "logging-stack-$ENVIRONMENT" -n openshift-gitops &> /dev/null; then
        error "ArgoCD application 'logging-stack-$ENVIRONMENT' not found. Run bootstrap-environment.sh first."
    fi
    
    log "✓ Prerequisites verified"
}

# Production safety check
production_safety_check() {
    if [ "$ENVIRONMENT" = "production" ]; then
        header "Production Safety Check"
        
        cat << EOF
${RED}⚠️  PRODUCTION DEPLOYMENT WARNING ⚠️${NC}

You are about to deploy to the PRODUCTION environment.

${BLUE}Pre-deployment checklist:${NC}
[ ] Change control approval obtained
[ ] Deployment window scheduled
[ ] Rollback plan documented
[ ] Team notified of deployment
[ ] Monitoring alerts configured
[ ] AWS resources verified
[ ] External secrets validated

${YELLOW}Do you want to proceed with production deployment? (yes/no):${NC}
EOF
        
        read -r confirmation
        case $confirmation in
            yes|YES|y|Y)
                log "Production deployment approved"
                ;;
            *)
                log "Production deployment cancelled by user"
                exit 0
                ;;
        esac
    fi
}

# Trigger ArgoCD application sync
trigger_sync() {
    header "Triggering ArgoCD Sync for $ENVIRONMENT"
    
    local app_name="logging-stack-$ENVIRONMENT"
    
    # Check current application status
    log "Checking current application status..."
    local sync_status=$(oc get application "$app_name" -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    local health_status=$(oc get application "$app_name" -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    
    log "Current status: sync=$sync_status, health=$health_status"
    
    # Try ArgoCD CLI first
    if command -v argocd &> /dev/null; then
        log "Using ArgoCD CLI to trigger sync..."
        
        # Check if logged into ArgoCD
        if argocd account get &> /dev/null; then
            log "Syncing application: $app_name"
            if argocd app sync "$app_name"; then
                log "✓ ArgoCD CLI sync initiated successfully"
                return 0
            else
                warn "ArgoCD CLI sync failed, falling back to kubectl method"
            fi
        else
            warn "Not logged into ArgoCD CLI, using kubectl method"
        fi
    fi
    
    # Fallback to kubectl method
    log "Using kubectl to trigger sync..."
    
    # Method 1: Force refresh and sync
    if oc patch application "$app_name" -n openshift-gitops \
        --type merge \
        --patch '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'; then
        log "✓ ArgoCD refresh triggered"
    else
        warn "Failed to trigger refresh"
    fi
    
    # Method 2: Enable auto-sync temporarily for this deployment
    log "Enabling auto-sync for deployment..."
    if oc patch application "$app_name" -n openshift-gitops \
        --type merge \
        --patch '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'; then
        log "✓ Auto-sync enabled"
    else
        warn "Failed to enable auto-sync"
    fi
}

# Monitor deployment progress
monitor_deployment() {
    header "Monitoring Deployment Progress"
    
    local app_name="logging-stack-$ENVIRONMENT"
    local timeout=600  # 10 minutes
    local check_interval=15
    
    log "Monitoring application sync for up to $(($timeout / 60)) minutes..."
    
    while [ $timeout -gt 0 ]; do
        local sync_status=$(oc get application "$app_name" -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        local health_status=$(oc get application "$app_name" -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        local operation_state=$(oc get application "$app_name" -n openshift-gitops -o jsonpath='{.status.operationState.phase}' 2>/dev/null || echo "Unknown")
        
        log "Status: sync=$sync_status, health=$health_status, operation=$operation_state"
        
        # Check for successful completion
        if [ "$sync_status" = "Synced" ] && [ "$health_status" = "Healthy" ]; then
            log "✅ Deployment completed successfully!"
            break
        fi
        
        # Check for failures
        if [ "$operation_state" = "Failed" ]; then
            error "Deployment failed. Check ArgoCD application for details."
        fi
        
        # Show resource status
        show_resource_status
        
        sleep $check_interval
        timeout=$((timeout - check_interval))
    done
    
    if [ $timeout -eq 0 ]; then
        warn "Deployment monitoring timed out. Check ArgoCD application manually."
        show_manual_commands
    fi
}

# Show status of key resources
show_resource_status() {
    # External Secrets
    if oc get externalsecret loki-s3-credentials -n openshift-logging &> /dev/null; then
        local es_status=$(oc get externalsecret loki-s3-credentials -n openshift-logging -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        log "  External Secret: $es_status"
    fi
    
    # LokiStack
    if oc get lokistack logging-loki -n openshift-logging &> /dev/null; then
        local loki_status=$(oc get lokistack logging-loki -n openshift-logging -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        log "  LokiStack: $loki_status"
    fi
    
    # ClusterLogging
    if oc get clusterlogging instance -n openshift-logging &> /dev/null; then
        local cl_status=$(oc get clusterlogging instance -n openshift-logging -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        log "  ClusterLogging: $cl_status"
    fi
}

# Validate successful deployment
validate_deployment() {
    header "Validating Deployment"
    
    local validation_passed=true
    
    # Check External Secret
    if oc get externalsecret loki-s3-credentials -n openshift-logging &> /dev/null; then
        local es_status=$(oc get externalsecret loki-s3-credentials -n openshift-logging -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
        if [ "$es_status" = "True" ]; then
            log "✅ External Secret is synced"
        else
            warn "❌ External Secret is not synced: $es_status"
            validation_passed=false
        fi
    else
        warn "❌ External Secret not found"
        validation_passed=false
    fi
    
    # Check generated secret
    if oc get secret loki-s3-credentials -n openshift-logging &> /dev/null; then
        log "✅ S3 credentials secret exists"
    else
        warn "❌ S3 credentials secret not found"
        validation_passed=false
    fi
    
    # Check LokiStack
    if oc get lokistack logging-loki -n openshift-logging &> /dev/null; then
        local loki_status=$(oc get lokistack logging-loki -n openshift-logging -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
        if [ "$loki_status" = "True" ]; then
            log "✅ LokiStack is ready"
        else
            warn "❌ LokiStack is not ready: $loki_status"
            validation_passed=false
        fi
    else
        warn "❌ LokiStack not found"
        validation_passed=false
    fi
    
    # Check Loki pods
    local loki_pods=$(oc get pods -n openshift-logging -l app.kubernetes.io/name=loki --no-headers 2>/dev/null | wc -l)
    if [ "$loki_pods" -gt 0 ]; then
        log "✅ Loki pods found: $loki_pods"
    else
        warn "❌ No Loki pods found"
        validation_passed=false
    fi
    
    if [ "$validation_passed" = true ]; then
        log "🎉 All validation checks passed!"
        return 0
    else
        warn "⚠️ Some validation checks failed"
        return 1
    fi
}

# Show manual commands for troubleshooting
show_manual_commands() {
    header "Manual Commands for Monitoring"
    
    cat << EOF

${BLUE}ArgoCD Application Status:${NC}
${YELLOW}oc get application logging-stack-$ENVIRONMENT -n openshift-gitops -o yaml${NC}

${BLUE}External Secrets:${NC}
${YELLOW}oc get externalsecret -n openshift-logging${NC}
${YELLOW}oc describe externalsecret loki-s3-credentials -n openshift-logging${NC}

${BLUE}LokiStack Status:${NC}
${YELLOW}oc get lokistack -n openshift-logging${NC}
${YELLOW}oc describe lokistack logging-loki -n openshift-logging${NC}

${BLUE}Loki Pods:${NC}
${YELLOW}oc get pods -n openshift-logging -l app.kubernetes.io/name=loki${NC}

${BLUE}ArgoCD UI:${NC}
${YELLOW}oc get route argocd-server -n openshift-gitops${NC}
EOF
}

# Show completion summary
show_completion_summary() {
    header "Deployment Summary"
    
    cat << EOF

${GREEN}🎉 GitOps Deployment Complete for $ENVIRONMENT!${NC}

${BLUE}What was deployed:${NC}
✅ External Secrets configuration
✅ LokiStack with S3 storage
✅ Environment-specific configurations

${BLUE}ArgoCD Management:${NC}
• Application: ${YELLOW}logging-stack-$ENVIRONMENT${NC}
• All future updates managed via Git
• Automatic drift detection and correction

${BLUE}Next Steps:${NC}
1. Verify log collection:
   ${YELLOW}oc get pods -n openshift-logging -l app.kubernetes.io/name=vector${NC}

2. Test log queries in OpenShift Console:
   ${YELLOW}Web Console → Observe → Logs${NC}

3. Monitor ongoing health:
   ${YELLOW}oc get applications -n openshift-gitops${NC}

${BLUE}Configuration Changes:${NC}
• All future changes via Git commits
• ArgoCD will automatically sync changes
• Use overlays/$ENVIRONMENT/ for environment-specific config

${GREEN}Welcome to GitOps! 🚀${NC}
EOF
}

# Main execution
main() {
    show_banner
    verify_prerequisites
    production_safety_check
    trigger_sync
    monitor_deployment
    
    if validate_deployment; then
        show_completion_summary
    else
        show_manual_commands
        exit 1
    fi
}

# Run main function
main "$@"
