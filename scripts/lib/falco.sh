#!/usr/bin/env bash
source "$(dirname "$0")/lib/common.sh"

install_falco() {
  local env=$1
  log_info "Installing Falco..."
  require_cmd helm

  helm repo add falcosecurity https://falcosecurity.github.io/charts
  helm repo update

  local values_file="falco/values.yaml"
  helm upgrade --install falco falcosecurity/falco \
    --namespace falco \
    --create-namespace \
    -f "${values_file}" \
    --wait \
    --timeout 300s

  if [[ "${env}" == "self-hosted" ]]; then
    log_info "self-hosted environment requires sudo to configure kube-apiserver audit webhook"
    sudo -v
    configure_audit_webhook
  else
    log_info "Skipping audit webhook config (not self-hosted — configure CloudWatch audit logs manually for EKS)"
  fi

  log_success "Falco installed"
}

uninstall_falco() {
  log_info "Removing Falco..."
  helm uninstall falco -n falco --ignore-not-found
  kubectl delete namespace falco --ignore-not-found
  kubectl delete svc falco -n falco --ignore-not-found 2>/dev/null || true
  log_success "Falco removed"
}

configure_audit_webhook() {
  log_info "Creating Falco service for audit webhook..."
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: falco
  namespace: falco
spec:
  selector:
    app.kubernetes.io/name: falco
  ports:
  - port: 9765
    targetPort: 9765
EOF

  local falco_svc_ip
  falco_svc_ip=$(kubectl get svc -n falco falco -o jsonpath='{.spec.clusterIP}')
  log_info "Falco service ClusterIP: ${falco_svc_ip}"

  log_info "Writing /etc/kubernetes/audit-webhook.yaml..."
  sudo tee /etc/kubernetes/audit-webhook.yaml > /dev/null <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: http://${falco_svc_ip}:9765/k8s-audit
  name: falco
contexts:
- context:
    cluster: falco
    user: ""
  name: default-context
current-context: default-context
preferences: {}
users: []
EOF

  if sudo grep -q "audit-webhook-config-file" /etc/kubernetes/manifests/kube-apiserver.yaml; then
    log_info "audit-webhook flags already present in kube-apiserver.yaml — skipping"
  else
    log_info "Adding audit webhook flags to kube-apiserver.yaml..."
    sudo sed -i '/- --audit-log-path/a\    - --audit-webhook-config-file=\/etc\/kubernetes\/audit-webhook.yaml\n    - --audit-webhook-mode=batch' \
      /etc/kubernetes/manifests/kube-apiserver.yaml
    log_info "Waiting for kube-apiserver to restart..."
    sleep 15
    kubectl wait --for=condition=Ready pod -l component=kube-apiserver \
      -n kube-system --timeout=120s
  fi

  log_success "Audit webhook configured (Falco → ${falco_svc_ip}:9765)"
}
