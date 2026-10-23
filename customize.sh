#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════
# QwennHide — customize.sh
# ═══════════════════════════════════════════════════════════════════════

SKIPUNZIP=1

ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "     QwennHide — NeoZygisk Aligned"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$ZYGISK_ENABLED" != "1" ]; then
    ui_print "! Zygisk tidak aktif. Aborting."
    abort
fi

# ─── Extract file utama ─────────────────────────────────────────────────
unzip -o "$ZIPFILE" 'module.prop' -d "$MODPATH" >/dev/null 2>&1
unzip -o "$ZIPFILE" 'zygisk/*' -d "$MODPATH" >/dev/null 2>&1
unzip -o "$ZIPFILE" 'service.sh' -d "$MODPATH" >/dev/null 2>&1
unzip -o "$ZIPFILE" 'action.sh' -d "$MODPATH" >/dev/null 2>&1
unzip -o "$ZIPFILE" 'uninstall.sh' -d "$MODPATH" >/dev/null 2>&1

# ─── Extract WebUI + API ────────────────────────────────────────────────
unzip -o "$ZIPFILE" 'api.sh' -d "$MODPATH" >/dev/null 2>&1
unzip -o "$ZIPFILE" 'webroot/*' -d "$MODPATH" >/dev/null 2>&1

# ─── Buat data dir + config default ────────────────────────────────────
DATADIR="/data/adb/qwennhide"
mkdir -p "$DATADIR"
[ -f "$DATADIR/mode" ]       || echo "basic" > "$DATADIR/mode"
[ -f "$DATADIR/prop_spoof" ] || echo "0" > "$DATADIR/prop_spoof"
[ -f "$DATADIR/apps.list" ]  || : > "$DATADIR/apps.list"
chmod 700 "$DATADIR"
chmod 600 "$DATADIR/mode" "$DATADIR/prop_spoof" "$DATADIR/apps.list" 2>/dev/null

# ─── Permissions ────────────────────────────────────────────────────────
set_perm_recursive "$MODPATH" root root 0755 0644
set_perm "$MODPATH/service.sh"  root root 0755
set_perm "$MODPATH/action.sh"   root root 0755
set_perm "$MODPATH/uninstall.sh" root root 0755
set_perm "$MODPATH/api.sh"      root root 0755

if [ -d "$MODPATH/webroot" ]; then
    chmod 755 "$MODPATH/webroot"
    find "$MODPATH/webroot" -type f -exec chmod 644 {} \;
fi

ui_print "- Data dir : $DATADIR"
ui_print "- WebUI    : terinstall"
ui_print ""
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  Selesai! Reboot untuk menerapkan."
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
