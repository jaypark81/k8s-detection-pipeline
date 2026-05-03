#!/usr/bin/env bash
source "$(dirname "$0")/lib/common.sh"

install_hitchhiker() {
  local env=$1
  local cluster_name=$2
  local git_sha
  git_sha=$(git rev-parse --short HEAD)
  local image="ghcr.io/jaypark81/hitchhiker-webhook:${git_sha}"

  log_info "Deploying Hitchhiker webhook + Redis (image: ${image})..."
  kubectl create namespace hitchhiker --dry-run=client -o yaml | kubectl apply -f -

  sed \
    -e "s|image: hitchhiker-webhook:00000|image: ${image}|g" \
    -e "s|value: \"cluster-name\"|value: \"${cluster_name}\"|g" \
    hitchhikers/k8s/manifests.yaml | kubectl apply -f -

  wait_for_rollout deployment hitchhiker-webhook hitchhiker
  wait_for_pods hitchhiker app=redis 1
  log_success "Hitchhiker deployed (${image})"
}

uninstall_hitchhiker() {
  log_info "Removing Hitchhiker..."
  kubectl delete -f hitchhikers/k8s/ --ignore-not-found
  kubectl delete namespace hitchhiker --ignore-not-found
  log_success "Hitchhiker removed"
}
