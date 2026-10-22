#!/system/bin/sh
SKIPUNZIP=1

ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "     QwennHide v2.0 (Proven Architecture)"
ui_print "     Compatible: Magisk Alpha + NeoZygisk"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$ZYGISK_ENABLED" != "1" ]; then
    ui_print "! Zygisk is NOT enabled. Aborting."
    abort
fi

ui_print "- Extracting module files..."
unzip -o "$ZIPFILE" 'module.prop' 'zygisk/*' 'service.sh' 'action.sh' 'customize.sh' -d "$MODPATH" >/dev/null 2>&1

DATADIR="/data/adb/qwennhide"
mkdir -p "$DATADIR"
chmod 700 "$DATADIR"

# Default to basic mode
if [ ! -f "$DATADIR/mode" ]; then
    echo "basic" > "$DATADIR/mode"
fi

set_perm_recursive "$MODPATH" root root 0755 0644
set_perm "$MODPATH/service.sh" root root 0755
set_perm "$MODPATH/action.sh" root root 0755

ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  Installation complete! Reboot to apply."
ui_print "  Use Magisk Action button to switch modes."
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
