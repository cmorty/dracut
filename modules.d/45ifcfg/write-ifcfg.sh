#!/bin/sh
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

# NFS root might have reached here before /tmp/net.ifaces was written
udevadm settle --timeout=30
# Don't write anything if we don't know our bootdev
[ -f /tmp/net.ifaces ] || return 1

read IFACES < /tmp/net.ifaces

if [ -e /tmp/bond.info ]; then
    . /tmp/bond.info
fi

if [ -e /tmp/bridge.info ]; then
    . /tmp/bridge.info
fi

mkdir -m 0755 -p /tmp/ifcfg/
mkdir -m 0755 -p /tmp/ifcfg-leases/

get_config_line_by_subchannel()
{
    local CHANNEL
    local line

    CHANNELS="$1"
    while read line; do
        if strstr "$line" "$CHANNELS"; then
            echo $line
            return 0
        fi
    done < /etc/ccw.conf
    return 1
}

print_s390() {
    local _netif
    local SUBCHANNELS
    local OPTIONS
    local NETTYPE
    local CONFIG_LINE
    local i
    local channel
    local OLD_IFS

    _netif="$1"
    # if we find ccw channel, then use those, instead of
    # of the MAC
    SUBCHANNELS=$({
        for i in /sys/class/net/$_netif/device/cdev[0-9]*; do
            [ -e $i ] || continue
            channel=$(readlink -f $i)
            echo -n "${channel##*/},"
        done
    })
    [ -n "$SUBCHANNELS" ] || return 1

    SUBCHANNELS=${SUBCHANNELS%,}
    echo "SUBCHANNELS=\"${SUBCHANNELS}\""
    CONFIG_LINE=$(get_config_line_by_subchannel $SUBCHANNELS)

    [ $? -ne 0 -o -z "$CONFIG_LINE" ] && return

    OLD_IFS=$IFS
    IFS=","
    set -- $CONFIG_LINE
    IFS=$OLD_IFS
    NETTYPE=$1
    shift
    SUBCHANNELS="$1"
    OPTIONS=""
    shift
    while [ $# -gt 0 ]; do
        case $1 in
            *=*) OPTIONS="$OPTIONS $1";;
        esac
        shift
    done
    OPTIONS=${OPTIONS## }
    echo "NETTYPE=\"${NETTYPE}\""
    echo "OPTIONS=\"${OPTIONS}\""
}


for netif in $IFACES ; do
    # bridge?
    unset bridge
    unset bond
    uuid=$(cat /proc/sys/kernel/random/uuid)
    if [ "$netif" = "$bridgename" ]; then
        bridge=yes
    elif [ "$netif" = "$bondname" ]; then
    # $netif can't be bridge and bond at the same time
        bond=yes
    fi
    cat /sys/class/net/$netif/address > /tmp/net.$netif.hwaddr
    {
        echo "# Generated by dracut initrd"
        echo "DEVICE=$netif"
        echo "ONBOOT=yes"
        echo "NETBOOT=yes"
        echo "UUID=$uuid"
        [ -n "$mtu" ] && echo "MTU=$mtu"
        if [ -f /tmp/net.$netif.lease ]; then
            strstr "$ip" '*:*:*' &&
            echo "DHCPV6C=yes"
            echo "BOOTPROTO=dhcp"
            cp /tmp/net.$netif.lease /tmp/ifcfg-leases/dhclient-$uuid-$netif.lease
        else
            echo "BOOTPROTO=none"
        # If we've booted with static ip= lines, the override file is there
            [ -e /tmp/net.$netif.override ] && . /tmp/net.$netif.override
            echo "IPADDR=$ip"
            if strstr "$mask" "."; then
                echo "NETMASK=$mask"
            else
                echo "PREFIX=$mask"
            fi
            [ -n "$gw" ] && echo "GATEWAY=$gw"
        fi
    } > /tmp/ifcfg/ifcfg-$netif

    # bridge needs different things written to ifcfg
    if [ -z "$bridge" ] && [ -z "$bond" ]; then
        # standard interface
        {
            if [ -n "$macaddr" ]; then
                echo "MACADDR=$macaddr"
            else
                echo "HWADDR=\"$(cat /sys/class/net/$netif/address)\""
            fi
            print_s390 $netif
            echo "TYPE=Ethernet"
            echo "NAME=\"Boot Disk\""
            [ -n "$mtu" ] && echo "MTU=$mtu"
        } >> /tmp/ifcfg/ifcfg-$netif
    fi

    if [ -n "$bond" ] ; then
        # bond interface
        {
            # This variable is an indicator of a bond interface for initscripts
            echo "BONDING_OPTS=\"$bondoptions\""
            echo "NAME=\"Boot Disk\""
        } >> /tmp/ifcfg/ifcfg-$netif

        for slave in $bondslaves ; do
            # Set ONBOOT=no to prevent initscripts from trying to setup already bonded physical interface
            # write separate ifcfg file for the raw eth interface
            {
                echo "# Generated by dracut initrd"
                echo "DEVICE=$slave"
                echo "TYPE=Ethernet"
                echo "ONBOOT=no"
                echo "NETBOOT=yes"
                echo "HWADDR=$(cat /sys/class/net/$slave/address)"
                echo "SLAVE=yes"
                echo "MASTER=$netif"
                echo "NAME=$slave"
            } >> /tmp/ifcfg/ifcfg-$slave
        done
    fi

    if [ -n "$bridge" ] ; then
        # bridge
        {
            echo "TYPE=Bridge"
            echo "NAME=\"Boot Disk\""
        } >> /tmp/ifcfg/ifcfg-$netif
        if [ "$ethname" = "$bondname" ] ; then
            {
                # Set ONBOOT=no to prevent initscripts from trying to setup already bridged bond interface
                echo "# Generated by dracut initrd"
                echo "DEVICE=$bondname"
                echo "ONBOOT=no"
                echo "NETBOOT=yes"
                # This variable is an indicator of a bond interface for initscripts
                echo "BONDING_OPTS=\"$bondoptions\""
                echo "BRIDGE=$netif"
                echo "NAME=\"$bondname\""
            } >> /tmp/ifcfg/ifcfg-$bondname
            for slave in $bondslaves ; do
                # write separate ifcfg file for the raw eth interface
                # Set ONBOOT=no to prevent initscripts from trying to setup already bridged physical interface
                {
                    echo "# Generated by dracut initrd"
                    echo "DEVICE=$slave"
                    echo "TYPE=Ethernet"
                    echo "ONBOOT=no"
                    echo "NETBOOT=yes"
                    echo "HWADDR=$(cat /sys/class/net/$slave/address)"
                    echo "SLAVE=yes"
                    echo "MASTER=$bondname"
                    echo "NAME=$slave"
                } >> /tmp/ifcfg/ifcfg-$slave
            done
        else
            # write separate ifcfg file for the raw eth interface
            {
                echo "# Generated by dracut initrd"
                echo "DEVICE=$ethname"
                echo "TYPE=Ethernet"
                echo "ONBOOT=no"
                echo "NETBOOT=yes"
                echo "HWADDR=$(cat /sys/class/net/$ethname/address)"
                echo "BRIDGE=$netif"
                echo "NAME=$ethname"
            } >> /tmp/ifcfg/ifcfg-$ethname
        fi
    fi
    i=1
    for ns in $(getargs nameserver); do
        echo "DNS${i}=${ns}" >> /tmp/ifcfg/ifcfg-$netif
        i=$((i+1))
    done
done

# Pass network opts
mkdir -m 0755 -p /run/initramfs/state/etc/sysconfig/network-scripts
mkdir -m 0755 -p /run/initramfs/state/var/lib/dhclient
echo "files /etc/sysconfig/network-scripts" >> /run/initramfs/rwtab
echo "files /var/lib/dhclient" >> /run/initramfs/rwtab
{
    cp /tmp/net.* /run/initramfs/
    cp /tmp/net.$netif.resolv.conf /run/initramfs/state/etc/resolv.conf
    copytree /tmp/ifcfg /run/initramfs/state/etc/sysconfig/network-scripts
    cp /tmp/ifcfg-leases/* /run/initramfs/state/var/lib/dhclient
} > /dev/null 2>&1
