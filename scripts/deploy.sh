#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/storage.sh"
source "${SCRIPT_DIR}/lib/eck.sh"
source "${SCRIPT_DIR}/lib/kafka.sh"
source "${SCRIPT_DIR}/lib/falco.sh"
source "${SCRIPT_DIR}/lib/hitchhiker.sh"
source "${SCRIPT_DIR}/lib/fluent-bit.sh"
source "${SCRIPT_DIR}/lib/logstash.sh"
source "${SCRIPT_DIR}/lib/cert-manager.sh"

# ── Defaults ─────────────────────────────────────────────────────────────────
ENV=""
CLUSTER_NAME=""

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --env           Deployment environment: self-hosted | eks (required)
  --cluster-name  Cluster name used for metadata tagging (required)
  -h, --help      Show this help message

Example:
  $0 --env self-hosted --cluster-name kuber-1
  $0 --env eks --cluster-name prod-eks
EOF
}

# ── Parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --env)          ENV=$2;          shift 2 ;;
    --cluster-name) CLUSTER_NAME=$2; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *) log_error "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

# ── Validate ──────────────────────────────────────────────────────────────────
if [[ -z "${ENV}" ]]; then
  log_error "--env is required"
  usage; exit 1
fi

if [[ -z "${CLUSTER_NAME}" ]]; then
  log_error "--cluster-name is required"
  usage; exit 1
fi

if [[ "${ENV}" != "self-hosted" && "${ENV}" != "eks" ]]; then
  log_error "--env must be self-hosted or eks"
  usage; exit 1
fi

require_cmd kubectl
require_cmd helm

log_info "========================================"
log_info " K8S-DETECTION-PIPELINE Deploy"
log_info " env=${ENV}  cluster=${CLUSTER_NAME}"
log_info "========================================"

# ── Deploy ────────────────────────────────────────────────────────────────────

# 1. Storage (self-hosted only)
if [[ "${ENV}" == "self-hosted" ]]; then
  install_storage
fi

install_cert_manager

# 2. Falco
install_falco "${ENV}"

# 3. ECK (Elasticsearch + Kibana)
install_eck "${CLUSTER_NAME}"

# 4. Kafka
install_kafka

# 5. Hitchhiker (webhook + Redis)
install_hitchhiker "${ENV}" "${CLUSTER_NAME}"

# 6. Fluent Bit
install_fluent_bit "${ENV}" "${CLUSTER_NAME}"

# 7. Logstash
install_logstash

# 8. Lambda (eks only)
if [[ "${ENV}" == "eks" ]]; then
  log_info "Deploying Lambda..."
  bash lambda/builder.sh
  log_success "Lambda deployed"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
log_success "========================================"
log_success " Deployment complete!"
log_success "========================================"
log_info "Kibana: https://$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}'):30561"
log_info "ES Password: $(kubectl -n elastic-system get secret siem-es-elastic-user \
  -o go-template='{{.data.elastic | base64decode}}')"
