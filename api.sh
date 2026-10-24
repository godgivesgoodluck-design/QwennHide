#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════
# QwennHide — api.sh
# Backend untuk WebUI dan Action button.
#
# Commands:
#   api.sh list
#   api.sh diag
#   api.sh set <package> <basic|aggressive|persistent|default>
#   api.sh default <basic|aggressive|persistent>
#   api.sh prop <0|1>
#   api.sh reset-all
# ═══════════════════════════════════════════════════════════════════════

BASE="/data/adb/qwennhide"
MODE_FILE="$BASE/mode"
PROP_FILE="$BASE/prop_spoof"
APPS_FILE="$BASE/apps.list"
RUNTIME_DIR="$BASE/runtime"
DENY_TMP="$BASE/.deny.tmp"

DENY_FILES="
/data/adb/modules/neozygisk/denylist
/data/adb/modules/zygisksu/denylist
/data/adb/neozygisk/denylist
/data/adb/zygisksu/denylist
/data/adb/zygisknext/denylist
"

# ─── Helpers ───────────────────────────────────────────────────────────

ensure() {
    mkdir -p "$BASE"
    mkdir -p "$RUNTIME_DIR"
    chmod 700 "$BASE"
    chmod 700 "$RUNTIME_DIR"

    [ -f "$MODE_FILE" ] || echo "basic" > "$MODE_FILE"
    [ -f "$PROP_FILE" ] || echo "0" > "$PROP_FILE"
    [ -f "$APPS_FILE" ] || : > "$APPS_FILE"

    chmod 600 "$MODE_FILE" "$PROP_FILE" "$APPS_FILE" 2>/dev/null
}

json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' | tr '\n\r' '  '
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

sanitize_file_name() {
    printf '%s' "$1" | sed -e 's/[^A-Za-z0-9._]/_/g'
}

find_magisk() {
    if command -v magisk >/dev/null 2>&1; then
        printf 'magisk'
        return
    fi

    for p in \
        /data/adb/magisk/magisk \
        /sbin/magisk \
        /debug_ramdisk/magisk \
        /data/adb/magisk/magisk64 \
        /data/adb/magisk/magisk32
    do
        if [ -x "$p" ]; then
            printf '%s' "$p"
            return
        fi
    done

    printf ''
}

normalize_pkgs() {
    awk -F'|' '
    {
        sub(/\r$/, "");
        if ($0 ~ /^[ \t]*#/) next;

        pkg = "";
        if ($1 ~ /^[ \t]*[0-9]+[ \t]*$/ && NF >= 2) {
            pkg = $2;
        } else {
            pkg = $1;
        }

        gsub(/^[ \t\r]+|[ \t\r]+$/, "", pkg);
        sub(/:.*/, "", pkg);

        if (pkg ~ /^[A-Za-z][A-Za-z0-9._]*$/) {
            print pkg;
        }
    }'
}

get_denylist_packages() {
    {
        m=$(find_magisk)
        if [ -n "$m" ]; then
            "$m" --denylist ls 2>/dev/null | normalize_pkgs
        fi

        for f in $DENY_FILES "$BASE/umount_list"; do
            if [ -r "$f" ]; then
                normalize_pkgs < "$f"
            fi
        done
    } | sort -u
}

is_pid_for_pkg() {
    local pid="$1"
    local pkg="$2"

    [ -n "$pid" ] || return 1
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    [ "$pid" -gt 0 ] || return 1
    [ -d "/proc/$pid" ] || return 1

    local first=""
    local base=""

    if [ -r "/proc/$pid/cmdline" ]; then
        first=$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | head -n 1)
        base=${first%%:*}
        [ "$base" = "$pkg" ] && return 0
    fi

    if [ -r "/proc/$pid/comm" ]; then
        first=$(head -n 1 "/proc/$pid/comm" 2>/dev/null)
        base=${first%%:*}
        [ "$base" = "$pkg" ] && return 0
    fi

    return 1
}

action_to_mode() {
    case "$1" in
        1) printf 'basic' ;;
        2) printf 'aggressive' ;;
        3) printf 'persistent' ;;
        *) printf '' ;;
    esac
}

# ─── Commands ──────────────────────────────────────────────────────────

cmd_list() {
    ensure

    default=$(get_default_mode)
    prop=$(get_prop)

    get_denylist_packages > "$DENY_TMP"

    printf '{'
    printf '"default_mode":"%s",' "$(json_escape "$default")"
    printf '"prop_spoof":"%s",' "$(json_escape "$prop")"
    printf '"apps":['

    first=1
    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue

        override=$(get_app_override "$pkg")
        if [ -n "$override" ]; then
            mode="$override"
            overridden=true
        else
            mode="$default"
            overridden=false
        fi

        rt_file="$RUNTIME_DIR/$(sanitize_file_name "$pkg")"
        rt_running=false
        rt_mode=""
        rt_pid=0
        rt_age=0

        if [ -r "$rt_file" ]; then
            IFS='|' read -r rpid raction rts < "$rt_file" 2>/dev/null

            rpid=${rpid:-0}
            raction=${raction:-0}
            rts=${rts:-0}

            case "$rpid" in ''|*[!0-9]*) rpid=0 ;; esac
            case "$raction" in ''|*[!0-9]*) raction=0 ;; esac
            case "$rts" in ''|*[!0-9]*) rts=0 ;; esac

            now=$(date +%s)
            if [ "$rts" -gt 0 ]; then
                rt_age=$((now - rts))
                [ "$rt_age" -lt 0 ] && rt_age=0
            fi

            rt_mode=$(action_to_mode "$raction")

            if is_pid_for_pkg "$rpid" "$pkg"; then
                rt_running=true
                rt_pid=$rpid
            else
                rt_running=false
                rt_pid=0
            fi
        fi

        [ $first -eq 0 ] && printf ','
        printf '\n{"pkg":"%s","mode":"%s","overridden":%s,"runtime_running":%s,"runtime_mode":"%s","runtime_pid":%s,"runtime_age":%s}' \
            "$(json_escape "$pkg")" \
            "$(json_escape "$mode")" \
            "$overridden" \
            "$rt_running" \
            "$(json_escape "$rt_mode")" \
            "$rt_pid" \
            "$rt_age"

        first=0
    done < "$DENY_TMP"

    printf '\n]}\n'
    rm -f "$DENY_TMP"
}

cmd_diag() {
    ensure

    m=$(find_magisk)
    raw=""
    if [ -n "$m" ]; then
        raw=$("$m" --denylist ls 2>&1 | head -10)
    fi

    get_denylist_packages > "$DENY_TMP"
    count=$(grep -c . "$DENY_TMP" 2>/dev/null || echo 0)

    rt_count=0
    if [ -d "$RUNTIME_DIR" ]; then
        rt_count=$(find "$RUNTIME_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
    fi

    printf '{"magisk_bin":"%s","magisk_raw":"%s","denylist_count":%s,"runtime_count":%s,"files":{' \
        "$(json_escape "$m")" \
        "$(json_escape "$raw")" \
        "$count" \
        "$rt_count"

    first=1
    for f in $DENY_FILES "$BASE/umount_list"; do
        [ $first -eq 0 ] && printf ','
        if [ -r "$f" ]; then
            readable=true
        else
            readable=false
        fi
        printf '"%s":%s' "$(json_escape "$f")" "$readable"
        first=0
    done

    printf '},"packages":['

    first=1
    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        [ $first -eq 0 ] && printf ','
        printf '"%s"' "$(json_escape "$pkg")"
        first=0
    done < "$DENY_TMP"

    printf ']}\n'

    rm -f "$DENY_TMP"
}

cmd_set() {
    local pkg="$1"
    local mode="$2"
    ensure

    valid_pkg "$pkg" || {
        printf '{"ok":false,"error":"invalid_package"}\n'
        exit 1
    }

    valid_mode "$mode" || {
        printf '{"ok":false,"error":"invalid_mode"}\n'
        exit 1
    }

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
        *)
            printf '{"ok":false,"error":"invalid_mode"}\n'
            exit 1
            ;;
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
        *)
            printf '{"ok":false,"error":"invalid_value"}\n'
            exit 1
            ;;
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

cmd="$1"
shift 2>/dev/null

case "$cmd" in
    list)      cmd_list ;;
    diag)      cmd_diag ;;
    set)       cmd_set "$@" ;;
    default)   cmd_default "$@" ;;
    prop)      cmd_prop "$@" ;;
    reset-all) cmd_reset_all ;;
    *)
        printf '{"ok":false,"error":"usage: api.sh list|diag|set|default|prop|reset-all"}\n'
        exit 1
        ;;
esac