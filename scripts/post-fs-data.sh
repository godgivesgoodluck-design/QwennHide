#!/system/bin/sh

MODDIR=${0%/*}

log -t SysOverlayPatch "Post-fs-data started"

# Early hiding: Bind mount /dev/null ke binary su yang umum
# Ini mencegah aplikasi yang menjalankan "which su" atau mengecek path menemukan file tersebut
for su_path in /system/bin/su /system/xbin/su /sbin/su /system/bin/.magisk; do
    if [ -f "$su_path" ] || [ -L "$su_path" ]; then
        mount -o bind /dev/null "$su_path" 2>/dev/null
        log -t SysOverlayPatch "Hidden: $su_path"
    fi
done

exit 0
