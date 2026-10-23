#!/system/bin/sh
# QwennHide - service.sh
# Mode-aware property spoofing:
#   - Basic: minimal spoofing only
#   - Aggressive: minimal + aggressive spoofing (bootloader, encryption, custom ROM)

DATADIR="/data/adb/qwennhide"
MODE_FILE="$DATADIR/mode"
mkdir -p "$DATADIR"

# Wait for boot
while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done
sleep 3

# ─── Read current mode ────────────────────────────────────────────────
MODE="basic"
if [ -f "$MODE_FILE" ]; then
    MODE=$(cat "$MODE_FILE" | tr -d '\r\n ')
fi

log_msg() {
    echo "[$(date '+%H:%M:%S')] [service] $1" >> "$DATADIR/service.log"
}

log_msg "QwennHide service started. Mode: $MODE"

# ─── Minimal Property Spoofing (Both Modes) ───────────────────────────
# These are safe and always applied
log_msg "Applying minimal property spoofing..."

resetprop ro.debuggable 0 2>/dev/null
resetprop ro.secure 1 2>/dev/null
resetprop ro.build.tags "release-keys" 2>/dev/null
resetprop ro.build.type "user" 2>/dev/null

# Hide Magisk-specific properties
resetprop --delete ro.magisk.hide 2>/dev/null
resetprop --delete ro.boot.magisk 2>/dev/null
resetprop --delete ro.magisk.version 2>/dev/null
resetprop --delete persist.magisk.hide 2>/dev/null
resetprop --delete persist.magisk.zygisk 2>/dev/null

log_msg "Minimal spoofing applied"

# ─── Aggressive Property Spoofing (Aggressive Mode Only) ──────────────
if [ "$MODE" = "aggressive" ]; then
    log_msg "Applying AGGRESSIVE property spoofing..."

    # Bootloader unlock detection
    resetprop ro.boot.verifiedbootstate green 2>/dev/null
    resetprop ro.boot.flash.locked 1 2>/dev/null
    resetprop ro.boot.veritymode enforcing 2>/dev/null
    resetprop ro.boot.vbmeta.device_state locked 2>/dev/null

    # Data encryption detection
    resetprop ro.crypto.state encrypted 2>/dev/null
    resetprop ro.crypto.type file 2>/dev/null
    resetprop ro.crypto.encrypted_state encrypted 2>/dev/null

    # Custom ROM detection (generic safe values)
    resetprop ro.build.selinux 0 2>/dev/null

    log_msg "Aggressive spoofing applied (bootloader + encryption + ROM)"
else
    log_msg "Basic mode: skipping aggressive spoofing"
fi

# ─── Trim log ─────────────────────────────────────────────────────────
LOG_SIZE=$(wc -c < "$DATADIR/service.log" 2>/dev/null || echo 0)
if [ "$LOG_SIZE" -gt 512000 ]; then
    tail -n 500 "$DATADIR/service.log" > "$DATADIR/service.log.tmp" && mv "$DATADIR/service.log.tmp" "$DATADIR/service.log"
fi

log_msg "Service done."
