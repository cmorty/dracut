#!/bin/sh
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh
# live images are specified with
# root=live:backingdev

isofile=$(getarg iso-scan/filename)

if [ -n "$isofile" ]; then
    {
        printf 'KERNEL=="loop0", RUN+="/sbin/initqueue --settled --onetime --unique /sbin/iso-scan %s"\n' \
            "'${isofile}'"
    } >> /etc/udev/rules.d/99-isofile-mount.rules
fi
