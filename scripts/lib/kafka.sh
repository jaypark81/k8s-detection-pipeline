#!/usr/bin/env bash
source "$(dirname "$0")/lib/common.sh"

TOPICS=(siem-falco siem-tetragon siem-k8s siem-kyverno siem-k8s-audit)

install_kafka() {
  log_info "Installing Strimzi operator..."

  kubectl create namespace kafka --dry-run=client -o yaml | kubectl apply -f -

  kubectl apply -f "https://strimzi.io/install/latest?namespace=kafka" -n kafka
  wait_for_rollout deployment strimzi-cluster-operator kafka

  log_info "Deploying Kafka cluster..."
  kubectl apply -f kafka/kafka.yaml
  wait_for_kafka 600

  log_info "Creating Kafka topics..."
  kubectl apply -f kafka/topics.yaml

  wait_for_pods kafka strimzi.io/cluster=siem 1
  log_success "Kafka deployed with topics: ${TOPICS[*]}"
}

uninstall_kafka() {
  log_info "Removing Kafka..."
  for topic in "${TOPICS[@]}"; do
    kubectl delete kafkatopic "${topic}" -n kafka --ignore-not-found
  done
  kubectl delete kafka siem -n kafka --ignore-not-found
  kubectl delete kafkanodepool combined -n kafka --ignore-not-found
  kubectl delete -f "https://strimzi.io/install/latest?namespace=kafka" \
    -n kafka --ignore-not-found
  kubectl delete namespace kafka --ignore-not-found
  log_success "Kafka removed"
}

wait_for_kafka() {
  local timeout=${1:-600}
  local interval=10
  local elapsed=0

  log_info "Waiting for Kafka cluster to be ready..."
  while [ $elapsed -lt $timeout ]; do
    ready=$(kubectl get kafka siem -n kafka \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [ "${ready}" == "True" ]; then
      log_success "Kafka is ready"
      return 0
    fi
    sleep $interval
    elapsed=$((elapsed + interval))
  done
  log_error "Kafka did not become ready within ${timeout}s"
  exit 1
}
