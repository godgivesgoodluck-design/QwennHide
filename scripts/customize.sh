#!/system/bin/sh

SKIPUNZIP=1

ui_print "*******************************"
ui_print "   My Root Hider v1.1.0        "
ui_print "   Auto DenyList Integration   "
ui_print "*******************************"
ui_print ""

ui_print "- Extracting module files..."
unzip -o "$ZIPFILE" -x 'META-INF/*' -d "$MODPATH" >&2

chmod 755 "$MODPATH/service.sh"
chmod 755 "$MODPATH/post-fs-data.sh"

if [ -d "$MODPATH/zygisk" ]; then
    chmod 755 "$MODPATH/zygisk"/*.so 2>/dev/null
fi

rm -f "$MODPATH/customize.sh"

ui_print "*******************************"
ui_print " Installation complete!        "
ui_print "                               "
ui_print " HOW TO USE:                   "
ui_print " 1. Open Magisk app            "
ui_print " 2. Enable Zygisk              "
ui_print " 3. Enable Enforce DenyList    "
ui_print " 4. Configure DenyList         "
ui_print " 5. Check apps to hide root    "
ui_print " 6. Reboot device              "
ui_print "*******************************"
ui_print ""
