# My Root Hider

Root hider untuk **Magisk Alpha + NeoZygisk** yang **otomatis membaca DenyList Magisk**. Tidak perlu edit file manual!

## ✨ Fitur

- ✅ **Auto DenyList** - Baca otomatis dari Magisk Alpha
- ✅ **Zero Config** - Cukup centang app di Magisk app
- ✅ **Direct Mount Manipulation** - Optimal untuk NeoZygisk
- ✅ **Procfs Filtering** - Sembunyikan dari /proc reader
- ✅ **Self-Unload** - Module hilang dari memory app
- ✅ **Auto-Refresh** - DenyList di-refresh setiap 30 detik

## 🚀 Instalasi

1. Download `.zip` dari [Releases](../../releases) atau tab **Actions**
2. Flash via Magisk app
3. Reboot

## 📱 Cara Pakai

1. Buka **Magisk app**
2. Tap **Settings** ⚙️
3. Aktifkan **Zygisk**
4. Aktifkan **Enforce DenyList**
5. Tap **Configure DenyList**
6. **Centang aplikasi** yang ingin disembunyikan rootnya
7. Selesai! Module otomatis detect

## 🔧 Troubleshooting

### Cek Log
```bash
logcat | grep MyRootHider
