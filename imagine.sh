#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause-FreeBSD
#
# Copyright 2022, 2023 Michael Dexter
# All rights reserved
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted providing that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
# IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# Version v.0.3


# CAVEATS

# This intimately follows the FreeBSD Release Engineering mirror layout.
# If the layout changes, this will break.

# FreeBSD RE 'makefs -t zfs' VM-IMAGES use the pool name 'zroot', with is the
# default suggestion in the installer - realistically import by id and rename.

# FreeBSD 15.0-CURRENT VM-IMAGES are now 6GB in size.

# The generated bhyve boot scripts require the bhyve-firmware UEFI package.

# The canonical /media temporary mount point is hard-coded.

# The canonical /usr/src directory is hard-coded when using -r obj or a path.

# 'fetch -i' only checks date stamps, allow for false matches on interrupted downlods.

# Running imagine.sh in the work directory will cause existing release versions to be
# misinterpreted as image paths to be copied


# EXAMPLES

# To fetch a 15.0-CURRENT raw boot image to ~/imagine-work/boot.raw
#
# sh imagine.sh -r 15.0-CURRENT

# To fetch a 15.0-CURRENT raw boot image and write to /dev/da1
#
# sh imagine.sh -r 15.0-CURRENT -t /dev/da1
 
# To copy a "make release" VM image from the canonical object directory:
#	/usr/obj/usr/src/amd64.amd64/release/vm.raw to ~/imagine-work/boot.raw
#
# sh imagine.sh -r obj

# To copy a boot image from a custom path and name to a custom path and name:
#
# sh imagine.sh -r /tmp/myvm.img -t /tmp/myvmcopy.raw

# Add '-w /tmp/mydir' to override '~/imagine-work' with an existing directory
# Add '-z' to fetch the root-on-ZFS image
# Add '-b' to generate a simple bhyve, xen, or QEMU boot scripts depending on the architecture
# Add '-g 10' to grow boot image to 10GB

# The local and fetched source boot images will be always preserved for re-use

# To generate a 10GB RISC-V system with root-on-ZFS and a QEMU boot script:
#
# sh imagine.sh -a riscv -r 14.0-BETA4 -z -g 10 -b
#
# Add '-v' to generate a VMDK that is QEMU compatible, because you can
#
# Do increase the RAM with root-on-ZFS systems but it WILL support the 1G default

f_usage() {
	echo ; echo "USAGE:"
	echo "-w <working directory> (Default: /root/imagine-work)"
	echo "-a <architecture> [ amd64 arm64 i386 riscv ] (Default: amd64)"
	echo "-r [ obj | /path/to/image | <version> ] (Release - Required)"
	echo "obj = /usr/obj/usr/src/<target>.<target_arch>/release/vm.raw"
	echo "/path/to/image for an existing image"
	echo "<version> i.e. 13.2-RELEASE 14.0-ALPHAn|BETAn|RCn 15.0-CURRENT"
	echo "-o (Offline mode to re-use fetched releases and src.txz)"
	echo "-t <target> [ img | /dev/device | /path/myimg ] (Default: img)"
	echo "-f (FORCE imaging to a device without asking)"
	echo "-g <gigabytes> (grow image to gigabytes i.e. 10)"
	echo "-s (Include src.txz or /usr/src as appropriate)"
	echo "-m (Mount image and keep mounted for further configuration)"
	echo "-v (Generate VMDK image wrapper)"
	echo "-b (Genereate boot scripts)"
	echo
	exit 0
}


# INTERNAL VARIABLES AND DEFAULTS

#work_dir="/root/imagine-work"	# Default
#work_dir="~/imagine-work"	# Default
work_dir=~/imagine-work		# Default - fails if quoted
arch_input="amd64"		# Default
hw_platform="amd64"
cpu_arch="amd64"
image_arch="amd64"
release_input=""
offline_mode=0
release_type=""
release_name=""
release_image_file=""
release_branch=""
release_image_xz=""
rootfs=""
rootpart=""
zfs_string=""
target_input="img"		# Default
target_type=""
target_path=""
target_prefix=""
force=0
grow_required=0
grow_size=""
include_src=0
must_mount=0
keep_mounted=0
vmdk=0
boot_scripts=0
vm_device=""
vm_name="vm0"			# Default
md_id=42			# Default


# USER INPUT AND VARIABLE OVERRIDES

while getopts w:a:r:zt:ofg:smvb opts ; do
	case $opts in
	w)
		work_dir="$OPTARG"
		;;
	a)
		case "$OPTARG" in
			amd64|arm64|i386|riscv)
				arch_input="$OPTARG"
			;;
			*)
				echo "Invalid architecture"
				f_usage
			;;
		esac

		case "$arch_input" in
			amd64)
				hw_platform="amd64"
				cpu_arch="amd64"
				image_arch="amd64"
			;;
			arm64)
				hw_platform="arm64"
				cpu_arch="aarch64"
				image_arch="arm64-aarch64"
			;;
			i386)
				hw_platform="i386"
				cpu_arch="i386"
				image_arch="i386"
			;;
			riscv)
				hw_platform="riscv"
				cpu_arch="riscv64"
				image_arch="riscv-riscv64"
			;;

		esac
		;;
	r) 
		[ "$OPTARG" ] || f_usage
		release_input="$OPTARG"
		;;
	o)
		offline_mode=1
		;;
	z)
		zfs_string="-zfs"
		;;
	t)
		[ "$OPTARG" ] || f_usage
		target_input="$OPTARG"
		;;
	f)
		force=1
		;;
	g)
		grow_size="$OPTARG"
		# Implied numeric validation
		[ "$grow_size" -gt 7 ] || \
			{ echo "-g must be a number larger than 7" ; exit 1 ; }
		grow_required=1
		;;
	s)
		include_src=1
		grow_required=1
		must_mount=1
		;;
	m)
		must_mount=1
		keep_mounted=1
		;;
	v)
		vmdk=1
		;;
	b)
		boot_scripts=1
		;;
	*)
		f_usage
		;;
	esac
done


[ -n "$release_input" ] || { echo "-r Release required" ; f_usage ; exit 1 ; }


# HEAVY LIFTING FLAG -r RELEASE

# Shorten these paths
# Kludgy 13.x and 14.x makefs -t zfs workarounds

if [ "$release_input" = "obj" ] ; then
	release_type="file"
if [ -f "/usr/obj/usr/src/${hw_platform}.${cpu_arch}/release/vm.raw" ] ; then
release_image_file="/usr/obj/usr/src/${hw_platform}.${cpu_arch}/release/vm.raw"
elif [ -n "$zfs_string" ] ; then
release_image_file="/usr/obj/usr/src/${hw_platform}.${cpu_arch}/release/vm.zfs.raw"
else
release_image_file="/usr/obj/usr/src/${hw_platform}.${cpu_arch}/release/vm.ufs.raw"
fi
		[ -r "$release_image_file" ] || \
			{ echo "$release_image_file not found" ; exit 1 ; }

elif [ -r "$release_input" ] ; then # path to an image
	release_type="file"
	# Consider the vmrun.sh "file" test for boot blocks
	release_image_file="$release_input"
	[ -r "$release_image_file" ] || \
		{ echo "$release_image_file not found" ; exit 1 ; }
	[ -d "$release_image_file" ] || \
		{ echo "$release_image_file is a directory" ; exit 1 ; }

	[ "$include_src" = 1 ] && \
		{ echo "-s src not available with a custom image" ; exit 1 ; }

else # release version i.e. 15.0-CURRENT
	release_type="ftp"
	echo "$release_input" | grep -q "-" || \
		{ echo "Invalid release" ; exit 1 ; }
	echo "$release_input" | grep -q "FreeBSD" && \
		{ echo "Invalid release" ; exit 1 ; }
	release_name="$release_input"
	release_version=$( echo "$release_input" | cut -d "-" -f 1 )
	# Further validate the numeric version?
	release_build=$( echo "$release_input" | cut -d "-" -f 2 )
	case "$release_build" in
		CURRENT|STABLE)
			release_branch="snapshot"
		;;
		*)
			release_branch="release"
			# This is a false assumption for ALPHA builds
		;;
	esac

	release_image_url="https://download.freebsd.org/${release_branch}s/VM-IMAGES/${release_name}/${cpu_arch}/Latest/FreeBSD-${release_name}-${image_arch}${zfs_string}.raw.xz"
	release_image_xz="${work_dir}/${release_name}/FreeBSD-${release_name}-${image_arch}${zfs_string}.raw.xz"

# Create the work directory if missing
	[ -d "${work_dir}/${release_name}" ] || \
		mkdir -p "${work_dir}/${release_name}"
	[ -d "${work_dir}/${release_name}" ] || \
		{ echo "mkdir ${work_dir}/${release_name} failed" ; exit 1 ; }

	# Needed for fetch to save the upstream file name
	cd "${work_dir}/${release_name}"

	# fetch is not idempotent - check if exists before fetch -i
	if [ -r $release_image_xz ] ; then
		if [ "$offline_mode" = 0 ] ; then
		fetch -a -i "$release_image_xz" "$release_image_url" || \
			{ echo "$release_image_url fetch failed" ; exit 1 ; }
		fi
	else
	fetch -a "$release_image_url" || \
		{ echo "$release_image_url fetch failed" ; exit 1 ; }
	fi

release_dist_url="https://download.freebsd.org/${release_branch}s/$image_arch/$release_name"
src_url="https://download.freebsd.org/${release_branch}s/${hw_platform}/${cpu_arch}/${release_name}/src.txz"

	if [ "$include_src" = 1 ] ; then
		if [ -r	"src.txz" ] ; then
			if [ "$offline_mode" = 0 ] ; then
				fetch -a -i src.txz "$src_url" || \
				{ echo "$src_url fetch failed" ; exit 1 ; }
			fi
	else
			fetch -a "$src_url" || \
				{ echo "$src_url fetch failed" ; exit 1 ; }
		fi
	fi
	# Better test for invalid input?
fi # End -r RELEASE HEAVY LIFTING


# HEAVY LIFTING FLAG -t TARGET

target_prefix=$( printf %.1s "$target_input" )

if [ "$target_input" = "img" ] ; then
	target_type="img"
	target_path="${work_dir}/boot.raw"

	[ -d "$work_dir" ] || mkdir -p "$work_dir"
	[ -d "$work_dir" ] || { echo "mkdir -p $work_dir failed" ; exit 1 ; }

elif [ "$target_prefix" = "/" ] ; then
	if [ "$( echo "$target_input" | cut -d "/" -f 2 )" = "dev" ] ; then

		target_type="dev"

		[ "$( id -u )" = 0 ] || { echo "Must be root for -t dev" ; exit 1 ; } 

		target_device="$target_input"
		grow_required=1

	else # image path
		[ -d $( dirname "$target_input" ) ] || \
			{ echo "-t directory path does not exist" ; exit 1 ; }
		[ -w $( dirname "$target_input" ) ] || \
			{ echo "-t directory path is not writable" ; exit 1 ; }
		target_type="path"
		target_path="$target_input"
	fi
else
	f_usage
fi # End -t TARGET HEAVY LIFTING


if [ "$target_type" = "img" -o "$target_type" = "path" ] ; then
	if [ "$grow_required" = 1 ] ; then
		[ -n "$grow_size" ] || { echo "-g size is required" ; exit 1 ; }
	fi
fi

case "$target_type" in
	img|path)
		[ -f "$target_path" ] && rm "$target_path"

		if [ "$release_type" = "ftp" ] ; then
			# -c implies --keep but just in case
			echo ; echo "Extracting $release_image_xz"
			unxz --verbose --keep -c "$release_image_xz" \
				> "$target_path" || \
				{ echo "unxz failed" ; exit 1 ; }
			echo ; echo "Output boot image is $target_path"
		else # file
			cp "$release_image_file" "$target_path"
			# release_image_file and target_path are both full-path
			echo ; echo "Output boot image is $target_path"
		fi

		mdconfig -lv | grep "$target_path" && \
			{ echo "Warning: $target_path is attached with mdconfig" ; exit 1 ; }
		;;
	dev)
		if [ -n "$release_image_file" ] ; then

			if [ "$force" = 0 ] ; then
				echo "WARNING! Writing to $target_device!"
				diskinfo -v $target_device
				echo -n "Continue? (y/n): " ; read warning
				[ "$warning" = "y" ] || exit 1
			fi

		\time -h dd if="$release_image_file" of="$target_device" \
			bs=1m status=progress || \
				{ echo "dd failed" ; exit 1 ; }

		elif [ -n "$release_image_xz" ] ; then

			if [ "$force" = 0 ] ; then
				echo "WARNING! Writing to $target_device!"
				diskinfo -v $target_device
				echo -n "Continue? (y/n): " ; read warning
				[ "$warning" = "y" ] || exit 1
			fi

			\time -h cat "$release_image_xz" | 
				xz -d -k | \
				dd of="$target_device" \
				bs=1m status=progress \
				iflag=fullblock || \
					{ echo "dd failed" ; exit 1 ; }
		else
			echo "Something went wrong"
			exit 1
		fi
		gpart recover $target_device || \
			{ echo gpart recover failed ; exit 1 ; }
		gpart show $target_device
		;;
esac


if [ "$grow_required" = 1 ] ; then

	[ "$( id -u )" = 0 ] || { echo "Must be root for image growth" ; exit 1 ; } 

	case "$target_type" in
		img|path)
			echo ; echo "Truncating $target_path"
			truncate -s ${grow_size}G "$target_path" || \
				{ echo truncate failed ; exit 1 ; }

			mdconfig -lv | grep -q "md$md_id" && \
				{ echo "md$md_id in use" ; exit 1 ; }

			echo ; echo "Attaching $target_path"
			mdconfig -a -f "$target_path" -u $md_id || \
				{ echo mdconfig failed ; exit 1 ; }
			target_device="/dev/md$md_id"

			mdconfig -lv

			gpart recover $target_device || \
				{ echo gpart recover failed ; exit 1 ; }
			;;
	esac

# /dev/${target_device}pN is now dev/img agnostic at this point

	if [ "$( gpart show $target_device | grep freebsd-zfs )" ] ; then
		rootfs="freebsd-zfs"
	else
		rootfs="freebsd-ufs"
	fi

	rootpart="$( gpart show $target_device | grep $rootfs | awk '{print $3}' )"

	echo ; echo "Resizing ${target_device}p${rootpart}"
	gpart resize -i "$rootpart" "$target_device"
	gpart show "$target_device"

mount | grep "on /media" && { echo "/media mount point in use" ; exit 1 ; }

	if [ "$rootfs" = "freebsd-ufs" ] ; then
		echo ; echo Growing ${target_device}p${rootpart}
		growfs -y "${target_device}p${rootpart}" || \
			{ echo "growfs failed" ; exit 1 ; }

		if [ "$must_mount" = 1 ] ; then
			mount | grep "on /media" && \
				{ echo "/media mount point in use" ; exit 1 ; }
			mount ${target_device}p${rootpart} /media || \
				{ echo mount failed ; exit 1 ; }
			df -h | grep media
		fi
	else # freebsd-zfs
		zpool list
		zpool get name zroot > /dev/null 2>&1 && \
			{ echo zpool zroot in use and will conflict ; exit 1 ; }
			# -f does not appear to be needed

		zpool import

		# Rename the pool without heavy regex?

		echo ; echo Importing zpool for expansion
		zpool import -o autoexpand=on -N zroot || \
			{ echo "zroot failed to import" ; exit 1 ; }

		echo ; echo Expanding the zpool root partition

		if [ "$target_type" = "img" ] ; then
			zpool online -e zroot ${target_device}p${rootpart}
		elif [ "$target" = "dev" ] ; then
			zpool online -e zroot /dev/gpt/rootfs
		fi

		zpool list
		zpool status zroot

		echo ; echo "Exporting the zpool for re-import"

		zpool export zroot

		if [ "$must_mount" = 1 ] ; then
			mount | grep "on /media" && \
				{ echo "/media mount point in use" ; exit 1 ; }
			sleep 3
			echo ; echo Importing zpool
			zpool import -R /media zroot || \
				{ echo "zroot failed to import" ; exit 1 ; }
		fi
	fi
fi


# OPTIONAL SOURCES

if [ "$include_src" = 1 ] ; then
	if [ "$release_type" = "ftp" ] ; then

	# Add dpv(1) progress?
	echo "Extracting ${work_dir}/${release_name}/src.txz"
	cat "${work_dir}/${release_name}/src.txz" | tar -xpf - -C /media/ || \
		{ echo "src.txz extraction failed" ; exit 1 ; }
	else
		echo ; echo "Copying /usr/src"
		tar cf - /usr/src | tar xpf - -C /media || \
			{ echo "/usr/src failed to copy" ; exit 1 ; }
			df -h | grep media
	fi
	[ -f "/media/usr/src/Makefile" ] || { echo "/usr/src failed to copy" ; exit 1 ; }
fi

# OPTIONAL VMDK WRAPPER

if [ "$vmdk" = 1 ] ; then
	vmdk_image="$target_path"
	vmdk_image_base="${vmdk_image%.raw}"

	# Assuming blocksize of 512
	size_bytes="$( stat -f %z "$vmdk_image" )"
	RW=$(( "$size_bytes" / 512 ))
	cylinders=$(( "$RW" / 255 / 63 ))

	cat << EOF > "${vmdk_image_base}.vmdk"
# Disk DescriptorFile
version=1
CID=12345678
parentCID=ffffffff
createType="vmfs"

RW $(( "$size_bytes" / 512 )) VMFS "${vmdk_image_base}-flat.vmdk"

# The Disk Data Base 
#DDB

ddb.adapterType = "lsilogic"
ddb.encoding = "UTF-8"
ddb.geometry.cylinders = "$cylinders"
ddb.geometry.heads = "255"
ddb.geometry.sectors = "63"
ddb.longContentID = "0123456789abcdefghijklmnopqrstuv"
ddb.toolsInstallType = "0"
ddb.toolsVersion = "2147483647"
ddb.virtualHWVersion = "4"
EOF

	echo ; echo Renaming "$vmdk_image" to "${vmdk_image_base}-flat.vmdk"
	mv "$vmdk_image" "${vmdk_image_base}-flat.vmdk"
fi


# OPTIONAL VM BOOT SCRIPT SUPPORT

if [ "$boot_scripts" = 1 ] ; then

	[ -d "$work_dir" ] || mkdir -p "$work_dir"
	[ -d "$work_dir" ] || { echo "mkdir -p $work_dir failed" ; exit 1 ; }

	if [ -n "$target_path" ] ; then
		if [ "$vmdk" = 1 ] ; then
			vm_device="${vmdk_image_base}-flat.vmdk"
		else
			vm_device="$target_path"
		fi
	elif [ -n "$target_device" ] ; then
		vm_device="$target_device"
	else
		echo "Something went wrong"
		exit 1
	fi

	case "$arch_input" in
		amd64|i386)
			cat << EOF > "${work_dir}/boot-bhyve.sh"
#!/bin/sh
[ -e /dev/vmm/$vm_name ] && { bhyvectl --destroy --vm=$vm_name ; sleep 1 ; }
[ -f /usr/local/share/uefi-firmware/BHYVE_UEFI.fd ] || \\
	{ echo \"BHYVE_UEFI.fd missing\" ; exit 1 ; }
kldstat -q -m vmm || kldload vmm
sleep 1
#bhyveload -d $vm_device -m 1024 $vm_name
#sleep 1
bhyve -c 1 -m 1024 -H -A \\
	-l com1,stdio \\
	-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd \\
	-s 0,hostbridge \\
	-s 2,virtio-blk,$vm_device \\
	-s 31,lpc \\
	$vm_name

# Devices to consider:

# -s 30:0,fbuf,tcp=0.0.0.0:5900,w=1024,h=768,wait \\
# -s 3,virtio-net,tap0 \\

sleep 2
bhyvectl --destroy --vm=$vm_name
EOF
			echo ; echo Note: ${work_dir}/boot-bhyve.sh

			cat << HERE > $work_dir/xen.cfg
type = "hvm"
memory = 1024
vcpus = 1
name = "$vm_name"
disk = [ '$vm_device,raw,hda,w' ]
boot = "c"
serial = 'pty'
on_poweroff = 'destroy'
on_reboot = 'restart'
on_crash = 'restart'
#vif = [ 'bridge=bridge0' ]
HERE

			echo ; echo "Note: $work_dir/xen.cfg"

	echo "xl list | grep $vm_name && xl destroy $vm_name" \
		> $work_dir/boot-xen.sh
	echo "xl create -c $work_dir/xen.cfg" \
		>> $work_dir/boot-xen.sh
	echo ; echo Note: $work_dir/boot-xen.sh

	echo "xl shutdown $vm_name ; xl destroy $vm_name ; xl list" > \
		$work_dir/destroy-xen.sh
			echo ; echo Note: $work_dir/destroy-xen.sh
			;;
		arm64)
			cat << HERE > $work_dir/boot-qemu-arm64.sh
#!/bin/sh
[ -f /usr/local/share/u-boot/u-boot-qemu-arm64/u-boot.bin ] || \\
	{ echo \"u-boot.bin missing\" ; exit 1 ; }
# pkg install qemu u-boot-qemu-arm64
/usr/local/bin/qemu-system-aarch64 -m 1024 \
-cpu cortex-a57 -M virt \
-drive file=${vm_device},format=raw \
-bios /usr/local/share/u-boot/u-boot-qemu-arm64/u-boot.bin \
-nographic
HERE
			echo ; echo Note: $work_dir/boot-qemu-arm64.sh
			;;
		riscv)
			cat << HERE > $work_dir/boot-qemu-riscv.sh
#!/bin/sh
#pkg install qemu opensbi u-boot-qemu-riscv64
[ -f /usr/local/share/opensbi/lp64/generic/firmware/fw_jump.elf ] || \\
        { echo "Missing opensbi package" ; exit 1 ; }

/usr/local/bin/qemu-system-riscv64 -machine virt -m 1024 -nographic \\
-bios /usr/local/share/opensbi/lp64/generic/firmware/fw_jump.elf \\
-kernel /usr/local/share/u-boot/u-boot-qemu-riscv64/u-boot.bin \\
-drive file=${vm_device},format=raw,id=hd0 \\
-device virtio-blk-device,drive=hd0

# Devices to consider:

-netdev user,id=net0 \\
-device virtio-net-device,netdev=net0
HERE
			echo ; echo Note: $work_dir/boot-qemu-riscv.sh
			;;
	esac
fi

if [ "$keep_mounted" = 0 -a "$must_mount" = 1 ] ; then
	# umount/clean up if not requested to keep_mounted
	if [ "$rootfs" = "freebsd-ufs" ] ; then
		echo ; echo "Unmounting /media"
		umount /media || { echo "umount failed" ; exit 1 ; }
	else
		zpool export zroot || { echo "zpool export failed" ; exit 1 ; }
	fi
	if [ "$target_type" = "img" ] ; then
		echo ; echo "Destroying $target_device"
		mdconfig -du $md_id || \
			{ echo "$target_device mdconfig -du failed" ; mdconfig -lv ; exit 1 ; }
	fi
elif [ "$keep_mounted" = 1 ] ; then
	if [ "$rootfs" = "freebsd-ufs" ] ; then
		echo ; echo "Run 'umount /media' when finished"
	else
		echo ; echo "Run 'zpool export zroot' when finished"
	fi

	if [ "$target_type" = "img" ] ; then
		echo "Run 'mdconfig -du $md_id' when finished"
	fi
fi
exit 0
