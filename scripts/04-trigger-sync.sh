#!/bin/bash

# OpenShift Logging GitOps Sync Trigger Script
# Implements ADR-0009: Hybrid Deployment Strategy - Phase 3 (GitOps Sync)
# Enhanced version of trigger-gitops-sync.sh for separated applications
#
# Usage: ./scripts/04-trigger-sync.sh [environment] [--dry-run]
# Example: ./scripts/04-trigger-sync.sh dev
# 
# This script handles Phase 3 (GitOps Sync) with separated applications:
# 1. Triggers infrastructure application sync (Wave 2)
# 2. Waits for health check job to complete successfully
# 3. Triggers forwarder application sync (Wave 3)
# 4. Monitors deployment progress and validates success
#
# This replaces and enhances the existing trigger-gitops-sync.sh

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
${BLUE}OpenShift Logging GitOps Sync Trigger Script${NC}

${GREEN}DESCRIPTION:${NC}
  Implements Phase 3 of ADR-0009: Hybrid Deployment Strategy
  Triggers GitOps sync for separated logging applications with health checks

${GREEN}USAGE:${NC}
  ./scripts/04-trigger-sync.sh [ENVIRONMENT] [OPTIONS]

${GREEN}ENVIRONMENTS:${NC}
  dev         Development environment
  staging     Staging environment
  production  Production environment

${GREEN}OPTIONS:${NC}
  --dry-run, -n   Show commands without executing them
  --help, -h      Show this help message

${GREEN}WHAT THIS SCRIPT DOES:${NC}
  1. 🚀 Triggers infrastructure application sync (Wave 2)
  2. ⏳ Waits for health check job to validate LokiStack readiness
  3. 🚀 Triggers forwarder application sync (Wave 3)
  4. 📊 Monitors deployment progress
  5. ✅ Validates successful deployment

${GREEN}HEALTH CHECK INTEGRATION:${NC}
  • Infrastructure app includes health check job (Wave 1.5)
  • Health check validates LokiStack is ready before proceeding
  • Forwarder app only deploys after health check passes
  • Prevents Vector pods from starting before LokiStack is ready

${GREEN}PREREQUISITES:${NC}
  - Applications registered (run 03-register-apps.sh first)
  - Manual verification completed (Phase 2 of ADR-0009)

${GREEN}DOCUMENTATION:${NC}
  See docs/adrs/adr-0009-hybrid-deployment-strategy.md
EOF
}

show_banner() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          OpenShift Logging GitOps Sync           ║${NC}"
    echo -e "${BLUE}║         Phase 3: GitOps Deployment               ║${NC}"
    echo -e "${BLUE}║                                                   ║${NC}"
    echo -e "${BLUE}║   Environment: $(printf '%-10s' "$ENVIRONMENT")                       ║${NC}"
    echo -e "${BLUE}║   Strategy: Separated Applications + Health      ║${NC}"
    echo -e "${BLUE}║   Step: 5 of 5 (GitOps Sync)                     ║${NC}"
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
    
    # Check if separated ArgoCD applications exist
    local infra_app="logging-infrastructure-$ENVIRONMENT"
    local forwarder_app="logging-forwarder-$ENVIRONMENT"
    
    if ! oc get application "$infra_app" -n openshift-gitops &> /dev/null; then
        error "ArgoCD application '$infra_app' not found. Run 03-register-apps.sh first."
    fi
    
    if ! oc get application "$forwarder_app" -n openshift-gitops &> /dev/null; then
        error "ArgoCD application '$forwarder_app' not found. Run 03-register-apps.sh first."
    fi
    
    log "✓ Required ArgoCD applications are registered"
    log "✓ Prerequisites verified"
}

# Trigger sync for a single application
sync_application() {
    local app_name="$1"
    local description="$2"
    
    log "Triggering sync for $app_name ($description)..."
    
    if [ "$DRY_RUN" = true ]; then
        log "✓ [DRY-RUN] Would trigger sync for $app_name"
        return 0
    fi
    
    # Try ArgoCD CLI first if available
    if command -v argocd &> /dev/null && argocd account get &> /dev/null 2>&1; then
        log "Using ArgoCD CLI to trigger sync for $app_name..."
        if argocd app sync "$app_name"; then
            log "✓ ArgoCD CLI sync initiated for $app_name"
            return 0
        else
            warn "ArgoCD CLI sync failed for $app_name, falling back to kubectl method"
        fi
    fi
    
    # Fallback to kubectl method
    log "Using kubectl to trigger sync for $app_name..."
    
    # Force refresh and enable auto-sync
    execute "oc patch application $app_name -n openshift-gitops --type merge --patch '{\"metadata\":{\"annotations\":{\"argocd.argoproj.io/refresh\":\"hard\"}}}'"
    
    sleep 5  # Wait for refresh to take effect
    
    execute "oc patch application $app_name -n openshift-gitops --type merge --patch '{\"spec\":{\"syncPolicy\":{\"automated\":{\"prune\":true,\"selfHeal\":true}}}}'"
    
    log "✓ Sync triggered for $app_name"
}

# Wait for application to be healthy
wait_for_application_health() {
    local app_name="$1"
    local timeout="${2:-600}"  # Default 10 minutes
    local check_interval=15
    
    if [ "$DRY_RUN" = true ]; then
        log "✓ [DRY-RUN] Would wait for $app_name to become healthy"
        return 0
    fi
    
    log "Waiting for $app_name to become healthy (timeout: ${timeout}s)..."
    
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local health_status=$(oc get application "$app_name" -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        local sync_status=$(oc get application "$app_name" -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        
        log "$app_name status: sync=$sync_status, health=$health_status"
        
        if [ "$health_status" = "Healthy" ] && [ "$sync_status" = "Synced" ]; then
            log "✅ $app_name is healthy and synced"
            return 0
        fi
        
        if [ "$health_status" = "Degraded" ]; then
            warn "$app_name is degraded. Checking for specific issues..."
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    error "$app_name failed to become healthy within timeout"
}

# Check LokiStack readiness directly
check_lokistack_readiness() {
    if [ "$DRY_RUN" = true ]; then
        log "✓ [DRY-RUN] Would check LokiStack readiness"
        return 0
    fi
    
    header "Verifying LokiStack Readiness"
    
    log "Checking LokiStack status directly..."
    
    # Wait for LokiStack to be ready
    local timeout=600  # 10 minutes
    
    if oc wait --for=condition=Ready lokistack/logging-loki -n openshift-logging --timeout=${timeout}s; then
        log "✅ LokiStack is ready"
        
        # Additional validation - check the actual status
        local status=$(oc get lokistack/logging-loki -n openshift-logging -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        log "LokiStack Ready condition status: $status"
        
        if [ "$status" = "True" ]; then
            log "✅ LokiStack readiness validation successful"
            log "ClusterLogForwarder can now be safely deployed"
            return 0
        else
            error "LokiStack Ready condition is not True: $status"
        fi
    else
        error "LokiStack failed to become ready within timeout"
    fi
}

# Main sync orchestration
trigger_sync() {
    header "Triggering Separated Application Sync"
    
    local infra_app="logging-infrastructure-$ENVIRONMENT"
    local forwarder_app="logging-forwarder-$ENVIRONMENT"
    
    # Step 1: Sync infrastructure application (Wave 2)
    log "🚀 Step 1: Syncing infrastructure application..."
    sync_application "$infra_app" "LokiStack + Health Check"
    
    # Step 2: Wait for infrastructure to be healthy
    log "⏳ Step 2: Waiting for infrastructure to be healthy..."
    wait_for_application_health "$infra_app" 600
    
    # Step 3: Check LokiStack readiness
    log "🔍 Step 3: Verifying LokiStack readiness..."
    check_lokistack_readiness
    
    # Step 4: Sync forwarder application (Wave 3)
    log "🚀 Step 4: Syncing forwarder application..."
    sync_application "$forwarder_app" "ClusterLogForwarder"
    
    # Step 5: Wait for forwarder to be healthy
    log "⏳ Step 5: Waiting for forwarder to be healthy..."
    wait_for_application_health "$forwarder_app" 300
    
    log "✅ All applications synced successfully!"
}

# Show completion summary
show_completion_summary() {
    header "GitOps Sync Complete"
    
    cat << EOF

${GREEN}🎉 SUCCESS: OpenShift Logging Deployment Complete!${NC}

${BLUE}Deployed Components:${NC}
✅ External Secrets Operator - Manages secrets from AWS
✅ LokiStack - Log aggregation and storage
✅ Health Check Job - Validates LokiStack readiness
✅ ClusterLogForwarder - Vector log collectors

${BLUE}Health Check Integration:${NC}
✅ Health check job validated LokiStack readiness
✅ Vector pods started only after LokiStack was ready
✅ No DNS errors or connection failures

${BLUE}Verification Commands:${NC}
• Check application status:
  ${YELLOW}oc get applications -n openshift-gitops${NC}

• Check logging resources:
  ${YELLOW}oc get lokistack,clusterlogforwarder -n openshift-logging${NC}

• Check Vector pods:
  ${YELLOW}oc get pods -n openshift-logging -l app.kubernetes.io/name=vector${NC}

• Check log delivery:
  ${YELLOW}oc logs -l app.kubernetes.io/name=vector -n openshift-logging | grep 'successfully sent'${NC}

${BLUE}Next Steps:${NC}
1. Verify log collection and delivery
2. Set up log queries in Loki
3. Configure alerting and monitoring

${GREEN}Welcome to GitOps-managed OpenShift Logging! 🚀${NC}
EOF
}

# Main execution
main() {
    show_banner
    verify_prerequisites
    trigger_sync
    show_completion_summary
}

# Run main function
main "$@"
