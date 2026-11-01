#!/usr/bin/env bash
# Membuat cluster kind "belajar" lengkap dengan ingress-nginx dan metrics-server.
set -euo pipefail

CLUSTER_NAME="belajar"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for cmd in docker kind kubectl; do
  command -v "$cmd" >/dev/null || { echo "ERROR: $cmd belum terpasang"; exit 1; }
done

if [ "$(stat -fc %T /sys/fs/cgroup/)" != "cgroup2fs" ]; then
  echo "ERROR: cgroup v1 terdeteksi. Aktifkan cgroup v2 (lihat README)."
  exit 1
fi

if kind get clusters | grep -qx "$CLUSTER_NAME"; then
  echo "Cluster $CLUSTER_NAME sudah ada, lewati pembuatan."
else
  kind create cluster --config "$ROOT/cluster/kind-config.yaml"
fi

echo ">> Memasang ingress-nginx"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=600s

echo ">> Memasang metrics-server"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch -n kube-system deployment metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl rollout status -n kube-system deployment/metrics-server --timeout=300s

echo "Selesai. Lanjut: scripts/deploy-apps.sh"
