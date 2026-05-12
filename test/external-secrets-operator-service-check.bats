#!/usr/bin/env bats

@test "xternal-secrets status is Running" {
  run bash -c "kubectl get pods --selector app.kubernetes.io/name=external-secrets -n psk-system"
  [[ "${output}" =~ "Running" ]]
}

@test "external-secrets-webhook status is Running" {
  run bash -c "kubectl get pods --selector app.kubernetes.io/name=external-secrets-webhook -n psk-system"
  [[ "${output}" =~ "Running" ]]
}

@test "external-secrets-cert-controller status is Running" {
  run bash -c "kubectl get pods --selector app.kubernetes.io/name=external-secrets-cert-controller -n psk-system"
  [[ "${output}" =~ "Running" ]]
}
