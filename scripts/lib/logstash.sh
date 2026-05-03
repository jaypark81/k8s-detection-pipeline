#!/usr/bin/env bash
source "$(dirname "$0")/lib/common.sh"

install_logstash() {
  log_info "Deploying Logstash..."

  kubectl apply -f logstash/configmap-pipeline.yaml
  kubectl apply -f elastic/logstash.yaml
  wait_for_health logstash siem elastic-system green 300

  log_success "Logstash deployed"
}

uninstall_logstash() {
  log_info "Removing Logstash..."
  kubectl delete -f elastic/logstash.yaml --ignore-not-found
  kubectl delete -f logstash/configmap-pipeline.yaml --ignore-not-found
  log_success "Logstash removed"
}
