#!/usr/bin/env bash
install_hitchhiker() {
  local env=$1
  local cluster_name=$2
  local git_sha
  image_sha=$(grep 'tag:' hitchhikers/k8s/values.yaml | awk '{print $2}' | tr -d '"')
  local image="ghcr.io/jaypark81/hitchhiker-webhook:${image_sha}"

  log_info "Deploying Hitchhiker webhook + Redis (image: ${image})..."
  kubectl create namespace hitchhiker --dry-run=client -o yaml | kubectl apply -f -

  # Copy ES secret to hitchhiker namespace
  local es_password
  es_password=$(kubectl -n elastic-system get secret siem-es-elastic-user \
    -o go-template='{{.data.elastic | base64decode}}')
  kubectl create secret generic siem-es-elastic-user \
    -n hitchhiker \
    --from-literal=elastic=${es_password} \
    --dry-run=client -o yaml | kubectl apply -f -

  sed \
    -e "s|image: hitchhiker-webhook:00000|image: ${image}|g" \
    -e "s|value: \"cluster-name\"|value: \"${cluster_name}\"|g" \
    hitchhikers/k8s/manifests.yaml | kubectl apply -f -

  wait_for_rollout deployment hitchhiker-webhook hitchhiker
  log_success "Hitchhiker deployed (${image})"
}

uninstall_hitchhiker() {
  log_info "Removing Hitchhiker..."
  kubectl delete -f hitchhikers/k8s/manifests.yaml --ignore-not-found
  kubectl delete namespace hitchhiker --ignore-not-found
  log_success "Hitchhiker removed"
}
