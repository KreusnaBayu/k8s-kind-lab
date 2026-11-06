#!/usr/bin/env bash
# Menerapkan manifest aplikasi myapp. Secret TIDAK disimpan di Git.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

DB_USER="${DB_USER:-admin}"
if [ -z "${DB_PASSWORD:-}" ]; then
  echo "ERROR: set dulu DB_PASSWORD, contoh: DB_PASSWORD=ganti-ini $0"
  exit 1
fi

kubectl create secret generic myapp-secret \
  --from-literal=DB_USER="$DB_USER" \
  --from-literal=DB_PASSWORD="$DB_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

for f in configmap-myapp deployment-myapp service-myapp ingress-myapp; do
  kubectl apply -f "$ROOT/apps/myapp/$f.yaml"
done

for f in hpa-myapp rbac-dev-reader netpol-myapp; do
  kubectl apply -f "$ROOT/manifests/$f.yaml"
done

kubectl rollout status deployment/myapp
echo "Tes: curl -H 'Host: myapp.local' http://localhost:8080"
