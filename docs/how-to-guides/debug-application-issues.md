# How to Troubleshoot OpenShift Logging Deployment Issues

This guide helps you diagnose and resolve common issues when deploying OpenShift logging infrastructure using ArgoCD and GitOps.

## When to Use This Guide

Use this guide when you encounter:
- ArgoCD applications not syncing
- Operators failing to install
- LokiStack not starting
- External Secrets not creating secrets
- Log collection not working
- S3 storage connectivity issues

## Prerequisites

- Cluster admin access to OpenShift 4.18+
- ArgoCD/OpenShift GitOps installed
- Basic understanding of the logging architecture (see ADRs)

## Quick Diagnosis Checklist

Before diving into detailed troubleshooting, run this quick health check:

```bash
# Check ArgoCD applications
oc get applications -n openshift-gitops

# Check operator installations
oc get csv -A | grep -E "(external-secrets|loki|logging|observability)"

# Check logging namespace
oc get pods -n openshift-logging

# Check External Secrets system
oc get pods -n external-secrets-system
```

## ArgoCD Application Issues

### Problem: Application Stuck in "OutOfSync" State

**Symptoms:**
- ArgoCD shows application as "OutOfSync"
- Manual sync attempts fail
- Resources not being created

**Diagnosis:**
```bash
# Check application details
oc describe application argocd-loki-operator -n openshift-gitops

# Check sync operation status
oc get application argocd-loki-operator -n openshift-gitops -o yaml | grep -A 20 status
```

**Solution:**
1. **Check for resource conflicts:**
   ```bash
   # Look for existing resources that might conflict
   oc get crd | grep loki
   oc get operatorgroups -A
   ```

2. **Force refresh and sync:**
   ```bash
   # Via ArgoCD CLI (if available)
   argocd app sync argocd-loki-operator --force

   # Or delete and recreate the application
   oc delete application argocd-loki-operator -n openshift-gitops
   oc apply -f apps/applications/argocd-loki-operator.yaml
   ```

3. **Check sync waves and dependencies:**
   ```bash
   # Ensure operators are installed in correct order
   # External Secrets → Loki Operator → Logging Operator → Observability
   ```

### Problem: Application Showing "Unknown" Health

**Symptoms:**
- ArgoCD shows "Unknown" health status
- Resources exist but health status unclear

**Diagnosis:**
```bash
# Check resource status in detail
oc get application argocd-external-secrets-operator -n openshift-gitops -o jsonpath='{.status.resources[*].health}'
```

**Solution:**
1. **Check operator readiness:**
   ```bash
   # Verify CSV status
   oc get csv -n openshift-operators | grep external-secrets
   # Should show "Succeeded" phase
   ```

2. **Restart ArgoCD if needed:**
   ```bash
   oc rollout restart deployment/openshift-gitops-application-controller -n openshift-gitops
   ```

## Operator Installation Issues

### Problem: External Secrets Operator Not Installing

**Symptoms:**
- CSV shows "Failed" or "Installing" state indefinitely
- Operator pods not starting

**Diagnosis:**
```bash
# Check CSV details
oc describe csv external-secrets-operator.v0.11.0 -n openshift-operators

# Check operator events
oc get events -n openshift-operators --sort-by='.lastTimestamp'
```

**Solution:**
1. **Check resource requirements:**
   ```bash
   # Ensure cluster has sufficient resources
   oc describe nodes | grep -E "(CPU|Memory).*:"
   ```

2. **Verify OperatorGroup:**
   ```bash
   # Check if OperatorGroup exists and is correct
   oc get operatorgroup -n openshift-operators
   oc describe operatorgroup global-operators -n openshift-operators
   ```

3. **Reinstall operator:**
   ```bash
   # Delete failed CSV
   oc delete csv external-secrets-operator.v0.11.0 -n openshift-operators
   
   # Reapply subscription
   oc apply -f base/external-secrets-operator/subscription.yaml
   ```

### Problem: Loki Operator Installation Fails

**Symptoms:**
- Loki CSV installation fails
- Pod creation errors

**Diagnosis:**
```bash
# Check specific CSV
oc describe csv loki-operator.v5.9.6 -n openshift-operators

# Check pod logs if available
oc logs deployment/loki-operator-controller-manager -n openshift-operators
```

**Solution:**
1. **Check CRD conflicts:**
   ```bash
   # Look for existing Loki CRDs
   oc get crd | grep loki
   
   # If found, check ownership
   oc describe crd lokistacks.loki.grafana.com
   ```

2. **Verify OpenShift version compatibility:**
   ```bash
   # Ensure OpenShift 4.18+ for Loki Operator v5.9.6
   oc version
   ```

## External Secrets Issues

### Problem: ClusterSecretStore Not Connecting to AWS

**Symptoms:**
- ExternalSecrets showing "SecretSyncError"
- AWS authentication failures

**Diagnosis:**
```bash
# Check ClusterSecretStore status
oc describe clustersecretstore aws-secrets-manager

# Check External Secrets controller logs
oc logs deployment/external-secrets -n external-secrets-system
```

**Solution:**
1. **Verify AWS credentials:**
   ```bash
   # Check secret exists and has correct keys
   oc get secret aws-credentials -n external-secrets-system -o yaml
   
   # Decode and verify (be careful with sensitive data)
   oc get secret aws-credentials -n external-secrets-system -o jsonpath='{.data.access-key-id}' | base64 -d
   ```

2. **Test AWS connectivity:**
   ```bash
   # Create test pod to verify AWS access
   oc run aws-test --image=amazon/aws-cli --rm -it -- aws sts get-caller-identity
   ```

3. **Check IAM permissions:**
   - Ensure IAM user has `secretsmanager:GetSecretValue` permission
   - Verify secret ARN is accessible from cluster region

### Problem: ExternalSecret Not Creating Target Secret

**Symptoms:**
- ExternalSecret shows "Ready" but target secret doesn't exist
- Sync errors in ExternalSecret status

**Diagnosis:**
```bash
# Check ExternalSecret status
oc describe externalsecret logging-loki-s3 -n openshift-logging

# Check target namespace
oc get secrets -n openshift-logging | grep loki
```

**Solution:**
1. **Verify secret structure in AWS:**
   ```bash
   # Check secret exists and has correct keys
   aws secretsmanager get-secret-value --secret-id openshift-logging-s3-credentials
   ```

2. **Check namespace and RBAC:**
   ```bash
   # Ensure target namespace exists
   oc get namespace openshift-logging
   
   # Check if service account has permissions
   oc describe clusterrole external-secrets-operator
   ```

## LokiStack Deployment Issues

### Problem: LokiStack Pods Not Starting

**Symptoms:**
- LokiStack shows "Pending" or "Failed" status
- Pods stuck in pending state

**Diagnosis:**
```bash
# Check LokiStack status
oc describe lokistack logging-loki -n openshift-logging

# Check pod events
oc get events -n openshift-logging --sort-by='.lastTimestamp'
```

**Solution:**
1. **Check S3 secret:**
   ```bash
   # Verify secret exists and has correct format
   oc get secret logging-loki-s3 -n openshift-logging -o yaml
   
   # Check required keys: access_key_id, access_key_secret, bucketnames, endpoint, region
   ```

2. **Verify S3 connectivity:**
   ```bash
   # Test S3 access from cluster
   oc run s3-test --image=amazon/aws-cli --rm -it \
     --env="AWS_ACCESS_KEY_ID=<key>" \
     --env="AWS_SECRET_ACCESS_KEY=<secret>" \
     -- aws s3 ls s3://my-cluster-logging-loki
   ```

3. **Check storage class:**
   ```bash
   # Ensure storage class exists and is working
   oc get storageclass
   oc describe storageclass gp3-csi
   ```

## Log Collection Issues

### Problem: No Logs Appearing in Loki

**Symptoms:**
- LokiStack is running but no logs visible
- Vector collector pods running but not forwarding

**Diagnosis:**
```bash
# Check ClusterLogging instance
oc describe clusterlogging instance -n openshift-logging

# Check Vector collector logs
oc logs daemonset/collector -n openshift-logging

# Check ClusterLogForwarder
oc describe clusterlogforwarder instance -n openshift-logging
```

**Solution:**
1. **Verify ClusterLogForwarder output configuration:**
   ```bash
   # Check Loki gateway URL is correct
   oc get service -n openshift-logging | grep loki-gateway
   
   # Test connectivity
   oc run test-curl --image=curlimages/curl --rm -it \
     -- curl -k https://logging-loki-gateway-http.openshift-logging.svc:8080/ready
   ```

2. **Check tenant configuration:**
   ```yaml
   # Ensure tenantKey matches LokiStack tenants mode
   spec:
     outputs:
     - name: loki-app
       type: loki
       loki:
         tenantKey: kubernetes.namespace_name  # For mode: application
   ```

3. **Restart log collection:**
   ```bash
   # Restart Vector collectors
   oc rollout restart daemonset/collector -n openshift-logging
   ```

## Performance and Resource Issues

### Problem: High Resource Usage

**Symptoms:**
- Loki pods consuming excessive CPU/memory
- Slow log queries
- OOMKilled pod restarts

**Diagnosis:**
```bash
# Check resource usage
oc top pods -n openshift-logging

# Check pod resource limits
oc describe pod <loki-pod-name> -n openshift-logging | grep -A 10 "Limits"
```

**Solution:**
1. **Implement resource sizing from ADR-0006:**
   ```bash
   # Update LokiStack size
   oc patch lokistack logging-loki -n openshift-logging --type='merge' -p='{"spec":{"size":"1x.medium"}}'
   ```

2. **Tune retention policies:**
   ```yaml
   # Update storage configuration
   spec:
     storage:
       schemas:
       - version: v13
         effectiveDate: "2024-01-01"
         objectStorage:
           effectiveDateRetention: 30d  # Reduce if needed
   ```

## S3 Storage Issues

### Problem: S3 Connection Failures

**Symptoms:**
- Loki logs showing S3 connection errors
- "NoCredentialsError" or "AccessDenied" errors

**Diagnosis:**
```bash
# Check Loki logs for S3 errors
oc logs deployment/logging-loki-distributor -n openshift-logging | grep -i s3

# Verify S3 configuration
oc get secret logging-loki-s3 -n openshift-logging -o jsonpath='{.data}' | base64 -d
```

**Solution:**
1. **Verify S3 bucket permissions:**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "s3:GetObject",
           "s3:PutObject", 
           "s3:DeleteObject",
           "s3:ListBucket"
         ],
         "Resource": [
           "arn:aws:s3:::my-cluster-logging-loki",
           "arn:aws:s3:::my-cluster-logging-loki/*"
         ]
       }
     ]
   }
   ```

2. **Test S3 access manually:**
   ```bash
   # From Loki pod
   oc exec -it deployment/logging-loki-distributor -n openshift-logging -- \
     /bin/sh -c 'aws s3 ls s3://$BUCKET_NAME'
   ```

## Escalation Path

If issues persist after following this guide:

1. **Collect comprehensive logs:**
   ```bash
   # Create diagnostic bundle
   oc adm must-gather --image=quay.io/openshift/origin-must-gather:latest
   ```

2. **Check ADR decisions:**
   - Review relevant ADRs for architecture context
   - Ensure implementation matches documented decisions

3. **Engage support:**
   - Red Hat support for OpenShift issues
   - Community forums for Loki-specific problems
   - Internal team escalation with diagnostic data

## Prevention Best Practices

- **Monitor ArgoCD sync status regularly**
- **Implement health checks from ADR-0007**
- **Use staging environment for testing changes**
- **Document custom configurations**
- **Regular backup of critical secrets and configurations**

This troubleshooting guide focuses on the operational aspects of deploying and maintaining the OpenShift logging infrastructure, aligning with the architectural decisions documented in the ADRs.

### Correlate Events with Incidents

1. **Set specific time range during incident:**
   - Use the time picker to focus on the incident window
   - Example: 14:30-14:45 if incident occurred at 14:35

2. **Compare with baseline period:**
   ```
   # During incident
   count_over_time({namespace="my-app-namespace"} |~ "(?i)error"[1m])
   
   # Compare with previous day/hour
   count_over_time({namespace="my-app-namespace"} |~ "(?i)error"[1m] offset 1h)
   ```

### Track Error Progression

1. **Error timeline:**
   ```
   {namespace="my-app-namespace"} |~ "(?i)error" | line_format "{{.timestamp}} {{.level}} {{.msg}}"
   ```

2. **Escalation patterns:**
   ```
   {namespace="my-app-namespace"} |~ "(?i)(warn|error|fatal)" | line_format "{{.timestamp}} {{.level}}: {{.msg}}"
   ```

## Advanced Debugging Techniques

### Multi-Service Tracing

1. **Follow request across services:**
   ```
   {namespace=~"my-app-.*"} |~ "request-id.*12345" | line_format "{{.timestamp}} [{{.pod}}] {{.msg}}"
   ```

2. **Trace user sessions:**
   ```
   {namespace="my-app-namespace"} |~ "session.*abc123" | line_format "{{.timestamp}} {{.msg}}"
   ```

### Container-Level Analysis

1. **Compare containers in same pod:**
   ```
   {namespace="my-app-namespace", pod="my-pod-123", container="app-container"}
   {namespace="my-app-namespace", pod="my-pod-123", container="sidecar-container"}
   ```

2. **Find container restart reasons:**
   ```
   {namespace="my-app-namespace"} |~ "(?i)(restart|exit|kill|term)" | line_format "{{.timestamp}} [{{.pod}}] {{.msg}}"
   ```

## Collaborative Debugging

### Share Findings with Team

1. **Copy query URL:** The URL automatically updates with your query
2. **Export specific logs:** Use the export function for detailed analysis
3. **Document patterns:** Save frequently used queries as team runbooks

### Create Debug Sessions

1. **Live debugging:** Use auto-refresh during active incidents
2. **Historical analysis:** Turn off auto-refresh for focused investigation
3. **Time synchronization:** Ensure team members use same time range

## Common Debugging Workflows

### The "5 W's" Approach

1. **What happened?**
   ```
   {namespace="my-app-namespace"} |~ "(?i)error" | line_format "{{.msg}}"
   ```

2. **When did it happen?**
   - Use time picker to narrow timeframe
   - Look for first occurrence patterns

3. **Where did it happen?**
   ```
   {namespace="my-app-namespace"} |~ "(?i)error" | line_format "[{{.pod}}] {{.msg}}"
   ```

4. **Who was affected?**
   ```
   {namespace="my-app-namespace"} |~ "user.*error" | line_format "{{.msg}}"
   ```

5. **Why did it happen?**
   - Look for preceding events
   - Check for configuration changes
   - Analyze error context

### Root Cause Analysis

1. **Identify symptoms:**
   - Start with user-reported errors
   - Look for application-level errors

2. **Trace backwards:**
   - Find when symptoms first appeared
   - Look for configuration changes
   - Check for resource constraints

3. **Verify hypothesis:**
   - Test theories with targeted queries
   - Compare with known-good periods
   - Look for correlation patterns

## Best Practices

- **Start broad, narrow down:** Begin with namespace-level queries, then focus
- **Use time boundaries:** Always set appropriate time ranges for performance
- **Save useful queries:** Document patterns for future debugging
- **Combine with metrics:** Use logs alongside monitoring dashboards
- **Consider log levels:** Understand your application's logging levels (DEBUG, INFO, WARN, ERROR)

## Next Steps

- Learn about setting up log-based alerts for proactive monitoring
- Explore log aggregation patterns for complex applications
- Set up dashboard integrations for operational workflows
