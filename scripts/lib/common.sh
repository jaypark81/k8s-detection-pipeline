#!/usr/bin/env bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# Wait for a deployment/daemonset/statefulset to be ready
wait_for_rollout() {
  local kind=$1
  local name=$2
  local namespace=$3
  local timeout=${4:-300}

  log_info "Waiting for ${kind}/${name} in namespace ${namespace}..."
  kubectl rollout status "${kind}/${name}" -n "${namespace}" --timeout="${timeout}s"
  if [ $? -ne 0 ]; then
    log_error "${kind}/${name} failed to become ready"
    exit 1
  fi
  log_success "${kind}/${name} is ready"
}

# Wait for a CRD resource to reach expected health
wait_for_health() {
  local kind=$1
  local name=$2
  local namespace=$3
  local expected=${4:-green}
  local timeout=${5:-300}
  local interval=10
  local elapsed=0

  log_info "Waiting for ${kind}/${name} health=${expected}..."
  while [ $elapsed -lt $timeout ]; do
    health=$(kubectl get "${kind}" "${name}" -n "${namespace}" \
      -o jsonpath='{.status.health}' 2>/dev/null)
    if [ "${health}" == "${expected}" ]; then
      log_success "${kind}/${name} is ${expected}"
      return 0
    fi
    sleep $interval
    elapsed=$((elapsed + interval))
  done
  log_error "${kind}/${name} did not reach health=${expected} within ${timeout}s"
  exit 1
}

# Wait for pods with label to be running
wait_for_pods() {
  local namespace=$1
  local label=$2
  local expected_count=$3
  local timeout=${4:-300}
  local interval=10
  local elapsed=0

  log_info "Waiting for ${expected_count} pod(s) with label ${label} in ${namespace}..."
  while [ $elapsed -lt $timeout ]; do
    running=$(kubectl get pods -n "${namespace}" -l "${label}" \
      --field-selector=status.phase=Running \
      --no-headers 2>/dev/null | wc -l)
    if [ "${running}" -ge "${expected_count}" ]; then
      log_success "${running} pod(s) running"
      return 0
    fi
    sleep $interval
    elapsed=$((elapsed + interval))
  done
  log_error "Pods with label ${label} did not become ready within ${timeout}s"
  exit 1
}

# Check if a command exists
require_cmd() {
  if ! command -v "$1" &>/dev/null; then
    log_error "Required command not found: $1"
    exit 1
  fi
}
