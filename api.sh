#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════
# QwennHide — api.sh v3.1.1
# Backend WebUI / Action button.
#
# Prinsip:
#   - Selalu mencetak JSON valid ke stdout.
#   - Semua stderr ditekan.
#   - Jika gagal, tetap fallback JSON.
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

# ─── Root guard ────────────────────────────────────────────────────────
if command -v id >/dev/null 2>&1; then
    UID_VAL=$(id -u 2>/dev/null)
    if [ -n "$UID_VAL" ] && [ "$UID_VAL" != "0" ]; then
        printf '{"default_mode":"basic","prop_spoof":"0","apps":[],"ok":false,"error":"not_root"}\n'
        exit 0
    fi
fi

# ─── Helpers ───────────────────────────────────────────────────────────

is_uint() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

valid_pkg() {
    case "$1" in
        ''|*[!A-Za-z0-9._]*) return 1 ;;
        *) return 0 ;;
    esac
}

valid_mode() {
    case "$1" in
        basic|aggressive|persistent|default) return 0 ;;
        *) return 1 ;;
    esac
}

ensure() {
    mkdir -p "$BASE" "$RUNTIME_DIR" 2>/dev/null
    chmod 700 "$BASE" "$RUNTIME_DIR" 2>/dev/null

    [ -f "$MODE_FILE" ] || printf 'basic\n' > "$MODE_FILE" 2>/dev/null
    [ -f "$PROP_FILE" ] || printf '0\n' > "$PROP_FILE" 2>/dev/null
    [ -f "$APPS_FILE" ] || : > "$APPS_FILE" 2>/dev/null

    chmod 600 "$MODE_FILE" "$PROP_FILE" "$APPS_FILE" 2>/dev/null
}

get_first_line() {
    local line=""
    IFS= read -r line < "$1" 2>/dev/null || return 1
    printf '%s' "$line"
}

get_default_mode() {
    local m
    m=$(get_first_line "$MODE_FILE" 2>/dev/null)
    case "$m" in
        basic|aggressive|persistent) printf '%s' "$m" ;;
        *) printf 'basic' ;;
    esac
}

get_prop() {
    local p
    p=$(get_first_line "$PROP_FILE" 2>/dev/null)
    case "$p" in
        0|1) printf '%s' "$p" ;;
        *) printf '0' ;;
    esac
}

get_app_override() {
    awk -F'|' -v p="$1" '
        $1 == p { m = $2 }
        END { if (m != "") print m }
    ' "$APPS_FILE" 2>/dev/null
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
        sub(/\r$/, "")
        if ($0 ~ /^[ \t]*#/) next

        pkg = $1
        if ($1 ~ /^[ \t]*[0-9]+[ \t]*$/ && NF >= 2) {
            pkg = $2
        }

        gsub(/^[ \t\r]+|[ \t\r]+$/, "", pkg)
        sub(/:.*/, "", pkg)

        if (pkg ~ /^[A-Za-z][A-Za-z0-9._]*$/) {
            print pkg
        }
    }' 2>/dev/null
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
    } | awk '!seen[$0]++' 2>/dev/null
}

is_pid_for_pkg() {
    pid="$1"
    pkg="$2"

    is_uint "$pid" || return 1
    [ "$pid" -gt 0 ] || return 1
    [ -d "/proc/$pid" ] || return 1

    if [ -r "/proc/$pid/cmdline" ]; then
        first=$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | head -n 1 2>/dev/null)
        base=${first%%:*}
        [ "$base" = "$pkg" ] && return 0
    fi

    if [ -r "/proc/$pid/comm" ]; then
        first=""
        IFS= read -r first < "/proc/$pid/comm" 2>/dev/null
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

fallback_list_error() {
    printf '{"default_mode":"basic","prop_spoof":"0","apps":[],"ok":false,"error":"%s"}\n' "$1"
}

fallback_ok_error() {
    printf '{"ok":false,"error":"%s"}\n' "$1"
}

# ─── Commands ──────────────────────────────────────────────────────────

cmd_list() {
    ensure

    default=$(get_default_mode)
    prop=$(get_prop)

    get_denylist_packages > "$DENY_TMP" 2>/dev/null || : > "$DENY_TMP" 2>/dev/null

    printf '{"default_mode":"%s","prop_spoof":"%s","apps":[' "$default" "$prop"

    first=1
    if [ -r "$DENY_TMP" ]; then
        while IFS= read -r pkg; do
            [ -z "$pkg" ] && continue
            valid_pkg "$pkg" || continue

            override=$(get_app_override "$pkg")
            if [ -n "$override" ]; then
                mode="$override"
                overridden=true
            else
                mode="$default"
                overridden=false
            fi

            rt_file="$RUNTIME_DIR/$pkg"
            rt_running=false
            rt_mode=""
            rt_pid=0
            rt_age=0

            if [ -r "$rt_file" ]; then
                rpid=""
                raction=""
                rts=""
                IFS='|' read -r rpid raction rts < "$rt_file" 2>/dev/null

                is_uint "$rpid" || rpid=0
                is_uint "$raction" || raction=0
                is_uint "$rts" || rts=0

                now=$(date +%s 2>/dev/null)
                is_uint "$now" || now=0

                if [ "$rts" -gt 0 ] && [ "$now" -gt 0 ]; then
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
            printf '{"pkg":"%s","mode":"%s","overridden":%s,"runtime_running":%s,"runtime_mode":"%s","runtime_pid":%s,"runtime_age":%s}' \
                "$pkg" \
                "$mode" \
                "$overridden" \
                "$rt_running" \
                "$rt_mode" \
                "$rt_pid" \
                "$rt_age"

            first=0
        done < "$DENY_TMP"
    fi

    printf ']}\n'
    rm -f "$DENY_TMP" 2>/dev/null
}

cmd_diag() {
    ensure

    m=$(find_magisk)
    if [ -n "$m" ]; then
        magisk_found=true
    else
        magisk_found=false
    fi

    get_denylist_packages > "$DENY_TMP" 2>/dev/null || : > "$DENY_TMP" 2>/dev/null

    count=0
    if [ -r "$DENY_TMP" ]; then
        while IFS= read -r pkg; do
            [ -z "$pkg" ] && continue
            count=$((count + 1))
        done < "$DENY_TMP"
    fi

    rt_count=0
    if [ -d "$RUNTIME_DIR" ]; then
        for f in "$RUNTIME_DIR"/*; do
            [ -f "$f" ] && rt_count=$((rt_count + 1))
        done
    fi

    printf '{"magisk_found":%s,"magisk_bin":"%s","denylist_count":%s,"runtime_count":%s,"files":{' \
        "$magisk_found" \
        "$m" \
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
        printf '"%s":%s' "$f" "$readable"
        first=0
    done

    printf '},"packages":['

    first=1
    if [ -r "$DENY_TMP" ]; then
        while IFS= read -r pkg; do
            [ -z "$pkg" ] && continue
            valid_pkg "$pkg" || continue
            [ $first -eq 0 ] && printf ','
            printf '"%s"' "$pkg"
            first=0
        done < "$DENY_TMP"
    fi

    printf ']}\n'
    rm -f "$DENY_TMP" 2>/dev/null
}

cmd_set() {
    pkg="$1"
    mode="$2"
    ensure

    valid_pkg "$pkg" || {
        printf '{"ok":false,"error":"invalid_package"}\n'
        return 1
    }

    valid_mode "$mode" || {
        printf '{"ok":false,"error":"invalid_mode"}\n'
        return 1
    }

    tmp="$APPS_FILE.tmp"
    awk -F'|' -v p="$pkg" '$1 != p' "$APPS_FILE" > "$tmp" 2>/dev/null || : > "$tmp" 2>/dev/null

    if [ "$mode" != "default" ]; then
        printf '%s|%s\n' "$pkg" "$mode" >> "$tmp" 2>/dev/null
    fi

    mv -f "$tmp" "$APPS_FILE" 2>/dev/null || {
        printf '{"ok":false,"error":"write_failed"}\n'
        return 1
    }

    chmod 600 "$APPS_FILE" 2>/dev/null
    printf '{"ok":true}\n'
}

cmd_default() {
    mode="$1"
    ensure

    case "$mode" in
        basic|aggressive|persistent) ;;
        *)
            printf '{"ok":false,"error":"invalid_mode"}\n'
            return 1
            ;;
    esac

    printf '%s\n' "$mode" > "$MODE_FILE" 2>/dev/null || {
        printf '{"ok":false,"error":"write_failed"}\n'
        return 1
    }

    chmod 600 "$MODE_FILE" 2>/dev/null
    printf '{"ok":true}\n'
}

cmd_prop() {
    val="$1"
    ensure

    case "$val" in
        0|1) ;;
        *)
            printf '{"ok":false,"error":"invalid_value"}\n'
            return 1
            ;;
    esac

    printf '%s\n' "$val" > "$PROP_FILE" 2>/dev/null || {
        printf '{"ok":false,"error":"write_failed"}\n'
        return 1
    }

    chmod 600 "$PROP_FILE" 2>/dev/null
    printf '{"ok":true,"reboot_required":true}\n'
}

cmd_reset_all() {
    ensure
    : > "$APPS_FILE" 2>/dev/null || {
        printf '{"ok":false,"error":"write_failed"}\n'
        return 1
    }

    chmod 600 "$APPS_FILE" 2>/dev/null
    printf '{"ok":true}\n'
}

# ─── Dispatch with forced JSON ─────────────────────────────────────────

cmd="$1"
shift 2>/dev/null

out=$(
    case "$cmd" in
        list)      cmd_list ;;
        diag)      cmd_diag ;;
        set)       cmd_set "$@" ;;
        default)   cmd_default "$@" ;;
        prop)      cmd_prop "$@" ;;
        reset-all) cmd_reset_all ;;
        *)
            printf '{"ok":false,"error":"usage: api.sh list|diag|set|default|prop|reset-all"}\n'
            ;;
    esac
)

case "$out" in
    \{*)
        printf '%s\n' "$out"
        ;;
    *)
        case "$cmd" in
            list|diag)
                fallback_list_error "backend_failed"
                ;;
            *)
                fallback_ok_error "backend_failed"
                ;;
        esac
        ;;
esac