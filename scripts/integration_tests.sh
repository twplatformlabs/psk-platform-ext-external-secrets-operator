#!/usr/bin/env bash
set -euo pipefail
source bash-functions.sh

cluster=$1
cluster_role=$2
argocd_namespace=$(jq -er .argocd_namespace environments/$cluster_role.json)
external_secrets_operator_chart_version=$(jq -er .external_secrets_operator_chart_version environments/$cluster_role.json)

# confirm new version has been synced
validate_argocore_helm_app_resource "$argocd_namespace" "external-secrets-operator" "$external_secrets_operator_chart_version"

# run basic smoketest for external-secrets operator health
bats test/external-secrets-operator-service-check.bats

# write a value, then read it - proves functional health

# Files that will be applied
TEST_FILES=("test-secret.yaml" "write-test-secret.yaml" "read-test-secret.yaml")
cleanup() {
  echo "Deleting test files..."
  for f in "${TEST_FILES[@]}"; do
    kubectl delete -f "$f" --ignore-not-found=true
    echo "  removed: $f"
  done
}
trap cleanup EXIT INT TERM

# get unique value
uuid=$(date +%s%N)

# create test secret from uuid
cat <<EOF > test/test-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: test-secret
  namespace: $argocd_namespace
stringData:
  test-field: "$uuid"
EOF
kubectl apply -f test/test-secret.yaml

# write the secret value to platform-vault
cat <<EOF > test/write-test-secret.yaml
apiVersion: external-secrets.io/v1alpha1
kind: PushSecret
metadata:
  name: push-test-secret
  namespace: $argocd_namespace
spec:
  deletionPolicy: Delete
  refreshInterval: 1h0m0s
  secretStoreRefs:
    - name: platform-vault
      kind: ClusterSecretStore
  selector:
    secret:
      name: test-secret                 # Source Kubernetes secret
  data:
    - match:
        secretKey: test-field           # Source Kubernetes secret key to be pushed
        remoteRef:
          remoteKey: test-fixture-eso   # 1Password item name
          property: test-field          # Field label within the 1Password item

EOF
kubectl apply -f test/write-test-secret.yaml
sleep 15

# create ExternalSecret referencing the test-secret
cat <<EOF > test/read-test-secret.yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: fetch-from-onepassword
  namespace: $argocd_namespace
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: platform-vault
  data:
    - secretKey: test-uuid-value
      remoteRef:
        key: test-fixture-eso/test-field

EOF
kubectl apply -f test/read-test-secret.yaml

# print ExternalSecret status
kubectl get externalsecret fetch-from-onepassword -n "$argocd_namespace" \
  -o jsonpath='{.status.conditions[0]}' | jq .

# read the value from platform-vault
ACTUAL=$(kubectl get secret fetch-from-onepassword -n "$argocd_namespace" \
  -o jsonpath="{.data.test-uuid-value}" | base64 -d)

# expect value in 1password vault to match what was just written
if [[ "$ACTUAL" == "$uuid" ]]; then
  echo "✓ PASS: test-uuid-value matches expected value"
  EXIT_CODE=0
else
  echo "✗ FAIL: test-uuid-value does not match"
  echo "  expected: $uuid"
  echo "  actual:   $ACTUAL"
  EXIT_CODE=1
fi
exit $EXIT_CODE