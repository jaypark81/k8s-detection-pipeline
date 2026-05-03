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

ENV="self-hosted"

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --env   Deployment environment: self-hosted | eks (default: self-hosted)
  -h, --help  Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --env)    ENV=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

log_warn "========================================"
log_warn " K8S-DETECTION-PIPELINE Uninstall"
log_warn " env=${ENV}"
log_warn "========================================"
read -rp "Are you sure? (yes/no): " confirm
if [[ "${confirm}" != "yes" ]]; then
  log_info "Aborted"
  exit 0
fi

# Reverse order
uninstall_logstash
uninstall_cert_manager
uninstall_fluent_bit "${ENV}"
uninstall_hitchhiker
uninstall_kafka
uninstall_falco
uninstall_eck

if [[ "${ENV}" == "self-hosted" ]]; then
  uninstall_storage
fi

log_success "Uninstall complete"
