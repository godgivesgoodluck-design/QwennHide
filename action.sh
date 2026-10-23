#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════
# QwennHide — action.sh
# Fallback + status cepat. Pengaturan per-app dilakukan via WebUI.
#
#   VOL DOWN → pindah pilihan
#   VOL UP   → eksekusi pilihan
# ═══════════════════════════════════════════════════════════════════════

MODDIR="${0%/*}"
API="$MODDIR/api.sh"
DATADIR="/data/adb/qwennhide"

# ─── Non-interactive ───────────────────────────────────────────────────
if [ -n "$1" ]; then
    case "$1" in
        status)
            sh "$API" list 2>/dev/null | head -c 400
            echo ""
            exit 0
            ;;
        basic|aggressive|persistent)
            sh "$API" default "$1"
            exit 0
            ;;
        prop0) sh "$API" prop 0; exit 0 ;;
        prop1) sh "$API" prop 1; exit 0 ;;
        *)
            echo "Usage: $0 [status|basic|aggressive|persistent|prop0|prop1]"
            exit 1
            ;;
    esac
fi

# ─── Baca status saat ini ──────────────────────────────────────────────
get_default() {
    cat "$DATADIR/mode" 2>/dev/null | tr -d '\r\n ' || echo "basic"
}
get_prop() {
    cat "$DATADIR/prop_spoof" 2>/dev/null | tr -d '\r\n ' || echo "0"
}
count_overrides() {
    [ -f "$DATADIR/apps.list" ] && grep -c '|' "$DATADIR/apps.list" 2>/dev/null || echo 0
}

# ─── Cek getevent ──────────────────────────────────────────────────────
if ! command -v getevent >/dev/null 2>&1; then
    echo "getevent tidak tersedia."
    echo "Gunakan terminal:"
    echo "  $0 status"
    echo "  $0 basic|aggressive|persistent"
    echo "  $0 prop0|prop1"
    exit 1
fi

# ─── Menu ──────────────────────────────────────────────────────────────
selection=0
total=6
timeout=60
start_time=$(date +%s)

draw_menu() {
    local sel=$1
    local def prop ov
    def=$(get_default)
    prop=$(get_prop)
    ov=$(count_overrides)

    local prop_state="OFF"
    [ "$prop" = "1" ] && prop_state="ON"

    clear
    echo ""
    echo "  ╔════════════════════════════════╗"
    echo "  ║   QwennHide — Action (Fallback)║"
    echo "  ╚════════════════════════════════╝"
    echo ""
    echo "  Default mode   : $def"
    echo "  Prop spoofing  : $prop_state"
    echo "  Per-app override: $ov app (via WebUI)"
    echo ""
    echo "  Pilih aksi:"
    echo ""

    local i=0
    for label in \
        "Set default → Basic" \
        "Set default → Aggressive" \
        "Set default → Persistent" \
        "Toggle Prop Spoofing" \
        "Refresh status" \
        "Keluar"
    do
        if [ $sel -eq $i ]; then
            echo "    ▶ $label"
        else
            echo "      $label"
        fi
        i=$((i + 1))
    done

    echo ""
    echo "  ───────────────────────────────"
    echo "  VOL DOWN → pindah"
    echo "  VOL UP   → eksekusi"
    echo "  ───────────────────────────────"
}

while true; do
    now=$(date +%s)
    elapsed=$((now - start_time))
    remaining=$((timeout - elapsed))
    [ $remaining -le 0 ] && { clear; echo "Timeout."; exit 0; }

    draw_menu $selection

    event=$(timeout 1 getevent -l 2>/dev/null \
        | grep -E "KEY_VOLUME(UP|DOWN).*DOWN" | head -1)

    if echo "$event" | grep -q "KEY_VOLUMEDOWN"; then
        selection=$(( (selection + 1) % total ))
        sleep 0.2

    elif echo "$event" | grep -q "KEY_VOLUMEUP"; then
        clear
        echo ""
        case $selection in
            0)
                sh "$API" default basic >/dev/null
                echo "  ✓ Default mode → Basic"
                ;;
            1)
                sh "$API" default aggressive >/dev/null
                echo "  ✓ Default mode → Aggressive"
                ;;
            2)
                sh "$API" default persistent >/dev/null
                echo "  ✓ Default mode → Persistent"
                ;;
            3)
                cur=$(get_prop)
                if [ "$cur" = "1" ]; then
                    sh "$API" prop 0 >/dev/null
                    echo "  ✓ Prop spoofing → OFF"
                else
                    sh "$API" prop 1 >/dev/null
                    echo "  ✓ Prop spoofing → ON (reboot dibutuhkan)"
                fi
                ;;
            4)
                echo "  Status:"
                echo "    Default mode  : $(get_default)"
                echo "    Prop spoofing : $(get_prop)"
                echo "    Overrides     : $(count_overrides) app"
                sleep 2
                start_time=$(date +%s)
                continue
                ;;
            5)
                echo "  Keluar."
                exit 0
                ;;
        esac
        echo ""
        echo "  Perubahan mode per-app → via WebUI."
        sleep 2
        exit 0
    fi
done
