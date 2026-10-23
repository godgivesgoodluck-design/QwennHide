# QwennHide

Root hider untuk **Magisk Alpha / NeoZygisk / ZygiskNext** dengan **arsitektur companion-based**, **WebUI per-aplikasi**, dan **runtime mode switcher**. Adaptasi dari arsitektur [MagiskHideX](https://github.com/godgivesgoodluck-design/MagiskHideX) yang diperluas untuk kebutuhan GSI dan deteksi modern.

![Version](https://img.shields.io/badge/version-v3.0.0-blue)
![Platform](https://img.shields.io/badge/Android-8.0%2B-green)
![Zygisk](https://img.shields.io/badge/Zygisk-Required-orange)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

---

## ⚠️ Baca Dulu: Apa yang Module Ini Lakukan & Tidak Lakukan

QwennHide adalah **Zygisk module user-space**. Ia bekerja dengan:
- Meminta host (Magisk/NeoZygisk) melakukan unmount overlay dari namespace aplikasi target.
- Membersihkan jejak file descriptor & mount secara manual sebagai lapisan tambahan.
- Memalsukan properti sistem **secara global** (butuh reboot).

Ia **TIDAK**:
- Mengubah kernel, SELinux policy, atau attestation hardware.
- Menjamin lolos dari aplikasi dengan **server-side detection** (data dikirim ke server, server yang memutuskan).
- Mengalahkan teknik deteksi level kernel (KernelSU/APatch native) atau integrity check yang sangat agresif.
- Menyembunyikan keberadaan host Zygisk itu sendiri (Magisk/NeoZygisk) dari detector yang membaca `/proc/self/maps` saat module resident.

Jika tujuan Anda adalah **bypass 100% untuk aplikasi bank kelas atas**, module Zygisk user-space pada umumnya bukan alat yang tepat. Gunakan module ini untuk **aplikasi level menengah** dan sebagai **kerangka belajar/eksperimen** yang bersih dan mudah di-uninstall.

---

## ✨ Fitur

- ✅ **Auto DenyList** — Baca target dari Magisk/NeoZygisk + custom `umount_list`. Tidak perlu Enforce DenyList.
- ✅ **3 Mode Runtime** — Basic / Aggressive / Persistent, dipilih per-aplikasi via WebUI atau global via Action button.
- ✅ **WebUI (KSU Standalone)** — Daftar hanya aplikasi di DenyList, mode selector di kanan tiap baris, indikator status simpan (✓/✗) per aplikasi.
- ✅ **Companion IPC** — Keputusan mode diambil di konteks root, bukan di proses aplikasi (hindari masalah SELinux).
- ✅ **Tanpa PLT Hook** — Hindari integrity check aplikasi modern (yang justru mendeteksi hook).
- ✅ **Property Spoofing Global** — Opsional, dikontrol terpisah, butuh reboot. Termasuk spoofing untuk GSI (bootloader/encryption/build tags).
- ✅ **NeoZygisk Aligned** — Tidak mengganggu daemon/host, skip path NeoZygisk saat unmount manual, `DLCLOSE` dipanggil maksimal 1× per lifecycle.
- ✅ **Uninstall Bersih** — Tidak menulis state persisten di luar folder module; reboot mengembalikan properti asli.
- ✅ **Auto-Build** — GitHub Actions untuk `arm64-v8a` & `armeabi-v7a`.

---

## 🏗️ Arsitektur 3 Mode

| Mode | Host Unmount | Manual FD/Mount Cleanup | NeoZygisk Trace Cleanup | Module Unload (DLCLOSE) | Jejak di `/proc/self/maps` |
|---|---|---|---|---|---|
| **Basic** | ✅ | ❌ | ❌ | ✅ | Bersih |
| **Aggressive** | ✅ | ✅ | ✅ | ✅ | Bersih |
| **Persistent** | ✅ | ✅ | ✅ | ❌ | **Module terlihat** |

**Penjelasan singkat:**
- **Basic** — Ringan, cepat, andalkan host. Cocok untuk aplikasi yang hanya cek saat launch.
- **Aggressive** — Tambah cleanup manual FD + mount Magisk + jejak NeoZygisk. Cocok untuk aplikasi yang scan `/proc/self/fd` dan `/proc/self/mountinfo`.
- **Persistent** — Module tetap resident di memory. **Dibuat untuk aplikasi yang melakukan periodic root check** (cek berulang saat app berjalan). Trade-off: module terlihat di maps, jadi aplikasi yang scan maps bisa menemukannya.

> ⚠️ **Catatan jujur soal Persistent:** Mode ini menjaga kode module tetap di memory, tetapi **tidak memasang hook aktif**. Ia tidak "menyembunyikan" jejak baru secara real-time — ia hanya mencegah module unload sehingga cleanup awal tetap berlaku. Untuk aplikasi dengan periodic check yang membaca ulang `/proc/self/maps`, mode ini **belum tentu lolos**. Uji di device Anda.

---

## 📥 Instalasi

### Prasyarat
- Magisk Alpha ≥ 26402 **atau** NeoZygisk / ZygiskNext
- **Zygisk aktif**
- **Enforce DenyList: OFF** (module menangani sendiri via companion)
- Manager yang support **KSU WebUI** (untuk WebUI). Tanpa WebUI, gunakan Action button sebagai fallback.

### Langkah
1. Download artifact `qwennhide-v3.0.0.zip` dari tab **Actions** → run sukses → **Artifacts**.
2. Flash via Magisk/NeoZygisk → **Reboot**.
3. Buka **Magisk → Configure DenyList** → centang aplikasi target.
4. **(Wajib untuk test)** Clear data aplikasi target:
   ```bash
   adb shell pm clear <package.name>
