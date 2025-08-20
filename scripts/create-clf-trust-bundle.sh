#!/bin/bash
# Create ClusterLogForwarder Trust Bundle from Cert Manager Root CA
# This script extracts the Root CA certificate from Cert Manager and creates
# the properly formatted secret for ClusterLogForwarder TLS verification

set -euo pipefail

# Configuration
ROOT_CA_SECRET="internal-root-ca-secret"
ROOT_CA_NAMESPACE="cert-manager"
CLF_SECRET="clf-trust-bundle"
CLF_NAMESPACE="openshift-logging"
TEMP_FILE="/tmp/internal-root-ca.pem"

echo "🔐 Creating ClusterLogForwarder Trust Bundle from Cert Manager Root CA"

# Step 1: Verify Cert Manager Root CA secret exists
echo "📋 Step 1: Verifying Cert Manager Root CA secret..."
if ! oc get secret "$ROOT_CA_SECRET" -n "$ROOT_CA_NAMESPACE" >/dev/null 2>&1; then
    echo "❌ ERROR: Root CA secret '$ROOT_CA_SECRET' not found in namespace '$ROOT_CA_NAMESPACE'"
    echo "   Please ensure Cert Manager PKI is deployed first:"
    echo "   oc apply -f base/cluster-log-forwarder/option-b-cert-manager-pki.yaml"
    exit 1
fi
echo "✅ Root CA secret found"

# Step 2: Extract Root CA certificate
echo "📋 Step 2: Extracting Root CA certificate..."
oc get secret "$ROOT_CA_SECRET" -n "$ROOT_CA_NAMESPACE" \
    -o jsonpath='{.data.tls\.crt}' | base64 -d > "$TEMP_FILE"

if [[ ! -s "$TEMP_FILE" ]]; then
    echo "❌ ERROR: Failed to extract Root CA certificate"
    exit 1
fi

# Verify certificate format
if ! openssl x509 -in "$TEMP_FILE" -text -noout >/dev/null 2>&1; then
    echo "❌ ERROR: Extracted certificate is not valid PEM format"
    exit 1
fi

echo "✅ Root CA certificate extracted and validated"

# Step 3: Display certificate information
echo "📋 Step 3: Certificate Information:"
echo "   Subject: $(openssl x509 -in "$TEMP_FILE" -subject -noout | sed 's/subject=//')"
echo "   Issuer:  $(openssl x509 -in "$TEMP_FILE" -issuer -noout | sed 's/issuer=//')"
echo "   Valid:   $(openssl x509 -in "$TEMP_FILE" -dates -noout | grep notAfter | sed 's/notAfter=//')"

# Step 4: Create or update ClusterLogForwarder trust bundle secret
echo "📋 Step 4: Creating ClusterLogForwarder trust bundle secret..."

# Delete existing secret if it exists
if oc get secret "$CLF_SECRET" -n "$CLF_NAMESPACE" >/dev/null 2>&1; then
    echo "   Updating existing secret '$CLF_SECRET'"
    oc delete secret "$CLF_SECRET" -n "$CLF_NAMESPACE"
else
    echo "   Creating new secret '$CLF_SECRET'"
fi

# Create secret with proper key name for ClusterLogForwarder
oc create secret generic "$CLF_SECRET" -n "$CLF_NAMESPACE" \
    --from-file=ca-bundle.crt="$TEMP_FILE" \
    --dry-run=client -o yaml | oc apply -f -

# Add labels for tracking
oc label secret "$CLF_SECRET" -n "$CLF_NAMESPACE" \
    app.kubernetes.io/name=cluster-log-forwarder \
    app.kubernetes.io/component=trust-bundle \
    app.kubernetes.io/part-of=openshift-logging \
    logging.openshift.io/implementation-option=b-cert-manager \
    logging.openshift.io/source-secret="$ROOT_CA_SECRET" \
    logging.openshift.io/source-namespace="$ROOT_CA_NAMESPACE" \
    --overwrite

echo "✅ ClusterLogForwarder trust bundle secret created successfully"

# Step 5: Verify secret contents
echo "📋 Step 5: Verifying secret contents..."
SECRET_CERT=$(oc get secret "$CLF_SECRET" -n "$CLF_NAMESPACE" \
    -o jsonpath='{.data.ca-bundle\.crt}' | base64 -d)

if [[ "$SECRET_CERT" == "$(cat "$TEMP_FILE")" ]]; then
    echo "✅ Secret contents verified - matches Root CA certificate"
else
    echo "❌ ERROR: Secret contents do not match Root CA certificate"
    exit 1
fi

# Step 6: Cleanup
rm -f "$TEMP_FILE"

echo ""
echo "🎉 SUCCESS: ClusterLogForwarder trust bundle created!"
echo ""
echo "Next steps:"
echo "1. Apply Option B ClusterLogForwarder configuration:"
echo "   oc apply -f base/cluster-log-forwarder/option-b-full-validation.yaml"
echo ""
echo "2. Verify Vector logs for successful TLS verification:"
echo "   oc logs -f -l app.kubernetes.io/name=vector -n openshift-logging | grep -E 'TLS|certificate'"
echo ""
echo "3. Check log delivery success:"
echo "   oc logs -l app.kubernetes.io/name=vector -n openshift-logging | grep 'successfully sent'"
echo ""

# Display secret information for reference
echo "📊 Secret Information:"
echo "   Name: $CLF_SECRET"
echo "   Namespace: $CLF_NAMESPACE"
echo "   Key: ca-bundle.crt"
echo "   Size: $(oc get secret "$CLF_SECRET" -n "$CLF_NAMESPACE" -o jsonpath='{.data.ca-bundle\.crt}' | wc -c) bytes (base64)"
echo ""
