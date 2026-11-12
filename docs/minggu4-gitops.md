# Minggu 4: GitOps dengan ArgoCD dan Sealed Secrets

Cluster kind multi-node dikelola dengan pola GitOps: Git adalah sumber kebenaran,
ArgoCD menyinkronkan isi repo ke cluster, dan rahasia disimpan terenkripsi
dengan Sealed Secrets. Hasil akhir diuji dengan membangun ulang cluster dari nol.

## Lingkungan uji

| Komponen | Versi / keterangan |
|---|---|
| OS | Windows + WSL2 Ubuntu 24.04 (cgroup v2) |
| Docker | 29.9.3 |
| kind | v0.33.0 (1 control-plane + 2 worker) |
| Kubernetes | v1.37.0 |
| kubectl | v1.37.2 |
| ingress-nginx | controller v1.15.1 |
| metrics-server | v0.9.1 |
| Sealed Secrets | controller dan kubeseal v0.41.2 |
| ArgoCD | channel `stable` (belum dipin) |

## Arsitektur

```
GitHub (branch master)
   |  dibaca ArgoCD (automated sync, prune, selfHeal)
   v
ArgoCD (namespace argocd)
   |-- Application myapp           -> apps/myapp
   |-- Application myapp-policies  -> apps/myapp-policies
   v
Cluster kind "belajar"
   |-- ingress-nginx (di control-plane, port host 8080/8443)
   |-- myapp (Deployment, Service, Ingress, ConfigMap)
   |-- myapp-secret (dibuat controller dari SealedSecret)
   |-- NetworkPolicy, ServiceAccount, Role, RoleBinding
```

- `selfHeal`: perubahan manual di cluster dikembalikan ke keadaan di Git.
- `prune`: resource yang dihapus dari Git ikut dihapus dari cluster.
- HPA sengaja disimpan di `manifests/` (arsip) dan tidak dikelola ArgoCD.

## Sealed Secrets

SealedSecret hanya bisa didekripsi oleh controller yang memegang kunci privat
pasangannya. Kunci itu dibuat saat controller pertama kali berjalan, sehingga
**setiap cluster baru wajib me-reseal secret**.

Buktinya, setelah rebuild dan sebelum reseal, log controller menampilkan:

```
reason: 'ErrUnsealFailed' ... no key could decrypt secret (DB_USER, DB_PASSWORD)
```

Pod `myapp` tertahan di `ContainerCreating` sampai Secret terbentuk.

Cara reseal tanpa membocorkan password (tidak tampil di layar, tidak masuk
riwayat shell, tidak pernah ditulis ke disk dalam bentuk plaintext):

```bash
read -r -p "DB_USER: " DB_USER
read -r -s -p "DB_PASSWORD: " DB_PASSWORD; echo
kubectl create secret generic myapp-secret --namespace default \
  --from-literal=DB_USER="$DB_USER" \
  --from-literal=DB_PASSWORD="$DB_PASSWORD" \
  --dry-run=client -o yaml \
  | kubeseal --controller-name=sealed-secrets-controller \
      --controller-namespace=kube-system --format yaml \
  > apps/myapp/sealedsecret-myapp.yaml
unset DB_USER DB_PASSWORD
```

Pemeriksaan sebelum commit:

```bash
grep -c "kind: Secret$" apps/myapp/sealedsecret-myapp.yaml   # harus 0
git diff --stat                                              # hanya file SealedSecret
```

Nama dan namespace (`myapp-secret`, `default`) serta nama key harus sama persis
dengan yang dirujuk `deployment-myapp.yaml`, karena SealedSecret terikat ke
nama dan namespace.

## Uji bangun ulang dari nol

```bash
kind delete cluster --name belajar
time ./scripts/make-cluster.sh
kubectl apply -f argocd/app-myapp.yaml -f argocd/app-myapp-policies.yaml
# reseal myapp-secret (lihat bagian Sealed Secrets), commit, push
kubectl annotate application myapp -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl get applications -n argocd
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: myapp.local" http://localhost:8080/
```

`make-cluster.sh` membuat cluster, menunggu semua node Ready, lalu memasang
ingress-nginx, metrics-server, ArgoCD (server-side apply), dan Sealed Secrets.
Script aman dijalankan ulang.

Hasil uji:

| Fase | Waktu |
|---|---|
| `make-cluster.sh` | 6m43s |
| Total sampai `Synced/Healthy` dan HTTP 200 | sekitar 11 sampai 12 menit (perkiraan, jam mulai tidak dicatat) |

Hasil akhir: `myapp` dan `myapp-policies` berstatus `Synced` dan `Healthy`,
dan request lewat ingress mengembalikan `200`.

## Pelajaran dari cluster multi-node

Di cluster single-node dua masalah ini tidak pernah muncul.

### 1. Controller ingress mendarat di worker

- Gejala: `curl localhost:8080` mengembalikan `000` (`Connection reset by peer`).
- Penyebab: pemetaan port 8080 hanya ada di container control-plane, sedangkan
  pod ingress-nginx dijadwalkan di worker.
- Perbaikan: `nodeSelector ingress-ready=true` dan toleration control-plane,
  dipasang lewat `kubectl patch` di `make-cluster.sh`.
- Bukti: setelah rebuild, pod controller langsung berjalan di
  `belajar-control-plane` tanpa perbaikan manual.

### 2. NetworkPolicy memblokir ingress-nginx

- Gejala: setelah controller dipindah, `curl` mengembalikan `504`.
- Diagnosis: rute antar-node sehat, dua pod di worker berbeda saling terhubung
  (200), dan log kindnet bersih. Setelah NetworkPolicy dihapus sementara,
  ingress kembali `200`.
- Penyebab: `myapp-allow-klien` hanya mengizinkan pod berlabel `peran=klien`.
- Perbaikan di Git: tambahan `namespaceSelector` untuk namespace `ingress-nginx`
  pada `apps/myapp-policies/netpol-myapp.yaml`.

```yaml
ingress:
  - from:
      - podSelector:
          matchLabels:
            peran: klien
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: ingress-nginx
    ports:
      - protocol: TCP
        port: 80
```

Dua entri `from` terpisah berarti OR: pod `peran=klien` atau namespace `ingress-nginx`.

## Koreksi temuan Minggu 3: NetworkPolicy ditegakkan di setup ini

Di Minggu 3, NetworkPolicy tidak ditegakkan kindnet di kernel WSL2 (error
nftables, lihat `docs/kindnet-nftables-error.txt`). Di setup yang dipakai pada
Minggu 4 hasilnya berbeda:

| Uji | Dari node | Label pod uji | Hasil |
|---|---|---|---|
| uji-blokir | worker2 (antar-node) | tanpa | `000` (diblokir) |
| uji-klien | worker2 (antar-node) | `peran=klien` | `200` (lolos) |
| uji-blokir2 | worker (node yang sama dengan myapp) | tanpa | `000` (diblokir) |

Pembanding `uji-klien = 200` memastikan DNS, image, dan jalur jaringan sehat,
jadi `000` berasal dari policy.

Ini pengamatan per lingkungan, bukan kesimpulan umum. Penyebab perbedaan
(kernel, versi kindnet, atau konfigurasi) belum diselidiki. Catatan lama
dipertahankan sebagai dokumentasi setup sebelumnya.

## Batasan yang diketahui

- Manifest ArgoCD masih memakai channel `stable`, sehingga hasilnya bisa
  berubah seiring waktu. Versi ingress-nginx, metrics-server, dan Sealed Secrets
  dipin ke tag rilis.
- Reseal tidak bisa diotomasi: kunci controller berbeda di tiap cluster, dan
  hasil reseal harus di-commit ke Git.
- Penyebab NetworkPolicy tidak ditegakkan di setup Minggu 3 belum diketahui.
- Cluster ini lokal (kind di WSL2). Bukan lingkungan produksi.
