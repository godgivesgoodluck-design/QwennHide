#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════
# QwennHide — action.sh v3.1.4
# Fallback control. WebUI adalah cara utama.
# ═══════════════════════════════════════════════════════════════════════

MODDIR="${0%/*}"
API="$MODDIR/api.sh"
BASE="/data/adb/qwennhide"
MODE_FILE="$BASE/mode"
PROP_FILE="$BASE/prop_spoof"

get_mode() {
    if [ -f "$MODE_FILE" ]; then
        cat "$MODE_FILE" 2>/dev/null | tr -d '\r\n '
    else
        printf 'basic'
    fi
}

get_prop() {
    if [ -f "$PROP_FILE" ]; then
        cat "$PROP_FILE" 2>/dev/null | tr -d '\r\n '
    else
        printf '0'
    fi
}

apply_default() {
    sh "$API" default "$1" >/dev/null 2>&1
}

apply_prop() {
    sh "$API" prop "$1" >/dev/null 2>&1
}

if [ -n "$1" ]; then
    case "$1" in
        status)
            printf 'Current mode: %s\n' "$(get_mode)"
            printf 'Prop spoofing: %s\n' "$(get_prop)"
            exit 0
            ;;
        basic|aggressive|persistent)
            apply_default "$1"
            printf 'Default mode set to: %s\n' "$1"
            printf 'Per-process cleanup: immediate\n'
            printf 'Property spoofing: reboot required\n'
            exit 0
            ;;
        prop0)
            apply_prop 0
            printf 'Prop spoofing: OFF\n'
            exit 0
            ;;
        prop1)
            apply_prop 1
            printf 'Prop spoofing: ON (reboot required)\n'
            exit 0
            ;;
        *)
            printf 'Usage: %s [status|basic|aggressive|persistent|prop0|prop1]\n' "$0"
            exit 1
            ;;
    esac
fi

if [ ! -f "$API" ]; then
    printf 'ERROR: api.sh not found.\n'
    exit 1
fi

cur=$(get_mode)
prop=$(get_prop)

if command -v getevent >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
    selection=0
    total=6
    TIMEOUT_SEC=60
    start_time=$(date +%s)

    case "$cur" in
        aggressive) selection=1 ;;
        persistent) selection=2 ;;
        *) selection=0 ;;
    esac

    while true; do
        now=$(date +%s)
        elapsed=$((now - start_time))
        remaining=$((TIMEOUT_SEC - elapsed))

        if [ "$remaining" -le 0 ]; then
            clear 2>/dev/null
            printf '\nTimeout. Mode remains: %s\n' "$cur"
            exit 0
        fi

        clear 2>/dev/null || printf '\n\n\n\n\n\n\n\n\n\n\n\n'

        printf '\n'
        printf '  QwennHide Action (Volume)\n'
        printf '  -------------------------\n'
        printf '  Current mode : %s\n' "$cur"
        printf '  Prop spoofing: %s\n' "$prop"
        printf '\n'

        if [ "$selection" -eq 0 ]; then printf '  > '; else printf '    '; fi
        printf 'Basic\n'

        if [ "$selection" -eq 1 ]; then printf '  > '; else printf '    '; fi
        printf 'Aggressive\n'

        if [ "$selection" -eq 2 ]; then printf '  > '; else printf '    '; fi
        printf 'Persistent\n'

        if [ "$selection" -eq 3 ]; then printf '  > '; else printf '    '; fi
        printf 'Toggle Prop Spoofing\n'

        if [ "$selection" -eq 4 ]; then printf '  > '; else printf '    '; fi
        printf 'Status\n'

        if [ "$selection" -eq 5 ]; then printf '  > '; else printf '    '; fi
        printf 'Exit\n'

        printf '\n'
        printf '  VOL DOWN = move\n'
        printf '  VOL UP   = select\n'
        printf '  Timeout  = %ss\n' "$remaining"

        event=$(timeout 1 getevent -l 2>/dev/null | grep -E 'KEY_VOLUME(UP|DOWN).*DOWN' | head -n 1)

        if printf '%s' "$event" | grep -q 'KEY_VOLUMEDOWN'; then
            selection=$(( (selection + 1) % total ))

        elif printf '%s' "$event" | grep -q 'KEY_VOLUMEUP'; then
            clear 2>/dev/null
            printf '\n'

            if [ "$selection" -eq 0 ]; then
                apply_default basic
                printf '  Default mode -> Basic\n'
            elif [ "$selection" -eq 1 ]; then
                apply_default aggressive
                printf '  Default mode -> Aggressive\n'
            elif [ "$selection" -eq 2 ]; then
                apply_default persistent
                printf '  Default mode -> Persistent\n'
            elif [ "$selection" -eq 3 ]; then
                if [ "$(get_prop)" = "1" ]; then
                    apply_prop 0
                    printf '  Prop spoofing -> OFF\n'
                else
                    apply_prop 1
                    printf '  Prop spoofing -> ON (reboot required)\n'
                fi
            elif [ "$selection" -eq 4 ]; then
                printf '  Current mode : %s\n' "$(get_mode)"
                printf '  Prop spoofing: %s\n' "$(get_prop)"
            else
                printf '  Exit\n'
                exit 0
            fi

            printf '\n'
            printf '  Per-app mode: use WebUI\n'
            sleep 2
            exit 0
        fi
    done
else
    while true; do
        clear 2>/dev/null || printf '\n\n\n\n\n\n\n\n\n\n\n\n'

        cur=$(get_mode)
        prop=$(get_prop)

        printf '\n'
        printf '  QwennHide Action (Fallback)\n'
        printf '  ---------------------------\n'
        printf '  Current mode : %s\n' "$cur"
        printf '  Prop spoofing: %s\n' "$prop"
        printf '\n'
        printf '  [1] Basic\n'
        printf '  [2] Aggressive\n'
        printf '  [3] Persistent\n'
        printf '  [4] Toggle Prop Spoofing\n'
        printf '  [5] Status\n'
        printf '  [6] Exit\n'
        printf '\n'
        printf '  Per-app mode: use WebUI\n'
        printf '\n'
        printf 'Pilih [1-6]: '

        read -r ans || exit 0

        case "$ans" in
            1)
                apply_default basic
                printf 'Default mode -> Basic\n'
                sleep 2
                exit 0
                ;;
            2)
                apply_default aggressive
                printf 'Default mode -> Aggressive\n'
                sleep 2
                exit 0
                ;;
            3)
                apply_default persistent
                printf 'Default mode -> Persistent\n'
                sleep 2
                exit 0
                ;;
            4)
                if [ "$prop" = "1" ]; then
                    apply_prop 0
                    printf 'Prop spoofing -> OFF\n'
                else
                    apply_prop 1
                    printf 'Prop spoofing -> ON (reboot required)\n'
                fi
                sleep 2
                exit 0
                ;;
            5)
                printf 'Current mode : %s\n' "$cur"
                printf 'Prop spoofing: %s\n' "$prop"
                sleep 2
                ;;
            6)
                exit 0
                ;;
            *)
                printf 'Invalid choice\n'
                sleep 1
                ;;
        esac
    done
fi