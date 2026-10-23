#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════
# QwennHide — action.sh (3 Mode)
#
#   VOL DOWN  → Pindah pilihan ke bawah (wrap-around)
#   VOL UP    → Konfirmasi / OK
#
# Modes:
#   1. Basic      → Host unmount + DLCLOSE
#   2. Aggressive → Full cleanup + DLCLOSE
#   3. Persistent → Full cleanup + NO DLCLOSE (module stays resident)
# ═══════════════════════════════════════════════════════════════════════

DATADIR="/data/adb/qwennhide"
MODE_FILE="$DATADIR/mode"
mkdir -p "$DATADIR"

# ─── Helper ─────────────────────────────────────────────────────────────

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

draw_menu() {
    local sel=$1
    local cur=$2
    local rem=$3

    clear
    echo ""
    echo "  ╔══════════════════════════════════╗"
    echo "  ║    QwennHide Mode Switcher       ║"
    echo "  ╚══════════════════════════════════╝"
    echo ""
    echo "  Current : $cur"
    echo ""
    echo "  Select:"
    echo ""

    # Option 0: Basic
    if [ $sel -eq 0 ]; then
        echo "    ▶ Basic"
    else
        echo "      Basic"
    fi

    # Option 1: Aggressive
    if [ $sel -eq 1 ]; then
        echo "    ▶ Aggressive"
    else
        echo "      Aggressive"
    fi

    # Option 2: Persistent
    if [ $sel -eq 2 ]; then
        echo "    ▶ Persistent"
    else
        echo "      Persistent"
    fi

    echo ""
    echo "  ─────────────────────────────────"
    echo "  VOL DOWN  → Move selection"
    echo "  VOL UP    → Confirm (OK)"
    echo "  ─────────────────────────────────"
    echo ""
    printf "  Timeout: %ds" "$rem"
}

# ─── Non-interactive mode ──────────────────────────────────────────────

if [ -n "$1" ]; then
    case "$1" in
        basic|aggressive|persistent)
            set_mode "$1"
            echo "Mode switched to: $1"
            echo ""
            echo "Per-process cleanup : immediate"
            echo "Property spoofing   : reboot required"
            exit 0
            ;;
        status)
            echo "Current mode: $(get_mode)"
            exit 0
            ;;
        *)
            echo "Usage: $0 [basic|aggressive|persistent|status]"
            exit 1
            ;;
    esac
fi

# ─── Cek getevent ──────────────────────────────────────────────────────

if ! command -v getevent >/dev/null 2>&1; then
    echo ""
    echo "ERROR: getevent not found."
    echo "Use terminal instead:"
    echo "  $0 basic"
    echo "  $0 aggressive"
    echo "  $0 persistent"
    echo "  $0 status"
    exit 1
fi

# ─── Menu navigation ───────────────────────────────────────────────────

current=$(get_mode)
selection=0
total=3
timeout=60
start_time=$(date +%s)

# Set posisi awal sesuai mode aktif
case "$current" in
    aggressive) selection=1 ;;
    persistent) selection=2 ;;
    *)          selection=0 ;;
esac

while true; do
    now=$(date +%s)
    elapsed=$((now - start_time))
    remaining=$((timeout - elapsed))

    if [ $remaining -le 0 ]; then
        clear
        echo ""
        echo "  Timeout. Mode remains: $current"
        exit 0
    fi

    draw_menu $selection "$current" $remaining

    event=$(timeout 1 getevent -l 2>/dev/null \
        | grep -E "KEY_VOLUME(UP|DOWN).*DOWN" \
        | head -1)

    if echo "$event" | grep -q "KEY_VOLUMEDOWN"; then
        selection=$(( (selection + 1) % total ))
        sleep 0.2

    elif echo "$event" | grep -q "KEY_VOLUMEUP"; then
        clear
        echo ""

        if [ $selection -eq 0 ]; then
            set_mode "basic"
            echo "  ╔══════════════════════════════════╗"
            echo "  ║  ✓ Mode: BASIC                   ║"
            echo "  ╚══════════════════════════════════╝"
            echo ""
            echo "  Host unmount only."
            echo "  Module unloads after hide."
            echo "  Lightest footprint."

        elif [ $selection -eq 1 ]; then
            set_mode "aggressive"
            echo "  ╔══════════════════════════════════╗"
            echo "  ║  ✓ Mode: AGGRESSIVE              ║"
            echo "  ╚══════════════════════════════════╝"
            echo ""
            echo "  Host + manual + NeoZygisk cleanup."
            echo "  Module unloads after hide."

        elif [ $selection -eq 2 ]; then
            set_mode "persistent"
            echo "  ╔══════════════════════════════════╗"
            echo "  ║  ✓ Mode: PERSISTENT              ║"
            echo "  ╚══════════════════════════════════╝"
            echo ""
            echo "  Full cleanup + module stays resident."
            echo "  Handles periodic root checks."
            echo "  ⚠ Module visible in /proc/self/maps"
        fi

        echo ""
        echo "  Per-process : immediate"
        echo "  Properties  : reboot required"
        echo ""
        sleep 3
        exit 0
    fi
done
