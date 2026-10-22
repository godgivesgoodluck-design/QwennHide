#!/system/bin/sh

# Set permissions untuk script
chmod 755 "$MODPATH/uninstall.sh" 2>/dev/null
chmod 755 "$MODPATH/action.sh" 2>/dev/null

# Set permissions untuk zygisk libraries
if [ -d "$MODPATH/zygisk" ]; then
    chmod 755 "$MODPATH/zygisk"
    for lib in "$MODPATH/zygisk"/*.so; do
        [ -f "$lib" ] && chmod 755 "$lib"
    done
fi

# Create mode flag file dengan default "basic"
# File ini dibaca oleh module C++ untuk menentukan mode
MODE_FILE="$MODPATH/mode"
if [ ! -f "$MODE_FILE" ]; then
    echo "basic" > "$MODE_FILE"
fi
chmod 644 "$MODE_FILE"

# Verifikasi file penting
if [ ! -f "$MODPATH/action.sh" ]; then
    ui_print "WARNING: action.sh missing!"
fi
if [ ! -f "$MODE_FILE" ]; then
    ui_print "WARNING: mode file missing!"
fi
