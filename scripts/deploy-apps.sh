#!/usr/bin/env bash
# Menerapkan manifest aplikasi myapp. Secret TIDAK disimpan d
#!/usr/bin/env bash
# Menerapkan manifest aplikasi myapp lewat kubectl (alternatif tanpa ArgoCD).
# Secret dikelola lewat SealedSecret (apps/myapp/sealedsecret-myapp.yaml).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

kubectl apply -f "$ROOT/apps/myapp/"

for f in hpa-myapp rbac-dev-reader netpol-myapp; do
  kubectl apply -f "$ROOT/manifests/$f.yaml"
done

kubectl rollout status deployment/myapp
echo "Tes: curl -H 'Host: myapp.local' http://localhost:8080"
