#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════
# QwennHide — action.sh
# Menu navigasi via tombol volume:
#   VOL DOWN  → Pindah pilihan ke bawah (wrap-around)
#   VOL UP    → Konfirmasi / OK
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
    echo "  ╔══════════════════════════════╗"
    echo "  ║     QwennHide Mode Switcher  ║"
    echo "  ╚══════════════════════════════╝"
    echo ""
    echo "  Current mode : $cur"
    echo ""
    echo "  Select mode:"
    echo ""

    if [ $sel -eq 0 ]; then
        echo "    ▶ Basic"
        echo "      Aggressive"
    elif [ $sel -eq 1 ]; then
        echo "      Basic"
        echo "    ▶ Aggressive"
    fi

    echo ""
    echo "  ─────────────────────────────"
    echo "  VOL DOWN  → Move selection"
    echo "  VOL UP    → Confirm (OK)"
    echo "  ─────────────────────────────"
    echo ""
    printf "  Timeout: %ds" "$rem"
}

# ─── Non-interactive mode (untuk scripting/terminal) ────────────────────

if [ -n "$1" ]; then
    case "$1" in
        basic|aggressive)
            set_mode "$1"
            echo "Mode switched to: $1"
            echo "Per-process cleanup: immediate"
            echo "Property spoofing:   reboot required"
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

# ─── Cek getevent ───────────────────────────────────────────────────────

if ! command -v getevent >/dev/null 2>&1; then
    echo ""
    echo "ERROR: getevent not found."
    echo "Use terminal instead:"
    echo "  $0 basic"
    echo "  $0 aggressive"
    echo "  $0 status"
    exit 1
fi

# ─── Interactive menu navigation ────────────────────────────────────────

current=$(get_mode)
selection=0
total=2
timeout=60
start_time=$(date +%s)

# Set posisi awal sesuai mode aktif
if [ "$current" = "aggressive" ]; then
    selection=1
fi

while true; do
    now=$(date +%s)
    elapsed=$((now - start_time))
    remaining=$((timeout - elapsed))

    if [ $remaining -le 0 ]; then
        clear
        echo ""
        echo "  Timeout. No selection made."
        echo "  Mode remains: $current"
        exit 0
    fi

    # Gambar menu
    draw_menu $selection "$current" $remaining

    # Baca event volume (timeout 1 detik agar countdown update)
    event=$(timeout 1 getevent -l 2>/dev/null \
        | grep -E "KEY_VOLUME(UP|DOWN).*DOWN" \
        | head -1)

    if echo "$event" | grep -q "KEY_VOLUMEDOWN"; then
        # Pindah pilihan ke bawah, wrap ke atas jika mentok
        selection=$(( (selection + 1) % total ))
        sleep 0.2  # Debounce: cegah double-trigger

    elif echo "$event" | grep -q "KEY_VOLUMEUP"; then
        # Konfirmasi pilihan
        clear
        echo ""
        if [ $selection -eq 0 ]; then
            set_mode "basic"
            echo "  ╔══════════════════════════════╗"
            echo "  ║   ✓ Mode set to BASIC        ║"
            echo "  ╚══════════════════════════════╝"
            echo ""
            echo "  Host unmount only."
            echo "  Module unloads after hide."
        else
            set_mode "aggressive"
            echo "  ╔══════════════════════════════╗"
            echo "  ║   ✓ Mode set to AGGRESSIVE   ║"
            echo "  ╚══════════════════════════════╝"
            echo ""
            echo "  Host + manual cleanup + NeoZygisk traces."
            echo "  Module unloads after hide."
        fi
        echo ""
        echo "  Per-process cleanup : immediate (next app launch)"
        echo "  Property spoofing   : reboot required"
        echo ""
        sleep 3
        exit 0
    fi
done
