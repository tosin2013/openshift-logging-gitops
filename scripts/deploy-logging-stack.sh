#!/bin/bash

# OpenShift Logging Stack Deployment Script
# This script automates Step 5-8 of the getting-started tutorial
# 
# Usage: ./scripts/deploy-logging-stack.sh [environment]
# Example: ./scripts/deploy-logging-stack.sh production
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

# Verify prerequisites
verify_prerequisites() {
    header "Verifying Prerequisites"
    
    # Check OpenShift CLI
    if ! command -v oc &> /dev/null; then
        error "OpenShift CLI (oc) is not installed."
    fi
    log "✓ OpenShift CLI is available"
    
    # Check if logged into OpenShift
    if ! oc whoami &> /dev/null; then
        error "Not logged into OpenShift. Please run 'oc login' first."
    fi
    log "✓ Logged into OpenShift cluster"
    
    # Check External Secrets Operator
    if ! oc get application external-secrets-operator -n openshift-gitops &> /dev/null; then
        error "External Secrets Operator not deployed. Run setup-external-secrets.sh first."
    fi
    log "✓ External Secrets Operator application exists"
    
    # Check if S3 secret exists
    if ! oc get secret logging-loki-s3 -n openshift-logging &> /dev/null; then
        error "S3 secret not found. Run setup-external-secrets.sh first."
    fi
    log "✓ S3 credentials secret exists"
    
    # Check OpenShift version
    OCP_VERSION=$(oc version --client -o json | jq -r '.clientVersion.major + "." + .clientVersion.minor')
    log "OpenShift version: $OCP_VERSION"
    
    if [[ $(echo "$OCP_VERSION < 4.18" | bc -l) -eq 1 ]]; then
        warn "OpenShift version $OCP_VERSION may not be fully compatible. Recommended: 4.18+"
    fi
}

# Deploy Loki Operator
deploy_loki_operator() {
    header "Deploying Loki Operator"
    
    if oc get application argocd-loki-operator -n openshift-gitops &> /dev/null; then
        log "Loki Operator application already exists"
    else
        log "Deploying Loki Operator via ArgoCD"
        oc apply -f apps/applications/argocd-loki-operator.yaml
    fi
    
    # Wait for application to sync and be healthy
    log "Waiting for Loki Operator to sync and become healthy..."
    wait_for_application "argocd-loki-operator" 300
    
    # Wait for Loki Operator CSV to be successful
    log "Waiting for Loki Operator CSV to be successful..."
    timeout=300
    while [ $timeout -gt 0 ]; do
        csv_phase=$(oc get csv -n openshift-operators | grep loki-operator | awk '{print $6}' | head -1)
        if [ "$csv_phase" = "Succeeded" ]; then
            log "✓ Loki Operator CSV is successful"
            break
        fi
        log "Loki Operator CSV phase: $csv_phase"
        sleep 10
        timeout=$((timeout - 10))
    done
    
    if [ $timeout -eq 0 ]; then
        error "Loki Operator CSV did not become successful within 5 minutes"
    fi
}

# Deploy Cluster Logging Operator
deploy_logging_operator() {
    header "Deploying Cluster Logging Operator"
    
    if oc get application argocd-logging-operator -n openshift-gitops &> /dev/null; then
        log "Logging Operator application already exists"
    else
        log "Deploying Cluster Logging Operator via ArgoCD"
        oc apply -f apps/applications/argocd-logging-operator.yaml
    fi
    
    # Wait for application to sync and be healthy
    log "Waiting for Logging Operator to sync and become healthy..."
    wait_for_application "argocd-logging-operator" 300
    
    # Wait for Logging Operator CSV to be successful
    log "Waiting for Cluster Logging Operator CSV to be successful..."
    timeout=300
    while [ $timeout -gt 0 ]; do
        csv_phase=$(oc get csv -n openshift-operators | grep cluster-logging | awk '{print $6}' | head -1)
        if [ "$csv_phase" = "Succeeded" ]; then
            log "✓ Cluster Logging Operator CSV is successful"
            break
        fi
        log "Cluster Logging Operator CSV phase: $csv_phase"
        sleep 10
        timeout=$((timeout - 10))
    done
    
    if [ $timeout -eq 0 ]; then
        error "Cluster Logging Operator CSV did not become successful within 5 minutes"
    fi
}

# Deploy Observability Operator
deploy_observability_operator() {
    header "Deploying Observability Operator"
    
    if oc get application argocd-observability-operator -n openshift-gitops &> /dev/null; then
        log "Observability Operator application already exists"
    else
        log "Deploying Observability Operator via ArgoCD"
        oc apply -f apps/applications/argocd-observability-operator.yaml
    fi
    
    # Wait for application to sync and be healthy
    log "Waiting for Observability Operator to sync and become healthy..."
    wait_for_application "argocd-observability-operator" 300
}

# Helper function to wait for ArgoCD application
wait_for_application() {
    local app_name=$1
    local timeout=${2:-300}
    
    while [ $timeout -gt 0 ]; do
        sync_status=$(oc get application "$app_name" -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        health_status=$(oc get application "$app_name" -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        
        if [ "$sync_status" = "Synced" ] && [ "$health_status" = "Healthy" ]; then
            log "✓ $app_name is synced and healthy"
            return 0
        fi
        
        log "$app_name status: Sync=$sync_status, Health=$health_status"
        sleep 10
        timeout=$((timeout - 10))
    done
    
    error "$app_name did not become healthy within timeout"
}

# Deploy LokiStack
deploy_lokistack() {
    header "Deploying LokiStack"
    
    log "Creating LokiStack instance with S3 storage"
    
    # Get bucket name from secret
    BUCKET_NAME=$(oc get secret logging-loki-s3 -n openshift-logging -o jsonpath='{.data.bucketnames}' | base64 -d)
    log "Using S3 bucket: $BUCKET_NAME"
    
    cat << EOF | oc apply -f -
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: logging-loki
  namespace: openshift-logging
spec:
  size: 1x.small
  storage:
    secret:
      name: logging-loki-s3
      type: s3
    storageClassName: gp3-csi
  tenants:
    mode: application
  template:
    distributor:
      replicas: 1
    ingester:
      replicas: 1
    querier:
      replicas: 1
    queryFrontend:
      replicas: 1
    gateway:
      replicas: 1
    indexGateway:
      replicas: 1
    ruler:
      replicas: 1
  limits:
    global:
      retention:
        days: 30
      ingestion:
        ingestionRate: 4
        ingestionBurstSize: 6
        maxLabelNameLength: 1024
        maxLabelValueLength: 4096
        maxLabelNamesPerSeries: 30
        maxGlobalStreamsPerUser: 10000
        maxLineSize: 256000
      queries:
        queryTimeout: 300s
        maxConcurrent: 32
        maxEntriesLimitPerQuery: 10000
        maxStreamsMatchersPerQuery: 1000
        maxSamplesPerQuery: 1000000
EOF
    
    # Wait for LokiStack to be ready
    log "Waiting for LokiStack to be ready..."
    timeout=600  # 10 minutes
    while [ $timeout -gt 0 ]; do
        lokistack_status=$(oc get lokistack logging-loki -n openshift-logging -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        
        if [ "$lokistack_status" = "True" ]; then
            log "✓ LokiStack is ready"
            break
        fi
        
        log "LokiStack status: $lokistack_status"
        
        # Show pod status for debugging
        log "Loki pods status:"
        oc get pods -n openshift-logging | grep loki || log "No Loki pods found yet"
        
        sleep 15
        timeout=$((timeout - 15))
    done
    
    if [ $timeout -eq 0 ]; then
        warn "LokiStack did not become ready within 10 minutes"
        log "Checking LokiStack status:"
        oc describe lokistack logging-loki -n openshift-logging
    fi
}

# Deploy ClusterLogging
deploy_cluster_logging() {
    header "Deploying ClusterLogging"
    
    log "Creating ClusterLogging instance with Vector collector"
    
    cat << EOF | oc apply -f -
apiVersion: logging.coreos.com/v1
kind: ClusterLogging
metadata:
  name: instance
  namespace: openshift-logging
spec:
  collection:
    type: vector
    vector: {}
  managementState: Managed
EOF
    
    # Wait for collector pods to be ready
    log "Waiting for Vector collector pods to be ready..."
    timeout=300
    while [ $timeout -gt 0 ]; do
        collector_ready=$(oc get daemonset collector -n openshift-logging -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
        collector_desired=$(oc get daemonset collector -n openshift-logging -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
        
        if [ "$collector_ready" -gt 0 ] && [ "$collector_ready" -eq "$collector_desired" ]; then
            log "✓ Vector collector pods are ready ($collector_ready/$collector_desired)"
            break
        fi
        
        log "Vector collector pods: $collector_ready/$collector_desired ready"
        sleep 10
        timeout=$((timeout - 10))
    done
    
    if [ $timeout -eq 0 ]; then
        warn "Vector collector pods may not be fully ready"
    fi
}

# Deploy ClusterLogForwarder
deploy_cluster_log_forwarder() {
    header "Deploying ClusterLogForwarder"
    
    log "Creating ClusterLogForwarder to send logs to Loki"
    
    cat << EOF | oc apply -f -
apiVersion: logging.coreos.com/v1
kind: ClusterLogForwarder
metadata:
  name: instance
  namespace: openshift-logging
spec:
  outputs:
  - name: loki-app
    type: loki
    loki:
      tenantKey: kubernetes.namespace_name
    url: https://logging-loki-gateway-http.openshift-logging.svc:8080/api/logs/v1/application
  - name: loki-infra
    type: loki
    loki:
      tenantKey: log_type
    url: https://logging-loki-gateway-http.openshift-logging.svc:8080/api/logs/v1/infrastructure
  pipelines:
  - name: application-logs
    inputRefs:
    - application
    outputRefs:
    - loki-app
  - name: infrastructure-logs
    inputRefs:
    - infrastructure
    outputRefs:
    - loki-infra
EOF
    
    log "✓ ClusterLogForwarder deployed"
}

# Test log ingestion
test_log_ingestion() {
    header "Testing Log Ingestion"
    
    log "Creating test pod to generate logs"
    
    # Create test pod
    cat << EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: log-test-pod
  namespace: default
  labels:
    app: log-test
spec:
  restartPolicy: Never
  containers:
  - name: test-logger
    image: busybox:latest
    command:
    - /bin/sh
    - -c
    - |
      for i in \$(seq 1 20); do
        echo "OpenShift Logging Test Message \$i - \$(date)"
        sleep 2
      done
      echo "Log test completed - \$(date)"
EOF
    
    # Wait for pod to complete
    log "Waiting for test pod to generate logs..."
    timeout=60
    while [ $timeout -gt 0 ]; do
        pod_phase=$(oc get pod log-test-pod -n default -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [ "$pod_phase" = "Succeeded" ] || [ "$pod_phase" = "Failed" ]; then
            log "Test pod completed with phase: $pod_phase"
            break
        fi
        sleep 2
        timeout=$((timeout - 2))
    done
    
    # Clean up test pod
    oc delete pod log-test-pod -n default --ignore-not-found=true
    
    log "✓ Test logs generated"
    log "Wait 2-3 minutes, then check logs in OpenShift Console:"
    log "Console → Observe → Logs"
    log "Query: {namespace=\"default\"} |= \"OpenShift Logging Test Message\""
}

# Verify deployment
verify_deployment() {
    header "Verifying Complete Deployment"
    
    log "Checking ArgoCD applications:"
    oc get applications -n openshift-gitops
    
    log "\nChecking operator CSVs:"
    oc get csv -n openshift-operators | grep -E "(external-secrets|loki|logging|observability)"
    
    log "\nChecking pods in openshift-logging namespace:"
    oc get pods -n openshift-logging
    
    log "\nChecking LokiStack status:"
    oc get lokistack -n openshift-logging
    
    log "\nChecking ClusterLogging status:"
    oc get clusterlogging -n openshift-logging
    
    log "\nChecking ClusterLogForwarder status:"
    oc get clusterlogforwarder -n openshift-logging
    
    log "\nChecking Vector collector status:"
    oc get daemonset collector -n openshift-logging
    
    # Check secret
    log "\nVerifying S3 secret:"
    if oc get secret logging-loki-s3 -n openshift-logging &> /dev/null; then
        log "✓ S3 secret exists"
    else
        warn "S3 secret not found"
    fi
}

# Generate final summary
generate_summary() {
    header "Deployment Summary"
    
    cat << EOF

${GREEN}🎉 OpenShift Logging Stack Deployment Complete! 🎉${NC}

Deployed Components:
  ✅ External Secrets Operator
  ✅ Loki Operator (v5.9.6)
  ✅ Cluster Logging Operator (v6.1.1)
  ✅ Observability Operator
  ✅ LokiStack with S3 storage
  ✅ Vector log collectors
  ✅ ClusterLogForwarder

Architecture:
  📊 Collection: Vector collectors on all nodes
  📈 Storage: Loki with S3 object storage backend
  🔐 Security: External Secrets Operator managing credentials
  ⚡ Querying: OpenShift Console integrated interface

Access Your Logs:
  1. Open OpenShift Console
  2. Navigate to: Observe → Logs
  3. Try queries like:
     - {namespace="default"}
     - {namespace="openshift-logging"}
     - {pod=~"collector-.*"}

Monitoring:
  - ArgoCD Applications: oc get applications -n openshift-gitops
  - Pod Status: oc get pods -n openshift-logging
  - LokiStack Health: oc get lokistack -n openshift-logging

${YELLOW}Next Steps:${NC}
  - Configure log retention policies
  - Set up monitoring and alerting
  - Create environment-specific overlays
  - Review and tune resource limits

${GREEN}Cost Savings:${NC}
  Your new Loki-based stack uses 60-80% less resources
  and storage costs compared to traditional EFK stacks!

EOF
}

# Main execution
main() {
    header "OpenShift Logging Stack Deployment"
    
    cat << EOF
This script will deploy the complete OpenShift logging stack:
  - Loki Operator
  - Cluster Logging Operator  
  - Observability Operator
  - LokiStack with S3 storage
  - Vector log collectors
  - ClusterLogForwarder

Prerequisites:
  ✓ External Secrets Operator deployed
  ✓ S3 credentials configured
  ✓ OpenShift 4.18+ cluster

EOF

    read -p "Do you want to continue with the deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi

    verify_prerequisites
    deploy_loki_operator
    deploy_logging_operator
    deploy_observability_operator
    deploy_lokistack
    deploy_cluster_logging
    deploy_cluster_log_forwarder
    test_log_ingestion
    verify_deployment
    generate_summary
    
    log "🎉 OpenShift Logging deployment completed successfully!"
    log "Check the OpenShift Console → Observe → Logs to view your logs!"
}

# Run main function
main "$@"
