#!/usr/bin/env bash

install_alerter() {
  local image_sha
  image_sha=$(grep 'tag:' alerter/k8s/values.yaml | awk '{print $2}' | tr -d '"')
  local image="ghcr.io/jaypark81/hitchhiker-alerter:${image_sha}"

  log_info "Deploying Alerter (image: ${image})..."
  sed \
    -e "s|image: alerter:latest|image: ${image}|g" \
    alerter/k8s/manifests.yaml | kubectl apply -f -

  log_success "Alerter deployed (${image})"
}

uninstall_alerter() {
  log_info "Removing Alerter..."
  kubectl delete -f alerter/k8s/manifests.yaml --ignore-not-found
  log_success "Alerter removed"
}
