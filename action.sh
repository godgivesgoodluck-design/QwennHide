#!/system/bin/sh
# QwennHide - action.sh (Volume Button Control)

DATADIR="/data/adb/qwennhide"
MODE_FILE="$DATADIR/mode"
mkdir -p "$DATADIR"

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
            echo "Mode: $1"
            echo ""
            echo "Note: Per-process cleanup takes effect immediately."
            echo "      Property spoofing requires REBOOT to apply."
            exit 0
            ;;
        status)
            echo "Current: $(get_mode)"
            exit 0
            ;;
        *)
            echo "Usage: $0 [basic|aggressive|status]"
            exit 1
            ;;
    esac
fi

# Interactive Volume Button Mode
current=$(get_mode)
echo ""
echo "================================"
echo "   QwennHide Mode Switcher"
echo "================================"
echo "Current mode: $current"
echo ""
echo "  [VOL UP]   → Basic mode"
echo "               (Minimal: host unmount only)"
echo ""
echo "  [VOL DOWN] → Aggressive mode"
echo "               (Full: host + manual cleanup"
echo "                + aggressive property spoof)"
echo ""
echo "⚠️  Property spoofing changes need REBOOT"
echo "    Per-process cleanup is immediate"
echo ""
echo "Press a volume button within 30 seconds..."

choice=""
timeout=30
start_time=$(date +%s)

if ! command -v getevent >/dev/null 2>&1; then
    echo "getevent not found. Use: $0 basic OR $0 aggressive"
    exit 1
fi

while [ -z "$choice" ]; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    remaining=$((timeout - elapsed))
    if [ $remaining -le 0 ]; then echo "Timeout."; exit 0; fi
    if [ $((elapsed % 5)) -eq 0 ] && [ $elapsed -gt 0 ]; then
        printf "\rWaiting... %ds remaining   " "$remaining"
    fi

    event=$(timeout 1 getevent -l 2>/dev/null | grep -E "KEY_VOLUME(UP|DOWN).*DOWN" | head -1)
    if echo "$event" | grep -q "KEY_VOLUMEUP"; then choice="basic"
    elif echo "$event" | grep -q "KEY_VOLUMEDOWN"; then choice="aggressive"
    fi
done

set_mode "$choice"
echo ""
echo "✓ Switched to $(echo $choice | tr '[:lower:]' '[:upper:]') mode"
echo ""
echo "Per-process cleanup: IMMEDIATE (next app launch)"
echo "Property spoofing:   REBOOT REQUIRED"
echo ""
sleep 3
