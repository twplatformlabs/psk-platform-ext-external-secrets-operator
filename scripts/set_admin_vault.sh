#!/usr/bin/env bash

# the argocd core reconciliation loop runs every 3min
sleep 240

cluster_role=$1

external_secrets_operator_chart_version=$(jq -er .external_secrets_operator_chart_version environments/$cluster_role.json)
argocd_namespace=$(jq -er .argocd_namespace environments/$cluster_role.json)

cat <<EOF > tpl/platform-vault.yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: onepassword-platform-service-account
  namespace: $argocd_namespace
type: Opaque
stringData:
  op-service-account-token: $OP_SERVICE_ACCOUNT_TOKEN

---
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: platform-vault
  namespace: $argocd_namespace
spec:
  conditions:
      - namespaceSelector:
          matchLabels:
            platform-vault: "true"    # annotate a ns with this label to use this vault
      - namespaces:
          - "kube-system"
  provider:
    onepasswordSDK:
      vault: platform
      auth:
        serviceAccountSecretRef:
          name: onepassword-platform-service-account
          namespace: $argocd_namespace
          key: op-service-account-token 
EOF
kubectl apply -f tpl/platform-vault.yaml
