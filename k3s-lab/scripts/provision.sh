#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Error handling
trap 'echo "ERROR: Provisioning failed at line $LINENO" >&2; exit 1' ERR

# ------------ Config via env (Vagrantfile passes these) ------------
VM_IP="${VM_IP:-10.0.1.90}"
RELEASE_NAME="${RELEASE_NAME:-myrelease}"
RELEASE_NS="${RELEASE_NS:-checkmk-monitoring}"
NODEPORT="${NODEPORT:-30035}"
CHART_REPO="${CHART_REPO:-https://checkmk.github.io/checkmk_kube_agent}"
CHART_NAME="${CHART_NAME:-checkmk-chart/checkmk}"

# Paths on the guest
VALUES_ORIG="/home/ubuntu/values.original.yaml"
VALUES_AMENDED="/home/ubuntu/values.yaml"
VALUES_HASH_PATH="/home/ubuntu/.values.sha256"
TOKEN_FILE="/home/ubuntu/token.txt"
CA_FILE="/home/ubuntu/ca.crt"

echo "[*] Base packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl ca-certificates apt-transport-https jq bash-completion

# ------------ Expand disk to use full allocation (libvirt workaround) ------------
echo "[*] Expanding LVM to use full disk..."
pvresize /dev/vda3 2>/dev/null || true
lvextend -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv 2>/dev/null || true
resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv 2>/dev/null || true
df -h /

# ------------ k3s install / ensure running (idempotent) ------------
if ! systemctl is-active --quiet k3s; then
  echo "[*] Installing k3s..."
  curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=${K3S_CHANNEL:-stable} sh -s - server \
    --write-kubeconfig-mode=644 \
    --node-ip="${VM_IP}"
  # allow kubeconfig to appear
  sleep 8
fi

# ------------ Configure insecure registry for local Docker registry ------------
echo "[*] Configuring k3s for insecure registry at 192.168.121.1:5000..."
mkdir -p /etc/rancher/k3s
cat >/etc/rancher/k3s/registries.yaml <<'EOF'
mirrors:
  192.168.121.1:5000:
    endpoint:
      - http://192.168.121.1:5000
configs:
  192.168.121.1:5000:
    tls:
      insecure_skip_verify: true
EOF
systemctl restart k3s
sleep 3

# kubeconfig: point API to the LAN IP
if grep -q 'server: https://127.0.0.1:6443' /etc/rancher/k3s/k3s.yaml; then
  sed -i "s#https://127\.0\.0\.1:6443#https://${VM_IP}:6443#" /etc/rancher/k3s/k3s.yaml
fi

# make kubeconfig available to root & vagrant user, and export globally
mkdir -p /home/vagrant/.kube /root/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >/etc/profile.d/k3s.sh
chmod +x /etc/profile.d/k3s.sh
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# wait for node Ready
echo "[*] Waiting for Kubernetes node to be Ready..."
for i in {1..120}; do
  if kubectl get nodes >/dev/null 2>&1; then
    if kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' | grep -q True; then
      echo "    Node Ready."
      break
    fi
  fi
  sleep 2
  [[ $i -eq 120 ]] && echo "ERROR: Node not ready in time" && exit 1
done

# ------------ Helm install / repo ------------
if ! command -v helm >/dev/null 2>&1; then
  echo "[*] Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# add chart repo (idempotent)
helm repo add checkmk-chart "${CHART_REPO}" >/dev/null 2>&1 || true
helm repo update

# ------------ yq install (for amending values) ------------
if ! command -v yq >/dev/null 2>&1; then
  echo "[*] Installing yq..."
  YQ_VER=v4.44.3
  curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VER}/yq_linux_amd64" -o /usr/local/bin/yq
  chmod +x /usr/local/bin/yq
fi

# ------------ Build values.yaml from upstream defaults ------------
echo "[*] Fetching chart defaults and amending..."
helm show values "${CHART_NAME}" > "${VALUES_ORIG}"
cp -f "${VALUES_ORIG}" "${VALUES_AMENDED}"

# k3s containerd socket (so container metrics work)
yq -i '.containerdOverride = "/run/k3s/containerd/containerd.sock"' "${VALUES_AMENDED}"

# expose clusterCollector via NodePort
yq -i '.clusterCollector.service.type = "NodePort"' "${VALUES_AMENDED}"
yq -i ".clusterCollector.service.nodePort = ${NODEPORT}" "${VALUES_AMENDED}"

chown ubuntu:ubuntu "${VALUES_ORIG}" "${VALUES_AMENDED}"

# compute hash for idempotence
NEW_HASH=$(sha256sum "${VALUES_AMENDED}" | awk '{print $1}')
OLD_HASH=$(cat "${VALUES_HASH_PATH}" 2>/dev/null || true)

# ------------ Health function for Helm release ------------
is_release_healthy() {
  helm status "${RELEASE_NAME}" -n "${RELEASE_NS}" >/dev/null 2>&1 || return 1
  kubectl -n "${RELEASE_NS}" get svc "${RELEASE_NAME}-checkmk-cluster-collector" >/dev/null 2>&1 || return 1
  kubectl -n "${RELEASE_NS}" wait --for=condition=Available deployment --all --timeout=120s >/dev/null 2>&1 || return 1
  kubectl -n "${RELEASE_NS}" wait --for=condition=Ready pod -l app.kubernetes.io/instance="${RELEASE_NAME}" --timeout=120s >/dev/null 2>&1 || return 1
  return 0
}

# ------------ Deploy / Upgrade ------------
NEED_DEPLOY=0
if ! is_release_healthy; then
  echo "[*] Release missing or not healthy -> (re)deploy."
  NEED_DEPLOY=1
elif [[ "${NEW_HASH}" != "${OLD_HASH}" ]]; then
  echo "[*] values.yaml changed -> upgrade."
  NEED_DEPLOY=1
else
  echo "[*] Release healthy and values unchanged -> skipping Helm upgrade."
fi

if [[ "${NEED_DEPLOY}" -eq 1 ]]; then
  echo "[*] Applying Helm release..."
  helm upgrade --install --atomic --wait --timeout 5m \
    -n "${RELEASE_NS}" --create-namespace \
    "${RELEASE_NAME}" "${CHART_NAME}" -f "${VALUES_AMENDED}"

  echo "${NEW_HASH}" > "${VALUES_HASH_PATH}"
  chown ubuntu:ubuntu "${VALUES_HASH_PATH}"
fi

# ------------ Export token & CA ------------
echo "[*] Exporting Checkmk token and CA..."
TOKEN_SECRET="${RELEASE_NAME}-checkmk-checkmk"
kubectl -n "${RELEASE_NS}" get secret "${TOKEN_SECRET}" -o jsonpath='{.data.token}' | base64 -d > "${TOKEN_FILE}"
kubectl -n "${RELEASE_NS}" get secret "${TOKEN_SECRET}" -o jsonpath='{.data.ca\.crt}' | base64 -d > "${CA_FILE}"
chown ubuntu:ubuntu "${TOKEN_FILE}" "${CA_FILE}"
chmod 600 "${TOKEN_FILE}" "${CA_FILE}"

# ------------ Info helper ------------
cat >/home/ubuntu/checkmk_info.sh <<EOSH
#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
NS="${RELEASE_NS}"
REL="${RELEASE_NAME}"
NODE_IP="${VM_IP}"
NODE_PORT=\$(kubectl -n "\$NS" get svc \${REL}-checkmk-cluster-collector -o jsonpath="{.spec.ports[0].nodePort}")
echo "Cluster Collector URL: http://\$NODE_IP:\$NODE_PORT"
echo "Token: /home/ubuntu/token.txt"
echo "CA:    /home/ubuntu/ca.crt"
echo
TOKEN=\$(cat /home/ubuntu/token.txt)
echo "Metadata (Bearer auth):"
curl -sS -H "Authorization: Bearer \$TOKEN" http://\$NODE_IP:\$NODE_PORT/metadata | jq .
EOSH
chmod +x /home/ubuntu/checkmk_info.sh
chown ubuntu:ubuntu /home/ubuntu/checkmk_info.sh

echo
echo "[*] Done."
echo "    URL:  http://${VM_IP}:${NODEPORT}"
echo "    Token: ${TOKEN_FILE}"
echo "    CA:    ${CA_FILE}"
echo "    Info:  ssh ubuntu@${VM_IP} && bash /home/ubuntu/checkmk_info.sh"
