#!/bin/sh
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

export DRACUT_SYSTEMD=1
if [ -f /dracut-state.sh ]; then
    . /dracut-state.sh 2>/dev/null
fi
type getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh

source_conf /etc/conf.d

make_trace_mem "hook initqueue" '1:shortmem' '2+:mem' '3+:slab'
getarg 'rd.break=initqueue' -d 'rdbreak=initqueue' && emergency_shell -n initqueue "Break before initqueue"

RDRETRY=$(getarg rd.retry -d 'rd_retry=')
RDRETRY=${RDRETRY:-180}
RDRETRY=$(($RDRETRY*2))
export RDRETRY

main_loop=0
export main_loop

while :; do

    check_finished && break

    udevadm settle --exit-if-exists=$hookdir/initqueue/work

    check_finished && break

    if [ -f $hookdir/initqueue/work ]; then
        rm $hookdir/initqueue/work
    fi

    for job in $hookdir/initqueue/*.sh; do
        [ -e "$job" ] || break
        job=$job . $job
        check_finished && break 2
    done

    udevadm settle --timeout=0 >/dev/null 2>&1 || continue

    for job in $hookdir/initqueue/settled/*.sh; do
        [ -e "$job" ] || break
        job=$job . $job
        check_finished && break 2
    done

    udevadm settle --timeout=0 >/dev/null 2>&1 || continue

    # no more udev jobs and queues empty.
    sleep 0.5

    if [ $main_loop -gt $((2*$RDRETRY/3)) ]; then
        for job in $hookdir/initqueue/timeout/*.sh; do
            [ -e "$job" ] || break
            job=$job . $job
            udevadm settle --timeout=0 >/dev/null 2>&1 || main_loop=0
            [ -f $hookdir/initqueue/work ] && main_loop=0
        done
    fi

    main_loop=$(($main_loop+1))
    [ $main_loop -gt $RDRETRY ] && emergency_shell "Could not boot."
done

unset job
unset queuetriggered
unset main_loop
unset RDRETRY

export -p > /dracut-state.sh

service="${0##*/}"
cp "/etc/systemd/system/${service%.sh}.service" /run/systemd/system/
exit 0
