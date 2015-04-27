#!/bin/sh

. /lib/dracut-lib.sh

if [ -n "$root" -a -z "${root%%block:*}" ]; then
    mount -t ${fstype:-auto} -o "$rflags" "${root#block:}" "$NEWROOT" \
        && ROOTFS_MOUNTED=yes

    if ! getarg rd_NO_FSTAB \
      && ! getarg rootflags \
      && [ -f "$NEWROOT/etc/fstab" ] \
      && ! [ -L "$NEWROOT/etc/fstab" ]; then
        # if $NEWROOT/etc/fstab contains special mount options for 
        # the root filesystem,
        # remount it with the proper options
	rootfs="auto"
	rootopts="defaults"
	while read dev mp fs opts rest; do 
            if [ "$mp" = "/" ]; then
		rootfs=$fs
		rootopts=$opts
		break
            fi
	done < "$NEWROOT/etc/fstab"

	if [ "$rootopts" != "defaults" ]; then
            umount $NEWROOT
            info "Remounting ${root#block:} with -o $rflags,$rootopts"
            mount -t "$rootfs" -o "$rflags","$rootopts" \
                "${root#block:}" "$NEWROOT" 2>&1 | vinfo
	fi
    fi
fi
