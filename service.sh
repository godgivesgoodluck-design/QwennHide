#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════
# QwennHide — service.sh v3.1.4
# Prop spoofing global + fingerprint normalization untuk Momo/GSI.
# ═══════════════════════════════════════════════════════════════════════

DATADIR="/data/adb/qwennhide"
PROP_FILE="$DATADIR/prop_spoof"
LOGFILE="$DATADIR/service.log"

mkdir -p "$DATADIR" 2>/dev/null

while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 1
done

sleep 3

log_msg() {
    echo "[$(date '+%H:%M:%S')] [service] $1" >> "$LOGFILE" 2>/dev/null
}

PROP_ENABLED=0
if [ -f "$PROP_FILE" ]; then
    PROP_ENABLED=$(cat "$PROP_FILE" 2>/dev/null | tr -d '\r\n ')
fi

log_msg "Prop spoofing enabled: $PROP_ENABLED"

if [ "$PROP_ENABLED" != "1" ]; then
    log_msg "Prop spoofing disabled, skipping"
    exit 0
fi

HAS_RESETPROP=0
RESETPROP_BIN=""

if command -v resetprop >/dev/null 2>&1; then
    HAS_RESETPROP=1
    RESETPROP_BIN="resetprop"
elif [ -x "/data/adb/magisk/resetprop" ]; then
    HAS_RESETPROP=1
    RESETPROP_BIN="/data/adb/magisk/resetprop"
fi

if [ "$HAS_RESETPROP" -ne 1 ]; then
    log_msg "resetprop not available, prop spoofing skipped"
    exit 0
fi

log_msg "Using resetprop: $RESETPROP_BIN"

rp() {
    "$RESETPROP_BIN" "$@" 2>/dev/null
}

getp() {
    getprop "$1" 2>/dev/null
}

set_if_present() {
    _SIP_NAME="$1"
    _SIP_VALUE="$2"
    _SIP_CUR=$(getp "$_SIP_NAME")

    if [ -n "$_SIP_CUR" ]; then
        rp "$_SIP_NAME" "$_SIP_VALUE"
        log_msg "set $_SIP_NAME=$_SIP_VALUE"
    fi
}

normalize_fp_value() {
    printf '%s' "$1" | sed \
        -e 's|:userdebug/|:user/|g' \
        -e 's|:eng/|:user/|g' \
        -e 's|test-keys|release-keys|g'
}

normalize_fp_prop() {
    _NFP_NAME="$1"
    _NFP_CUR=$(getp "$_NFP_NAME")

    if [ -z "$_NFP_CUR" ]; then
        return
    fi

    _NFP_NEW=$(normalize_fp_value "$_NFP_CUR")

    if [ "$_NFP_NEW" != "$_NFP_CUR" ]; then
        rp "$_NFP_NAME" "$_NFP_NEW"
        log_msg "normalized $_NFP_NAME"
        log_msg "  old: $_NFP_CUR"
        log_msg "  new: $_NFP_NEW"
    fi
}

rp ro.debuggable 0
rp ro.secure 1
rp ro.build.type user
rp ro.build.tags release-keys

log_msg "Core props applied"

for _TYPE_PROP in \
    ro.system.build.type \
    ro.vendor.build.type \
    ro.odm.build.type \
    ro.product.build.type \
    ro.product_services.build.type \
    ro.bootimage.build.type
do
    set_if_present "$_TYPE_PROP" user
done

for _TAGS_PROP in \
    ro.system.build.tags \
    ro.vendor.build.tags \
    ro.odm.build.tags \
    ro.product.build.tags \
    ro.product_services.build.tags \
    ro.bootimage.build.tags
do
    set_if_present "$_TAGS_PROP" release-keys
done

for _FP_PROP in \
    ro.build.fingerprint \
    ro.system.build.fingerprint \
    ro.vendor.build.fingerprint \
    ro.odm.build.fingerprint \
    ro.product.build.fingerprint \
    ro.product_services.build.fingerprint \
    ro.bootimage.build.fingerprint
do
    normalize_fp_prop "$_FP_PROP"
done

rp --delete ro.magisk.hide
rp --delete ro.boot.magisk
rp --delete ro.magisk.version
rp --delete persist.magisk.hide
rp --delete persist.magisk.zygisk

log_msg "Magisk props deleted"

rp ro.boot.verifiedbootstate green
rp ro.boot.flash.locked 1
rp ro.boot.veritymode enforcing
rp ro.boot.vbmeta.device_state locked

rp ro.crypto.state encrypted
rp ro.crypto.type file

log_msg "GSI/bootloader/encryption props applied"

LOG_SIZE=$(wc -c < "$LOGFILE" 2>/dev/null || echo 0)
case "$LOG_SIZE" in
    ''|*[!0-9]*) LOG_SIZE=0 ;;
esac

if [ "$LOG_SIZE" -gt 512000 ]; then
    tail -n 500 "$LOGFILE" > "$LOGFILE.tmp" 2>/dev/null
    mv -f "$LOGFILE.tmp" "$LOGFILE" 2>/dev/null
fi

log_msg "Service done."