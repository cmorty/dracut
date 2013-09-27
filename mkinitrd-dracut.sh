#!/bin/bash --norc
kver=$(uname -r)

boot_dir="/boot"
quiet=0

error() { echo "$@" >&2; }

usage () {
    [[ $1 = '-n' ]] && cmd=echo || cmd=error

    $cmd "usage: ${0##*/} [--version] [--help] [-v] [-f] [--preload <module>]"
    $cmd "       [--image-version] [--with=<module>]"
    $cmd "       [--nocompress]"
    $cmd "       <initrd-image> <kernel-version>"
    $cmd ""
    $cmd "       (ex: ${0##*/} /boot/initramfs-$kver.img $kver)"

    [[ $1 = '-n' ]] && exit 0
    exit 1
}

# Little helper function for reading args from the commandline.
# it automatically handles -a b and -a=b variants, and returns 1 if
# we need to shift $3.
read_arg() {
    # $1 = arg name
    # $2 = arg value
    # $3 = arg parameter
    param="$1"
    local rematch='^[^=]*=(.*)$' result
    if [[ $2 =~ $rematch ]]; then
        read "$param" <<< "${BASH_REMATCH[1]}"
    else
	for ((i=3; $i <= $#; i++)); do
            # Only read next arg if it not an arg itself.
            if [[ ${@:$i:1} = -* ]];then
		break
            fi
            result="$result ${@:$i:1}"
            # There is no way to shift our callers args, so
            # return "no of args" to indicate they should do it instead.
	done
	read "$1" <<< "$result"
        return $(($i - 3))
    fi
}

while (($# > 0)); do
    case ${1%%=*} in
        --with-usb) read_arg usbmodule "$@" || shift $?
            basicmodules="$basicmodules ${usbmodule:-usb-storage}"
            unset usbmodule;;
        --with-avail) read_arg modname "$@" || shift $?
            basicmodules="$basicmodules $modname";;
        --with) read_arg modname "$@" || shift $?
            basicmodules="$basicmodules $modname";;
        --version)
            echo "mkinitrd: dracut compatibility wrapper"
            exit 0;;
        -v|--verbose) dracut_args="${dracut_args} -v";;
        -f|--force) dracut_args="${dracut_args} -f";;
        --preload) read_arg modname "$@" || shift $?
            basicmodules="$basicmodules $modname";;
        --image-version) img_vers=yes;;
        --rootfs) read_arg rootfs "$@" || shift $?
            dracut_args="${dracut_args} --filesystems $rootfs";;
        --nocompress) dracut_args="$dracut_args --no-compress";;
        --help) usage -n;;
        --builtin) ;;
        --without*) ;;
        --without-usb) ;;
        --fstab*) ;;
        --ifneeded) ;;
        --omit-scsi-modules) ;;
        --omit-ide-modules) ;;
        --omit-raid-modules) ;;
        --omit-lvm-modules) ;;
        --omit-dmraid) ;;
        --allow-missing) ;;
        --net-dev*) ;;
        --noresume) ;;
        --rootdev*) ;;
        --thawdev*) ;;
        --rootopts*) ;;
        --root*) ;;
        --loopdev*) ;;
        --loopfs*) ;;
        --loopopts*) ;;
        --looppath*) ;;
        --dsdt*) ;;
        --bootchart) ;;
	--quiet|-q) quiet=1;;
	-b) read_arg boot_dir "$@" || shift $?
	    if [ ! -d $boot_dir ];then
		error "Boot directory $boot_dir does not exist"
		exit 1
	    fi
	    ;;
	-k) # Would be nice to get a list of images here
	    read_arg kernel_images "$@" || shift $?
	    for kernel_image in $kernel_images;do
		kernels="$kernels ${kernel_image#*-}"
	    done
	    ;;
	-i) read_arg initrd_images "$@" || shift $?
	    for initrd_image in $initrd_images;do
		targets="$targets $boot_dir/$initrd_image"
	    done
	    ;;
        *)  if [[ ! $targets ]]; then
            targets=$1
            elif [[ ! $kernels ]]; then
            kernels=$1
            else
            usage
            fi;;
    esac
    shift
done

[[ $targets && $kernels ]] || usage

# We can have several targets/kernels, transform the list to an array
targets=( $targets )
[[ $kernels ]] && kernels=( $kernels )

echo "Creating: target|kernel|dracut args|basicmodules "
for ((i=0 ; $i<${#targets[@]} ; i++)); do

    if [[ $img_vers ]];then
	target="${targets[$i]}-${kernels[$i]}"
    else
	target="${targets[$i]}"
    fi
    kernel="${kernels[$i]}"

    # Duplicate code: No way found how to redirect output based on $quiet
    if [[ $quiet == 1 ]];then
	echo "$target|$kernel|$dracut_args|$basicmodules"
	if [[ $basicmodules ]]; then
            dracut $dracut_args --add-drivers "$basicmodules" "$target" \
		"$kernel" &>/dev/null
	else
            dracut $dracut_args "$target" "$kernel" &>/dev/null
	fi
    else
	if [[ $basicmodules ]]; then
            dracut $dracut_args --add-drivers "$basicmodules" "$target" \
		"$kernel"
	else
            dracut $dracut_args "$target" "$kernel"
	fi
    fi
done
