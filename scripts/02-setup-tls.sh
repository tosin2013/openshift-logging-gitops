#!/bin/bash

# OpenShift Logging TLS Configuration Script
# 
# ⚠️  DEPRECATED: This script is no longer needed with the current implementation
# 
# The current ClusterLogForwarder implementation uses bearer token authentication
# with the 'loki' output type (not 'lokiStack'), making this TLS configuration
# script obsolete. TLS settings are now handled directly in the ClusterLogForwarder
# template with insecureSkipVerify for demo environments.
#
# See ADR-0018: ClusterLogForwarder Bearer Token Authentication for details.
#
# For production environments requiring proper TLS validation:
# - Update the bearer token secret with proper CA certificates
# - Set insecureSkipVerify: false in the ClusterLogForwarder template
# - See production configuration in overlays/production/
#
# Original purpose: TLS strategy for Vector → Loki communication (ADR-0016)
# Usage: ./scripts/02-setup-tls.sh [environment] --tls-option [a|b]
# Example: ./scripts/02-setup-tls.sh dev --tls-option a

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT=""
TLS_OPTION=""
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --tls-option)
            TLS_OPTION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            echo -e "${RED}[ERROR]${NC} Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            if [ -z "$ENVIRONMENT" ]; then
                ENVIRONMENT="$1"
            else
                echo -e "${RED}[ERROR]${NC} Unexpected argument: $1"
                exit 1
            fi
            shift
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
${RED}⚠️  DEPRECATED SCRIPT${NC}

${YELLOW}This script is no longer needed with the current ClusterLogForwarder implementation.${NC}

${GREEN}CURRENT IMPLEMENTATION:${NC}
  The ClusterLogForwarder now uses bearer token authentication with the 'loki' 
  output type, making this TLS configuration script obsolete.

${GREEN}TLS CONFIGURATION IS NOW HANDLED BY:${NC}
  • ClusterLogForwarder template: base/cluster-log-forwarder/cluster-log-forwarder-template.yaml
  • Demo environments: insecureSkipVerify: true (for immediate functionality)
  • Production environments: insecureSkipVerify: false (requires proper CA certificates)

${GREEN}FOR PRODUCTION TLS VALIDATION:${NC}
  1. Update the bearer token secret with proper CA certificates:
     ${YELLOW}oc patch secret lokistack-gateway-bearer-token -n openshift-logging \\
       --patch='{"data":{"ca-bundle.crt":"<base64-encoded-ca-cert>"}}'${NC}
  
  2. Set insecureSkipVerify: false in production overlay:
     ${YELLOW}overlays/production/cluster-log-forwarder-production.yaml${NC}
  
  3. Verify certificate chain:
     ${YELLOW}openssl verify -CAfile ca-bundle.crt server-cert.crt${NC}

${GREEN}UPDATED WORKFLOW:${NC}
  1. Phase 1a: ./scripts/00-setup-operators.sh
  2. Phase 1b: ./scripts/01-bootstrap-aws.sh
  3. Phase 1c: ${RED}SKIP THIS SCRIPT${NC} (TLS handled in templates)
  4. Phase 1d: ./scripts/03-register-apps.sh
  5. Phase 3:  ./scripts/04-trigger-sync.sh

${GREEN}DOCUMENTATION:${NC}
  See ADR-0018: ClusterLogForwarder Bearer Token Authentication
EOF
}

show_banner() {
    echo -e "${RED}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                ⚠️  DEPRECATED SCRIPT ⚠️           ║${NC}"
    echo -e "${RED}║          OpenShift Logging TLS Setup             ║${NC}"
    echo -e "${RED}║                                                   ║${NC}"
    echo -e "${RED}║   This script is no longer needed with the       ║${NC}"
    echo -e "${RED}║   current bearer token implementation.           ║${NC}"
    echo -e "${RED}║                                                   ║${NC}"
    echo -e "${RED}║   TLS is now configured in ClusterLogForwarder   ║${NC}"
    echo -e "${RED}║   templates. See --help for details.             ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════╝${NC}"
}

# Verify prerequisites
verify_prerequisites() {
    header "Verifying Prerequisites"
    
    # Check required parameters
    if [ -z "$ENVIRONMENT" ]; then
        error "Environment is required. Usage: $0 [environment] --tls-option [a|b]"
    fi
    
    if [ -z "$TLS_OPTION" ]; then
        error "TLS option is required. Use --tls-option a (bypass) or --tls-option b (validation)"
    fi
    
    if [[ ! "$TLS_OPTION" =~ ^[ab]$ ]]; then
        error "Invalid TLS option: $TLS_OPTION. Use 'a' for bypass or 'b' for validation"
    fi
    
    # Check OpenShift CLI
    if ! command -v oc &> /dev/null; then
        error "OpenShift CLI (oc) is not installed."
    fi
    log "✓ OpenShift CLI available"
    
    # Check if logged into OpenShift
    if ! oc whoami &> /dev/null; then
        error "Not logged into OpenShift. Please run 'oc login' first."
    fi
    log "✓ Logged into OpenShift as: $(oc whoami)"
    
    # Check if openshift-logging namespace exists
    if ! oc get namespace openshift-logging &> /dev/null; then
        error "openshift-logging namespace not found. Run previous setup steps first."
    fi
    log "✓ openshift-logging namespace exists"
    
    # Check if ClusterLogForwarder exists
    if ! oc get clusterlogforwarder instance -n openshift-logging &> /dev/null; then
        warn "ClusterLogForwarder not found. TLS configuration will be prepared for when it's deployed."
    else
        log "✓ ClusterLogForwarder exists"
    fi
    
    log "✓ All prerequisites verified"
}

# Configure TLS Option A: Bypass certificate validation
configure_tls_bypass() {
    header "Configuring TLS Option A: Certificate Bypass"
    
    log "Creating TLS bypass configuration for Vector collectors..."
    
    # Create the overlay directory if it doesn't exist
    local overlay_dir="overlays/${ENVIRONMENT}"
    mkdir -p "$overlay_dir"
    
    # Create ClusterLogForwarder patch for TLS bypass
    cat > "${overlay_dir}/cluster-log-forwarder-tls-bypass.yaml" << EOF
apiVersion: observability.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: instance
  namespace: openshift-logging
spec:
  serviceAccount:
    name: logcollector
  outputs:
  - name: default-lokistack
    type: lokiStack
    lokiStack:
      target:
        name: logging-loki
        namespace: openshift-logging
      authentication:
        token:
          from: serviceAccount
    tls:
      insecureSkipVerify: true
  pipelines:
  - name: default-logstore
    inputRefs:
    - application
    - infrastructure
    - audit
    outputRefs:
    - default-lokistack
EOF
    
    if [ "$DRY_RUN" = true ]; then
        log "✓ [DRY-RUN] Would create TLS bypass configuration"
        log "✓ [DRY-RUN] File: ${overlay_dir}/cluster-log-forwarder-tls-bypass.yaml"
    else
        log "✓ TLS bypass configuration created: ${overlay_dir}/cluster-log-forwarder-tls-bypass.yaml"
    fi
}

# Configure TLS Option B: Proper certificate validation
configure_tls_validation() {
    header "Configuring TLS Option B: Certificate Validation"

    warn "TLS Option B (Certificate Validation) has not been fully tested."
    warn "This option is intended for production use and may require manual setup."
    read -p "Are you sure you want to proceed? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Aborting TLS configuration."
        exit 1
    fi
    
    log "Creating TLS validation configuration for Vector collectors..."
    
    # Create the overlay directory if it doesn't exist
    local overlay_dir="overlays/${ENVIRONMENT}"
    mkdir -p "$overlay_dir"
    
    # Create ClusterLogForwarder patch for TLS validation
    cat > "${overlay_dir}/cluster-log-forwarder-tls-validation.yaml" << EOF
apiVersion: observability.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: instance
  namespace: openshift-logging
spec:
  serviceAccount:
    name: logcollector
  outputs:
  - name: default-lokistack
    type: lokiStack
    lokiStack:
      target:
        name: logging-loki
        namespace: openshift-logging
      authentication:
        token:
          from: serviceAccount
    tls:
      insecureSkipVerify: false
      caCert:
        key: service-ca.crt
        configMapName: openshift-service-ca.crt
  pipelines:
  - name: default-logstore
    inputRefs:
    - application
    - infrastructure
    - audit
    outputRefs:
    - default-lokistack
EOF
    
    # Ensure the service CA ConfigMap exists
    if [ "$DRY_RUN" = false ]; then
        if ! oc get configmap openshift-service-ca.crt -n openshift-logging &> /dev/null; then
            log "Creating service CA ConfigMap..."
            oc annotate namespace openshift-logging service.beta.openshift.io/inject-cabundle=true --overwrite
            # The ConfigMap will be automatically created by OpenShift
            sleep 2
        fi
        log "✓ Service CA ConfigMap configured"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log "✓ [DRY-RUN] Would create TLS validation configuration"
        log "✓ [DRY-RUN] File: ${overlay_dir}/cluster-log-forwarder-tls-validation.yaml"
        log "✓ [DRY-RUN] Would configure service CA ConfigMap"
    else
        log "✓ TLS validation configuration created: ${overlay_dir}/cluster-log-forwarder-tls-validation.yaml"
    fi
}

# Apply TLS configuration
apply_tls_configuration() {
    header "Applying TLS Configuration"
    
    local overlay_dir="overlays/${ENVIRONMENT}"
    local config_file=""
    
    if [ "$TLS_OPTION" = "a" ]; then
        config_file="${overlay_dir}/cluster-log-forwarder-tls-bypass.yaml"
    else
        config_file="${overlay_dir}/cluster-log-forwarder-tls-validation.yaml"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log "✓ [DRY-RUN] Would apply TLS configuration: $config_file"
        return 0
    fi
    
    if [ -f "$config_file" ]; then
        log "Applying TLS configuration..."
        if oc apply -f "$config_file"; then
            log "✓ TLS configuration applied successfully"
        else
            error "Failed to apply TLS configuration"
        fi
    else
        error "TLS configuration file not found: $config_file"
    fi
}

# Show completion summary
show_completion_summary() {
    header "TLS Configuration Complete"
    
    local strategy_name=""
    local strategy_desc=""
    
    if [ "$TLS_OPTION" = "a" ]; then
        strategy_name="TLS Bypass"
        strategy_desc="Certificate validation disabled (insecureSkipVerify: true)"
    else
        strategy_name="Certificate Validation"
        strategy_desc="Proper certificate validation using OpenShift service CA"
    fi
    
    cat << EOF

${GREEN}✅ Phase 1c Complete: TLS Configuration Applied${NC}

${BLUE}TLS Strategy:${NC}
• Option $TLS_OPTION: $strategy_name
• Configuration: $strategy_desc
• Environment: $ENVIRONMENT

${BLUE}What was configured:${NC}
• ClusterLogForwarder TLS settings updated
• Vector collectors will use new TLS configuration
• Log forwarding should now work properly

${BLUE}Next Steps:${NC}
1. Register ArgoCD applications:
   ${YELLOW}./scripts/03-register-apps.sh $ENVIRONMENT${NC}

2. Trigger GitOps sync:
   ${YELLOW}./scripts/04-trigger-sync.sh $ENVIRONMENT${NC}

${BLUE}Verification:${NC}
• Check Vector collector logs for TLS errors:
  ${YELLOW}oc logs -l component=collector -n openshift-logging${NC}

• Monitor ClusterLogForwarder status:
  ${YELLOW}oc get clusterlogforwarder instance -n openshift-logging -o yaml${NC}

${GREEN}Ready for Phase 1d: ArgoCD Application Registration! 🚀${NC}
EOF
}

# Main execution
main() {
    show_banner
    verify_prerequisites
    
    if [ "$TLS_OPTION" = "a" ]; then
        configure_tls_bypass
    else
        configure_tls_validation
    fi
    
    apply_tls_configuration
    show_completion_summary
}

# Run main function
main "$@"
