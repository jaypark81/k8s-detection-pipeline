#!/usr/bin/env bash
source "$(dirname "$0")/lib/common.sh"

ECK_VERSION="3.3.2"

install_eck() {
  local cluster_name=$1

  log_info "Installing ECK operator v${ECK_VERSION}..."
  kubectl apply -f "https://download.elastic.co/downloads/eck/${ECK_VERSION}/crds.yaml"
  kubectl apply -f "https://download.elastic.co/downloads/eck/${ECK_VERSION}/operator.yaml"
  wait_for_rollout statefulset elastic-operator elastic-system

  log_info "Deploying Elasticsearch..."
  kubectl apply -f elastic/elasticsearch.yaml
  wait_for_es 600

  log_info "Deploying Kibana..."
  kubectl apply -f elastic/kibana.yaml
  wait_for_health kibana siem elastic-system green 300

  log_success "ECK stack deployed"
  local es_password
  es_password=$(kubectl -n elastic-system get secret siem-es-elastic-user \
    -o go-template='{{.data.elastic | base64decode}}')
  log_info "Kibana URL: https://<NODE_IP>:30561"
  log_info "ES Password: ${es_password}"
}

uninstall_eck() {
  log_info "Removing ECK resources..."
  kubectl delete kibana siem -n elastic-system --ignore-not-found
  kubectl delete elasticsearch siem -n elastic-system --ignore-not-found
  kubectl delete -f "https://download.elastic.co/downloads/eck/${ECK_VERSION}/operator.yaml" \
    --ignore-not-found
  kubectl delete -f "https://download.elastic.co/downloads/eck/${ECK_VERSION}/crds.yaml" \
    --ignore-not-found
  log_success "ECK removed"
}

wait_for_es() {
  local timeout=${1:-600}
  local interval=10
  local elapsed=0

  log_info "Waiting for Elasticsearch to be ready..."
  while [ $elapsed -lt $timeout ]; do
    health=$(kubectl get elasticsearch siem -n elastic-system \
      -o jsonpath='{.status.health}' 2>/dev/null)
    phase=$(kubectl get elasticsearch siem -n elastic-system \
      -o jsonpath='{.status.phase}' 2>/dev/null)
    if [[ "${health}" == "green" || "${health}" == "yellow" ]] && \
       [[ "${phase}" == "Ready" ]]; then
      log_success "Elasticsearch is ready (health=${health})"
      return 0
    fi
    sleep $interval
    elapsed=$((elapsed + interval))
  done
  log_error "Elasticsearch did not become ready within ${timeout}s"
  exit 1
}
