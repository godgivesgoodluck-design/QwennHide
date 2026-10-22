#!/system/bin/sh

# Set permissions
chmod 755 "$MODPATH/uninstall.sh" 2>/dev/null
chmod 755 "$MODPATH/action.sh" 2>/dev/null

if [ -d "$MODPATH/zygisk" ]; then
    chmod 755 "$MODPATH/zygisk"
    for lib in "$MODPATH/zygisk"/*.so; do
        [ -f "$lib" ] && chmod 755 "$lib"
    done
fi

# Create mode flag file with default "basic" mode
# This file is read by the module at runtime
MODE_FILE="$MODPATH/mode"
if [ ! -f "$MODE_FILE" ]; then
    echo "basic" > "$MODE_FILE"
    chmod 644 "$MODE_FILE"
fi
