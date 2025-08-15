# OpenShift Logging GitOps Setup Guide

This guide provides step-by-step instructions to set up a GitOps-driven OpenShift Logging stack using ArgoCD (OpenShift GitOps) on an OpenShift 4.18+ cluster.

## Prerequisites
- Access to an OpenShift 4.18+ cluster with cluster-admin privileges
- `oc` CLI installed and logged in
- Git access to this repository

## 1. Install OpenShift GitOps (ArgoCD)

1. Install OpenShift GitOps (ArgoCD) using the provided kustomize base:
  ```sh
  oc create -k base/openshift-gitops
  ```

  If you see an error about missing CRDs for `ArgoCD`, this is expected if the OpenShift GitOps Operator is not fully installed yet. Wait a few minutes for the operator to finish installing and register the CRDs, then re-run the command above.

2. Wait for the ArgoCD pods to be ready:
  ```sh
  oc get pods -n openshift-gitops
  ```

## 2. Verify Cluster State

- List all projects:
  ```sh
  oc get projects
  ```
- Check operator status:
  ```sh
  oc get csv -A
  ```

## 3. Prepare GitOps Repository

- Clone this repository:
  ```sh
  git clone <your-fork-or-this-repo-url>
  cd openshift-logging-gitops
  ```

## 4. Deploy Logging Stack via ArgoCD

1. Log in to the ArgoCD UI (see OpenShift Console > Networking > Routes in `openshift-gitops` namespace).
2. Deploy the External Secrets Operator (ESO) first, to manage S3 credentials for Loki:
   ```sh
   oc apply -f apps/applications/argocd-external-secrets-operator.yaml -n openshift-gitops
   ```
3. Add your S3 credentials as an ExternalSecret or SecretStore resource, following the ESO documentation and your cloud provider's best practices. Example (replace with your values):
   ```yaml
   apiVersion: external-secrets.io/v1alpha1
   kind: SecretStore
   metadata:
     name: s3-secret-store
     namespace: external-secrets-operator
   spec:
     provider:
       aws:
         service: SecretsManager
         region: <your-region>
         auth:
           secretRef:
             accessKeyIDSecretRef:
               name: aws-creds
               key: access-key-id
             secretAccessKeySecretRef:
               name: aws-creds
               key: secret-access-key
   ---
   apiVersion: external-secrets.io/v1alpha1
   kind: ExternalSecret
   metadata:
     name: loki-s3-creds
     namespace: openshift-logging
   spec:
     refreshInterval: 1h
     secretStoreRef:
       name: s3-secret-store
       kind: SecretStore
     target:
       name: loki-s3-creds
     data:
     - secretKey: access_key_id
       remoteRef:
         key: <remote-key-for-access-key-id>
     - secretKey: secret_access_key
       remoteRef:
         key: <remote-key-for-secret-access-key>
   ```
   Ensure the secret is available in the namespace where Loki will run before deploying the Loki operator and stack.
4. Deploy the rest of the logging stack applications:
   ```sh
   oc apply -f apps/applications/ -n openshift-gitops
   ```
5. Monitor the deployment in the ArgoCD UI or with:
   ```sh
   oc get applications.argoproj.io -A
   ```

## 5. Validate Logging Stack

- Check that the Loki, Logging, and Observability operators are installed and running in their respective namespaces.
- Confirm that the LokiStack and ClusterLogForwarder resources are created and healthy.

## 6. Troubleshooting

- Check pod and operator status in each namespace:
  ```sh
  oc get pods -n openshift-logging
  oc get pods -n openshift-operators
  oc get pods -n openshift-observability-operator
  ```
- Review ArgoCD sync status and events in the UI or with:
  ```sh
  oc describe application <app-name> -n openshift-gitops
  ```

## 7. References
- [OpenShift GitOps Documentation](https://docs.openshift.com/container-platform/latest/cicd/gitops/understanding-openshift-gitops.html)
- [OpenShift Logging Documentation](https://docs.openshift.com/container-platform/latest/logging/cluster-logging.html)
- [Loki Operator](https://github.com/grafana/loki-operator)

---

_This README will be updated as the project evolves. Please contribute improvements!_
