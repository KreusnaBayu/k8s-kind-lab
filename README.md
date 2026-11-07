# k8s-kind-lab

Latihan administrasi Kubernetes di cluster lokal (kind di WSL2), dengan manifest
deklaratif dan skrip yang bisa diulang.

## Yang dicakup
Pod, Deployment, Service, ConfigMap, Secret, Ingress (ingress-nginx),
PV/PVC, HPA (metrics-server), RBAC, NetworkPolicy.

## Prasyarat
Docker Engine, kind, kubectl, cgroup v2 (WSL2).

## Cara pakai
```bash
./scripts/make-cluster.sh
DB_PASSWORD=ganti-ini ./scripts/deploy-apps.sh
curl -H "Host: myapp.local" http://localhost:8080
```

## Struktur
- `cluster/` konfigurasi kind (port 8080/8443 untuk Ingress)
- `manifests/` semua manifest Kubernetes
- `scripts/` pembuat cluster dan deploy aplikasi
- `docs/` bukti dan catatan troubleshooting

## Temuan & troubleshooting
1. **cgroup v1 di WSL2**: Kubernetes baru menolak cgroup v1. Perbaikan: tambahkan
   `kernelCommandLine = cgroup_no_v1=all` di `.wslconfig`, lalu `wsl --shutdown`.
2. **`docker-credential-desktop.exe` not found**: sisa `credsStore` Docker Desktop di
   `~/.docker/config.json`. Perbaikan: ganti dengan `{}`.
3. **ConfigMap berubah, env tidak**: file mount diperbarui otomatis, env hanya dibaca saat
   container start. Perlu `kubectl rollout restart`.
4. **Update gagal (`nginx:9.99`)**: rolling update menahan Pod lama tetap hidup
   (maxUnavailable 0 untuk 3 replika), lalu `rollout undo`.
5. **NetworkPolicy tidak ditegakkan**: policy diterima API server, tapi uji `klien-b`
   tetap lolos. Log kindnet menunjukkan `nftables ... operation not supported`
   (kernel WSL2). Lihat `docs/kindnet-nftables-error.txt`. Solusi lanjutan: CNI
   berbasis iptables seperti Calico.
6. **Secret hanya base64**: dibuktikan dengan `base64 -d`; yang melindungi adalah RBAC
   (ServiceAccount `dev-reader` mendapat `Forbidden`).

## Catatan keamanan
Secret tidak disimpan di repo; dibuat lewat skrip dari variabel lingkungan.

## GitOps dengan ArgoCD
- `argocd/app-myapp.yaml`: Application yang memantau `apps/myapp/` (automated, prune, selfHeal).
- Secret dikelola dengan Sealed Secrets: `sealedsecret-myapp.yaml` aman di Git karena terenkripsi.
- Keterbatasan: kunci privat controller hanya ada di cluster. Kalau cluster dihapus,
  SealedSecret harus dibuat ulang dengan `kubeseal`.
- Manifest latihan (`manifests/`) tidak dikelola ArgoCD.
