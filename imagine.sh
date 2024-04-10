#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause-FreeBSD
#
# Copyright 2022, 2023, 2024 Michael Dexter
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

# Version v.0.4.0


# CAVEATS

# This intimately follows the FreeBSD Release Engineering mirror layout.
# If the layout changes, this will probably break.

# FreeBSD 15.0-CURRENT VM-IMAGES are now 6GB in size.

# The generated bhyve boot scripts require the bhyve-firmware UEFI package.

# The canonical /media temporary mount point is hard-coded for now.

# The canonical /usr/src directory is hard-coded when using -r obj or a path.

# 'fetch -i' only checks date stamps, allow for false matches on interrupted downlods.

# Running imagine.sh in the working directory will cause existing release versions to be misinterpreted as image paths to be copied.

# This will clean up previous images but not boot scripts.


# EXAMPLES

# To fetch a 15.0-CURRENT raw boot image to ~/imagine-work/freebsd.raw
#
# sh imagine.sh -r 15.0-CURRENT

# To fetch a 15.0-CURRENT raw boot image and write to /dev/da1
#
# sh imagine.sh -r 15.0-CURRENT -t /dev/da1
 
# To copy a "make release" VM image from the canonical object directory:
#	/usr/obj/usr/src/amd64.amd64/release/vm.raw to ~/imagine-work/freebsd.raw
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
# sh imagine.sh -a riscv -r 14.0-RELEASE -z -g 10 -b
#
# Add '-v' to generate a VMDK that is QEMU compatible, because you can
#
# Do increase the RAM with root-on-ZFS systems but it WILL support the 1G default

f_usage() {
	echo ; echo "USAGE:"
	echo "-w <working directory> (Default: /root/imagine-work)"
	echo "-a <architecture> [ amd64 | arm64 | i386 | riscv - default amd64 ]"
	echo "-r [ obj | debian | /path/to/image | <version> ] (Release - Required)"
	echo "obj = /usr/obj/usr/src/<target>.<target_arch>/release/vm.raw"
	echo "/path/to/image.raw for an existing image"
	echo "<version> i.e. 14.0-RELEASE | 15.0-CURRENT | 15.0-ALPHAn|BETAn|RCn"
	echo "-o (Offline mode to re-use fetched releases and src.txz)"
	echo "-t <target> [ img | /dev/device | /path/myimg - default img ]"
#	echo "-T <mirror target> [ img | /dev/device | /path/myimg ]"
	echo "-f (FORCE imaging to a device without asking)"
	echo "-g <gigabytes> (grow image to gigabytes i.e. 10)"
	echo "-s (Include src.txz or /usr/src as appropriate)"
	echo "-m (Mount image and keep mounted for further configuration)"
	echo "-v (Generate VMDK image wrapper)"
	echo "-b (Genereate boot scripts)"
	echo "-z (Use a 14.0-RELEASE or newer root on ZFS image)"
	echo "-Z <new zpool name>"
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
zfs_string=""

advanced_preparation=0
root_fs=""
root_part=""
zpool_name=""
zpool_rename=""
zpool_newname=""
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
md_id=42			# Default for easier cleanup if interrupted


# USER INPUT AND VARIABLE OVERRIDES

while getopts w:a:r:zZ:t:ofg:smvb opts ; do
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
		release_input="$OPTARG"
	;;
	o)
		offline_mode=1
	;;
	z)
		zfs_string="-zfs"
	;;
	Z)
		advanced_preparation=1
		zpool_newname="$OPTARG"
		# Consider validation
		# Implying this for use as shorthand
		zfs_string="-zfs"
		zpool_rename=1
	;;
	t)
		[ "$OPTARG" ] || f_usage
		target_input="$OPTARG"
	;;
#	T)
# Problem... images are quite dynamic
#		[ "$OPTARG" ] || f_usage
#		mirror_path="$OPTARG"
#	;;
	f)
		force=1
	;;
	g)
		advanced_preparation=1
		grow_size="$OPTARG"
		# Implied numeric validation
		[ "$grow_size" -gt 7 ] || \
			{ echo "-g must be a number larger than 7" ; exit 1 ; }
		grow_required=1
	;;
	s)
		advanced_preparation=1
		include_src=1
		grow_required=1
		must_mount=1
	;;
	m)
		advanced_preparation=1
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

if [ $zpool_newname ] ; then
	zpool get name $zpool_newname > /dev/null 2>&1 && \
{ echo zpool $zpool_newname in use and will conflict - use -Z ; exit 1 ; }
fi

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

elif [ "$release_input" = "debian" ] ; then
	release_type="file"
	release_image_url="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-amd64.raw"
	release_name="debian"
	release_image_file="debian-12-nocloud-amd64.raw"

# TEST AND FAIL EARLY
	[ "$include_src" = 1 ] && \
		{ echo "-s src not available with Debian images" ; exit 1 ; }

	[ -n "$zfs_string" ] && \
		{ echo "-z ZFS not available with Debian images" ; exit 1 ; }

# Redundant from FreeBSD/xz - refactor!
# Create the work directory if missing
	[ -d "${work_dir}/${release_name}" ] || \
		mkdir -p "${work_dir}/${release_name}"
	[ -d "${work_dir}/${release_name}" ] || \
		{ echo "mkdir ${work_dir}/${release_name} failed" ; exit 1 ; }

	# Needed for fetch to save the upstream file name
	cd "${work_dir}/${release_name}"

	# fetch is not idempotent - check if exists before fetch -i
	if [ -r $release_image_file ] ; then
		if [ "$offline_mode" = 0 ] ; then
		fetch -a -i "$release_image_file" "$release_image_url" || \
			{ echo "$release_image_url fetch failed" ; exit 1 ; }
		fi
	else
	fetch -a "$release_image_url" || \
		{ echo "$release_image_url fetch failed" ; exit 1 ; }
	fi
elif [ -f "$release_input" ] ; then # path to an image
	release_type="file"
	# Consider the vmrun.sh "file" test for boot blocks
	release_image_file="$release_input"
	[ -r "$release_image_file" ] || \
		{ echo "$release_image_file not found" ; exit 1 ; }

	[ "$include_src" = 1 ] && \
		{ echo "-s src not available with a custom image" ; exit 1 ; }

else # release version i.e. 15.0-CURRENT
	release_type="xz"
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

# Determine if the first character is a "/"
target_prefix=$( printf %.1s "$target_input" )

if [ "$target_input" = "img" ] ; then
	target_type="img"

	if [ "$release_name" = "debian" ] ; then
		target_path="${work_dir}/debian.raw"
	else
		target_path="${work_dir}/freebsd.raw"
	fi

	[ -d "$work_dir" ] || mkdir -p "$work_dir"
	[ -d "$work_dir" ] || { echo "mkdir -p $work_dir failed" ; exit 1 ; }

elif [ "$target_prefix" = "/" ] ; then
	if [ "$( echo "$target_input" | cut -d "/" -f 2 )" = "dev" ] ; then

		target_type="dev"

		[ "$( id -u )" = 0 ] || \
			{ echo "Must be root for -t dev" ; exit 1 ; } 

		target_dev="$target_input"
		advanced_preparation=1
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


# FAIL EARLY

echo
if [ "$target_type" = "img" -o "$target_type" = "path" ] ; then
	if [ "$grow_required" = 1 ] ; then
		[ -n "$grow_size" ] || { echo "-g size is required" ; exit 1 ; }
	fi
fi

if [ "$advanced_preparation" = "1" -a "$target_type" = "img" ] ; then
	mdconfig -lv | grep "$target_path" > /dev/null 2>&1 && \
	{ echo "$target_path must be detached with mdconfig -du $md_id" ; exit 1 ; }
fi

if [ "$release_name" = "debian" -a "$grow_required" = "1" ] ; then
	which resize2fs > /dev/null 2>&1 || \
		{ echo "fusefs-ext2 not installed" ; exit 1 ; }
fi


# EXTRACTION TO FILE OR DEVICE

case "$target_type" in
	img|path)
		[ -f "$target_path" ] && rm "$target_path"

		if [ "$release_type" = "xz" ] ; then
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

		mdconfig -lv | grep "$target_path" > /dev/null 2>&1 && \
{ echo "$target_path must be detached with mdconfig -du $md_id" ; exit 1 ; }
		;;
	dev)
		if [ -n "$release_image_file" ] ; then

			if [ "$force" = 0 ] ; then
				echo "WARNING! Writing to $target_dev!"
				diskinfo -v $target_dev
				echo -n "Continue? (y/n): " ; read warning
				[ "$warning" = "y" ] || exit 1
			fi

		\time -h dd if="$release_image_file" of="$target_dev" \
			bs=1m status=progress || \
				{ echo "dd failed" ; exit 1 ; }

		elif [ -n "$release_image_xz" ] ; then

			if [ "$force" = 0 ] ; then
				echo "WARNING! Writing to $target_dev!"
				diskinfo -v $target_dev
				echo -n "Continue? (y/n): " ; read warning
				[ "$warning" = "y" ] || exit 1
			fi

			\time -h cat "$release_image_xz" | 
				xz -d -k | \
				dd of="$target_dev" \
				bs=1m status=progress \
				iflag=fullblock || \
					{ echo "dd failed" ; exit 1 ; }
		else
			echo "Something went wrong"
			exit 1
		fi
		gpart recover $target_dev || \
			{ echo gpart recover failed ; exit 1 ; }
		gpart show $target_dev
	;;
esac

# Simply usaged is finished at this point



# ADVANCED PREPARATION (Not simply copy the expanded stock VM image

if [ "$advanced_preparation" = "1" ] ; then

	[ "$( id -u )" = 0 ] || \
		{ echo "Must be root for image growth" ; exit 1 ; } 

	case "$target_type" in
		img|path)

			mdconfig -lv | grep -q "md$md_id" && \
				{ echo "md$md_id in use" ; exit 1 ; }

# MUST truncate larger before attaching
			if [ "$grow_required" = 1 ] ; then
				echo ; echo "Truncating $target_path"
				truncate -s ${grow_size}G "$target_path" || \
					{ echo truncation failed ; exit 1 ; }
			fi

			echo ; echo "Attaching $target_path"
			mdconfig -a -f "$target_path" -u $md_id || \

				{ echo mdconfig failed ; exit 1 ; }
			target_dev="/dev/md$md_id"

			mdconfig -lv
	
			gpart recover $target_dev || \
				{ echo gpart recover failed ; exit 1 ; }
		;;
	esac

# FreeBSD /dev/${target_dev}pN is now dev/img agnostic at this point

	echo ; echo Determining root file system with gpart

	if [ "$( gpart show $target_dev | grep freebsd-ufs )" ] ; then
		root_fs="freebsd-ufs"
	elif [ "$( gpart show $target_dev | grep freebsd-zfs )" ] ; then
		root_fs="freebsd-zfs"
	elif [ "$( gpart show $target_dev | grep linux-data )" ] ; then
		root_fs="linux-data"
	else
		echo "Unrecognized root file system"
		exit 1
	fi

	echo ; echo Root file system appears to be $root_fs

	# These should be file system-agnostic at this point
root_part="$( gpart show $target_dev | grep $root_fs | awk '{print $3}' )"
root_dev="${target_dev}p${root_part}"

	if [ "$root_fs" = "freebsd-zfs" ] ; then
		echo ; echo Obtaining zpool guid from $root_dev
	zpool_name=$( zdb -l $root_dev | grep " name:" | awk '{print $2}' )
		echo ; echo Obtaining zpool guid from $root_dev
	zpool_guid=$( zdb -l $root_dev | grep pool_guid | awk '{print $2}' )
	fi

fi # End advanced_preparation

# That should have set $target_dev $root_fs $root_part $root_dev for use by
# advanced preparation steps


# INDIVIDUAL ADVANCED PREPARATIONS

if [ "$grow_required" = 1 -o "$zpool_rename" = 1 ] ; then
	echo ; echo "Resizing $root_dev"
	# Should be file system-agnostic
	gpart resize -i "$root_part" "$target_dev"
	gpart show "$target_dev"

	gpart recover $target_dev || \
		{ echo gpart recover failed ; exit 1 ; }

# GROW BY FILE SYSTEM

	if [ "$root_fs" = "freebsd-ufs" ] ; then
		echo ; echo Growing ${target_dev}p${root_part}
		growfs -y "${target_dev}p${root_part}" || \
		{ echo "growfs failed" ; exit 1 ; }
	elif [ "$root_fs" = "linux-data" ] ; then
#		[ $( which resize2fs ) ] || \
		which resize2fs > /dev/null 2>&1 || \
			{ echo "fusefs-ext2 not installed" ; exit 1 ; }

#		echo ; echo Growing ${target_dev}p1
		echo ; echo Growing ${target_dev}p${root_part}
#		resize2fs "${target_dev}p1" || \
		resize2fs "${target_dev}p${root_part}" || \
			{ echo "resize2fs failed" ; exit 1 ; }

	# Could be 'else' having completed the recognition test above
	elif [ "$root_fs" = "freebsd-zfs" ] ; then

		# Goal is grow, but must accomodate rename (guessing no harm)

#		echo ; echo Obtaining zpool guid from $root_dev
#	zpool_name=$( zdb -l $root_dev | grep " name:" | awk '{print $2}' )
#	echo ; echo Obtaining zpool guid from $root_dev
#	zpool_guid=$( zdb -l $root_dev | grep pool_guid | awk '{print $2}' )

		# Must rename to import if conflicting
		if [ "$zpool_rename" = 1 ] ; then
		echo ; echo Importing and expanding zpool with guid $zpool_guid
		zpool import -o autoexpand=on -N $zpool_guid $zpool_newname || \
			{ echo "$zpool_newname failed to import" ; exit 1 ; }
				zpool_name="$zpool_newname"
		else
			echo ; echo Importing and expanding zpool $zpool_name
			zpool import -o autoexpand=on -N $zpool_name || \
			{ echo "$zpool_name failed to import" ; exit 1 ; }
		fi

		if [ "$target_type" = "img" ] ; then
			zpool online -e $zpool_name $root_dev
		elif [ "$target_type" = "dev" ] ; then
			zpool online -e $zpool_name /dev/gpt/root_fs
		fi

		zpool list $zpool_name

		echo ; echo Reguiding and upgrading $zpool_name

		zpool reguid $zpool_name
		zpool upgrade $zpool_name

		zpool status $zpool_name

		echo ; echo "Exporting the $zpool_name"

		zpool export $zpool_name

	fi # End root_fs
fi # End grow_required


# note that source forces mount... nest it


if [ "$must_mount" = 1 ] ; then
	mount | grep "on /media" && \
		{ echo "/media mount point in use" ; exit 1 ; }

	if [ "$root_fs" = "freebsd-ufs" ] ; then
		mount $root_dev /media || \
			{ echo mount failed ; exit 1 ; }

	elif [ "$root_fs" = "linux-data" ] ; then
		kldstat -q -m fusefs || kldload fusefs
		kldstat -q -m fusefs || \
			{ echo fusefs.ko failed to load ; exit 1 ; }
		fuse-ext2 $root_dev /media -o rw+ || \
			{ echo $root_dev fuse-ext2 mount failed ; exit 1 ; }

	elif [ "$root_fs" = "freebsd-ufs" ] ; then

		echo ; echo Importing zpool $zpool_name for mounting
		zpool import -R /media $zpool_name || \
			{ echo "$zpool_name failed to import" ; exit 1 ; }
	fi # End if root_fs


# OPTIONAL SOURCES

	if [ "$include_src" = 1 ] ; then
		if [ "$release_type" = "xz" ] ; then

		[ -f "${work_dir}/${release_name}/src.txz" ] || \
			{ echo "src.txz missing" ; exit 1 ; }
		# Add dpv(1) progress?
		echo "Extracting ${work_dir}/${release_name}/src.txz"
		cat "${work_dir}/${release_name}/src.txz" | \
			tar -xpf - -C /media/ || \
				{ echo "src.txz extraction failed" ; exit 1 ; }
		else
			echo ; echo "Copying /usr/src"
			tar cf - /usr/src | tar xpf - -C /media || \
				{ echo "/usr/src failed to copy" ; exit 1 ; }
		fi
		[ -f "/media/usr/src/Makefile" ] || \
			{ echo "/usr/src failed to copy" ; exit 1 ; }
	fi

	df -h | grep media
	ls /media
fi



# OPTIONAL VMDK WRAPPER

# These would want mirriring support but that would be a leap of faith
# if the mirroring has not been performed yet

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
	elif [ -n "$target_dev" ] ; then
		vm_device="$target_dev"
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
bhyve -c 1 -m 1024 -H -A \\
	-l com1,stdio \\
	-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd \\
	-s 0,hostbridge \\
	-s 2,virtio-blk,$vm_device \\
	-s 30,xhci,tablet \\
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


# UNMOUNT OR REMIND OF THE MOUNT

# Could be moved to before VM scripts but should remain last,
# followed by mirroring

if [ "$keep_mounted" = 0 ] ; then
	if [ "$must_mount" = 1 ] ; then

		if [ "$root_fs" = "freebsd-ufs" ] ; then
			echo ; echo "Unmounting /media"
			umount /media || { echo "umount failed" ; exit 1 ; }
		elif [ "$root_fs" = "freebsd-zfs" ] ; then
			zpool export $zpool_name || \
				{ echo "zpool export failed" ; exit 1 ; }
		fi
	fi

# Could be a better test: Is img but was attached for growth
	if [ "$target_type" = "img" -a "$grow_required" = 1 ] ; then
		echo ; echo "Destroying $target_dev"
		mdconfig -du $md_id || \
	{ echo "$target_dev mdconfig -du failed" ; mdconfig -lv ; exit 1 ; }
	fi

else
	if [ "$root_fs" = "freebsd-ufs" ] ; then
		echo ; echo "Run 'umount /media' when finished"
	else
		echo ; echo "Run 'zpool export $zpool_name' when finished"
	fi

	if [ "$target_type" = "img" ] ; then
		echo "Run 'mdconfig -du $md_id' when finished"
	fi
fi


# MIRRORING SCAFOLDING

# Framing in but may rip out

# Challenge: Automatic image handling
# Challenge: User can specify a custom path, image or file?


# Imagine images to devices... return the device

# Would need a quiet mode for this to work
#echo -n $target_path
