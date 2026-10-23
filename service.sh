#!/system/bin/sh
# QwennHide - service.sh (NeoZygisk Aligned)
# Tidak bergantung pada resetprop Magisk. Detect environment dulu.

DATADIR="/data/adb/qwennhide"
MODE_FILE="$DATADIR/mode"
mkdir -p "$DATADIR"

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done
sleep 3

MODE="basic"
[ -f "$MODE_FILE" ] && MODE=$(cat "$MODE_FILE" | tr -d '\r\n ')

log_msg() {
    echo "[$(date '+%H:%M:%S')] [service] $1" >> "$DATADIR/service.log"
}

log_msg "=== QwennHide service started ==="
log_msg "Mode: $MODE"

# ─── Detect environment: Magisk / KernelSU / APatch ────────────────────
HAS_RESETPROP=0
RESETPROP_BIN=""

if command -v resetprop >/dev/null 2>&1; then
    HAS_RESETPROP=1
    RESETPROP_BIN="resetprop"
    log_msg "Environment: Magisk (resetprop available)"
elif [ -x "/data/adb/magisk/resetprop" ]; then
    HAS_RESETPROP=1
    RESETPROP_BIN="/data/adb/magisk/resetprop"
    log_msg "Environment: Magisk (resetprop at explicit path)"
elif [ -x "/data/adb/ksu/bin/ksud" ]; then
    log_msg "Environment: KernelSU (no resetprop)"
elif [ -x "/data/adb/ap/bin/apd" ]; then
    log_msg "Environment: APatch (no resetprop)"
else
    log_msg "Environment: Unknown (no resetprop)"
fi

# ─── Property spoofing ──────────────────────────────────────────────────
if [ "$HAS_RESETPROP" -eq 1 ]; then
    log_msg "Applying property spoofing via $RESETPROP_BIN"

    # Basic (selalu)
    $RESETPROP_BIN ro.debuggable 0 2>/dev/null
    $RESETPROP_BIN ro.secure 1 2>/dev/null
    $RESETPROP_BIN ro.build.tags "release-keys" 2>/dev/null
    $RESETPROP_BIN ro.build.type "user" 2>/dev/null
    $RESETPROP_BIN --delete ro.magisk.hide 2>/dev/null
    $RESETPROP_BIN --delete ro.boot.magisk 2>/dev/null
    $RESETPROP_BIN --delete persist.magisk.hide 2>/dev/null

    # Aggressive (hanya jika mode aggressive)
    if [ "$MODE" = "aggressive" ]; then
        log_msg "Applying aggressive props"
        $RESETPROP_BIN ro.boot.verifiedbootstate green 2>/dev/null
        $RESETPROP_BIN ro.boot.flash.locked 1 2>/dev/null
        $RESETPROP_BIN ro.boot.veritymode enforcing 2>/dev/null
        $RESETPROP_BIN ro.boot.vbmeta.device_state locked 2>/dev/null
        $RESETPROP_BIN ro.crypto.state encrypted 2>/dev/null
        $RESETPROP_BIN ro.crypto.type file 2>/dev/null
    fi
else
    # Fallback: setprop biasa (terbatas, hanya non-ro.*)
    log_msg "No resetprop, using setprop fallback (limited)"
    setprop debug.debuggable 0 2>/dev/null
fi

# ─── Trim log ───────────────────────────────────────────────────────────
LOG_SIZE=$(wc -c < "$DATADIR/service.log" 2>/dev/null || echo 0)
if [ "$LOG_SIZE" -gt 512000 ]; then
    tail -n 500 "$DATADIR/service.log" > "$DATADIR/service.log.tmp" && mv "$DATADIR/service.log.tmp" "$DATADIR/service.log"
fi

log_msg "Service done."
