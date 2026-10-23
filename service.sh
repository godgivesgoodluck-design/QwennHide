#!/system/bin/sh
# QwennHide v2.1 - service.sh (GSI Optimized)

DATADIR="/data/adb/qwennhide"
MODE_FILE="$DATADIR/mode"
mkdir -p "$DATADIR"

# Wait for boot
while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done
sleep 3

MODE="basic"
[ -f "$MODE_FILE" ] && MODE=$(cat "$MODE_FILE" | tr -d '\r\n ')

log_msg() {
    echo "[$(date '+%H:%M:%S')] [service] $1" >> "$DATADIR/service.log"
}

log_msg "Mode: $MODE"

# ─── 1. Basic Security Props (Always Applied) ─────────────────────────
# Ini membuat GSI terlihat seperti build "user" standar, bukan "userdebug"
resetprop ro.debuggable 0 2>/dev/null
resetprop ro.secure 1 2>/dev/null
resetprop ro.build.tags "release-keys" 2>/dev/null
resetprop ro.build.type "user" 2>/dev/null

# Sembunyikan jejak Magisk di properti
resetprop --delete ro.magisk.hide 2>/dev/null
resetprop --delete ro.boot.magisk 2>/dev/null
resetprop --delete persist.magisk.hide 2>/dev/null

# ─── 2. Aggressive Props (GSI Specific) ───────────────────────────────
if [ "$MODE" = "aggressive" ]; then
    log_msg "Applying Aggressive GSI Spoofing..."

    # Bootloader & Verity (Sering terdeteksi "orange" di GSI)
    resetprop ro.boot.verifiedbootstate green 2>/dev/null
    resetprop ro.boot.flash.locked 1 2>/dev/null
    resetprop ro.boot.veritymode enforcing 2>/dev/null
    resetprop ro.boot.vbmeta.device_state locked 2>/dev/null

    # Encryption State
    resetprop ro.crypto.state encrypted 2>/dev/null
    resetprop ro.crypto.type file 2>/dev/null

    # GSI Fingerprint Normalization
    # GSI sering punya fingerprint "generic". Kita coba samakan dengan vendor jika memungkinkan.
    # Catatan: Mengubah fingerprint sepenuhnya berisiko, jadi kita hanya ubah tags/type.
    # Jika Anda ingin spoof fingerprint spesifik device, tambahkan di sini secara manual:
    # resetprop ro.build.fingerprint "brand/device/device:version/build_id/build_number:user/release-keys"
    
    log_msg "Aggressive GSI props applied"
else
    log_msg "Basic mode: skipping aggressive props"
fi

# Trim log
LOG_SIZE=$(wc -c < "$DATADIR/service.log" 2>/dev/null || echo 0)
if [ "$LOG_SIZE" -gt 512000 ]; then
    tail -n 500 "$DATADIR/service.log" > "$DATADIR/service.log.tmp" && mv "$DATADIR/service.log.tmp" "$DATADIR/service.log"
fi
