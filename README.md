# QwennHide

Root hider untuk **Magisk Alpha + NeoZygisk** dengan **runtime mode switcher**. Baca otomatis DenyList Magisk — cukup centang aplikasi di Magisk, module menangani sisanya.

![Version](https://img.shields.io/badge/version-v1.7.0-blue)
![Magisk](https://img.shields.io/badge/Magisk-Alpha+-green)
![License](https://img.shields.io/badge/license-MIT-orange)

---

## ✨ Fitur Utama

- ✅ **Auto DenyList** — Baca otomatis dari Magisk Alpha via native API (`PROCESS_ON_DENYLIST`)
- ✅ **Zero Config** — Cukup centang aplikasi di Magisk DenyList, tidak perlu edit file
- ✅ **Runtime Mode Switcher** — Ganti mode Basic/Aggressive via tombol **Action** di Magisk, tanpa reboot
- ✅ **Dual-Mode Architecture**:
  - **Basic Mode**: Module unload dari memory, minimal footprint
  - **Aggressive Mode**: PLT hook + companion daemon untuk app agresif
- ✅ **PLT Hooking** — Hook 9 fungsi syscall (`stat`, `open`, `openat`, `access`, dll)
- ✅ **Property Spoofing** — Palsukan `ro.build.tags`, `ro.debuggable`, `ro.boot.*`, dll
- ✅ **Path Hiding** — Sembunyikan `/system/bin/su`, `/data/adb`, `/debug_ramdisk`, dll
- ✅ **Companion Daemon** — Root process untuk unmount namespace di app target
- ✅ **Clean Uninstall** — Tidak meninggalkan bekas setelah dihapus
- ✅ **Auto-Build** — GitHub Actions compile otomatis untuk arm64-v8a & armeabi-v7a

---

## 📱 Cara Install

### 1. Download Module
- Buka tab **Actions** di repository GitHub
- Klik workflow run terbaru (centang hijau ✅)
- Download artifact `qwennhide-v1.7.0.zip` dari bagian **Artifacts**

### 2. Flash Module
- Buka aplikasi **Magisk** → **Modules** → **Install from storage**
- Pilih file `qwennhide-v1.7.0.zip`
- **Reboot** perangkat

### 3. Konfigurasi DenyList
- Buka **Magisk** → **Settings** ⚙️
- Aktifkan **Zygisk**
- **Enforce DenyList**: OFF (disarankan — module menangani sendiri)
- Tap **Configure DenyList**
- **Centang aplikasi** yang ingin disembunyikan rootnya
- Selesai! Module otomatis mendeteksi saat aplikasi diluncurkan

---

## 🎛️ Cara Pakai: Mode Switcher

### Via Tombol Action (UI Magisk)
1. Buka **Magisk** → **Modules**
2. Cari module **QwennHide**
3. Tap tombol **Action** 🎯
4. Pilih mode:
   - `[1]` Basic mode
   - `[2]` Aggressive mode
5. Perubahan berlaku untuk aplikasi yang diluncurkan **setelah toggle**

### Via Terminal
```bash
# Cek mode saat ini
su -c /data/adb/modules/qwennhide/action.sh status

# Switch ke aggressive
su -c /data/adb/modules/qwennhide/action.sh aggressive

# Switch ke basic
su -c /data/adb/modules/qwennhide/action.sh basic
