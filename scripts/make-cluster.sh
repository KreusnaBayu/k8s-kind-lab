#!/usr/bin/env bash
# Membuat cluster kind "belajar" (1 control-plane + 2 worker) lengkap dengan
# ingress-nginx, metrics-server, ArgoCD, dan Sealed Secrets.
set -euo pipefail

CLUSTER_NAME="belajar"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SEALED_SECRETS_VERSION="v0.41.2"

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

kubectl config use-context "kind-$CLUSTER_NAME" >/dev/null

echo ">> Menunggu semua node Ready"
kubectl wait --for=condition=Ready node --all --timeout=300s

echo ">> Memasang ingress-nginx"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl patch deployment ingress-nginx-controller -n ingress-nginx --type=merge -p '{"spec":{"template":{"spec":{"nodeSelector":{"ingress-ready":"true"},"tolerations":[{"key":"node-role.kubernetes.io/control-plane","operator":"Equal","effect":"NoSchedule"},{"key":"node-role.kubernetes.io/master","operator":"Equal","effect":"NoSchedule"}]}}}}'
kubectl wait --namespace ingress-nginx --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=600s

echo ">> Memasang metrics-server"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
if ! kubectl get deployment -n kube-system metrics-server \
  -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q -- '--kubelet-insecure-tls'; then
  kubectl patch -n kube-system deployment metrics-server --type=json \
    -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
fi
kubectl rollout status -n kube-system deployment/metrics-server --timeout=300s

echo ">> Memasang ArgoCD (server-side apply)"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait -n argocd --for=condition=available deployment --all --timeout=600s
kubectl rollout status -n argocd statefulset/argocd-application-controller --timeout=600s

echo ">> Memasang Sealed Secrets ${SEALED_SECRETS_VERSION}"
kubectl apply -f "https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/controller.yaml"
kubectl rollout status -n kube-system deployment/sealed-secrets-controller --timeout=300s

echo
echo "Selesai. Cluster siap."
echo "Berikutnya: reseal myapp-secret dengan kunci cluster ini, commit + push,"
echo "lalu: kubectl apply -f argocd/app-myapp.yaml -f argocd/app-myapp-policies.yaml"
