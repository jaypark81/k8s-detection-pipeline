#!/usr/bin/env bash
source "$(dirname "$0")/lib/common.sh"

CERT_MANAGER_VERSION="v1.20.2"

install_cert_manager() {
  log_info "Installing cert-manager ${CERT_MANAGER_VERSION}..."

  if kubectl get namespace cert-manager &>/dev/null; then
    log_warn "cert-manager already exists, skipping"
    return 0
  fi

  kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
  wait_for_rollout deployment cert-manager cert-manager
  wait_for_rollout deployment cert-manager-webhook cert-manager
  wait_for_rollout deployment cert-manager-cainjector cert-manager

  log_success "cert-manager installed"
}

uninstall_cert_manager() {
  log_info "Removing cert-manager..."
  kubectl delete -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml" \
    --ignore-not-found
  log_success "cert-manager removed"
}
