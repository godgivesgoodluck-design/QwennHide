#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════
# QwennHide — customize.sh v3.1.5
# ═══════════════════════════════════════════════════════════════════════

SKIPUNZIP=1

ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "     QwennHide v3.1.5"
ui_print "     Verified per-app mode + NeoZygisk aligned"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$ZYGISK_ENABLED" != "1" ]; then
    ui_print "! Warning: ZYGISK_ENABLED tidak terdeteksi sebagai 1."
    ui_print "! Pastikan Zygisk/NeoZygisk/ZygiskNext aktif."
else
    ui_print "- Zygisk detected: OK"
fi

if [ -z "$MAGISK_VER_CODE" ]; then
    ui_print "! Warning: MAGISK_VER_CODE tidak terdeteksi."
else
    ui_print "- Magisk version code: $MAGISK_VER_CODE"
fi

ui_print "- Extracting module files..."

unzip -o "$ZIPFILE" 'module.prop' -d "$MODPATH" >/dev/null 2>&1
unzip -o "$ZIPFILE" 'zygisk/*' -d "$MODPATH" >/dev/null 2>&1
unzip -o "$ZIPFILE" 'service.sh' -d "$MODPATH" >/dev/null 2>&1
unzip -o "$ZIPFILE" 'action.sh' -d "$MODPATH" >/dev/null 2>&1
unzip -o "$ZIPFILE" 'uninstall.sh' -d "$MODPATH" >/dev/null 2>&1
unzip -o "$ZIPFILE" 'api.sh' -d "$MODPATH" >/dev/null 2>&1
unzip -o "$ZIPFILE" 'webroot/*' -d "$MODPATH" >/dev/null 2>&1

DATADIR="/data/adb/qwennhide"
RUNTIME_DIR="$DATADIR/runtime"

mkdir -p "$DATADIR" 2>/dev/null
mkdir -p "$RUNTIME_DIR" 2>/dev/null

[ -f "$DATADIR/mode" ] || printf 'basic\n' > "$DATADIR/mode" 2>/dev/null
[ -f "$DATADIR/prop_spoof" ] || printf '0\n' > "$DATADIR/prop_spoof" 2>/dev/null
[ -f "$DATADIR/apps.list" ] || : > "$DATADIR/apps.list" 2>/dev/null

chmod 700 "$DATADIR" 2>/dev/null
chmod 700 "$RUNTIME_DIR" 2>/dev/null
chmod 600 "$DATADIR/mode" "$DATADIR/prop_spoof" "$DATADIR/apps.list" 2>/dev/null

ui_print "- Data dir : $DATADIR"
ui_print "- Runtime  : $RUNTIME_DIR"

for f in customize.sh service.sh action.sh uninstall.sh api.sh; do
    if [ -f "$MODPATH/$f" ]; then
        chmod 0755 "$MODPATH/$f" 2>/dev/null
    fi
done

if [ -d "$MODPATH/zygisk" ]; then
    chmod 0755 "$MODPATH/zygisk" 2>/dev/null
    find "$MODPATH/zygisk" -type f -exec chmod 0755 {} + 2>/dev/null
fi

if [ -d "$MODPATH/webroot" ]; then
    chmod 0755 "$MODPATH/webroot" 2>/dev/null
    find "$MODPATH/webroot" -type f -exec chmod 0644 {} + 2>/dev/null
fi

if [ ! -f "$MODPATH/api.sh" ]; then
    ui_print "! WARNING: api.sh tidak ditemukan di module dir."
fi

if [ ! -f "$MODPATH/webroot/index.html" ]; then
    ui_print "! WARNING: webroot/index.html tidak ditemukan."
fi

ui_print ""
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  Installation complete."
ui_print "  Reboot untuk menerapkan."
ui_print "  WebUI: buka lewat KSU WebUI / manager support."
ui_print "  Fallback: tombol Action di halaman module."
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"