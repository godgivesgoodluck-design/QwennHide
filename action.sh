#!/system/bin/sh

MODDIR="${0%/*}"
MODE_FILE="$MODDIR/mode"

# Helper: read current mode
get_mode() {
    if [ -f "$MODE_FILE" ]; then
        cat "$MODE_FILE" | tr -d '\r\n '
    else
        echo "basic"
    fi
}

# Helper: set mode
set_mode() {
    echo "$1" > "$MODE_FILE"
    chmod 644 "$MODE_FILE"
}

# Non-interactive mode (if argument provided)
if [ -n "$1" ]; then
    case "$1" in
        basic|aggressive)
            set_mode "$1"
            echo "✓ Mode switched to: $1"
            echo ""
            echo "Changes take effect on next app launch."
            echo "Already-running apps keep their current mode until restarted."
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

# Interactive mode
while true; do
    clear
    current=$(get_mode)
    
    echo "================================"
    echo "   QwennHide Mode Switcher"
    echo "================================"
    echo ""
    echo "Current mode: $current"
    echo ""
    echo "  [1] Basic mode"
    echo "      - Module unload dari memory"
    echo "      - Minimal jejak di /proc/self/maps"
    echo "      - Cocok untuk app biasa"
    echo ""
    echo "  [2] Aggressive mode"
    echo "      - PLT hook aktif (property, path, maps)"
    echo "      - Companion daemon untuk unmount"
    echo "      - Module tetap di memory"
    echo "      - Untuk app bank/wallet/game agresif"
    echo ""
    echo "  [3] Exit"
    echo ""
    printf "Choose [1/2/3]: "
    read -r choice
    
    case "$choice" in
        1)
            set_mode "basic"
            echo ""
            echo "✓ Switched to BASIC mode"
            sleep 1
            ;;
        2)
            set_mode "aggressive"
            echo ""
            echo "✓ Switched to AGGRESSIVE mode"
            sleep 1
            ;;
        3)
            echo "Bye."
            exit 0
            ;;
        *)
            echo "Invalid choice"
            sleep 1
            ;;
    esac
done
