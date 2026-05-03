#!/usr/bin/env bash
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

install_storage() {
  log_info "Installing local-path-provisioner..."

  if kubectl get storageclass local-path &>/dev/null; then
    log_warn "local-path storageclass already exists, skipping"
    return 0
  fi

  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.31/deploy/local-path-storage.yaml
  wait_for_rollout deployment local-path-provisioner local-path-storage

  # Set as default storageclass
  kubectl patch storageclass local-path \
    -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

  log_success "local-path-provisioner installed"
}

uninstall_storage() {
  log_info "Removing local-path-provisioner..."
  kubectl delete -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.31/deploy/local-path-storage.yaml \
    --ignore-not-found
  log_success "local-path-provisioner removed"
}
