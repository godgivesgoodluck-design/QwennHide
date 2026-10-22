#!/system/bin/sh

# Only set permissions. Never write outside MODPATH.
chmod 755 "$MODPATH/uninstall.sh" 2>/dev/null

if [ -d "$MODPATH/zygisk" ]; then
    chmod 755 "$MODPATH/zygisk"
    for lib in "$MODPATH/zygisk"/*.so; do
        [ -f "$lib" ] && chmod 755 "$lib"
    done
fi
