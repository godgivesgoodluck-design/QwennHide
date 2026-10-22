#!/system/bin/sh

# Cleanup optional runtime data
for d in /data/adb/qwennhide /data/local/tmp/qwennhide; do
    [ -e "$d" ] && rm -rf "$d"
done

# Defensive unmount of any global bind-mounts from older versions
for p in \
    /system/bin/su /system/xbin/su /sbin/su \
    /system/bin/.magisk /system/bin/magisk \
    /system/bin/magiskinit /system/bin/magiskpolicy \
    /data/adb/magisk /data/adb/modules \
    /data/adb/service.d /data/adb/post-fs-data.d \
    /debug_ramdisk /dev/.magisk /dev/.magisk.unblock /dev/zygisk \
; do
    if grep -q " ${p} " /proc/self/mountinfo 2>/dev/null; then
        umount -l "$p" 2>/dev/null
    fi
done

exit 0
