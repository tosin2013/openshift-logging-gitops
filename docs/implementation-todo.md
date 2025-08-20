# OpenShift Logging Implementation TODO

## 🎯 **Priority-Based Implementation Plan**

Based on cluster status analysis and ADR decisions, here's the prioritized implementation roadmap:

---

## 🚨 **CRITICAL - Immediate Action Required**

### ✅ **Task 1: Implement TLS Certificate Resolution (ADR-0016)**
**Status**: 🔴 BLOCKED - Active log delivery failure  
**Evidence**: Vector TLS errors: `certificate verify failed: self-signed certificate in certificate chain`  
**Impact**: Logs collected but not delivered to storage

#### Subtasks:
- [ ] **1.1** Update ClusterLogForwarder TLS Configuration
  - File: `base/cluster-log-forwarder/cluster-log-forwarder-template.yaml`
  - Add: `tls.caCert.configMapName: openshift-service-ca.crt`
  - Validation: Server-side dry run
  
- [ ] **1.2** Validate TLS Configuration
  ```bash
  kustomize build overlays/dev | oc apply --dry-run=server -f -
  ```
  
- [ ] **1.3** Deploy and Monitor TLS Fix
  - Deploy via GitOps (git push)
  - Monitor Vector logs for TLS resolution
  - Validate log delivery to Loki Gateway

**Success Criteria**: 
- ✅ No TLS certificate verification errors in Vector logs
- ✅ Log delivery successful to Loki Gateway
- ✅ End-to-end log flow operational

---

## 🔧 **HIGH PRIORITY - Infrastructure Gaps**

### ✅ **Task 2: Resolve Cluster Observability Operator Issues (ADR-0014)**
**Status**: 🟡 INVESTIGATION NEEDED  
**Evidence**: CSV Failed - `TooManyOperatorGroups`  
**Impact**: Missing unified observability dashboard and UIPlugin capabilities

#### Subtasks:
- [ ] **2.1** Investigate OperatorGroup Conflicts
  ```bash
  oc get operatorgroups -A
  oc describe csv cluster-observability-operator.v1.2.2 -n openshift-cluster-observability-operator
  ```
  
- [ ] **2.2** Clean Up Conflicting OperatorGroups
  - Identify conflicting groups in observability namespace
  - Remove or consolidate duplicate OperatorGroups
  - Document resolution procedure
  
- [ ] **2.3** Reinstall Cluster Observability Operator
  - Reinstall operator after conflict resolution
  - Validate CSV status: Succeeded
  - Test observability components

**Success Criteria**:
- ✅ Cluster Observability Operator CSV status: Succeeded
- ✅ No OperatorGroup conflicts
- ✅ Observability components healthy

---

### ✅ **Task 3: Address ArgoCD Sync Drift**
**Status**: 🟡 MONITORING NEEDED  
**Evidence**: `logging-stack-dev` OutOfSync but Healthy  
**Impact**: Configuration drift may cause future deployment issues

#### Subtasks:
- [ ] **3.1** Analyze Sync Drift Root Cause
  ```bash
  oc describe application logging-stack-dev -n openshift-gitops
  ```
  
- [ ] **3.2** Implement Sync Health Monitoring
  - Set up alerts for persistent OutOfSync status
  - Document acceptable drift scenarios
  - Create sync remediation procedures

**Success Criteria**:
- ✅ ArgoCD application shows Synced status
- ✅ No configuration drift between Git and cluster
- ✅ Monitoring alerts configured

---

## 🎨 **MEDIUM PRIORITY - User Experience**

### ✅ **Task 4: Implement Logging Console Integration (ADR-0015)**
**Status**: 🟢 READY FOR DEVELOPMENT  
**Evidence**: No logging console plugins, external Loki route only  
**Impact**: Poor user experience requiring external navigation

#### Subtasks:
- [ ] **4.1** Design Console Plugin Architecture
  - Create ConsolePlugin CRD specification
  - Design backend service architecture
  - Plan RBAC integration
  
- [ ] **4.2** Develop Logging Console Plugin Service
  - Implement Loki proxy service
  - Configure secure backend communication
  - Integrate with OpenShift authentication
  
- [ ] **4.3** Deploy and Enable Console Plugin
  ```bash
  oc patch console.operator.openshift.io cluster \
    --type='json' \
    -p='[{"op": "add", "path": "/spec/plugins/-", "value": "logging-plugin"}]'
  ```

**Success Criteria**:
- ✅ Logging tab appears in OpenShift console
- ✅ Users can access logs without external navigation
- ✅ RBAC permissions properly enforced

---

## 📊 **LOW PRIORITY - Operational Excellence**

### ✅ **Task 5: Validate End-to-End Log Flow**
**Status**: 🟢 READY AFTER TLS FIX  
**Evidence**: Collection working, delivery blocked by TLS  
**Impact**: Comprehensive validation needed

#### Subtasks:
- [ ] **5.1** Create Log Flow Validation Procedures
  - Test log generation from sample applications
  - Validate collection by Vector
  - Confirm delivery to Loki Gateway
  - Verify storage in S3 backend
  
- [ ] **5.2** Implement Log Flow Monitoring
  - Set up metrics for log delivery rates
  - Configure alerts for delivery failures
  - Create operational dashboards

**Success Criteria**:
- ✅ Logs flow from source to storage without errors
- ✅ Monitoring and alerting operational
- ✅ Performance baselines established

---

### ✅ **Task 6: Document Implementation Procedures**
**Status**: 🟢 ONGOING  
**Evidence**: ADRs created, operational procedures needed  
**Impact**: Knowledge transfer and operational readiness

#### Subtasks:
- [ ] **6.1** Create TLS Troubleshooting Runbook
  - Document TLS certificate verification procedures
  - Create troubleshooting decision tree
  - Include validation commands
  
- [ ] **6.2** Document Console Plugin Maintenance
  - Plugin update procedures
  - RBAC management
  - Performance monitoring
  
- [ ] **6.3** Create Observability Operator Management Guide
  - OperatorGroup conflict resolution
  - Upgrade procedures
  - Integration testing

**Success Criteria**:
- ✅ Operational runbooks complete
- ✅ Troubleshooting procedures documented
- ✅ Knowledge transfer materials ready

---

## 📈 **Implementation Timeline**

### **Week 1: Critical Issues**
- **Day 1-2**: Implement TLS certificate resolution (Task 1)
- **Day 3-4**: Validate end-to-end log flow (Task 5.1)
- **Day 5**: Address ArgoCD sync issues (Task 3)

### **Week 2: Infrastructure**
- **Day 1-3**: Resolve Cluster Observability Operator (Task 2)
- **Day 4-5**: Begin console plugin design (Task 4.1)

### **Week 3: User Experience**
- **Day 1-4**: Develop and deploy console plugin (Task 4.2-4.3)
- **Day 5**: Complete documentation (Task 6)

---

## 🎯 **Success Metrics**

### **Technical Metrics**
- ✅ Zero TLS certificate verification errors
- ✅ 100% log delivery success rate
- ✅ ArgoCD applications in Synced status
- ✅ Console plugin response time < 2 seconds

### **Operational Metrics**
- ✅ All ADR implementations complete
- ✅ Runbooks and procedures documented
- ✅ Monitoring and alerting operational
- ✅ User acceptance criteria met

---

## 📞 **Escalation Procedures**

### **Critical Issues (Task 1)**
- **Escalate if**: TLS fix doesn't resolve log delivery within 24 hours
- **Contact**: Platform team for certificate infrastructure support

### **Infrastructure Issues (Task 2)**
- **Escalate if**: OperatorGroup conflicts can't be resolved within 48 hours
- **Contact**: OpenShift support for operator installation guidance

### **Development Issues (Task 4)**
- **Escalate if**: Console plugin development blocked > 72 hours
- **Contact**: Frontend development team for console integration support
