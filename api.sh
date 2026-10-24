#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════
# QwennHide — api.sh v3.1.2
# POSIX-safe backend untuk WebUI / Action button.
#
# Prinsip:
#   - Selalu mencetak JSON valid ke stdout.
#   - Semua stderr ditekan.
#   - Tidak memakai local / bashism.
#   - Jika gagal, tetap fallback JSON.
# ═══════════════════════════════════════════════════════════════════════

BASE="/data/adb/qwennhide"
MODE_FILE="$BASE/mode"
PROP_FILE="$BASE/prop_spoof"
APPS_FILE="$BASE/apps.list"
RUNTIME_DIR="$BASE/runtime"
DENY_TMP="$BASE/.deny.tmp"
DBG_LOG="$BASE/api-debug.log"

DENY_FILES="
/data/adb/modules/neozygisk/denylist
/data/adb/modules/zygisksu/denylist
/data/adb/neozygisk/denylist
/data/adb/zygisksu/denylist
/data/adb/zygisknext/denylist
"

# ─── Root guard ────────────────────────────────────────────────────────
if command -v id >/dev/null 2>&1; then
    _RG_UID=$(id -u 2>/dev/null)
    if [ -n "$_RG_UID" ] && [ "$_RG_UID" != "0" ]; then
        printf '{"default_mode":"basic","prop_spoof":"0","apps":[],"ok":false,"error":"not_root"}\n'
        exit 0
    fi
fi

# ─── Validators ────────────────────────────────────────────────────────

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

# ─── Base helpers ──────────────────────────────────────────────────────

ensure() {
    mkdir -p "$BASE" "$RUNTIME_DIR" 2>/dev/null
    chmod 700 "$BASE" "$RUNTIME_DIR" 2>/dev/null

    [ -f "$MODE_FILE" ] || printf 'basic\n' > "$MODE_FILE" 2>/dev/null
    [ -f "$PROP_FILE" ] || printf '0\n' > "$PROP_FILE" 2>/dev/null
    [ -f "$APPS_FILE" ] || : > "$APPS_FILE" 2>/dev/null

    chmod 600 "$MODE_FILE" "$PROP_FILE" "$APPS_FILE" 2>/dev/null
}

get_first_line() {
    _GFL_LINE=""
    IFS= read -r _GFL_LINE < "$1" 2>/dev/null || return 1
    printf '%s' "$_GFL_LINE" | tr -d '\r\n ' 2>/dev/null
}

get_default_mode() {
    _GDM=$(get_first_line "$MODE_FILE" 2>/dev/null)
    case "$_GDM" in
        basic|aggressive|persistent) printf '%s' "$_GDM" ;;
        *) printf 'basic' ;;
    esac
}

get_prop() {
    _GP=$(get_first_line "$PROP_FILE" 2>/dev/null)
    case "$_GP" in
        0|1) printf '%s' "$_GP" ;;
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

    for _FM_P in \
        /data/adb/magisk/magisk \
        /sbin/magisk \
        /debug_ramdisk/magisk \
        /data/adb/magisk/magisk64 \
        /data/adb/magisk/magisk32
    do
        if [ -x "$_FM_P" ]; then
            printf '%s' "$_FM_P"
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
        _GDP_MAGISK=$(find_magisk)
        if [ -n "$_GDP_MAGISK" ]; then
            "$_GDP_MAGISK" --denylist ls 2>/dev/null | normalize_pkgs
        fi

        for _GDP_F in $DENY_FILES "$BASE/umount_list"; do
            if [ -r "$_GDP_F" ]; then
                normalize_pkgs < "$_GDP_F"
            fi
        done
    } | sort -u 2>/dev/null
}

is_pid_for_pkg() {
    _IPFP_PID="$1"
    _IPFP_PKG="$2"

    is_uint "$_IPFP_PID" || return 1
    [ "$_IPFP_PID" -gt 0 ] || return 1
    [ -d "/proc/$_IPFP_PID" ] || return 1

    if [ -r "/proc/$_IPFP_PID/cmdline" ]; then
        _IPFP_FIRST=$(tr '\0' '\n' < "/proc/$_IPFP_PID/cmdline" 2>/dev/null | head -n 1 2>/dev/null)
        _IPFP_BASE=${_IPFP_FIRST%%:*}
        [ "$_IPFP_BASE" = "$_IPFP_PKG" ] && return 0
    fi

    if [ -r "/proc/$_IPFP_PID/comm" ]; then
        _IPFP_FIRST=""
        IFS= read -r _IPFP_FIRST < "/proc/$_IPFP_PID/comm" 2>/dev/null
        _IPFP_BASE=${_IPFP_FIRST%%:*}
        [ "$_IPFP_BASE" = "$_IPFP_PKG" ] && return 0
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

dbg_log() {
    _DL_TS=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    [ -n "$_DL_TS" ] || _DL_TS="-"

    printf '[%s] %s\n' "$_DL_TS" "$*" >> "$DBG_LOG" 2>/dev/null

    _DL_SZ=$(wc -c < "$DBG_LOG" 2>/dev/null)
    case "$_DL_SZ" in
        ''|*[!0-9]*) _DL_SZ=0 ;;
    esac

    if [ "$_DL_SZ" -gt 262144 ]; then
        tail -n 200 "$DBG_LOG" > "$DBG_LOG.tmp" 2>/dev/null
        mv -f "$DBG_LOG.tmp" "$DBG_LOG" 2>/dev/null
    fi
}

# ─── Commands ──────────────────────────────────────────────────────────

cmd_list() {
    ensure

    _CL_DEFAULT=$(get_default_mode)
    _CL_PROP=$(get_prop)

    get_denylist_packages > "$DENY_TMP" 2>/dev/null || : > "$DENY_TMP" 2>/dev/null

    printf '{"default_mode":"%s","prop_spoof":"%s","apps":[' "$_CL_DEFAULT" "$_CL_PROP"

    _CL_FIRST=1

    if [ -r "$DENY_TMP" ]; then
        while IFS= read -r _CL_PKG; do
            [ -z "$_CL_PKG" ] && continue
            valid_pkg "$_CL_PKG" || continue

            _CL_OVERRIDE=$(get_app_override "$_CL_PKG")

            if [ -n "$_CL_OVERRIDE" ]; then
                _CL_MODE="$_CL_OVERRIDE"
                _CL_OVERRIDDEN=true
            else
                _CL_MODE="$_CL_DEFAULT"
                _CL_OVERRIDDEN=false
            fi

            _CL_RT_FILE="$RUNTIME_DIR/$_CL_PKG"
            _CL_RT_RUNNING=false
            _CL_RT_MODE=""
            _CL_RT_PID=0
            _CL_RT_AGE=0

            if [ -r "$_CL_RT_FILE" ]; then
                _CL_RPID=""
                _CL_RACTION=""
                _CL_RTS=""

                IFS='|' read -r _CL_RPID _CL_RACTION _CL_RTS < "$_CL_RT_FILE" 2>/dev/null

                is_uint "$_CL_RPID" || _CL_RPID=0
                is_uint "$_CL_RACTION" || _CL_RACTION=0
                is_uint "$_CL_RTS" || _CL_RTS=0

                _CL_NOW=$(date +%s 2>/dev/null)
                is_uint "$_CL_NOW" || _CL_NOW=0

                if [ "$_CL_RTS" -gt 0 ] && [ "$_CL_NOW" -gt 0 ]; then
                    _CL_RT_AGE=$((_CL_NOW - _CL_RTS))
                    [ "$_CL_RT_AGE" -lt 0 ] && _CL_RT_AGE=0
                fi

                _CL_RT_MODE=$(action_to_mode "$_CL_RACTION")

                if is_pid_for_pkg "$_CL_RPID" "$_CL_PKG"; then
                    _CL_RT_RUNNING=true
                    _CL_RT_PID="$_CL_RPID"
                else
                    _CL_RT_RUNNING=false
                    _CL_RT_PID=0
                fi
            fi

            [ "$_CL_FIRST" -eq 0 ] && printf ','

            printf '{"pkg":"%s","mode":"%s","overridden":%s,"runtime_running":%s,"runtime_mode":"%s","runtime_pid":%s,"runtime_age":%s}' \
                "$_CL_PKG" \
                "$_CL_MODE" \
                "$_CL_OVERRIDDEN" \
                "$_CL_RT_RUNNING" \
                "$_CL_RT_MODE" \
                "$_CL_RT_PID" \
                "$_CL_RT_AGE"

            _CL_FIRST=0
        done < "$DENY_TMP"
    fi

    printf ']}\n'
    rm -f "$DENY_TMP" 2>/dev/null
}

cmd_diag() {
    ensure

    _CD_M=$(find_magisk)

    if [ -n "$_CD_M" ]; then
        _CD_MAGISK_FOUND=true
    else
        _CD_MAGISK_FOUND=false
    fi

    get_denylist_packages > "$DENY_TMP" 2>/dev/null || : > "$DENY_TMP" 2>/dev/null

    _CD_COUNT=0
    if [ -r "$DENY_TMP" ]; then
        while IFS= read -r _CD_PKG; do
            [ -z "$_CD_PKG" ] && continue
            _CD_COUNT=$((_CD_COUNT + 1))
        done < "$DENY_TMP"
    fi

    _CD_RT_COUNT=0
    if [ -d "$RUNTIME_DIR" ]; then
        for _CD_RT_F in "$RUNTIME_DIR"/*; do
            [ -f "$_CD_RT_F" ] && _CD_RT_COUNT=$((_CD_RT_COUNT + 1))
        done
    fi

    printf '{"magisk_found":%s,"magisk_bin":"%s","denylist_count":%s,"runtime_count":%s,"files":{' \
        "$_CD_MAGISK_FOUND" \
        "$_CD_M" \
        "$_CD_COUNT" \
        "$_CD_RT_COUNT"

    _CD_FIRST=1
    for _CD_F in $DENY_FILES "$BASE/umount_list"; do
        [ "$_CD_FIRST" -eq 0 ] && printf ','

        if [ -r "$_CD_F" ]; then
            _CD_READABLE=true
        else
            _CD_READABLE=false
        fi

        printf '"%s":%s' "$_CD_F" "$_CD_READABLE"
        _CD_FIRST=0
    done

    printf '},"packages":['

    _CD_FIRST=1
    if [ -r "$DENY_TMP" ]; then
        while IFS= read -r _CD_PKG; do
            [ -z "$_CD_PKG" ] && continue
            valid_pkg "$_CD_PKG" || continue

            [ "$_CD_FIRST" -eq 0 ] && printf ','
            printf '"%s"' "$_CD_PKG"
            _CD_FIRST=0
        done < "$DENY_TMP"
    fi

    printf ']}\n'
    rm -f "$DENY_TMP" 2>/dev/null
}

cmd_set() {
    _CS_RAW1="$1"
    _CS_RAW2="$2"
    _CS_PKG=""
    _CS_MODE=""

    if [ -n "$_CS_RAW2" ]; then
        _CS_PKG="$_CS_RAW1"
        _CS_MODE="$_CS_RAW2"
    else
        case "$_CS_RAW1" in
            *:*)
                _CS_PKG=${_CS_RAW1%:*}
                _CS_MODE=${_CS_RAW1##*:}
                ;;
        esac
    fi

    dbg_log "SET raw1=[$_CS_RAW1] raw2=[$_CS_RAW2] pkg=[$_CS_PKG] mode=[$_CS_MODE]"

    ensure

    if ! valid_pkg "$_CS_PKG"; then
        dbg_log "SET invalid_package pkg=[$_CS_PKG]"
        printf '{"ok":false,"error":"invalid_package"}\n'
        return 1
    fi

    if ! valid_mode "$_CS_MODE"; then
        dbg_log "SET invalid_mode pkg=[$_CS_PKG] mode=[$_CS_MODE]"
        printf '{"ok":false,"error":"invalid_mode"}\n'
        return 1
    fi

    _CS_TMP="$APPS_FILE.tmp"

    awk -F'|' -v p="$_CS_PKG" '$1 != p' "$APPS_FILE" > "$_CS_TMP" 2>/dev/null || : > "$_CS_TMP" 2>/dev/null

    if [ "$_CS_MODE" != "default" ]; then
        printf '%s|%s\n' "$_CS_PKG" "$_CS_MODE" >> "$_CS_TMP" 2>/dev/null
    fi

    if ! mv -f "$_CS_TMP" "$APPS_FILE" 2>/dev/null; then
        dbg_log "SET write_failed pkg=[$_CS_PKG] mode=[$_CS_MODE]"
        printf '{"ok":false,"error":"write_failed"}\n'
        return 1
    fi

    chmod 600 "$APPS_FILE" 2>/dev/null

    dbg_log "SET ok pkg=[$_CS_PKG] mode=[$_CS_MODE]"
    printf '{"ok":true}\n'
}

cmd_default() {
    _CDFT_MODE="$1"

    dbg_log "DEFAULT mode=[$_CDFT_MODE]"
    ensure

    case "$_CDFT_MODE" in
        basic|aggressive|persistent) ;;
        *)
            printf '{"ok":false,"error":"invalid_mode"}\n'
            return 1
            ;;
    esac

    printf '%s\n' "$_CDFT_MODE" > "$MODE_FILE" 2>/dev/null || {
        printf '{"ok":false,"error":"write_failed"}\n'
        return 1
    }

    chmod 600 "$MODE_FILE" 2>/dev/null
    printf '{"ok":true}\n'
}

cmd_prop() {
    _CPROP_VAL="$1"

    dbg_log "PROP val=[$_CPROP_VAL]"
    ensure

    case "$_CPROP_VAL" in
        0|1) ;;
        *)
            printf '{"ok":false,"error":"invalid_value"}\n'
            return 1
            ;;
    esac

    printf '%s\n' "$_CPROP_VAL" > "$PROP_FILE" 2>/dev/null || {
        printf '{"ok":false,"error":"write_failed"}\n'
        return 1
    }

    chmod 600 "$PROP_FILE" 2>/dev/null
    printf '{"ok":true,"reboot_required":true}\n'
}

cmd_reset_all() {
    dbg_log "RESET_ALL"
    ensure

    : > "$APPS_FILE" 2>/dev/null || {
        printf '{"ok":false,"error":"write_failed"}\n'
        return 1
    }

    chmod 600 "$APPS_FILE" 2>/dev/null
    printf '{"ok":true}\n'
}

# ─── Dispatch with forced JSON ─────────────────────────────────────────

_CMD="$1"
shift 2>/dev/null

_OUT=$(
    {
        case "$_CMD" in
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
    } 2>/dev/null
)

_FIRST_CHAR=$(printf '%.1s' "$_OUT" 2>/dev/null)

if [ "$_FIRST_CHAR" = "{" ]; then
    printf '%s\n' "$_OUT"
else
    case "$_CMD" in
        list|diag)
            fallback_list_error "backend_failed"
            ;;
        *)
            fallback_ok_error "backend_failed"
            ;;
    esac
fi