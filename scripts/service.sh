#!/system/bin/sh

MODDIR=${0%/*}

while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 1
done
sleep 5

log -t MyRootHider "Service started"

exit 0
