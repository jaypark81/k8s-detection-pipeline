#!/usr/bin/env bash
source "$(dirname "$0")/lib/common.sh"

install_fluent_bit() {
  local env=$1
  local cluster_name=$2

  log_info "Deploying Fluent Bit (env=${env}, cluster=${cluster_name})..."

  # Patch cluster name
  kubectl create configmap fluent-bit-env \
    --from-literal=CLUSTER_NAME="${cluster_name}" \
    -n kube-system --dry-run=client -o yaml | kubectl apply -f -

  kubectl apply -k "fluent-bit/overlays/${env}/"
  wait_for_rollout daemonset fluent-bit kube-system

  log_success "Fluent Bit deployed"
}

uninstall_fluent_bit() {
  local env=$1

  log_info "Removing Fluent Bit..."
  kubectl delete -k "fluent-bit/overlays/${env}/" --ignore-not-found
  kubectl delete configmap fluent-bit-env -n kube-system --ignore-not-found
  log_success "Fluent Bit removed"
}
