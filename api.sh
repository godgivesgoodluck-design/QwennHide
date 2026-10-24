#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════════════
# QwennHide — api.sh v3.1.5
# POSIX-safe, forced JSON, verified per-app mode, no awk dependency.
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

if command -v id >/dev/null 2>&1; then
    _RG_UID=$(id -u 2>/dev/null)
    if [ -n "$_RG_UID" ] && [ "$_RG_UID" != "0" ]; then
        printf '{"default_mode":"basic","prop_spoof":"0","apps":[],"ok":false,"error":"not_root"}\n'
        exit 0
    fi
fi

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

valid_override_mode() {
    case "$1" in
        basic|aggressive|persistent) return 0 ;;
        *) return 1 ;;
    esac
}

dbg_log() {
    _DL_TS=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    [ -n "$_DL_TS" ] || _DL_TS="-"

    mkdir -p "$BASE" 2>/dev/null
    printf '[%s] %s\n' "$_DL_TS" "$*" >> "$DBG_LOG" 2>/dev/null

    _DL_SZ=$(wc -c < "$DBG_LOG" 2>/dev/null | tr -d ' \t\r\n')
    case "$_DL_SZ" in
        ''|*[!0-9]*) _DL_SZ=0 ;;
    esac

    if [ "$_DL_SZ" -gt 262144 ]; then
        tail -n 200 "$DBG_LOG" > "$DBG_LOG.tmp" 2>/dev/null
        mv -f "$DBG_LOG.tmp" "$DBG_LOG" 2>/dev/null
    fi
}

run_with_timeout() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 2 "$@" 2>/dev/null
    else
        "$@" 2>/dev/null
    fi
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
    _GAO_PKG="$1"
    _GAO_FOUND=""

    [ -r "$APPS_FILE" ] || return 0

    while IFS= read -r _GAO_LINE || [ -n "$_GAO_LINE" ]; do
        _GAO_LINE=$(printf '%s' "$_GAO_LINE" | tr -d '\r' 2>/dev/null)
        [ -z "$_GAO_LINE" ] && continue

        case "$_GAO_LINE" in
            '#'*) continue ;;
        esac

        case "$_GAO_LINE" in
            *'|'*)
                _GAO_K=${_GAO_LINE%%|*}
                _GAO_V=${_GAO_LINE#*|}
                ;;
            *)
                continue
                ;;
        esac

        _GAO_K=$(printf '%s' "$_GAO_K" | tr -d ' \t\r\n' 2>/dev/null)
        _GAO_V=$(printf '%s' "$_GAO_V" | tr -d ' \t\r\n' 2>/dev/null)

        if [ "$_GAO_K" = "$_GAO_PKG" ]; then
            _GAO_FOUND="$_GAO_V"
        fi
    done < "$APPS_FILE"

    printf '%s' "$_GAO_FOUND"
}

count_apps_entries() {
    _CAE_COUNT=0

    [ -r "$APPS_FILE" ] || {
        printf '0'
        return
    }

    while IFS= read -r _CAE_LINE || [ -n "$_CAE_LINE" ]; do
        _CAE_LINE=$(printf '%s' "$_CAE_LINE" | tr -d '\r' 2>/dev/null)
        [ -z "$_CAE_LINE" ] && continue

        case "$_CAE_LINE" in
            '#'*) continue ;;
        esac

        case "$_CAE_LINE" in
            *'|'*)
                _CAE_K=${_CAE_LINE%%|*}
                _CAE_V=${_CAE_LINE#*|}
                ;;
            *)
                continue
                ;;
        esac

        _CAE_K=$(printf '%s' "$_CAE_K" | tr -d ' \t\r\n' 2>/dev/null)
        _CAE_V=$(printf '%s' "$_CAE_V" | tr -d ' \t\r\n' 2>/dev/null)

        if valid_pkg "$_CAE_K" && valid_override_mode "$_CAE_V"; then
            _CAE_COUNT=$((_CAE_COUNT + 1))
        fi
    done < "$APPS_FILE"

    printf '%s' "$_CAE_COUNT"
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
    while IFS= read -r _NP_LINE || [ -n "$_NP_LINE" ]; do
        _NP_LINE=$(printf '%s' "$_NP_LINE" | tr -d '\r' 2>/dev/null)
        [ -z "$_NP_LINE" ] && continue

        case "$_NP_LINE" in
            '#'*) continue ;;
        esac

        _NP_F1=""
        _NP_F2=""

        case "$_NP_LINE" in
            *'|'*)
                _NP_F1=${_NP_LINE%%|*}
                _NP_F2=${_NP_LINE#*|}
                ;;
            *)
                _NP_F1="$_NP_LINE"
                ;;
        esac

        _NP_PKG="$_NP_F1"

        if is_uint "$_NP_F1" && [ -n "$_NP_F2" ]; then
            case "$_NP_F2" in
                *'|'*)
                    _NP_PKG=${_NP_F2%%|*}
                    ;;
                *)
                    _NP_PKG="$_NP_F2"
                    ;;
            esac
        fi

        _NP_PKG=${_NP_PKG%%:*}
        _NP_PKG=$(printf '%s' "$_NP_PKG" | tr -d ' \t\r\n' 2>/dev/null)

        if valid_pkg "$_NP_PKG"; then
            printf '%s\n' "$_NP_PKG"
        fi
    done
}

get_denylist_packages() {
    {
        _GDP_MAGISK=$(find_magisk)
        if [ -n "$_GDP_MAGISK" ]; then
            run_with_timeout "$_GDP_MAGISK" --denylist ls | normalize_pkgs
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

    if [ -r "$APPS_FILE" ]; then
        _CD_APPS_READABLE=true
    else
        _CD_APPS_READABLE=false
    fi

    _CD_APPS_COUNT=$(count_apps_entries)

    printf '{"magisk_found":%s,"magisk_bin":"%s","denylist_count":%s,"runtime_count":%s,"apps_list_readable":%s,"apps_list_count":%s,"files":{' \
        "$_CD_MAGISK_FOUND" \
        "$_CD_M" \
        "$_CD_COUNT" \
        "$_CD_RT_COUNT" \
        "$_CD_APPS_READABLE" \
        "$_CD_APPS_COUNT"

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

    ensure

    dbg_log "SET raw1=[$_CS_RAW1] raw2=[$_CS_RAW2] pkg=[$_CS_PKG] mode=[$_CS_MODE]"

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

    if ! : > "$_CS_TMP" 2>/dev/null; then
        dbg_log "SET tmp_create_failed pkg=[$_CS_PKG] mode=[$_CS_MODE]"
        printf '{"ok":false,"error":"tmp_create_failed"}\n'
        return 1
    fi

    if [ -r "$APPS_FILE" ]; then
        while IFS= read -r _CS_LINE || [ -n "$_CS_LINE" ]; do
            _CS_LINE=$(printf '%s' "$_CS_LINE" | tr -d '\r' 2>/dev/null)
            [ -z "$_CS_LINE" ] && continue

            case "$_CS_LINE" in
                '#'*) continue ;;
            esac

            case "$_CS_LINE" in
                *'|'*)
                    _CS_K=${_CS_LINE%%|*}
                    _CS_V=${_CS_LINE#*|}
                    ;;
                *)
                    continue
                    ;;
            esac

            _CS_K=$(printf '%s' "$_CS_K" | tr -d ' \t\r\n' 2>/dev/null)
            _CS_V=$(printf '%s' "$_CS_V" | tr -d ' \t\r\n' 2>/dev/null)

            [ "$_CS_K" = "$_CS_PKG" ] && continue

            if valid_pkg "$_CS_K" && valid_override_mode "$_CS_V"; then
                printf '%s|%s\n' "$_CS_K" "$_CS_V" >> "$_CS_TMP" 2>/dev/null
            fi
        done < "$APPS_FILE"
    fi

    if [ "$_CS_MODE" != "default" ]; then
        printf '%s|%s\n' "$_CS_PKG" "$_CS_MODE" >> "$_CS_TMP" 2>/dev/null
    fi

    if ! mv -f "$_CS_TMP" "$APPS_FILE" 2>/dev/null; then
        dbg_log "SET write_failed pkg=[$_CS_PKG] mode=[$_CS_MODE]"
        printf '{"ok":false,"error":"write_failed"}\n'
        return 1
    fi

    chmod 600 "$APPS_FILE" 2>/dev/null
    sync 2>/dev/null

    _CS_CHECK=$(get_app_override "$_CS_PKG")

    if [ "$_CS_MODE" = "default" ]; then
        if [ -n "$_CS_CHECK" ]; then
            dbg_log "SET verify_failed pkg=[$_CS_PKG] expected=default got=[$_CS_CHECK]"
            printf '{"ok":false,"error":"verify_failed"}\n'
            return 1
        fi
    else
        if [ "$_CS_CHECK" != "$_CS_MODE" ]; then
            dbg_log "SET verify_failed pkg=[$_CS_PKG] expected=[$_CS_MODE] got=[$_CS_CHECK]"
            printf '{"ok":false,"error":"verify_failed"}\n'
            return 1
        fi
    fi

    dbg_log "SET ok pkg=[$_CS_PKG] mode=[$_CS_MODE]"
    printf '{"ok":true}\n'
}

cmd_default() {
    _CDFT_MODE="$1"

    ensure
    dbg_log "DEFAULT mode=[$_CDFT_MODE]"

    case "$_CDFT_MODE" in
        basic|aggressive|persistent) ;;
        *)
            dbg_log "DEFAULT invalid_mode mode=[$_CDFT_MODE]"
            printf '{"ok":false,"error":"invalid_mode"}\n'
            return 1
            ;;
    esac

    printf '%s\n' "$_CDFT_MODE" > "$MODE_FILE" 2>/dev/null || {
        dbg_log "DEFAULT write_failed mode=[$_CDFT_MODE]"
        printf '{"ok":false,"error":"write_failed"}\n'
        return 1
    }

    chmod 600 "$MODE_FILE" 2>/dev/null
    sync 2>/dev/null

    _CDFT_CHECK=$(get_first_line "$MODE_FILE" 2>/dev/null)
    if [ "$_CDFT_CHECK" != "$_CDFT_MODE" ]; then
        dbg_log "DEFAULT verify_failed expected=[$_CDFT_MODE] got=[$_CDFT_CHECK]"
        printf '{"ok":false,"error":"verify_failed"}\n'
        return 1
    fi

    dbg_log "DEFAULT ok mode=[$_CDFT_MODE]"
    printf '{"ok":true}\n'
}

cmd_prop() {
    _CPROP_VAL="$1"

    ensure
    dbg_log "PROP val=[$_CPROP_VAL]"

    case "$_CPROP_VAL" in
        0|1) ;;
        *)
            dbg_log "PROP invalid_value val=[$_CPROP_VAL]"
            printf '{"ok":false,"error":"invalid_value"}\n'
            return 1
            ;;
    esac

    printf '%s\n' "$_CPROP_VAL" > "$PROP_FILE" 2>/dev/null || {
        dbg_log "PROP write_failed val=[$_CPROP_VAL]"
        printf '{"ok":false,"error":"write_failed"}\n'
        return 1
    }

    chmod 600 "$PROP_FILE" 2>/dev/null
    sync 2>/dev/null

    _CPROP_CHECK=$(get_first_line "$PROP_FILE" 2>/dev/null)
    if [ "$_CPROP_CHECK" != "$_CPROP_VAL" ]; then
        dbg_log "PROP verify_failed expected=[$_CPROP_VAL] got=[$_CPROP_CHECK]"
        printf '{"ok":false,"error":"verify_failed"}\n'
        return 1
    fi

    dbg_log "PROP ok val=[$_CPROP_VAL]"
    printf '{"ok":true,"reboot_required":true}\n'
}

cmd_reset_all() {
    ensure
    dbg_log "RESET_ALL"

    : > "$APPS_FILE" 2>/dev/null || {
        dbg_log "RESET_ALL write_failed"
        printf '{"ok":false,"error":"write_failed"}\n'
        return 1
    }

    chmod 600 "$APPS_FILE" 2>/dev/null
    sync 2>/dev/null

    _RA_CHECK=$(count_apps_entries)
    if [ "$_RA_CHECK" != "0" ]; then
        dbg_log "RESET_ALL verify_failed count=[$_RA_CHECK]"
        printf '{"ok":false,"error":"verify_failed"}\n'
        return 1
    fi

    dbg_log "RESET_ALL ok"
    printf '{"ok":true}\n'
}

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
    dbg_log "DISPATCH fallback cmd=[$_CMD] first_char=[$_FIRST_CHAR]"
    case "$_CMD" in
        list|diag)
            fallback_list_error "backend_failed"
            ;;
        *)
            fallback_ok_error "backend_failed"
            ;;
    esac
fi