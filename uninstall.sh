#!/system/bin/sh
# QwennHide - uninstall.sh (Clean, NeoZygisk-safe)

# Satu-satunya data milik QwennHide di luar module dir:
rm -rf /data/adb/qwennhide

# TIDAK melakukan:
#   - umount global (bisa ganggu NeoZygisk/Magisk)
#   - resetprop -p (tidak pernah dipakai)
#   - kill daemon (NeoZygisk yang manage companion)
#
# Prop non-persist hilang otomatis saat reboot.
# Unmount per-proses mati bersama proses app.

exit 0
