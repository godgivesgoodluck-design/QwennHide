#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════
# QwennHide — service.sh
# Prop spoofing global, dikontrol /data/adb/qwennhide/prop_spoof
# ═══════════════════════════════════════════════════════════════════════

DATADIR="/data/adb/qwennhide"
PROP_FILE="$DATADIR/prop_spoof"
LOGFILE="$DATADIR/service.log"

mkdir -p "$DATADIR"

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done
sleep 3

log_msg() { echo "[$(date '+%H:%M:%S')] [service] $1" >> "$LOGFILE"; }

PROP_ENABLED=0
[ -f "$PROP_FILE" ] && PROP_ENABLED=$(cat "$PROP_FILE" | tr -d '\r\n ')

log_msg "Prop spoofing enabled: $PROP_ENABLED"

if [ "$PROP_ENABLED" = "1" ]; then
    HAS_RESETPROP=0
    RESETPROP_BIN=""

    if command -v resetprop >/dev/null 2>&1; then
        HAS_RESETPROP=1; RESETPROP_BIN="resetprop"
    elif [ -x "/data/adb/magisk/resetprop" ]; then
        HAS_RESETPROP=1; RESETPROP_BIN="/data/adb/magisk/resetprop"
    fi

    if [ "$HAS_RESETPROP" -eq 1 ]; then
        log_msg "Applying prop spoofing via $RESETPROP_BIN"
        $RESETPROP_BIN ro.debuggable 0 2>/dev/null
        $RESETPROP_BIN ro.secure 1 2>/dev/null
        $RESETPROP_BIN ro.build.tags "release-keys" 2>/dev/null
        $RESETPROP_BIN ro.build.type "user" 2>/dev/null
        $RESETPROP_BIN --delete ro.magisk.hide 2>/dev/null
        $RESETPROP_BIN --delete ro.boot.magisk 2>/dev/null
        $RESETPROP_BIN --delete persist.magisk.hide 2>/dev/null
        $RESETPROP_BIN ro.boot.verifiedbootstate green 2>/dev/null
        $RESETPROP_BIN ro.boot.flash.locked 1 2>/dev/null
        $RESETPROP_BIN ro.boot.veritymode enforcing 2>/dev/null
        $RESETPROP_BIN ro.boot.vbmeta.device_state locked 2>/dev/null
        $RESETPROP_BIN ro.crypto.state encrypted 2>/dev/null
        $RESETPROP_BIN ro.crypto.type file 2>/dev/null
        log_msg "Prop spoofing applied"
    else
        log_msg "resetprop not available, prop spoofing skipped"
    fi
else
    log_msg "Prop spoofing disabled"
fi

LOG_SIZE=$(wc -c < "$LOGFILE" 2>/dev/null || echo 0)
if [ "$LOG_SIZE" -gt 512000 ]; then
    tail -n 500 "$LOGFILE" > "$LOGFILE.tmp" && mv "$LOGFILE.tmp" "$LOGFILE"
fi
