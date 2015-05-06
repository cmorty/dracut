#!/bin/sh

. /lib/dracut-lib.sh

aufs=$(getargs aufs)

if [ -z "$aufs" ] ; then
    return
fi

modprobe aufs

# a little bit tuning
mount -o remount,nolock,noatime $NEWROOT

# Move root
# NB: --move does not always work. Google >mount move "wrong fs"< for
#     details
mkdir -p /live/image
mount --bind $NEWROOT /live/image
umount $NEWROOT

# Create tmpfs
mkdir /cow
mount -n -t tmpfs -o mode=0755 tmpfs /cow

# Merge both to new Filesystem
mount -t aufs -o noatime,noxino,dirs=/cow=rw:/live/image=rr aufs $NEWROOT

# Let filesystems survive pivot
mkdir -p $NEWROOT/live/cow
mount --bind /cow $NEWROOT/live/cow
umount /cow 
mkdir -p $NEWROOT/live/image
mount --bind /live/image $NEWROOT/live/image
umount /live/image
