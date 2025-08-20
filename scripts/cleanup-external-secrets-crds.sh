#!/bin/bash

# External Secrets CRD Cleanup Script
# This script manually removes all External Secrets Operator CRDs and resources
# Use this when the operator uninstallation leaves behind stale CRDs
#
# Usage: ./scripts/cleanup-external-secrets-crds.sh [--dry-run]

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
${BLUE}External Secrets CRD Cleanup Script${NC}

${GREEN}DESCRIPTION:${NC}
  Manually removes all External Secrets Operator CRDs and resources
  Use this when operator uninstallation leaves behind stale CRDs

${GREEN}USAGE:${NC}
  ./scripts/cleanup-external-secrets-crds.sh [OPTIONS]

${GREEN}OPTIONS:${NC}
  --dry-run, -n   Show what would be deleted without actually deleting
  --help, -h      Show this help message

${GREEN}WHAT THIS SCRIPT DOES:${NC}
  1. 🔍 Lists all External Secrets custom resources
  2. 🗑️  Deletes all External Secrets custom resources
  3. 🗑️  Deletes all External Secrets CRDs
  4. ✅ Verifies cleanup is complete

${GREEN}WHEN TO USE:${NC}
  - After operator uninstallation when CRDs remain
  - When ClusterSecretStore shows "unable to create client" errors
  - Before clean reinstallation of External Secrets Operator

${GREEN}WARNING:${NC}
  This will permanently delete all External Secrets configurations!
EOF
}

show_banner() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        External Secrets CRD Cleanup              ║${NC}"
    echo -e "${BLUE}║                                                   ║${NC}"
    echo -e "${BLUE}║   ⚠️  WARNING: This will delete all ESO data!    ║${NC}"
    echo -e "${BLUE}║                                                   ║${NC}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}║   Mode: DRY RUN (no actual changes)              ║${NC}"
    else
        echo -e "${BLUE}║   Mode: DESTRUCTIVE (will delete resources)      ║${NC}"
    fi
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

# Check if External Secrets CRDs exist
check_external_secrets_crds() {
    header "Checking External Secrets CRDs"
    
    local crd_count=$(oc get crd 2>/dev/null | grep external-secrets | wc -l)
    
    if [ "$crd_count" -eq 0 ]; then
        log "✅ No External Secrets CRDs found - already clean!"
        exit 0
    fi
    
    log "Found $crd_count External Secrets CRDs:"
    oc get crd | grep external-secrets | awk '{print "  - " $1}'
    
    echo ""
    if [ "$DRY_RUN" = false ]; then
        read -p "Do you want to delete all External Secrets CRDs and resources? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
}

# Delete External Secrets custom resources
delete_external_secrets_resources() {
    header "Deleting External Secrets Custom Resources"
    
    # List of External Secrets resource types to clean up
    local resource_types=(
        "externalsecrets"
        "clustersecretstores"
        "secretstores"
        "clusterexternalsecrets"
        "pushsecrets"
    )
    
    for resource_type in "${resource_types[@]}"; do
        log "Checking for $resource_type resources..."
        
        if oc get "$resource_type" --all-namespaces &>/dev/null; then
            local resource_count=$(oc get "$resource_type" --all-namespaces --no-headers 2>/dev/null | wc -l)
            
            if [ "$resource_count" -gt 0 ]; then
                log "Found $resource_count $resource_type resources"
                oc get "$resource_type" --all-namespaces --no-headers | while read -r namespace name rest; do
                    if [ -n "$namespace" ] && [ -n "$name" ]; then
                        log "Deleting $resource_type/$name in namespace $namespace"
                        execute "oc delete $resource_type $name -n $namespace --ignore-not-found=true"
                    fi
                done
            else
                log "No $resource_type resources found"
            fi
        else
            log "Resource type $resource_type not available (CRD may not exist)"
        fi
    done
    
    # Handle cluster-scoped resources separately
    log "Checking for cluster-scoped External Secrets resources..."
    
    if oc get clustersecretstores &>/dev/null; then
        local cluster_resources=$(oc get clustersecretstores --no-headers 2>/dev/null | wc -l)
        if [ "$cluster_resources" -gt 0 ]; then
            log "Found $cluster_resources ClusterSecretStore resources"
            oc get clustersecretstores --no-headers | while read -r name rest; do
                if [ -n "$name" ]; then
                    log "Deleting ClusterSecretStore/$name"
                    execute "oc delete clustersecretstore $name --ignore-not-found=true"
                fi
            done
        fi
    fi
}

# Delete External Secrets CRDs
delete_external_secrets_crds() {
    header "Deleting External Secrets CRDs"
    
    local crds=$(oc get crd 2>/dev/null | grep external-secrets | awk '{print $1}')
    
    if [ -z "$crds" ]; then
        log "No External Secrets CRDs found to delete"
        return 0
    fi
    
    log "Deleting External Secrets CRDs..."
    for crd in $crds; do
        log "Deleting CRD: $crd"
        execute "oc delete crd $crd --ignore-not-found=true"
    done
}

# Verify cleanup is complete
verify_cleanup() {
    if [ "$DRY_RUN" = true ]; then
        log "✓ [DRY-RUN] Would verify cleanup is complete"
        return 0
    fi
    
    header "Verifying Cleanup"
    
    local remaining_crds=$(oc get crd 2>/dev/null | grep external-secrets | wc -l)
    
    if [ "$remaining_crds" -eq 0 ]; then
        log "✅ All External Secrets CRDs successfully removed"
    else
        warn "⚠️  $remaining_crds External Secrets CRDs still remain:"
        oc get crd | grep external-secrets | awk '{print "  - " $1}'
        error "Cleanup incomplete - some CRDs may be stuck"
    fi
}

# Show completion summary
show_completion_summary() {
    header "External Secrets CRD Cleanup Complete"
    
    if [ "$DRY_RUN" = true ]; then
        cat << EOF

${GREEN}✅ DRY RUN Complete: No changes made${NC}

${BLUE}What would have been deleted:${NC}
• All External Secrets custom resources
• All External Secrets CRDs
• ClusterSecretStores, SecretStores, ExternalSecrets, etc.

${BLUE}To actually perform cleanup:${NC}
${YELLOW}./scripts/cleanup-external-secrets-crds.sh${NC}

EOF
    else
        cat << EOF

${GREEN}✅ External Secrets CRD Cleanup Complete${NC}

${BLUE}Cleaned Up:${NC}
• All External Secrets custom resources
• All External Secrets CRDs
• ClusterSecretStores, SecretStores, ExternalSecrets, etc.

${BLUE}Next Steps:${NC}
1. Reinstall External Secrets Operator:
   ${YELLOW}./scripts/00-setup-operators.sh${NC}

2. Verify clean installation:
   ${YELLOW}oc get crd | grep external-secrets${NC}

${GREEN}Ready for clean External Secrets Operator installation! 🚀${NC}
EOF
    fi
}

# Main execution
main() {
    show_banner
    check_external_secrets_crds
    delete_external_secrets_resources
    delete_external_secrets_crds
    verify_cleanup
    show_completion_summary
}

# Run main function
main "$@"
