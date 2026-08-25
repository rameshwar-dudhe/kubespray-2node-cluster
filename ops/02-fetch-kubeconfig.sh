#!/usr/bin/env bash
# Pull admin.conf off the control plane and point it at the node IP.
set -euo pipefail
CP_IP=192.168.56.134
mkdir -p "$HOME/.kube"
ssh root@"$CP_IP" 'cat /etc/kubernetes/admin.conf' > "$HOME/.kube/config"
sed -i "s#https://127.0.0.1:6443#https://${CP_IP}:6443#g; s#https://localhost:6443#https://${CP_IP}:6443#g" "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"
echo "kubeconfig written to $HOME/.kube/config"
