# Research Questions: OpenShift Logging 6.3 TLS Certificate Verification Issues

**Generated**: 2025-08-17  
**Priority**: CRITICAL - Blocking log delivery  
**Context**: Vector TLS certificate verification failures with available Cert Manager v1.17.0

---

## 🎯 **Research Context**

### **Current Situation**
- **OpenShift Logging**: v6.3 with observability.openshift.io/v1 API
- **Vector Collectors**: 6 pods running, collecting logs but failing TLS verification
- **Loki Gateway**: Using OpenShift service-serving-signer certificates
- **Available Tools**: Cert Manager v1.17.0, External Secrets v0.11.0, ArgoCD v1.17.0
- **Error**: `certificate verify failed: self-signed certificate in certificate chain`

### **Critical Constraints**
- ❌ **NO insecureSkipVerify** in production
- ✅ **Must maintain security** with proper certificate verification
- ✅ **Must integrate** with existing GitOps workflow
- ✅ **Must be sustainable** with automatic certificate rotation

---

## 🔬 **CRITICAL PRIORITY Research Questions**

### **Q1: OpenShift Logging 6.3 TLS Configuration**
**Priority**: CRITICAL  
**Timeline**: Immediate (4 hours)

#### **Primary Questions**:
1. **What is the correct TLS configuration syntax for ClusterLogForwarder in OpenShift Logging 6.3?**
   - Does `tls.caCert.configMapName` work with `observability.openshift.io/v1` API?
   - Are there breaking changes in TLS configuration between logging versions?
   - What are the supported TLS configuration options in the new API?

2. **Why is the TLS configuration not being applied to the Vector pods?**
   - Is the configuration in ClusterLogForwarder spec or only annotations?
   - Do Vector pods need to be restarted to pick up TLS configuration changes?
   - Are there ArgoCD sync issues preventing configuration updates?

#### **Research Methods**:
- [ ] Review OpenShift Logging 6.3 official documentation
- [ ] Check Red Hat Knowledge Base for TLS configuration examples
- [ ] Analyze working TLS configurations in similar environments
- [ ] Test configuration changes in development environment

#### **Success Criteria**:
- ✅ Vector logs show no TLS certificate verification errors
- ✅ ClusterLogForwarder spec contains correct TLS configuration
- ✅ Log delivery to Loki Gateway succeeds

---

### **Q2: Cert Manager Integration with OpenShift Logging**
**Priority**: HIGH  
**Timeline**: 8 hours

#### **Primary Questions**:
1. **Can Cert Manager issue certificates for internal OpenShift services like Loki Gateway?**
   - What ClusterIssuer should be used for internal service certificates?
   - Can Let's Encrypt issue certificates for .svc.cluster.local domains?
   - Should we use self-signed ClusterIssuer for internal services?

2. **How to integrate Cert Manager certificates with LokiStack/Loki Gateway?**
   - Can LokiStack be configured to use Cert Manager certificates?
   - How to replace OpenShift service CA certificates with Cert Manager certificates?
   - What is the certificate renewal process for Loki Gateway?

#### **Research Methods**:
- [ ] Study Cert Manager documentation for internal service certificates
- [ ] Research LokiStack certificate configuration options
- [ ] Investigate OpenShift service certificate replacement procedures
- [ ] Test Cert Manager certificate issuance for internal services

#### **Success Criteria**:
- ✅ Cert Manager can issue certificates for Loki Gateway
- ✅ Vector can verify Cert Manager issued certificates
- ✅ Certificate renewal works automatically

---

### **Q3: Vector TLS Certificate Verification Mechanisms**
**Priority**: HIGH  
**Timeline**: 6 hours

#### **Primary Questions**:
1. **How does Vector verify TLS certificates in OpenShift environments?**
   - What CA bundle does Vector use by default?
   - Can Vector be configured to use custom CA bundles?
   - How does Vector handle certificate chain validation?

2. **What are the Vector configuration options for TLS in ClusterLogForwarder?**
   - What TLS settings are available in the ClusterLogForwarder spec?
   - Can Vector be configured to use specific CA certificates?
   - Are there Vector-specific TLS troubleshooting commands?

#### **Research Methods**:
- [ ] Review Vector documentation for TLS configuration
- [ ] Analyze Vector pod logs for detailed TLS error information
- [ ] Study ClusterLogForwarder TLS configuration options
- [ ] Test different TLS configuration approaches

#### **Success Criteria**:
- ✅ Understanding of Vector TLS verification process
- ✅ Identification of correct TLS configuration for Vector
- ✅ Working TLS configuration that passes verification

---

## 🔧 **HIGH PRIORITY Research Questions**

### **Q4: ArgoCD Sync Issues Impact on Configuration**
**Priority**: HIGH  
**Timeline**: 4 hours

#### **Primary Questions**:
1. **Why is the logging-stack-dev ArgoCD application showing OutOfSync status?**
   - What resources are causing the sync drift?
   - Is the OutOfSync status preventing TLS configuration updates?
   - How to resolve persistent ArgoCD sync issues?

2. **How to ensure GitOps compatibility with certificate management?**
   - Can Cert Manager certificates be managed through GitOps?
   - How to handle certificate secrets in ArgoCD applications?
   - What is the best practice for certificate lifecycle in GitOps?

#### **Research Methods**:
- [ ] Analyze ArgoCD application sync status and differences
- [ ] Review ArgoCD logs for sync failure reasons
- [ ] Study GitOps patterns for certificate management
- [ ] Test manual sync and configuration application

---

### **Q5: Alternative TLS Configuration Approaches**
**Priority**: MEDIUM  
**Timeline**: 6 hours

#### **Primary Questions**:
1. **What are alternative approaches to resolve Vector TLS verification?**
   - Can we create a custom CA bundle that includes both OpenShift service CA and public CAs?
   - Is there a way to configure Vector to trust multiple CA sources?
   - What are the security implications of different TLS approaches?

2. **How do other organizations solve similar TLS issues in OpenShift Logging?**
   - What are common patterns for TLS in containerized logging?
   - Are there established best practices for certificate management in logging infrastructure?
   - What are the trade-offs between different certificate management approaches?

#### **Research Methods**:
- [ ] Research community solutions for similar TLS issues
- [ ] Study enterprise patterns for logging certificate management
- [ ] Analyze security implications of different approaches
- [ ] Test alternative TLS configuration methods

---

## 📊 **MEDIUM PRIORITY Research Questions**

### **Q6: Long-term Certificate Management Strategy**
**Priority**: MEDIUM  
**Timeline**: 12 hours

#### **Primary Questions**:
1. **What is the optimal certificate management strategy for production logging infrastructure?**
   - Should we standardize on Cert Manager for all certificates?
   - How to handle certificate rotation without service disruption?
   - What monitoring and alerting should be in place for certificate expiry?

2. **How to integrate certificate management with existing External Secrets Operator?**
   - Can External Secrets manage certificate secrets from Cert Manager?
   - How to coordinate between Cert Manager and External Secrets?
   - What are the benefits of integrating these tools?

---

## 🎯 **Research Execution Plan**

### **Phase 1: Immediate Resolution (Day 1)**
**Focus**: Get log delivery working with secure TLS

1. **Execute Q1** (OpenShift Logging 6.3 TLS Configuration)
2. **Execute Q3** (Vector TLS Certificate Verification)
3. **Execute Q4** (ArgoCD Sync Issues)

**Target Outcome**: Working log delivery with proper TLS verification

### **Phase 2: Sustainable Solution (Day 2-3)**
**Focus**: Implement Cert Manager integration

1. **Execute Q2** (Cert Manager Integration)
2. **Execute Q5** (Alternative TLS Approaches)

**Target Outcome**: Cert Manager managed certificates for Loki Gateway

### **Phase 3: Optimization (Week 2)**
**Focus**: Long-term strategy and monitoring

1. **Execute Q6** (Long-term Certificate Management Strategy)

**Target Outcome**: Comprehensive certificate management strategy

---

## 📋 **Research Task Tracking**

### **Critical Tasks (Must Complete Today)**
- [ ] **Q1.1**: Research OpenShift Logging 6.3 TLS configuration syntax
- [ ] **Q1.2**: Debug why TLS config not applied to Vector pods
- [ ] **Q3.1**: Understand Vector TLS verification mechanisms
- [ ] **Q4.1**: Resolve ArgoCD sync issues

### **High Priority Tasks (Complete This Week)**
- [ ] **Q2.1**: Test Cert Manager certificate issuance for internal services
- [ ] **Q2.2**: Configure LokiStack to use Cert Manager certificates
- [ ] **Q5.1**: Research alternative TLS configuration approaches

### **Medium Priority Tasks (Complete Next Week)**
- [ ] **Q6.1**: Design long-term certificate management strategy
- [ ] **Q6.2**: Integrate with External Secrets Operator

---

## 🚨 **Escalation Criteria**

### **Immediate Escalation (4 hours)**
- If Q1 research doesn't identify correct TLS configuration
- If Vector TLS verification cannot be resolved with OpenShift service CA
- If ArgoCD sync issues prevent any configuration updates

### **24-Hour Escalation**
- If Cert Manager integration is not feasible for internal services
- If no working TLS solution can be implemented

### **Contact Information**
- **Platform Team**: For OpenShift and certificate infrastructure
- **Red Hat Support**: For OpenShift Logging specific issues
- **Security Team**: For TLS configuration approval

---

## 📊 **Success Metrics**

### **Technical Success**
- ✅ Zero TLS certificate verification errors in Vector logs
- ✅ 100% log delivery success rate to Loki Gateway
- ✅ ArgoCD application shows Synced status
- ✅ Certificate rotation works automatically

### **Operational Success**
- ✅ Monitoring and alerting for certificate expiry
- ✅ Documented procedures for certificate management
- ✅ Team knowledge transfer complete

### **Security Success**
- ✅ No insecureSkipVerify configurations in production
- ✅ All certificates properly verified
- ✅ Certificate management follows security best practices
