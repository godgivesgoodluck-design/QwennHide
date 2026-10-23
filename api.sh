#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════
# QwennHide — api.sh
# Backend untuk WebUI
#
# Usage:
#   api.sh list
#   api.sh set <package> <basic|aggressive|persistent|default>
#   api.sh default <basic|aggressive|persistent>
#   api.sh prop <0|1>
#   api.sh reset-all
# ═══════════════════════════════════════════════════════════════════════

BASE="/data/adb/qwennhide"
MODE_FILE="$BASE/mode"
PROP_FILE="$BASE/prop_spoof"
APPS_FILE="$BASE/apps.list"
DENY_TMP="$BASE/.deny.tmp"

ensure() {
    mkdir -p "$BASE"
    chmod 700 "$BASE"
    [ -f "$MODE_FILE" ] || echo "basic" > "$MODE_FILE"
    [ -f "$PROP_FILE" ] || echo "0" > "$PROP_FILE"
    [ -f "$APPS_FILE" ] || : > "$APPS_FILE"
    chmod 600 "$MODE_FILE" "$PROP_FILE" "$APPS_FILE" 2>/dev/null
}

valid_pkg() {
    printf '%s' "$1" | grep -Eq '^[A-Za-z0-9._]+$'
}

valid_mode() {
    case "$1" in
        basic|aggressive|persistent|default) return 0 ;;
        *) return 1 ;;
    esac
}

get_default_mode() {
    local m
    m=$(cat "$MODE_FILE" 2>/dev/null | tr -d '\r\n ')
    [ -n "$m" ] || m="basic"
    printf '%s' "$m"
}

get_prop() {
    local p
    p=$(cat "$PROP_FILE" 2>/dev/null | tr -d '\r\n ')
    [ -n "$p" ] || p="0"
    printf '%s' "$p"
}

get_app_override() {
    awk -F'|' -v p="$1" '$1 == p { m = $2 } END { if (m != "") print m }' \
        "$APPS_FILE" 2>/dev/null
}

get_denylist() {
    {
        magisk --denylist ls 2>/dev/null | awk -F'|' 'NF { print $1 }'
        for f in \
            /data/adb/modules/neozygisk/denylist \
            /data/adb/modules/zygisksu/denylist \
            "$BASE/umount_list"
        do
            [ -f "$f" ] && awk -F'|' '!/^#/ && NF { print $1 }' "$f"
        done
    } | sort -u
}

cmd_list() {
    ensure
    local default prop
    default=$(get_default_mode)
    prop=$(get_prop)
    get_denylist > "$DENY_TMP" 2>/dev/null

    printf '{'
    printf '"default_mode":"%s",' "$default"
    printf '"prop_spoof":"%s",' "$prop"
    printf '"apps":['

    local first=1 pkg override mode overridden deny
    for pkg in $(pm list packages -3 2>/dev/null | sed 's/^package://' | sort); do
        [ -z "$pkg" ] && continue
        override=$(get_app_override "$pkg")
        if [ -n "$override" ]; then
            mode="$override"; overridden=true
        else
            mode="$default"; overridden=false
        fi
        if grep -Fxq "$pkg" "$DENY_TMP" 2>/dev/null; then
            deny=true
        else
            deny=false
        fi
        [ $first -eq 0 ] && printf ','
        printf '\n{"pkg":"%s","mode":"%s","overridden":%s,"in_denylist":%s}' \
            "$pkg" "$mode" "$overridden" "$deny"
        first=0
    done

    printf '\n]}\n'
    rm -f "$DENY_TMP"
}

cmd_set() {
    local pkg="$1" mode="$2"
    ensure
    valid_pkg "$pkg" || { printf '{"ok":false,"error":"invalid_package"}\n'; exit 1; }
    valid_mode "$mode" || { printf '{"ok":false,"error":"invalid_mode"}\n'; exit 1; }

    local tmp="$APPS_FILE.tmp"
    awk -F'|' -v p="$pkg" '$1 != p' "$APPS_FILE" > "$tmp" 2>/dev/null || : > "$tmp"
    if [ "$mode" != "default" ]; then
        printf '%s|%s\n' "$pkg" "$mode" >> "$tmp"
    fi
    mv -f "$tmp" "$APPS_FILE"
    chmod 600 "$APPS_FILE"
    printf '{"ok":true}\n'
}

cmd_default() {
    local mode="$1"
    ensure
    case "$mode" in
        basic|aggressive|persistent) ;;
        *) printf '{"ok":false,"error":"invalid_mode"}\n'; exit 1 ;;
    esac
    printf '%s\n' "$mode" > "$MODE_FILE"
    chmod 600 "$MODE_FILE"
    printf '{"ok":true}\n'
}

cmd_prop() {
    local val="$1"
    ensure
    case "$val" in
        0|1) ;;
        *) printf '{"ok":false,"error":"invalid_value"}\n'; exit 1 ;;
    esac
    printf '%s\n' "$val" > "$PROP_FILE"
    chmod 600 "$PROP_FILE"
    printf '{"ok":true,"reboot_required":true}\n'
}

cmd_reset_all() {
    ensure
    : > "$APPS_FILE"
    chmod 600 "$APPS_FILE"
    printf '{"ok":true}\n'
}

cmd="$1"; shift 2>/dev/null
case "$cmd" in
    list)      cmd_list ;;
    set)       cmd_set "$@" ;;
    default)   cmd_default "$@" ;;
    prop)      cmd_prop "$@" ;;
    reset-all) cmd_reset_all ;;
    *) printf '{"ok":false,"error":"usage: api.sh list|set|default|prop|reset-all"}\n'; exit 1 ;;
esac
