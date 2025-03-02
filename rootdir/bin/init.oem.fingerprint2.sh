#!/vendor/bin/sh
#
# Start indicated fingerprint HAL service
#
# Copyright (c) 2019 Lenovo
# All rights reserved.
#
# April 15, 2019  chengql2@lenovo.com  Initial version
# December 2, 2019  chengql2  Store fps_id into persist fs

script_name=${0##*/}
script_name=${script_name%.*}
function log {
    echo "$script_name: $*" > /dev/kmsg
}

persist_fps_id=/mnt/vendor/persist/fps/vendor_id
persist_fps_id2=/mnt/vendor/persist/fps/last_vendor_id
MAX_TIMES=20

if [ ! -f $persist_fps_id ]; then
    log "warn: no associated persist file found"
    return -1
fi

FPS_VENDOR_NONE=none
FPS_VENDOR_FPC=fpc
FPS_VENDOR_GOODIX=goodix

prop_fps_status=vendor.hw.fingerprint.status
prop_persist_fps=persist.vendor.hardware.fingerprint

FPS_STATUS_NONE=none
FPS_STATUS_OK=ok

fps_vendor2=$(cat $persist_fps_id2)
if [ -z $fps_vendor2 ]; then
    fps_vendor2=$FPS_VENDOR_NONE
fi
log "FPS vendor (last): $fps_vendor2"
fps_vendor=$(cat $persist_fps_id)
if [ -z $fps_vendor ]; then
    fps_vendor=$FPS_VENDOR_NONE
fi
log "FPS vendor: $fps_vendor"

if [ $fps_vendor == $FPS_STATUS_NONE ]; then
    log "warn: boot as the last FPS"
    fps=$fps_vendor2
else
    fps=$fps_vendor
fi

for i in $(seq 1 2); do
    setprop $prop_fps_status $FPS_STATUS_NONE
    if [ $fps == $FPS_VENDOR_GOODIX ]; then
        log "- start service 'goodix_hal'"
        start goodix_hal
    else
        log "- start service 'fps_hal'"
        start fps_hal
    fi

    sleep 1.2
    fps_status=$(getprop $prop_fps_status)
    if [ $fps_status == $FPS_STATUS_NONE ]; then
        log "- wait for fingerprint HAL service ..."
        for j in $(seq 1 100); do
            fps_status=$(getprop $prop_fps_status)
            if [ $fps_status != $FPS_STATUS_NONE ]; then
                break
            fi
            sleep 0.2
        done
    fi
    log "status: $fps_status"
    if [ $fps_status == $FPS_STATUS_OK ]; then
        log "HAL success"
        setprop $prop_persist_fps $fps
        if [ $fps_vendor2 == $fps ]; then
            return 0
        fi
        log "- update FPS vendor (last)"
        echo $fps > $persist_fps_id2
        log "- done"
        return 0
    fi

    if [ $fps == $fps_vendor2 ]; then
        if [ $fps == $FPS_VENDOR_GOODIX ]; then
            rmmod goodix_fod_mmi
            insmod /vendor/lib/modules/fpc1020_mmi.ko
            fps=$FPS_VENDOR_FPC
        else
            rmmod fpc1020_mmi
            insmod /vendor/lib/modules/goodix_fod_mmi.ko
            fps=$FPS_VENDOR_GOODIX
        fi
        log "- update FPS vendor"
        echo $fps > $persist_fps_id
        sleep 1
    else
        log "error: HAL fail again"
        setprop $prop_persist_fps $FPS_VENDOR_NONE
        echo $FPS_VENDOR_NONE > $persist_fps_id
        log "- done"
        return 1
    fi
done
