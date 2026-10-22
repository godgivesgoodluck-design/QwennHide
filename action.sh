#!/system/bin/sh

# QwennHide Mode Switcher
# Tombol Action di halaman module Magisk
# Kontrol via Volume Up/Down

MODDIR="${0%/*}"
MODE_FILE="$MODDIR/mode"

# ============================================
# Helper functions
# ============================================

get_mode() {
    if [ -f "$MODE_FILE" ]; then
        cat "$MODE_FILE" | tr -d '\r\n '
    else
        echo "basic"
    fi
}

set_mode() {
    echo "$1" > "$MODE_FILE"
    chmod 644 "$MODE_FILE"
}

# ============================================
# Non-interactive mode (untuk scripting)
# ============================================

if [ -n "$1" ]; then
    case "$1" in
        basic|aggressive)
            set_mode "$1"
            echo "Mode switched to: $1"
            exit 0
            ;;
        status)
            echo "Current mode: $(get_mode)"
            exit 0
            ;;
        *)
            echo "Usage: $0 [basic|aggressive|status]"
            exit 1
            ;;
    esac
fi

# ============================================
# Interactive mode via Volume buttons
# ============================================

current=$(get_mode)

echo ""
echo "================================"
echo "   QwennHide Mode Switcher"
echo "================================"
echo ""
echo "Current mode: $current"
echo ""
echo "  [VOL UP]   → Basic mode"
echo "  [VOL DOWN] → Aggressive mode"
echo ""
echo "Press a volume button within 30 seconds..."
echo ""

# ============================================
# Deteksi tombol volume via getevent
# ============================================

choice=""
timeout=30
start_time=$(date +%s)

# Cek apakah getevent tersedia
if ! command -v getevent >/dev/null 2>&1; then
    echo "ERROR: getevent not found on this device."
    echo "Falling back to numeric input..."
    echo ""
    printf "Choose [1=Basic / 2=Aggressive]: "
    read -r num
    case "$num" in
        1) choice="basic" ;;
        2) choice="aggressive" ;;
        *) echo "Invalid choice"; exit 1 ;;
    esac
else
    # Loop sampai tombol volume ditekan atau timeout
    while [ -z "$choice" ]; do
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        remaining=$((timeout - elapsed))

        if [ $remaining -le 0 ]; then
            echo ""
            echo "Timeout. No button pressed. Cancelled."
            exit 0
        fi

        # Tampilkan countdown setiap 5 detik
        if [ $((elapsed % 5)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            printf "\rWaiting... %ds remaining   " "$remaining"
        fi

        # Baca event dengan timeout 1 detik
        # getevent -l output: /dev/input/eventX EV_KEY KEY_VOLUMEUP DOWN
        event=$(timeout 1 getevent -l 2>/dev/null | grep -E "KEY_VOLUME(UP|DOWN).*DOWN" | head -1)

        if echo "$event" | grep -q "KEY_VOLUMEUP"; then
            choice="basic"
        elif echo "$event" | grep -q "KEY_VOLUMEDOWN"; then
            choice="aggressive"
        fi
    done
fi

# ============================================
# Apply mode
# ============================================

set_mode "$choice"

echo ""
echo ""
if [ "$choice" = "basic" ]; then
    echo "✓ Switched to BASIC mode"
else
    echo "✓ Switched to AGGRESSIVE mode"
fi
echo "  Changes apply on next app launch"
echo ""
sleep 2
