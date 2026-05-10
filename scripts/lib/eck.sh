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
  apply_ilm

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

apply_ilm() {
  local es_password
  es_password=$(kubectl -n elastic-system get secret siem-es-elastic-user \
    -o go-template='{{.data.elastic | base64decode}}')

  local es_url
  es_url=$(kubectl get service siem-es-http -n elastic-system \
    -o jsonpath='{.spec.clusterIP}')

  log_info "Applying ILM policy..."
  curl -sk -u "elastic:${es_password}" \
    -X PUT "https://${es_url}:9200/_ilm/policy/siem-cleanup" \
    -H "Content-Type: application/json" \
    -d '{
            "policy": {
                "phases": {
                    "hot": {
                        "actions": {
                            "rollover": {
                                "max_primary_shard_size": "500mb",
                                "max_age": "1d"
                            }
                        }
                    },
                    "delete": {
                        "min_age": "1d",
                        "actions": { "delete": {} }
                    }
                }
            }
    }'

  curl -sk -u "elastic:${es_password}" \
    -X PUT "https://${es_url}:9200/_index_template/siem-template" \
    -H "Content-Type: application/json" \
    -d '{
            "priority": 200,
            "index_patterns": ["logs-*"],
            "data_stream": {},
            "template": {
                "settings": {
                    "index.lifecycle.name": "siem-cleanup"
                }
            }
        }'
  log_success "ILM policy applied"
}

copy_es_secret() {
  local es_password
  es_password=$(kubectl -n elastic-system get secret siem-es-elastic-user \
    -o go-template='{{.data.elastic | base64decode}}')

  kubectl create secret generic siem-es-elastic-user \
    -n hitchhiker \
    --from-literal=elastic=${es_password} \
    --dry-run=client -o yaml | kubectl apply -f -

  log_success "ES secret copied to hitchhiker namespace"
}
