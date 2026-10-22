#!/system/bin/sh
# QwennHide - service.sh

DATADIR="/data/adb/qwennhide"
mkdir -p "$DATADIR"

# Wait for boot
while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done
sleep 3

# Hide Magisk props using resetprop (Safe, global, no PLT hook needed)
resetprop --delete ro.magisk.hide 2>/dev/null
resetprop --delete ro.boot.magisk 2>/dev/null
resetprop ro.debuggable 0 2>/dev/null
resetprop ro.secure 1 2>/dev/null
