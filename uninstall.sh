#!/system/bin/sh

# QwennHide uninstall cleanup.
# This module never wrote persistent state outside its own directory,
# so there is nothing to roll back at the system level.
# We only clean up optional runtime data and defensive unmounts.

# 1. Defensive cleanup of optional runtime data owned by this module.
#    Fixed absolute paths only - no wildcards, no variable expansion.
for d in /data/adb/qwennhide /data/local/tmp/qwennhide; do
    [ -e "$d" ] && rm -rf "$d"
done

# 2. Defensive unmount of any global bind-mounts this module might have
#    created in earlier versions. These are per-mount-point, not recursive.
#    If the path is not a mount, `umount` silently fails - that's fine.
for p in \
    /system/bin/su \
    /system/xbin/su \
    /sbin/su \
    /system/bin/.magisk \
    /system/bin/magisk \
    /system/bin/magiskinit \
    /system/bin/magiskpolicy \
    /data/adb/magisk \
    /data/adb/modules \
    /data/adb/service.d \
    /data/adb/post-fs-data.d \
    /debug_ramdisk \
    /dev/.magisk \
    /dev/.magisk.unblock \
    /dev/zygisk \
; do
    # Only unmount if it is actually a mount point.
    if grep -q " ${p} " /proc/self/mountinfo 2>/dev/null; then
        umount -l "$p" 2>/dev/null
    fi
done

# 3. Deliberately NOT done here (would be unsafe or unnecessary):
#    - rm -rf "$MODDIR"          -> the manager handles this
#    - killing zygote            -> would reboot the user session
#    - resetprop -p / setprop    -> we never set persistent props
#    - modifying sepolicy        -> we never touched SELinux
#    - editing DenyList DB       -> that's the user's config
#
# Per-process mount changes die with the process.
# PLT hooks die when the app process exits.
# A reboot is recommended to clear any host-side module state.

exit 0
