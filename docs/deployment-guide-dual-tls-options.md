# Dual TLS Options Deployment Guide

**Quick Reference**: Choose your implementation path based on urgency and security requirements

---

## 🚨 **Option A: Immediate Resolution (15 minutes)**

**Use Case**: Emergency log delivery restoration, development environments  
**Security**: Encrypted but not verified  
**Timeline**: 15 minutes  

### Quick Deploy
```bash
# Deploy immediate TLS bypass solution
oc apply -f base/cluster-log-forwarder/option-a-tls-bypass.yaml

# Verify log delivery working
oc logs -f -l app.kubernetes.io/name=vector -n openshift-logging | grep "successfully sent"

# Add migration reminder
echo "TODO: Migrate to Option B within 30 days" >> TODO.md
```

### Validation
```bash
# Should see no TLS errors (bypass active)
oc logs -l app.kubernetes.io/name=vector -n openshift-logging --since=2m | grep "certificate verify failed" || echo "✅ No TLS errors"

# Should see successful log delivery
oc logs -l app.kubernetes.io/name=vector -n openshift-logging --since=2m | grep "successfully sent" | wc -l
```

---

## 🔐 **Option B: Production Security (2-4 hours)**

**Use Case**: Production environments, security compliance  
**Security**: Full certificate verification  
**Timeline**: 2-4 hours  

### Step 1: Deploy Cert Manager PKI
```bash
# Deploy internal PKI infrastructure
oc apply -f base/cluster-log-forwarder/option-b-cert-manager-pki.yaml

# Wait for certificates to be ready (2-3 minutes)
oc wait --for=condition=Ready certificate/internal-root-ca -n cert-manager --timeout=300s
oc wait --for=condition=Ready certificate/lokistack-gateway-tls -n openshift-logging --timeout=300s
```

### Step 2: Create Trust Bundle
```bash
# Create ClusterLogForwarder trust bundle from Root CA
./scripts/create-clf-trust-bundle.sh
```

### Step 3: Deploy Full Validation
```bash
# Deploy production TLS configuration
oc apply -f base/cluster-log-forwarder/option-b-full-validation.yaml
```

### Step 4: Configure ArgoCD (if using GitOps)
```bash
# Add ignoreDifferences to ArgoCD Application
oc patch application logging-stack-dev -n openshift-gitops --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/ignoreDifferences",
    "value": [
      {
        "group": "",
        "kind": "Secret",
        "name": "lokistack-gateway-tls-secret",
        "namespace": "openshift-logging",
        "jsonPointers": ["/data"]
      },
      {
        "group": "cert-manager.io",
        "kind": "Certificate",
        "jsonPointers": ["/status"]
      }
    ]
  }
]'
```

### Validation
```bash
# Verify certificate chain
openssl s_client -connect logging-loki-gateway-http.openshift-logging.svc:8080 -CAfile <(oc get secret clf-trust-bundle -n openshift-logging -o jsonpath='{.data.ca-bundle\.crt}' | base64 -d)

# Check Vector logs for successful TLS verification
oc logs -f -l app.kubernetes.io/name=vector -n openshift-logging | grep -E "TLS|certificate"

# Verify log delivery
oc logs -l app.kubernetes.io/name=vector -n openshift-logging | grep "successfully sent" | wc -l
```

---

## 🔄 **Migration Path: A → B**

For teams starting with Option A and migrating to Option B:

### Phase 1: Deploy Option A (Immediate)
```bash
oc apply -f base/cluster-log-forwarder/option-a-tls-bypass.yaml
```

### Phase 2: Implement Option B (Parallel)
```bash
# Deploy PKI infrastructure (parallel to Option A)
oc apply -f base/cluster-log-forwarder/option-b-cert-manager-pki.yaml
./scripts/create-clf-trust-bundle.sh
```

### Phase 3: Cutover (Planned)
```bash
# Switch to Option B during maintenance window
oc apply -f base/cluster-log-forwarder/option-b-full-validation.yaml

# Validate working
oc logs -l app.kubernetes.io/name=vector -n openshift-logging | grep -v "certificate verify failed"
```

---

## 🎯 **Decision Matrix**

| Criteria | Option A | Option B |
|----------|----------|----------|
| **Implementation Time** | 15 minutes | 2-4 hours |
| **Security Level** | Medium | High |
| **Production Ready** | No | Yes |
| **Compliance** | Limited | Full |
| **Maintenance** | Manual migration needed | Automated |
| **Dependencies** | None | Cert Manager |

---

## 🚨 **Troubleshooting**

### Option A Issues
```bash
# If logs still not delivering with bypass
oc logs -l app.kubernetes.io/name=vector -n openshift-logging | grep -E "error|failed"

# Check ClusterLogForwarder status
oc get clusterlogforwarder instance -n openshift-logging -o yaml | grep -A 10 status
```

### Option B Issues
```bash
# Check certificate status
oc get certificates -n openshift-logging
oc get certificates -n cert-manager

# Verify trust bundle secret
oc get secret clf-trust-bundle -n openshift-logging -o yaml

# Test certificate chain manually
openssl verify -CAfile <(oc get secret clf-trust-bundle -n openshift-logging -o jsonpath='{.data.ca-bundle\.crt}' | base64 -d) <(oc get secret lokistack-gateway-tls-secret -n openshift-logging -o jsonpath='{.data.tls\.crt}' | base64 -d)
```

---

## 📊 **Monitoring**

### Option A Monitoring
```bash
# Track migration deadline
oc get clusterlogforwarder instance -n openshift-logging -o jsonpath='{.metadata.annotations.logging\.openshift\.io/migration-deadline}'

# Monitor for security compliance
echo "⚠️  Option A active - migration to Option B required for production"
```

### Option B Monitoring
```bash
# Certificate expiry monitoring
oc get certificates -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[?(@.type=='Ready')].status,EXPIRY:.status.notAfter"

# Cert Manager metrics (if Prometheus available)
# certmanager_certificate_expiration_timestamp_seconds
# certmanager_certificate_ready_status
```

---

## 🎉 **Success Criteria**

### Option A Success
- ✅ Vector logs show no TLS certificate errors
- ✅ Log delivery to Loki Gateway successful
- ✅ Migration plan documented and scheduled

### Option B Success
- ✅ Full certificate verification working
- ✅ Automated certificate renewal configured
- ✅ Monitoring and alerting operational
- ✅ GitOps integration complete

Choose the option that best fits your current needs and timeline!
