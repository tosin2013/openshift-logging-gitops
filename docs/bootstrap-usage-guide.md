# Bootstrap Script Usage Guide

**Enhanced with Dual TLS Options and ArgoCD Cleanup**

---

## 🚀 **Quick Start**

### **Emergency Log Delivery (15 minutes)**
```bash
# Delete existing ArgoCD app and deploy with TLS bypass
./scripts/bootstrap-environment.sh dev --tls-option=a --clean-argocd --region us-east-1
```

### **Production Security (2-4 hours)**
```bash
# Clean deployment with full certificate validation
./scripts/bootstrap-environment.sh production --tls-option=b --clean-argocd --region us-west-2
```

---

## 🔐 **TLS Options Explained**

### **Option A: Immediate Resolution**
- **Timeline**: 15 minutes
- **Security**: Medium (encrypted but not verified)
- **Use Case**: Emergency situations, development environments
- **Migration**: Required to Option B within 30 days

```bash
./scripts/bootstrap-environment.sh dev --tls-option=a
```

**What it does**:
- ✅ Copies `option-a-tls-bypass.yaml` to environment overlay
- ✅ Configures TLS bypass for immediate log delivery
- ⚠️ Adds migration tracking annotations
- 📋 Provides migration guidance in output

### **Option B: Production Security**
- **Timeline**: 2-4 hours
- **Security**: High (full certificate verification)
- **Use Case**: Production environments, security compliance
- **Maintenance**: Automated certificate lifecycle

```bash
./scripts/bootstrap-environment.sh production --tls-option=b
```

**What it does**:
- 🏗️ Deploys Cert Manager PKI infrastructure
- 🔐 Creates internal Root CA and service certificates
- 🤖 Runs trust bundle creation script
- ✅ Copies full validation configuration to overlay
- 📊 Configures ArgoCD ignoreDifferences for cert management

---

## 🧹 **ArgoCD Cleanup**

### **When to Use --clean-argocd**
- Existing logging-stack application has configuration drift
- Switching between TLS options
- Starting fresh deployment
- Troubleshooting ArgoCD sync issues

```bash
# Clean existing applications before bootstrap
./scripts/bootstrap-environment.sh dev --clean-argocd --tls-option=b
```

**Applications Cleaned**:
- `logging-stack-{environment}`
- `external-secrets-operator`
- `loki-operator`
- `logging-operator`

---

## 📊 **Command Reference**

### **Basic Usage**
```bash
./scripts/bootstrap-environment.sh [ENVIRONMENT] [OPTIONS]
```

### **Environments**
- `dev` - Development (7-day retention)
- `staging` - Staging (30-day retention)
- `production` - Production (90-day retention)

### **TLS Options**
- `--tls-option=a` - Immediate resolution (TLS bypass)
- `--tls-option=b` - Production security (full validation)

### **Additional Options**
- `--clean-argocd` - Delete existing ArgoCD applications
- `--region us-east-1` - Specify AWS region
- `--dry-run` - Preview commands without execution

---

## 🎯 **Common Scenarios**

### **Scenario 1: Emergency Log Delivery**
**Situation**: Logs not being delivered, need immediate fix

```bash
# Quick resolution with cleanup
./scripts/bootstrap-environment.sh dev --tls-option=a --clean-argocd --region us-east-1

# Verify logs flowing
oc logs -f -l app.kubernetes.io/name=vector -n openshift-logging | grep "successfully sent"
```

### **Scenario 2: Production Deployment**
**Situation**: Setting up production logging with full security

```bash
# Production deployment with full validation
./scripts/bootstrap-environment.sh production --tls-option=b --clean-argocd --region us-west-2

# Monitor certificate readiness
oc get certificates -A
oc logs -l app.kubernetes.io/name=vector -n openshift-logging | grep -E "TLS|certificate"
```

### **Scenario 3: Migration A → B**
**Situation**: Migrating from emergency fix to production security

```bash
# Step 1: Current state (Option A active)
oc get clusterlogforwarder instance -n openshift-logging -o jsonpath='{.metadata.annotations}'

# Step 2: Deploy Option B infrastructure in parallel
./scripts/bootstrap-environment.sh dev --tls-option=b --region us-east-1

# Step 3: Switch during maintenance window (handled by ArgoCD sync)
```

### **Scenario 4: Troubleshooting**
**Situation**: ArgoCD application stuck or misconfigured

```bash
# Clean slate deployment with dry-run first
./scripts/bootstrap-environment.sh dev --clean-argocd --tls-option=b --dry-run

# If dry-run looks good, execute
./scripts/bootstrap-environment.sh dev --clean-argocd --tls-option=b
```

---

## 🔍 **Verification Steps**

### **After Option A Deployment**
```bash
# Should show no TLS errors (bypass active)
oc logs -l app.kubernetes.io/name=vector -n openshift-logging --since=2m | grep "certificate verify failed" || echo "✅ No TLS errors"

# Check migration annotations
oc get clusterlogforwarder instance -n openshift-logging -o jsonpath='{.metadata.annotations.logging\.openshift\.io/migration-deadline}'
```

### **After Option B Deployment**
```bash
# Verify certificates ready
oc get certificates -n cert-manager
oc get certificates -n openshift-logging

# Check trust bundle
oc get secret clf-trust-bundle -n openshift-logging

# Verify TLS validation working
oc logs -l app.kubernetes.io/name=vector -n openshift-logging | grep -E "TLS|certificate"
```

---

## 🚨 **Troubleshooting**

### **Common Issues**

#### **Issue**: Script hangs at region selection
**Solution**: Use `--region` flag to skip interactive selection
```bash
./scripts/bootstrap-environment.sh dev --tls-option=a --region us-east-1
```

#### **Issue**: Option B certificates not ready
**Solution**: Check Cert Manager status and wait longer
```bash
oc get pods -n cert-manager
oc describe certificate internal-root-ca -n cert-manager
```

#### **Issue**: ArgoCD cleanup fails
**Solution**: Manual cleanup then retry
```bash
oc delete application logging-stack-dev -n openshift-gitops --wait=true
./scripts/bootstrap-environment.sh dev --tls-option=b
```

#### **Issue**: Trust bundle creation fails
**Solution**: Run script manually with debug
```bash
bash -x ./scripts/create-clf-trust-bundle.sh
```

---

## 📚 **Related Documentation**

- **Dual TLS Options**: [docs/deployment-guide-dual-tls-options.md](deployment-guide-dual-tls-options.md)
- **ADR-0016**: [docs/adrs/adr-0016-tls-certificate-resolution-implementation.md](adrs/adr-0016-tls-certificate-resolution-implementation.md)
- **Original Tutorial**: [docs/tutorials/getting-started-with-logging.md](tutorials/getting-started-with-logging.md)

---

## 🎉 **Success Indicators**

### **Bootstrap Complete**
- ✅ Banner shows correct TLS strategy
- ✅ Prerequisites verified
- ✅ AWS resources created
- ✅ TLS configuration deployed
- ✅ ArgoCD applications registered

### **Ready for GitOps Sync**
- ✅ Manual verification steps completed
- ✅ All secrets and certificates ready
- ✅ ArgoCD application shows healthy status
- ✅ Ready to trigger GitOps sync

**Next Step**: Use ArgoCD UI or CLI to sync the `logging-stack-{environment}` application!
