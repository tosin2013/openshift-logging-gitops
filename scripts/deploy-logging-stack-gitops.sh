#!/bin/bash

# OpenShift Logging Stack Deployment Script (GitOps Enhanced)
# This script demonstrates the improved GitOps approach using Kustomize overlays
# 
# Usage: ./scripts/deploy-logging-stack-gitops.sh [environment]
# Example: ./scripts/deploy-logging-stack-gitops.sh production
# Prerequisites: External Secrets Operator deployed and S3 credentials configured

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

# Validate environment
case $ENVIRONMENT in
    dev|staging|production)
        log "Deploying to environment: $ENVIRONMENT"
        ;;
    *)
        error "Invalid environment: $ENVIRONMENT. Must be one of: dev, staging, production"
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
    echo -e "${BLUE}║             OpenShift Logging GitOps              ║${NC}"
    echo -e "${BLUE}║          Kustomize Overlay Deployment             ║${NC}"
    echo -e "${BLUE}║                                                   ║${NC}"
    echo -e "${BLUE}║   Environment: $(printf '%-10s' "$ENVIRONMENT")                       ║${NC}"
    echo -e "${BLUE}║   Mode: GitOps + Kustomize                        ║${NC}"
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
    
    # Check if overlay exists
    if [ ! -d "overlays/$ENVIRONMENT" ]; then
        error "Overlay directory overlays/$ENVIRONMENT does not exist. Run 'ls overlays/' to see available environments."
    fi
    
    # Check if kustomize is available (oc has built-in support)
    if ! oc version --client | grep -q kustomize; then
        warn "OpenShift CLI may not have Kustomize support. Proceeding anyway..."
    fi
    
    log "✓ OpenShift CLI available"
    log "✓ Connected to cluster: $(oc config current-context)"
    log "✓ Environment overlay exists: overlays/$ENVIRONMENT"
}

# Deploy operators (if not already done by ArgoCD)
deploy_operators() {
    header "Deploying Operators via ArgoCD"
    
    # Check if operators are already deployed
    if oc get application loki-operator -n openshift-gitops &> /dev/null; then
        log "✓ Loki Operator application already exists in ArgoCD"
    else
        warn "Loki Operator not found in ArgoCD. You may need to apply: oc apply -f apps/applications/argocd-loki-operator.yaml"
    fi
    
    if oc get application external-secrets-operator -n openshift-gitops &> /dev/null; then
        log "✓ External Secrets Operator application exists in ArgoCD"
    else
        warn "External Secrets Operator not found in ArgoCD"
    fi
}

# Test overlay before applying
test_overlay() {
    header "Testing Kustomize Overlay: $ENVIRONMENT"
    
    log "Running kustomize build to validate overlay..."
    
    if oc kustomize "overlays/$ENVIRONMENT/" > /tmp/overlay-test.yaml; then
        log "✓ Overlay builds successfully"
        
        # Show a preview of what will be applied
        log "Preview of resources to be created:"
        grep -E "^(kind|name):" /tmp/overlay-test.yaml | paste - - | head -10
        
        # Count resources
        resource_count=$(grep -c "^kind:" /tmp/overlay-test.yaml)
        log "Total resources to apply: $resource_count"
        
        rm -f /tmp/overlay-test.yaml
    else
        error "Overlay failed to build. Check kustomization.yaml syntax."
    fi
}

# Deploy logging stack using Kustomize overlays
deploy_logging_stack() {
    header "Deploying Logging Stack using Kustomize Overlay: $ENVIRONMENT"
    
    log "Applying overlay configuration for $ENVIRONMENT environment..."
    
    # Apply the overlay with server-side apply for better conflict resolution
    if oc apply -k "overlays/$ENVIRONMENT/" --server-side=true; then
        log "✓ Successfully applied $ENVIRONMENT overlay"
    else
        error "Failed to apply $ENVIRONMENT overlay"
    fi
}

# Wait for components to be ready
wait_for_readiness() {
    header "Waiting for Components to be Ready"
    
    # Wait for External Secrets to sync
    log "Checking External Secrets..."
    timeout=300
    while [ $timeout -gt 0 ]; do
        if oc get externalsecret loki-s3-credentials -n openshift-logging &> /dev/null; then
            sync_status=$(oc get externalsecret loki-s3-credentials -n openshift-logging -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
            if [ "$sync_status" = "True" ]; then
                log "✓ External Secret is synchronized"
                break
            fi
            log "External Secret status: $sync_status"
        else
            log "External Secret not found yet..."
        fi
        sleep 10
        timeout=$((timeout - 10))
    done
    
    if [ $timeout -eq 0 ]; then
        warn "External Secret did not sync within 5 minutes"
    fi
    
    # Wait for LokiStack to be ready
    log "Waiting for LokiStack to be ready..."
    timeout=600
    while [ $timeout -gt 0 ]; do
        if oc get lokistack logging-loki -n openshift-logging &> /dev/null; then
            status=$(oc get lokistack logging-loki -n openshift-logging -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
            if [ "$status" = "True" ]; then
                log "✓ LokiStack is ready"
                break
            fi
            log "LokiStack status: $status"
        else
            log "LokiStack not found yet..."
        fi
        sleep 15
        timeout=$((timeout - 15))
    done
    
    if [ $timeout -eq 0 ]; then
        warn "LokiStack did not become ready within 10 minutes"
    fi
}

# Verify deployment
verify_deployment() {
    header "Verifying Deployment"
    
    log "Checking deployed resources..."
    
    # Check External Secrets
    if oc get externalsecret -n openshift-logging &> /dev/null; then
        log "✓ External Secrets found:"
        oc get externalsecret -n openshift-logging
    fi
    
    # Check Secrets
    if oc get secret loki-s3-credentials -n openshift-logging &> /dev/null; then
        log "✓ S3 credentials secret exists"
    else
        warn "S3 credentials secret not found"
    fi
    
    # Check LokiStack
    if oc get lokistack -n openshift-logging &> /dev/null; then
        log "✓ LokiStack found:"
        oc get lokistack -n openshift-logging
    else
        warn "LokiStack not found"
    fi
    
    # Check Loki pods
    log "Checking Loki pods:"
    oc get pods -n openshift-logging -l app.kubernetes.io/name=loki
}

# Show next steps
show_next_steps() {
    header "Deployment Complete! 🎉"
    
    cat << EOF

${GREEN}✅ Successfully deployed OpenShift Logging using GitOps!${NC}

${BLUE}What was deployed:${NC}
- Environment: ${ENVIRONMENT}
- External Secrets for credential management  
- LokiStack for log aggregation
- S3 integration for storage

${BLUE}Environment-specific configuration:${NC}
$(case $ENVIRONMENT in
    dev)
        echo "- Size: 1x.demo (minimal resources)"
        echo "- Retention: 7 days"
        echo "- Region: us-east-1"
        ;;
    staging)
        echo "- Size: 1x.small (moderate resources)"
        echo "- Retention: 30 days" 
        echo "- Region: us-east-1"
        ;;
    production)
        echo "- Size: 1x.medium (production resources)"
        echo "- Retention: 90 days"
        echo "- Region: us-west-2"
        echo "- High availability: Multiple replicas"
        ;;
esac)

${BLUE}Next Steps:${NC}
1. Deploy log collection:
   ${YELLOW}oc apply -k overlays/$ENVIRONMENT/logging/  # If logging overlay exists${NC}

2. Verify log flow:
   ${YELLOW}oc logs deployment/vector-collector -n openshift-logging${NC}

3. Access logs in OpenShift Console:
   ${YELLOW}Web Console → Observe → Logs → Query: {namespace="default"}${NC}

4. Monitor the deployment:
   ${YELLOW}oc get applications -n openshift-gitops${NC}
   ${YELLOW}oc get lokistack -n openshift-logging${NC}

${BLUE}GitOps Benefits Achieved:${NC}
✅ Declarative configuration management
✅ Environment-specific customization via overlays
✅ Version-controlled infrastructure
✅ Consistent deployment across environments
✅ Easy rollback and change tracking

${BLUE}To deploy to another environment:${NC}
${YELLOW}./scripts/deploy-logging-stack-gitops.sh staging${NC}
${YELLOW}./scripts/deploy-logging-stack-gitops.sh production${NC}

${GREEN}Happy Logging! 🚀${NC}
EOF
}

# Main execution
main() {
    show_banner
    verify_prerequisites
    deploy_operators
    test_overlay
    deploy_logging_stack
    wait_for_readiness
    verify_deployment
    show_next_steps
}

# Run main function
main "$@"
