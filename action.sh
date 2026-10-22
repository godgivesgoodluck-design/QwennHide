#!/system/bin/sh

# QwennHide Mode Switcher
# File ini muncul sebagai tombol "Action" di halaman module Magisk

MODDIR="${0%/*}"
MODE_FILE="$MODDIR/mode"

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

# Non-interactive mode
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

# Interactive mode (tampil di terminal Magisk)
current=$(get_mode)

echo ""
echo "================================"
echo "   QwennHide Mode Switcher"
echo "================================"
echo ""
echo "Current mode: $current"
echo ""
echo "  [1] Basic mode (default)"
echo "      - Module unload dari memory"
echo "      - Minimal footprint"
echo "      - Untuk app biasa"
echo ""
echo "  [2] Aggressive mode"
echo "      - PLT hook aktif"
echo "      - Companion daemon aktif"
echo "      - Untuk app bank/wallet"
echo ""

printf "Choose [1/2]: "
read -r choice

case "$choice" in
    1)
        set_mode "basic"
        echo ""
        echo "✓ Switched to BASIC mode"
        echo "  Changes apply on next app launch"
        ;;
    2)
        set_mode "aggressive"
        echo ""
        echo "✓ Switched to AGGRESSIVE mode"
        echo "  Changes apply on next app launch"
        ;;
    *)
        echo "Invalid choice"
        ;;
esac

echo ""
sleep 2
