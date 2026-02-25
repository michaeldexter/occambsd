#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause-FreeBSD
#
# Copyright 2022, 2023, 2024, 2025, 2026 Michael Dexter
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

# Version v.0.99.10

# imagine.sh - a disk image imager for virtual and hardware machines


# MOTIVATION

# This is project motivated by the simple notion that "generic" raw boot images
# can be retrieved and booted on "generic" hardware and virtual machines.
# Unfortunately, operating systems are highly-inconsistent in providing
# "generic" raw boot images. The top issues are:

# * Lack of raw images (QEMU, VHDX, VDI, VMDK, etc. are obsoleted by OpenZFS)
# * Lack of "Latest" links (aliases to the most recent versions)
# * Lack of BIOS/Legacy and QEMU images
# * Inconsistent and/or ambiguous file naming with architecture


# SUPPORTED IMAGES SOURCES

# Downloaded FreeBSD amd64, arm64, i386, and riscv raw VM-IMAGEs
# Custom build FreeBSD raw VM-IMAGEs such as those build with OccamBSD
# OmniOS amd64 "cloud" images
# Debian amd64 and arm64 "cloud" images
# RouterOS amd64 and arm64 "cloud" images
# Windows autounattend.xml installations performed by bhyve(8)


# SUPPORTED IMAGE DESTINATIONS

# Unmodified copied or expanded images
# Resized copied or expanded images
# Mirrored unmodified or expanded root-on-ZFS images (FreeBSD)
# Physical block storage devices
# Mirrored physical root-on-ZFS block storage devices (FreeBSD only)


# ADDITIONAL OPTIONS

# Specify a work directory
# Resize images (needed for adding sources and other contents)
# Rename zpools (FreeBSD and OmniOS only)
# Keep the images or devices mounted for further configuration
# Include sources (FreeBSD only)
# Generate bhyve, QEMU, and Xen boot scripts
# Generate VMDK-compatible wrappers


# IN SHORT

# You can generate virtual and hardware machines in minutes in not seconds, and,
# combined with occambsd.sh, can build, release, configured, and boot custom
# operating systems in minutes, using mostly in-base tools.


# RELATIONSHIP TO OCCAMBSD

# occambsd.sh -p <profile> -v will build a UFS VM-IMAGE to
#	/usr/obj/usr/src/amd64.amd64/release/vm.ufs.raw
# occambsd.sh -p <profile> -v -z will build a ZFS VM-IMAGE to
#	/usr/obj/usr/src/amd64.amd64/release/vm.zfs.raw

# Accordingly, 'imagine -r raw' and 'imagine -r raw -z' will operate on these
# with flags such as -b for boot scripts, -g for growth, etc.


# CAVEATS

# This intimately follows the FreeBSD Release Engineering mirror layout.
# If the layout changes, this will probably break.
# FreeBSD 15.0-CURRENT VM-IMAGES are now 6GB in size.
# The generated bhyve boot scripts require the bhyve-firmware UEFI package.
# The canonical /usr/src directory is hard-coded when using -r obj or a path.
# 'fetch -i' only checks date stamps, allow for false matches on interrupted downloads.
# Xen boot scripts do not support mirrored devices yet
# Running imagine.sh in the working directory will cause existing release versions to be misinterpreted as image paths to be copied.
# This will clean up previous images but not boot scripts.
# /etc/fstab is moved to fstab.original and replaced with an empty file on any
# runs that include advanced zpool handling.
# imagine.sh -z is consistent in how it relabels partitions, making for a
# conflict if you try to run imagine.sh from an imagine.sh destination.
# Workaround: Us a UFS image to install to a ZFS one.
# Remember that FreeBSD Xen guests require these loader.conf entries for the serial console:
# console="comconsole"


# EXAMPLES

# To fetch a 15.0-CURRENT raw boot image to ~/imagine-work/freebsd.raw
#
# sh imagine.sh -r 15.0-CURRENT

# To fetch a 15.0-CURRENT raw boot image and write to /dev/da1
#
# sh imagine.sh -r 15.0-CURRENT -t /dev/da1
 
# To copy a "make release" VM image from the canonical object directory:
#	/usr/obj/usr/src/amd64.amd64/release/vm.ufs.raw to ~/imagine-work/freebsd.raw
#
# sh imagine.sh -r obj

# To copy a boot image from a custom path and name to a custom path and name:
#
# sh imagine.sh -r /tmp/myvm.img -t /tmp/myvmcopy.raw

# Add '-w /tmp/mydir' to override '~/imagine-work' with an existing directory
# Add '-z' to fetch the root-on-ZFS image
# Add '-b' to generate a simple bhyve, xen, and/or QEMU boot scripts depending on the architecture
# Add '-g 10' to grow boot image to 10GB

# The local and fetched source boot images will be always preserved for re-use
# and -o "offline" mode will skip the attempt to check for changes with fetch

# To generate a 10GB RISC-V system with root-on-ZFS and a QEMU boot script:
#
# sh imagine.sh -a riscv -r 15.0-RELEASE -z -g 10 -b
#
# Add '-V' to generate a VMDK that is VMware compatible, because you can


#########
# USAGE #
#########

f_usage() {
	echo ; echo "USAGE:"
	echo "-O <output directory> (Default: ~/imagine-work)"
	echo "-a <architecture> [ amd64 | arm64 | i386 | riscv ] (Default: Host)"
	echo "-r [ obj | /path/to/image | <version> | omnios | debian ]"

# HOW ARE obj and path any different? ONE TRIGGERS SRC - obj calculates the
# object directory path, for better or for worse

	echo "obj i.e. /usr/obj/usr/src/<target>.<target_arch>/release/vm.ufs.raw"
	echo "/path/to/image.raw for an existing image"
	echo "<version> i.e. 15.0-RELEASE | 16.0-CURRENT | 15.0-ALPHAn|BETAn|RCn"
	echo "(Default: Host)"
	echo "-o (Offline mode to re-use fetched releases)"
	echo "-t <target> [ img | /dev/<device> | /path/myimg ] (Default: img)"
	echo "-T <mirror target> [ img | /dev/<device> ]"
	echo "-f (FORCE imaging to a device without prompting for confirmation)"
	echo "-g <gigabytes> (grow image to gigabytes i.e. 10)"
	echo "-p \"<packages>\" (Quoted space-separated list)"
	echo "-c (Copy cached packages from the host to the target)"
	echo "-C (Clean package cache after installation)"
	echo "-u (Add root/root and freebsd/freebsd users and enable sshd)"
	echo "-d (Enable crash dumping)"
	echo "-m (Mount image and keep mounted for further configuration)"
	echo "-M <Mount point> (Default: /media)"
	echo "-V (Generate VMDK image wrapper)"
	echo "-v (Generate VM boot scripts)"
	echo "-n (Include tap0 e1000 network device in VM boot scripts)"
	echo "-U (Use a UFS image rather than ZFS image)"
	echo "-Z <new zpool name if conflicting i.e. with zroot>"
	echo "-A (Enable ZFS ARC cache to default rather than metadata)"
	echo "-x <autounattend.xml file for Windows> (Requires -i)"
	echo "-i <Full path to installation ISO file for Windows> (Requires -x)"
	echo
	exit 0
}


###################################
# INTERNAL VARIABLES AND DEFAULTS #
###################################

work_dir=~/imagine-work		# Default - fails if quoted
hw_platform=$( uname -m )	# i.e. arm64
cpu_arch=$( uname -p )		# i.e. aarch64
arch_string=""
release_input=$( uname -r | cut -d "-" -f1,2 )
offline_mode=0
force=0
release_type=""
release_name=""
release_image_url=""
release_image_file=""
#release_image_xz=""
release_branch=""
file_to_extract=""
fs_type="zfs"
#omnios_amd64_url="https://us-west.mirror.omnios.org/downloads/media/stable/omnios-r151054.cloud.raw.zst"
omnios_amd64_url="https://us-west.mirror.omnios.org/downloads/media/r151056/omnios-r151056.cloud.raw.zst"
omnios_arm64_url="https://downloads.omnios.org/media/braich/braich-151055.raw.zst"

debian_amd64_url="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-nocloud-amd64.raw"
debian_arm64_url="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-nocloud-arm64.raw"
#debian_amd64_url="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.raw"
#debian_arm64_url="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-arm64.raw"

# Stable CHR rather than LongTerm, Testing, or Development
routeros_amd64_url="https://download.mikrotik.com/routeros/7.21.3/chr-7.21.3.img.zip"
routeros_arm64_url="https://download.mikrotik.com/routeros/7.21.3/chr-7.21.3-arm64.img.zip"

memtest86_url="https://www.memtest86.com/downloads/memtest86-usb.zip"

attachment_required=0
root_fs=""
root_part=""
root_dev=""
part_scheme=""
scheme=""
root_part=""
zpool_name=""
zpool_rename=0
zpool_newname=""
zroot_in_use=0
zpool_newname_in_use=0
zfs_arc_default=0
label_id1=100
label_id2=200
label_conflict=0
target_input="img"
target_dev=""
target_dev2=""
target_type=""
target_path=""
target_prefix=""
iso_prefix=""
target_size=""
mirror_path=""
mirror_size=""
force=0
grow_required=0
grow_size=""
packages=""
copy_package_cache=0
clean_package_cache=0
add_users=0
enable_crash_dumping=0
mount_required=0
keep_mounted=0
mount_point="/media"
xml_file=""
iso_file=""
vmdk=0
boot_scripts=0
#vm_networking=0
vm_device=""
fbuf_string=""
storage_string=""
network_string=""
vm_name="vm0"			# Embedded Default
vm_ram="4096"			# Embedded Default
vm_cores=1			# Embedded Default
framebuffer_required=0
bhyve_script=""
qemu_script=""
xen_cfg=""
xen_script=""
xen_destroy=""
md_id=42			# Default for easier cleanup if interrupted


#####################################
# USER INPUT AND VARIABLE OVERRIDES #
#####################################

while getopts O:a:r:ot:T:fg:p:cCudmM:VvnUZ:Ax:i: opts ; do
	case $opts in
	O)
		work_dir="$OPTARG"
		[ -d "$work_dir" ] || mkdir -p "$work_dir"
	[ -d "$work_dir" ] || { echo "mkdir -p $work_dir failed" ; exit 1 ; }
	;;

	a)
		case "$OPTARG" in
			amd64|arm64|i386|riscv)
				hw_platform="$OPTARG"
		;;
			*)
				echo "Invalid architecture"
				f_usage
		;;
		esac
	;;

	r) 
	# -r [ <version> | obj | /path/to/image | omnios | debian | routeros ]
	# windows is requested by specifying an xml file
		release_input="$OPTARG"
	;;

	o)
		offline_mode=1
	;;

	t)
		[ "$( id -u )" = 0 ] || { echo "Must be root" ; exit 1 ; } 
		[ "$OPTARG" ] || f_usage
		target_input="$OPTARG"
		target_prefix=$( printf %.5s "$target_input" )
	;;

	T)
		[ "$( id -u )" = 0 ] || { echo "Must be root" ; exit 1 ; } 
		[ "$OPTARG" ] || f_usage
		mirror_path="$OPTARG"
		if [ ! "$mirror_path" = "img" ] ; then
			[ -c "$mirror_path" ] || \
			{ echo "Mirror target device not found" ; exit 1 ; }
		fi
		# Mounting is required for fstab modifications
		mount_required=1
		attachment_required=1
	;;

	f)
		# Write to a device without prompting for confirmation
		force=1
	;;

	g)
		grow_required=1
		grow_size="$OPTARG"
		# Implied numeric validation
		[ "$grow_size" -gt 7 ] || \
			{ echo "-g must be a number larger than 7" ; exit 1 ; }
		attachment_required=1
	;;

	p)
		[ "$( id -u )" = 0 ] || { echo "Must be root" ; exit 1 ; } 
		[ "$OPTARG" ] || f_usage
		packages="$OPTARG"
		# Strongly recommended but not required
#		grow_required=1
		mount_required=1
		attachment_required=1
	;;

	c)
		copy_package_cache=1
	;;

	C)
		clean_package_cache=1
	;;

	u)
		add_users=1
		mount_required=1
		attachment_required=1
	;;

	d)
		enable_crash_dumping=1
		mount_required=1
		attachment_required=1
	;;

	m)
		mount_required=1
		keep_mounted=1
		attachment_required=1
	;;

	M)
		[ "$OPTARG" ] || f_usage
		mount_point="$OPTARG"
		[ -d "$mount_point" ] || \
			{ echo "Mount point $mount_point missing" ; exit 1 ; }
	;;

	V)
		# Could simply add a wrapper to an existing image
		vmdk=1
	;;

	v)
		# root required to execute bhyve and Xen boot scripts
		boot_scripts=1
	;;

	n)
		network_string="-s 4,e1000,tap0"
	;;

	U)
		fs_type="ufs"
		# Not attachment_required if only copying to an image file 
	;;

	Z)
		[ "$( id -u )" = 0 ] || { echo "Must be root" ; exit 1 ; } 
		zpool_newname="$OPTARG"
		# Consider validation
		# Implying this for use as shorthand
		fs_type="zfs"
		zpool_rename=1
		# Needed for the fstab handling
		attachment_required=1
		mount_required=1
	;;

	A)
		zfs_arc_default=1
		fs_type="zfs"
		attachment_required=1
	;;

	x)
		# root required for initial boot though it could be QEMU
		xml_file="$OPTARG"
		[ -r "$xml_file" ] || \
			{ echo "$xml_file missing or unreadable" ; exit 1 ; }
		boot_scripts=1
		# DEBUG Refactor: This might be more than we need
		release_name="windows"
		release_input="windows" # Mutually exclusive with release_input
		framebuffer_required=1
		fs_type="ntfs"
	;;

	i)
		iso_file="$OPTARG"
		[ -r "$iso_file" ] || \
			{ echo "$iso_file missing or unreadable" ; exit 1 ; }
		iso_prefix=$( printf %.1s "$iso_file" )
		[ "$iso_prefix" = "/" ] || \
		{ echo "ISO must be prefixed with a full path" ; exit 1 ; }
	;;

	*)
		f_usage
	;;
	esac
done


# Get the hardware device write warnings out of the way early

if [ "$target_prefix" = "/dev/" ] ; then
	[ -c "$target_input" ] || \
		{ echo "$target_input device not found" ; exit 1 ; }
	if [ "$force" = 0 ] ; then
		echo ; echo "WARNING! Writing to $target_input !" ; echo
		diskinfo -v $target_input
		gpart show -l $target_input
		echo ; echo "WARNING! Writing to $target_input !" ; echo
		echo -n "Continue? (y/n): " ; read confirmation
		[ "$confirmation" = "y" ] || exit 0
	fi
fi

if [ "$mirror_path" ] ; then
	if [ ! "$mirror_path" = "img" ] ; then
		if [ "$force" = 0 ] ; then
			echo "WARNING! Writing to $mirror_path !"
			diskinfo -v $mirror_path
			gpart show -l $mirror_path
			echo ; echo "WARNING! Writing to $mirror_path !" ; echo
			echo -n "Continue? (y/n): " ; read confirmation2
			[ "$confirmation2" = "y" ] || exit 0
		fi
	fi
fi

# Download mirror path expansion for FreeBSD
case "$hw_platform" in
	amd64)
		cpu_arch="amd64"
		arch_string="amd64"
	;;
	arm64)
		cpu_arch="aarch64"
		arch_string="arm64-aarch64"
	;;
	i386)
		cpu_arch="i386"
		arch_string="i386"
	;;
	riscv)
		cpu_arch="riscv64"
		arch_string="riscv-riscv64"
	;;
esac

# Needed for ZFS handling
if [ "$fs_type" = "zfs" ] && [ "$grow_required" = 1 ] ; then
	if [ "$release_input" = "omnios" ] ; then
		mount_required=0
	else # release_input is a version for FreeBSD
		mount_required=1
	fi
fi

[ "$enable_crash_dumping" = "1" ] && packages="$packages gdb"

# Label conflict resolution strategy one: trust /dev/gpt/
# Check for anticipated conflicts and increment label_id1 and 2 until clear
# Defaults: bootfs efiesp|efiboot swapfs rootfs

[ -e /dev/gpt/rootfs$label_id1 ] && label_conflict=1
[ -e /dev/gpt/efiboot$label_id1 ] && label_conflict=1
[ -e /dev/gpt/swapfs$label_id1 ] && label_conflict=1

# Determine if these tests are comprehensive enough

if [ "$label_conflict" = 1 ] ; then
	while : ; do
		label_id1=$(($label_id1+1))
		label_id2=$(($label_id2+1))

		[ -e /dev/gpt/rootfs$label_id1 ] || \
		[ -e /dev/gpt/efiboot$label_id1 ] || \
		[ -e /dev/gpt/swapfs$label_id1 ] || break
	done

	echo ; echo "New label ID is $label_id1"
fi


######################
# TESTS - FAIL EARLY #
######################

# Copying packages probably, but not necessarily requires growth
# Checking for available space would come too late for clean-up
# Could compare the package cache size to the typical available free space
# or requested growth size
#if [ "$copy_package_cache" = "1" ] ; then
#	{ echo "-c requires -g" ; exit 1 ; }
#fi

if [ "$target_prefix" = "/dev/" ] ; then
	[ "$vmdk" = 0 ] || { echo "-v does not support devices" ; exit 1 ; }
fi

if [ "$fs_type" = "ufs" ] && [ -n "$mirror_path" ] ; then
	echo Device mirroring only works with ZFS
	exit 1
fi

if [ "$xml_file" ] ; then
	[ "$iso_file" ] || { echo "-x requires -i" ; exit 1 ; }

	[ "$packages" ] && { echo "-p not supported with -x" ; exit 1 ; }

	# Default is img
	if [ "$target_input" = "img" ] ; then
		[ "$grow_size" ] || \
			{ echo "-x without -t requires -g" ; exit 1 ; }
	fi
	# Disable this as a second boot does the installation
	grow_required=0

# Pointless until further notice
	# Default not overridden with -t
#	[ "$target_input" = "img" ] || \
#		target_path="${work_dir}/windows-${hw_platform}-${fs_type}.raw"
fi # End if xml_file

if [ "$iso_file" ] ; then
	[ "$xml_file" ] || { echo "-i requires -x" ; exit 1 ; }
fi

[ -n "$release_input" ] || [ -n "$xml_file" ] || \
	{ echo "-r <release> or -x/-i are required" ; f_usage ; exit 1 ; }

[ -n "$mirror_path" ] && [ "$vmdk" = 1 ] && \
	{ echo "Mirroring does not support VMDK" ; exit 1 ; }


#############
# FUNCTIONS #
#############


f_fetch_image () # $1 release_image_file $2 release_image_url
{
	# fetch is not idempotent - check if exists before with fetch -i
	if [ -r "$1" ] ; then
		if [ "$offline_mode" = 0 ] ; then
			[ -f "$1" ] && cp $1 ${1}.previous
			fetch -a -i "$1" "$2" || \
				{ echo "$2 fetch failed" ; exit 1 ; }
		fi
	else
	fetch -a "$2" || \
		{ echo "$2 fetch failed" ; exit 1 ; }
	fi
}

f_extract () # $1 release_image_file.compression_ending
{
	[ -f $1 ] || { echo "$1 not found" ; exit 1 ; }

	# Build-in dpv or dd? Some have -v verbose
	case ${1##*.} in
		xz) xzcat -k -d $1 ;;
		zst|zstd) unzstd -k -c $1 ;;
		zip) unzip -p $1 ;;
		gz) gunzip -k -c $1 ;;
		raw|img|dd) cat $1 ;;
		*)
			echo "Unrecognized compression format"
			exit 1
		;;
	esac
}

f_cleanse_device () # $1 device
{
	echo Destroying all partitions on $1
	gpart show -l $1 | tail -n+2 | grep . \
		| awk '{print $1,$2,$3,$4}' | \
		while read _start _stop _id _label ; do
			_label=$( echo $_label | tr -d "[:digit:]" )
			[ "$_label" = "null" -o "$_label" = "free" ] && break
			echo Clearing zpool labels on $_label
			zpool labelclear "$_label" >/dev/null 2>&1
		done
	echo Clearing zpool labels from $1
	# Okay to fail
	zpool labelclear "$1" >/dev/null 2>&1

	echo Clearing partitions from $1
	gpart recover "$1"
	gpart destroy -F "$1" # || { echo "gpart destroy failed" ; exit 1 ; }
	gpart create -s gpt "$1" || { echo "gpart create failed" ; exit 1 ; }
	gpart destroy -F "$1" || { echo "gpart destroy failed" ; exit 1 ; }

#	Required to avoid corrupt zpool metadata (!)
	dd if=/dev/zero of="$1" bs=1m count=1 # 1048576 bytes
	dd if=/dev/zero of="$1" bs=1m \
		oseek=`diskinfo $1 | awk '{print int($3 / (1024*1024)) - 4;}'`
}


#################################
# HEAVY LIFTING FLAG -r RELEASE #
#################################

# Identify or download a source image - hence the name imagine.sh

echo ; echo Status: Beginning -r release handling

if [ "$release_input" = "obj" ] ; then
	release_type="raw"

# Better approach? Check all possibilities?
	if [ -f "/usr/obj/usr/src/${hw_platform}.${cpu_arch}/release/vm.${fs_type}.raw" ] ; then
release_image_file="/usr/obj/usr/src/${hw_platform}.${cpu_arch}/release/vm.${fs_type}.raw"
	elif [ -f "/usr/obj/usr/src/${hw_platform}.${cpu_arch}/release/vm.raw" ] ; then
# Previous release naming
release_image_file="/usr/obj/usr/src/${hw_platform}.${cpu_arch}/release/vm.raw"
	else
		echo "$release_image_file not found"
		exit 1
	fi

# A COPY HERE COULD MEAN WE ARE DONE but it needs a work dir to copy to
# and optional boot scripts

elif [ "$release_name" = "windows" ] ; then
	echo "Preparing Windows ISO and boot script"


##########
# OMNIOS #
##########

elif [ "$release_input" = "omnios" ] ; then

# TEST AND FAIL EARLY
# Group these tests above?
	[ "$packages" ] && \
		{ echo "-s packages not available with OmniOS" ; exit 1 ; }

	[ "$zpool_rename" = 0 ] || \
		{ echo "-Z renaming not yet supported with OmniOS" ; exit 1 ; } 

	[ -n "$mirror_path" ] && \
		{ echo "-T mirroring not yet supported with OmniOS" ; exit 1 ; }

	case "$hw_platform" in
		amd64) release_image_url="$omnios_amd64_url"
		;;
		arm64) release_image_url="$omnios_arm64_url"
		;;
		*) echo Invalid hardware architecture ; exit 1
		;;
	esac

	release_name="omnios"
	release_image_file="$( basename $release_image_url )"

	[ -d "${work_dir}/${release_name}" ] || \
		mkdir -p "${work_dir}/${release_name}"
	[ -d "${work_dir}/${release_name}" ] || \
		{ echo "mkdir ${work_dir}/${release_name} failed" ; exit 1 ; }

	# Needed for fetch to save the upstream file name
	cd "${work_dir}/${release_name}"

	f_fetch_image "$release_image_file" "$release_image_url"


##########
# DEBIAN #
##########

elif [ "$release_input" = "debian" ] ; then
	release_type="raw"
	case "$hw_platform" in
		amd64) release_image_url="$debian_amd64_url"
		;;
		arm64) release_image_url="$debian_arm64_url"
		;;
		*) echo Invalid hardware architecture ; exit 1
		;;
	esac
	release_name="debian"
	release_image_file="$( basename $release_image_url )"

# TEST AND FAIL EARLY - can only test after parsing -r input
	[ "$packages" ] && \
		{ echo "-s Packages not available with Debian" ; exit 1 ; }

	[ "$fs_type" = "zfs" ] && \
		{ echo "-z ZFS not available with Debian" ; exit 1 ; }

	[ -n "$mirror_path" ] && \
		{ echo "-T mirroring not supported with Debian" ; exit 1 ; }

# Redundant from FreeBSD/xz - refactor if possible
# Create the work directory if missing
	[ -d "${work_dir}/${release_name}" ] || \
		mkdir -p "${work_dir}/${release_name}"
	[ -d "${work_dir}/${release_name}" ] || \
		{ echo "mkdir ${work_dir}/${release_name} failed" ; exit 1 ; }

	# Needed for fetch to save the upstream file name
	cd "${work_dir}/${release_name}"

	f_fetch_image "$release_image_file" "$release_image_url"


############
# ROUTEROS #
############

elif [ "$release_input" = "routeros" ] ; then
	# For UEFI handling
	attachment_required=1
	release_type="zip"
	case "$hw_platform" in
		amd64) release_image_url="$routeros_amd64_url"
		;;
		arm64) release_image_url="$routeros_arm64_url"
		;;
		*) echo Invalid hardware architecture ; exit 1
		;;
	esac

	release_name="routeros"
	release_image_file="$( basename $release_image_url )"

# TEST AND FAIL EARLY - can only test after parsing -r input
	[ "$packages" ] && \
		{ echo "-s Packages not available with RouterOS" ; exit 1 ; }

	[ "$fs_type" = "zfs" ] && \
		{ echo "-z ZFS not available with RouterOS" ; exit 1 ; }

	[ -n "$mirror_path" ] && \
			{ echo "-T mirroring not supported" ; exit 1 ; }

# Redundant from FreeBSD/xz - refactor if possible
	[ -d "${work_dir}/${release_name}" ] || \
		mkdir -p "${work_dir}/${release_name}"
	[ -d "${work_dir}/${release_name}" ] || \
		{ echo "mkdir ${work_dir}/${release_name} failed" ; exit 1 ; }

	# Needed for fetch to save the upstream file name
	cd "${work_dir}/${release_name}"

	f_fetch_image "$release_image_file" "$release_image_url"


################
# CUSTOM IMAGE #
################

elif [ -f "$release_input" ] ; then # if a path to an arbitrary image

	# Too complex to address
	[ "$packages" ] && \
	{ echo "-s Packages not available with a custom image" ; exit 1 ; }

	custom_image_file="$( basename $release_input )"

	release_image_file="$release_input"
	custom_image_file="$( basename $release_input )"
	release_name="custom"
	release_type="img"
	# Note that the vmrun.sh "file" test for boot blocks


#####################
# FREEBSD XZ IMAGES #
#####################

else
	# Release version i.e. 15.0-CURRENT
	release_type="xz"
	echo "$release_input" | grep -q "-" || \
		{ echo "Invalid release" ; exit 1 ; }
	echo "$release_input" | grep -q "FreeBSD" && \
		{ echo "Invalid release" ; exit 1 ; }
	release_name="freebsd"
	release_version=$( echo "$release_input" | cut -d "-" -f 1 )
	# Further validate the numeric version?
	release_build=$( echo "$release_input" | cut -d "-" -f 2 )
	case "$release_build" in
		CURRENT|STABLE)
			release_branch="snapshots"
		;;
		*)
			release_branch="releases"
			# This is a false assumption for ALPHA builds
		;;
	esac

# THIS CAN BE A MOVING TARGET
	release_image_url="https://download.freebsd.org/${release_branch}/VM-IMAGES/${release_input}/${cpu_arch}/Latest/FreeBSD-${release_input}-${arch_string}-${fs_type}.raw.xz"

	release_image_file="$( basename $release_image_url )"

	[ -d "${work_dir}/${release_input}" ] || \
		mkdir -p "${work_dir}/${release_input}"
	[ -d "${work_dir}/${release_input}" ] || \
		{ echo "mkdir ${work_dir}/${release_input} failed" ; exit 1 ; }

	# Needed for fetch to save the upstream file name
	cd "${work_dir}/${release_input}"

	f_fetch_image "$release_image_file" "$release_image_url"

release_dist_url="https://download.freebsd.org/${release_branch}/$arch_string/$release_input"

fi # End -r RELEASE HEAVY LIFTING


################################
# HEAVY LIFTING FLAG -t TARGET #
################################

# Default is img which can be user specified, a device under /dev/, or
# a path to a file

echo ; echo Status: Beginning -t target handling

if [ "$target_prefix" = "/dev/" ] ; then

	grow_required=1
	target_type="dev"
	target_dev="$target_input"
	# This is important for distinguishing extra ZFS handling
	attachment_required=1

	if [ -n "$mirror_path" ] ; then
		[ "$mirror_path" = "img" ] && \
			{ echo "-t and -T must both be devices" ; exit 1 ; }

		target_dev2="$mirror_path"

		target_size=$( diskinfo $target_dev | cut -f 3 )
		mirror_size=$( diskinfo $target_dev2 | cut -f 3 )
		if [ "$target_size" -gt "$mirror_size" ] ; then
			echo ; echo Mirror device smaller than target
			exit 1
		fi

		f_cleanse_device $target_dev2
	fi

	# After the size comparison in case the user backs out
	f_cleanse_device $target_dev
else
	target_type="img"

# Used for VM boot scripts but there could be a scenario where release is an
# arbitrary image and the target is a hardware device:  work_dir is not needed

	[ -d "$work_dir" ] || mkdir -p "$work_dir"
	[ -d "$work_dir" ] || { echo "mkdir -p $work_dir failed" ; exit 1 ; }

	if [ -n "$mirror_path" ] ; then
		[ "$mirror_path" = "img" ] || \
			{ echo "-t and -T must both be images" ; exit 1 ; }
	fi

	if [ "$release_name" = "omnios" ] ; then
		fs_type="zfs"
# If not a device and not overridden
		[ "$target_input" = "img" ] && \
		target_path="${work_dir}/omnios-${hw_platform}-${fs_type}.raw"
	elif [ "$release_name" = "debian" ] ; then
		fs_type="ext4"
		[ "$target_input" = "img" ] && \
		target_path="${work_dir}/debian-${hw_platform}-${fs_type}.raw"
	elif [ "$release_name" = "routeros" ] ; then
		fs_type="ext4"
		[ "$target_input" = "img" ] && \
		target_path="${work_dir}/routeros-${hw_platform}-${fs_type}.raw"
	elif [ "$release_name" = "windows" ] ; then
		fs_type="ntfs"
		[ "$target_input" = "img" ] && \
		target_path="${work_dir}/windows-${hw_platform}-${fs_type}.raw"
	elif [ "$release_name" = "custom" ] ; then
		fs_type=""
		[ "$target_input" = "img" ] && \
		target_path="${work_dir}/$custom_image_file"
	else
		# Challenge: FreeBSD does not have a notion of release_name
		# TEST with "path" because that might get inserted
		[ "$target_input" = "img" ] && \
		target_path="${work_dir}/FreeBSD-${hw_platform}-${release_input}-${fs_type}.raw"
	fi

	# Validate parent directory
	[ -d $( dirname "$target_path" ) ] || \
		{ echo "-t directory path does not exist" ; exit 1 ; }
	[ -w $( dirname "$target_path" ) ] || \
		{ echo "-t directory path is not writable" ; exit 1 ; }

	# Overridden by user
	[ "$target_input" = "img" ] || target_path="$target_input"

fi # End -t TARGET HEAVY LIFTING


# Test for default and requested zpool name collisions - must be post-cleanse
if [ "$fs_type" = "zfs" ] ; then
	zpool get name zroot > /dev/null 2>&1 && zroot_in_use=1
	[ "$zroot_in_use" = 1 -a "$zpool_rename" = 0 ] && \
	{ echo ; echo zpool zroot in use and will conflict - use -Z ; exit 1 ; }

	if [ -n "$zpool_newname" ] ; then
		zpool get name $zpool_newname > /dev/null 2>&1 && \
			zpool_newname_in_use=1
	fi

	[ "$zpool_newname_in_use" = 1 -a "$zpool_rename" = 0 ] && \
{ echo zpool $zpool_newname in use and will conflict - use -Z ; exit 1 ; }
fi

# grow_required=1 could have been set by target_type="dev"
# Test is regardless of where it was set
# Want grow for a device but do not need a size as it will use the whole dev

if [ "$grow_required" = 1 ] ; then
	if [ ! "$target_type" = "dev" ] ; then
		[ "$grow_size" ] || { echo "-g size required" ; exit 1 ; }
	fi
fi


###########
# WINDOWS #
###########

echo ; echo Status: Checking iso_file for Windows
if [ "$xml_file" ] && [ "$iso_file" ] ; then

	[ "$vmdk" = 1 ] && \
		{ echo "Windows mode does not support VMDK" ; exit 1 ; }

	# Ignore other unsupported flags at the risk of disappointment
	# This will take care of quite a few of them

	mount_required=0
	attachment_required=0

	which 7z > /dev/null 2>&1 || \
		{ echo "archivers/7-zip package not installed" ; exit 1 ; }
	which mkisofs > /dev/null 2>&1 || \
		{ echo "sysutils/cdrtools package not installed" ; exit 1 ; }
	which xmllint > /dev/null 2>&1 || \
		{ echo "textproc/libxml2 package not installed" ; exit 1 ; }

	[ -d $work_dir/windows/iso ] || mkdir -p $work_dir/windows/iso

	[ -d $work_dir/windows/iso ] || \
		{ echo Making $work_dir/windows/iso failed ; exit 1 ; }

	[ -f $work_dir/windows/iso/autorun.inf ] && \
		rm -rf $work_dir/windows/iso/*	

	# Copy before changing directory and to validate early
	echo ; echo Copying in $work_dir/windows/iso/autounattend.xml
	cp $xml_file $work_dir/windows/iso/autounattend.xml || \
		{ echo $xml_file copy failed ; exit 1 ; }

	echo ; echo Validating $work_dir/windows/iso/autounattend.xml
	xmllint --noout $work_dir/windows/iso/autounattend.xml || 
{ echo $work_dir/windows/iso/autounattend.xml failed to validate ; exit 1 ; }

	cd $work_dir/windows/iso

	echo ; echo Extracting $iso_file to $work_dir/windows/iso with 7z
	7z x $iso_file || { echo UDF extraction failed ; exit 1 ; }

	echo ; ls $work_dir/windows/iso

# Borrowing this convention for now
# TELL THE USER IT BEHAVES DIFFERENTLY - could copy things to the ISO
# and place them in with syntax in autounattend.xml
	if [ "$keep_mounted" = "1" ] ; then
       	echo ; echo Pausing to allow manual configuration in another console
		echo such as copying files to $work_dir/windows/iso
		echo Press any key when ready to re-master the ISO
	        read waiting
	fi

[ -f $work_dir/windows/iso/setup.exe ] || \
        { echo $work_dir/windows/iso/Setup.exe missing ; exit 1 ; }

	echo ; echo Remastering ISO

	mkisofs \
		-quiet \
		-b boot/etfsboot.com -no-emul-boot -c BOOT.CAT \
		-iso-level 4 -J -l -D \
		-N -joliet-long \
		-relaxed-filenames \
		-V "Custom" -udf \
		-boot-info-table -eltorito-alt-boot -eltorito-platform 0xEF \
		-eltorito-boot efi/microsoft/boot/efisys_noprompt.bin \
		-no-emul-boot \
		-o $work_dir/windows/windows.iso $work_dir/windows/iso || \
			{ echo mkisofs failed ; exit 1 ; }

	echo ; echo The resulting ISO image is $work_dir/windows/windows.iso

	cd -

# GENERATE WINDOWS ONE-TIME BOOT SCRIPTS

# Consider a warning that it will be writing to a device
# boot-windows-iso.sh to boot once to the ISO for auto-installation


#########
# BHYVE #
#########

	# Used here and below
	fbuf_string="-s 29,fbuf,tcp=0.0.0.0:5999,w=1024,h=768 -s 30,xhci,tablet"
	cat << HERE > $work_dir/bhyve-windows-iso.sh
#!/bin/sh
[ -e /dev/vmm/$vm_name ] && { bhyvectl --destroy --vm=$vm_name ; sleep 1 ; }
[ -f /usr/local/share/uefi-firmware/BHYVE_UEFI.fd ] || \\
        { echo "BHYVE_UEFI.fd missing" ; exit 1 ; }

kldstat -q -m vmm || kldload vmm
HERE

	if [ "$target_type" = "img" ] ; then
		# Needed now and for later bhyve boot scripts use
		vm_device="$target_path"

	# Note the >> to not overwrite
	cat << HERE >> $work_dir/bhyve-windows-iso.sh
echo ; echo Removing previous $vm_path if present
[ -f $vm_path ] && rm $vm_path

echo ; echo truncating ${grow_size}GB $vm_device
truncate -s ${grow_size}G $vm_device

HERE
	else
		vm_device="$target_dev"
	fi

# Note the >> to not overwrite
	cat << HERE >> $work_dir/bhyve-windows-iso.sh
bhyve -c 2 -m $vm_ram -H -A -D \\
	-l com1,stdio \\
	-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd \\
	-s 0,hostbridge \\
	-s 1,ahci-cd,$work_dir/windows/windows.iso \\
	-s 2,nvme,$vm_device \\
	$network_string \\
        $fbuf_string \\
	-s 31,lpc \\
	$vm_name

sleep 2
bhyvectl --destroy --vm=$vm_name
HERE

	echo Note: $work_dir/bhyve-windows-iso.sh


########
# QEMU #
########

	cat << HERE > $work_dir/qemu-windows-iso.sh
#!/bin/sh
[ -f /usr/local/bin/qemu-system-x86_64 ] || \\
	{ echo qemu-system-x86_64 not found ; exit ; }
[ -f /usr/local/share/edk2-qemu/QEMU_UEFI-x86_64.fd ] || \\
	{ echo edk2-qemu-x64 not found ; exit ; }
HERE

	if [ "$target_type" = "img" ] ; then
		# Needed now and for later bhyve boot scripts use
		vm_device="$target_path"

	# Note the >> to not overwrite
	cat << HERE >> $work_dir/qemu-windows-iso.sh
echo ; echo Removing previous $vm_device if present
[ -f $vm_device ] && rm $vm_device

echo ; echo truncating ${grow_size}GB $vm_device
truncate -s ${grow_size}G $vm_device

HERE
	else
		vm_device="$target_dev"
	fi

	cat << HERE >> $work_dir/qemu-windows-iso.sh
/usr/local/bin/qemu-system-x86_64 -m $vm_ram \\
-bios /usr/local/share/edk2-qemu/QEMU_UEFI-x86_64.fd \\
-cdrom $work_dir/windows/windows.iso \\
-drive file=${vm_device},format=raw \\
-display curses \\
-display vnc=0.0.0.0:0 \\
-usbdevice tablet
HERE

	echo Note: $work_dir/qemu-windows-iso.sh

	echo ; echo "Note $work_dir/bhyve|qemu-windows-iso.sh to boot the VM once for installation, which will be on 0.0.0.0:5999 for VNC attachment for monitoring."

	echo ; echo "Boot the resulting VM with the standard bhyve boot script or your utility of choice. The second boot will apply the configuration and reboot, making it ready for further use."

fi # End Windows handling but we rely on the bhyve boot script generation below


# CHECKS: FAIL EARLY

if [ "$attachment_required" = "1" ] && [ "$target_type" = "img" ] ; then
	mdconfig -lv | grep "$target_path" > /dev/null 2>&1 && \
{ echo "$target_path must be detached with mdconfig -du $md_id" ; exit 1 ; }
fi

if [ "$release_name" = "debian" ] && [ "$grow_required" = "1" ] ; then
	which resize2fs > /dev/null 2>&1 || \
		{ echo "e2fsprogs-core package not installed" ; exit 1 ; }
	kldstat -q -m fusefs || kldload fusefs
	kldstat -q -m fusefs || \
		{ echo fusefs.ko failed to load ; exit 1 ; }
fi


###############################
# IMAGE EXPANSION AND IMAGING #
###############################

echo ; echo Status: Entering case target_type for imaging

case "$target_type" in
	img)
		# Delete existing target image if present
		 [ -f "$target_path" ] && rm "$target_path"

		if [ "$release_input" = "windows" ] ; then
			echo "Preparing Windows ISO and boot script"
		else
			# A cp -p would be ideal for unmodified images
			f_extract "$release_image_file" > "$target_path" || \
		{ echo "$release_image_file extraction failed" ; exit 1 ; }
		fi

# Might not have the ending .raw? .img?
		;; # End image
	dev)
		if [ "$xml_file" ] ; then
			echo "Preparing Windows ISO and boot script"
		else
			if [ "$release_name" = "custom" ] ; then
				# Used for "path" release input
				file_to_extract="$release_input"
			else
#	file_to_extract="${work_dir}/${release_name}/$release_image_file"
	file_to_extract="$release_image_file"
			fi

			f_extract "$file_to_extract" > "$target_dev" || \
				{ echo "Extraction failed" ; exit 1 ; }
				zpool import

				gpart recover $target_dev || \
					{ echo gpart recover failed ; exit 1 ; }
				gpart show -l $target_dev
		fi
	;; # End dev
	
	*) # raw file # release_type="raw" is used for VM script generation
		echo ; echo "Copying $release_image_file to $target_path"
		cp -p "$release_image_file" "$target_path" || \
			{ echo "$release_image_file copy failed" ; exit 1 ; }
		# release_image_file and target_path are both full-path
		echo ; echo "Output boot image is $target_path"
	;;
esac

# Simple "copy" usage and Windows special handling are finished at this point


##########################################################
# ATTACHMENT REQUIRED (More than copying a raw VM image) #
##########################################################

# Image/device attachment is needed for:
# -g Growth required (implied on hardware devices)
# -Z Rename zpool
# -T Mirror zfs device
# -s Add Sources (FreeBSD)
# -m Mount required
# Detected target type device (grow at the file system level for additions)
#	Relable for UFS?
# -x Windows

# Three stages
# Download or locate the source boot image
# Make images and hardware devices equal, unless only an unmodified copy
# Image single or mirrored images or files
# Goal: NO FIRST BOOT STEPS


echo ; echo Status: Checking attachment_required
if [ "$attachment_required" = "1" ] ; then

	if [ "$target_type" = "img" ] ; then

		mdconfig -lv | grep -q "md$md_id" > /dev/null 2>&1 && \
{ echo "md$md_id must be detached with mdconfig -du $md_id" ; exit 1 ; }

		# Truncate larger before attaching
		if [ "$grow_required" = 1 ] ; then
			echo ; echo "Truncating $target_path"
			truncate -s ${grow_size}G "$target_path" || \
				{ echo truncation failed ; exit 1 ; }
		fi

		echo ; echo "Attaching $target_path"
		mdconfig -af "$target_path" -u $md_id || \
			{ echo mdconfig failed ; exit 1 ; }
		mdconfig -lv
		target_dev="/dev/md$md_id"

		gpart recover $target_dev || \
			{ echo gpart recover failed ; exit 1 ; }

		if [ "$release_name" = "omnios" ] ; then
			echo "Deleting the OmniOS solaris-reserved partition"
			gpart delete -i 9 md$md_id || \
				{ echo "gpart delete failed" ; exit 1 ; }
		fi

		mdconfig -lv
		gpart show -l md$md_id
	fi

# FreeBSD /dev/${target_dev}${scheme}N is now dev/img agnostic at this point


	echo ; echo Determining partitioning scheme with gpart
	part_scheme="$( gpart show $target_dev | head -1 | awk '{print $5}' )"

	echo ; echo Partition scheme appears to be $part_scheme

	case "$part_scheme" in
		GPT) scheme="p" ;;
		MBR) scheme="s" ;;
		*)
			echo "Partition scheme detection failed"
			exit 1
		;;
	esac

	# gpart root_fs will fail without relabeling the "linux-data" EFI part
	if [ "$release_name" = "routeros" ] ; then
		echo RouterOS: Relabeling /dev/md${md_id}${scheme}1 
		gpart modify -i 1 -t efi $target_dev || \
			{ echo $target_dev part 1 relabel failed ; exit 1 ; }
	fi

	echo ; echo Determining root file system with gpart
	# root_fs is needed for growth with gpart
	if [ "$( gpart show $target_dev | grep freebsd-ufs )" ] ; then
		root_fs="freebsd-ufs"
		fs_type="ufs"
	elif [ "$( gpart show $target_dev | grep freebsd-zfs )" ] ; then
		root_fs="freebsd-zfs"
		fs_type="zfs"
	elif [ "$( gpart show $target_dev | grep apple-zfs )" ] ; then
		root_fs="apple-zfs"
		fs_type="zfs"
	elif [ "$( gpart show $target_dev | grep linux-data )" ] ; then
		root_fs="linux-data"
		fs_type="ext4"
	# Because, Debian!
	elif [ "$( gpart show $target_dev | grep 4f68bce3-e8cd-4db1-96e7-fbcaf984b709 )" ] ; then
		root_fs="4f68bce3"
		fs_type="ext4"
	else
		echo "Unrecognized root file system"
		exit 1
	fi

	echo ; echo Root file system appears to be $root_fs

	# These should be file system-agnostic at this point
root_part="$( gpart show $target_dev | grep $root_fs | awk '{print $3}' )"
root_dev="${target_dev}p${root_part}"

	if [ "$root_fs" = "freebsd-zfs" -o "$root_fs" = "apple-zfs" ] ; then
		echo ; echo Obtaining zpool name from $root_dev
zpool_name=$( zdb -l $root_dev | grep " name:" | awk '{print $2}' | tr -d "'" )

		echo ; echo Obtaining zpool guid from $root_dev
	zpool_guid=$( zdb -l $root_dev | grep pool_guid | awk '{print $2}' )

	# Needed for fstab handling if attaching and relabeling
		if [ "$release_input" = "freebsd" ] ; then
			mount_required=1
		fi
	fi

# Disk images are now attached memory devices, allowing for identical handling
# Root file system is determined
# If a zpool, its name and guid are determined

fi # End Attachment Required Preflight


##########################
# ROUTEROS UEFI HANDLING #
##########################

# Must come after attachment_required to work on devices
# Must come before growing because of the partition relabeling

# Why on earth do they format their UEFI partition ext4?

if [ "$release_name" = "routeros" ] && [ "$hw_platform" = "amd64" ] ; then

	echo RouterOS: Checking for fuse-ext2
	which fuse-ext2 || { echo fuse-ext2 not found ; exit 1 ; }

	echo RouterOS: Making $work_dir/routeros/uefi if missing
	[ -d $work_dir/routeros/uefi ] || mkdir -p $work_dir/routeros/uefi

	echo RouterOS: Making $work_dir/routeros/mnt if missing
	[ -d $work_dir/routeros/mnt ] || \
		mkdir -p $work_dir/routeros/mnt

	kldstat -q -m fusefs || kldload fusefs
	kldstat -q -m fusefs || \
		{ echo fusefs.ko failed to load ; exit 1 ; }

	echo RouterOS: Mounting /dev/md${md_id}s1
	fuse-ext2 ${target_dev}s1 $work_dir/routeros/mnt || \
		{ echo fuse-ext2 mount failed ; exit 1 ; }
	mount | grep ${target_dev}

	ls $work_dir/routeros/mnt

	echo RouterOS: Copying the EFI partition to $work_dir/routeros/uefi
	cp -rp $work_dir/routeros/mnt/* $work_dir/routeros/uefi/ || \
		{ echo Copy failed ; exit 1 ; }

	echo RouterOS: Unmounting $work_dir/routeros/mnt/
	umount $work_dir/routeros/mnt/ || \
		{ echo Unmount failed ; exit 1 ; }

	echo RouterOS: Creating an msdosfs UEFI partition
	newfs_msdos ${target_dev}${scheme}1 || \
		{ echo newfs_msdos failed ; exit 1 ; }

	echo RouterOS: Mounting the msdosfs partition
	mount_msdosfs ${target_dev}s1 $work_dir/routeros/mnt || \
		{ echo msdosfs mount failed ; exit 1 ; }
	mount | grep ${target_dev}
	ls $work_dir/routeros/mnt

	echo RouterOS: Copying the EFI partition to the mounted partition
	cp -r $work_dir/routeros/uefi/* $work_dir/routeros/mnt/ || \
		{ echo Copy failed ; exit 1 ; }

	echo RouterOS: Unmounting $work_dir/routeros/mnt/
	umount $work_dir/routeros/mnt/ || \
		{ echo Unmount failed ; exit 1 ; }

fi # End RouterOS UEFI configuration


####################
# GROW IF REQUIRED #
####################

echo ; echo Status: Checking grow_required
if [ "$grow_required" = 1 ] ; then

	if [ "$xml_file" ] ; then
		echo "Preparing Windows ISO and boot script"
	else
		echo ; echo "Resizing $root_dev with gpart"
		# Should be file system-agnostic

		gpart resize -i "$root_part" "$target_dev" || \
			{ echo "gpart resize failed" ; exit 1 ; }
		gpart show -l "$target_dev"

		gpart recover $target_dev || \
			{ echo "gpart recover failed" ; exit 1 ; }

		if [ "$root_fs" = "freebsd-ufs" ] ; then
			echo ; echo Growing ${target_dev}p${root_part}
			growfs -y "${target_dev}${scheme}${root_part}" || \
				{ echo "growfs failed" ; exit 1 ; }

			elif [ "$root_fs" = "linux-data" ] ; then
			which resize2fs > /dev/null 2>&1 || \
			{ echo "fusefs-ext2 package not installed" ; exit 1 ; }

			echo ; echo Growing ${target_dev}p${root_part}

			resize2fs "${target_dev}${scheme}${root_part}" || \
				{ echo "resize2fs failed" ; exit 1 ; }
		fi
	fi 
fi # End grow_required


################
# ZFS HANDLING #
################

# The only simple ZFS case was to expand an image to an unmodified boot image

# This is based on the root partitioning type but we know the input
if [ "$fs_type" = "zfs" -a "$attachment_required" = 1 ] ; then

# Defaults: bootfs efiesp|efiboot swapfs rootfs
# Save much potential headache: plan for rootfs0 and rootfs1 being on the host
# and always relabling the partitions if:
# -g Growing - attachement required/relabel required
# -Z Renaming - attachment required/relabel required
# -T Mirroring - attachment required/relabel required - mount required for fstab
# -s Sources - attachment required/relabel required - mount required
# -m Mounting - attachment required - mount required

# LARGELY PREP AS IF MIRRORING BECAUSE OF LABELING, MIRROR FOR MIRRORING

	if [ -n "$mirror_path" ] ; then

# We are sure it is mdconfig attached?
gpart show -l $target_dev

# Assumtion: If the first mirror device is an image, the second will be too

		if [ "$target_type" = "img" ] || [ "$target_type" = "path" ] ; then
			md_id2=$(( $md_id + 1 ))

mdconfig -lv | grep -q "md$md_id2" > /dev/null 2>&1 && \
{ echo ; echo "md$md_id2 must be detached with mdconfig -du $md_id2" ; exit 1 ; }

			# Remove previous mirror image if found
			[ -f ${target_path}.mirror ] && rm ${target_path}.mirror

			# Determine the size of the original image
			mirror_size=$( stat -f %z $target_path )

			echo ; echo Truncating mirror image ${target_path}.mirror
			truncate -s $mirror_size ${target_path}.mirror || \
				{ echo "Mirror truncation failed" ; exit 1 ; }

			echo ; echo "Attaching ${target_path}.mirror"
			mdconfig -af "${target_path}.mirror" -u $md_id2 || \
				{ echo mdconfig failed ; exit 1 ; }
			mdconfig -lv
			target_dev2="/dev/md$md_id2"

		fi # End if type=img or dev

	fi # End if mirror_path PREP of images that are now equally devices

	echo ; echo Relabeling $target_dev

	# Host could have root-on-RaidZ with many similar partitions and devices

	gpart show -l $target_dev | tail -n+2 | grep . \
		| awk '{print $1,$2,$3,$4}' | \
		while read _start _stop _id _label ; do
			_label=$( echo $_label | tr -d "[:digit:]" )
			[ "$_label" = "null" -o "$_label" = "free" ] && break
		gpart modify -i $_id -l ${_label}$label_id1 $target_dev || \
			{ echo $target_dev part $_id relabel failed ; exit 1 ; }
		done
		gpart show -l $target_dev

	if [ -n "$mirror_path" ] ; then

# RECENT FreeBSD
# FYI zpool partition IDs: FreeBSD = 4 OmniOS = 2
# Partition types: FreeBSD = freebsd-zfs OmniOS = apple-zfs
# labels: FreeBSD = zfs0 OmniOS = zfs

##############################################################################
#	NOT mirroring with gpart backup because of that gpt bug
#		echo Mirroring the partition tables with gpart
#		gpart backup $target_dev | gpart restore -lF $target_dev2 || \
#			{ echo "gpart restored failed" ; exit 1 ; }
#	=>      34  20971446  md0  GPT  (10G)
#	=>      34  20971453  md1  GPT  (10G)
##############################################################################

		echo Mirroring the master boot record and GPT
		dd if=$target_dev of=$target_dev2 bs=512 count=3 \
			status=progress conv=sync || \
				{ echo "MBR and GPT dd failed" ; exit 1 ; }

		echo
		echo Recovering the partition table - not using 'gpart backup'
		gpart recover $target_dev2 || \
			{ echo "gpart recover failed" ; exit 1 ; }
		gpart show -l $target_dev2

	# Possibly terrible idea:
		# Mirror the non-root partitions on the fly here
	gpart show -l $target_dev2 | tail -n+2 | grep . \
		| awk '{print $1,$2,$3,$4}' | \
		while read _start _stop _id _label ; do
			_label=$( echo $_label | tr -d "[:digit:]" )
			[ "$_label" = "null" -o "$_label" = "free" ] && break
		gpart modify -i $_id -l ${_label}$label_id2 $target_dev2 || \
			{ echo $target_dev2 $_id relabel failed ; exit 1 ; }
		done
		gpart show -l $target_dev

		# Is there any reason this should be by label or is this safer?
		# That could avoid ${scheme}
		echo Mirroring the first partition
		dd if=${target_dev}${scheme}1 of=${target_dev2}${scheme}1 \
			status=progress conv=sync || \
				{ echo "p${scheme} dd failed" ; exit 1 ; }

		echo ; echo Mirroring the second partition
		dd if=${target_dev}${scheme}2 of=${target_dev2}${scheme}2 \
			status=progress conv=sync || \
				{ echo "p${scheme} dd failed" ; exit 1 ; }

	fi # End mirror_path partition mirroring and relabeling

	# OmniOS pre-excluded
	if [ "$zpool_rename" = 1 ] && [ "$grow_required" = 1 ] ; then
		echo ; echo Importing and expanding zpool with guid $zpool_guid
		zpool import -o autoexpand=on -N -f \
		-d /dev/gpt/rootfs$label_id1 $zpool_guid $zpool_newname || \
			{ echo "$zpool_newname failed to import" ; exit 1 ; }
		zpool_name="$zpool_newname"
		zpool status -v $zpool_name

		zpool online -e $zpool_newname /dev/gpt/rootfs$label_id1 || \
			{ echo "$zpool_newname failed to online -e" ; exit 1 ; }
		zpool_name="$zpool_newname"
		zpool status -v $zpool_name

	# OmniOS pre-excluded
	elif [ "$zpool_rename" = 1 ] ; then
		echo ; echo Importing zpool with new name $zpool_newname
		zpool import -N -f \
		-d /dev/gpt/rootfs$label_id1 $zpool_guid $zpool_newname || \
			{ echo "$zpool_newname failed to import" ; exit 1 ; }
		zpool_name="$zpool_newname"
		zpool status -v $zpool_name

	elif [ "$grow_required" = 1 ] ; then
		echo ; echo Importing and expanding zpool $zpool_name

		if [ "$release_name" = "freebsd" ] ; then
			zpool import -o autoexpand=on -N -f \
				-d /dev/gpt/rootfs$label_id1 $zpool_name || \
			{ echo "$zpool_name failed to import" ; exit 1 ; }
			zpool status -v $zpool_name

			zpool online -e $zpool_name \
				/dev/gpt/rootfs$label_id1 || \
			{ echo "$zpool_name failed to online -e" ; exit 1 ; }
		elif [ "$release_name" = "omnios" ] ; then
			zpool import -o autoexpand=on -N -f rpool || \
			{ echo "rpool failed to import" ; exit 1 ; }

			zpool online -e $zpool_name /dev/md${md_id}p2 || \
			{ echo "rpool online failed" ; exit 1 ; }

# Find a better method than by md_id, but it works
#NOTICE: Performing full ZFS device scan!
#NOTICE: Original /devices path (/pseudo/lofi@1:b) not available; ZFS is trying an alternate path (/pci@0,0/pcifb5d,a0a@2/blkdev@w589CFC20E4BC0001,0:b)
#NOTICE: vdev_disk_open /dev/md42p2: update devid from '<none>' to 'id1,kdev@i589cfc20e4bc0001/b'
#NOTICE: vdev_disk_open /dev/md42p2: update devid from '<none>' to 'id1,kdev@i589cfc20e4bc0001/b'

		else
			echo "$release_name not supported or other error"
			exit 1
		fi
	else
		# Import without expansion or rename
		zpool import -N -f -d /dev/gpt/rootfs$label_id1 $zpool_name || \
			{ echo "$zpool_name failed to import" ; exit 1 ; }
		zpool status -v $zpool_name

		# zpool is imported but not mounted
	fi # End rename and/or grow_required

	zpool list $zpool_name

	echo ; echo Reguiding $zpool_name
	zpool reguid $zpool_name || { echo "zpool reguid failed" ; exit 1 ; }

	if [ ! "$release_name" = "omnios" ] ; then
		echo ; echo Upgrading $zpool_name
		zpool upgrade $zpool_name || \
			{ echo "zpool upgrade failed" ; exit 1 ; }
	fi

	if [ "$zfs_arc_default" = 0 ] ; then
		echo ; echo Setting primarycache=metadata for $zpool_name
		zfs set primarycache=metadata $zpool_name || \
		{ echo "zfs set primarycache=metadata failed" ; exit 1 ; }
	fi

	if [ -n "$mirror_path" ] ; then
		echo ; echo Attaching the mirror device
		echo ; echo Performing a manual label clear to be safe

		# Renaming the pool may find "zroot" despite trying labelclear
		zpool attach -f $zpool_name \
			/dev/gpt/rootfs$label_id1 /dev/gpt/rootfs$label_id2 || \
			{ echo "zpool device attachment failed" ; exit 1 ; }
		zpool status -v $zpool_name

		echo ; echo Waiting 20 seconds for the attachment to complete
		sleep 10
		zpool status -v $zpool_name
		sleep 10
		zpool status -v $zpool_name
		echo ; echo Consider a zpool scrub

	fi # End mirror_path

	zpool status -v "$zpool_name"

zpool list

	echo ; echo "Exporting $zpool_name"
	zpool export $zpool_name || \
		{ echo "$zpool_name failed to export" ; exit 1 ; }

zpool list

fi # End ZFS HANDLING


###################################
# LOL ROUTEROS RELABELING TO BOOT #
###################################

if [ "$release_name" = "routeros" ] ; then
	echo "RouterOS: Relabeling /dev/md${md_id}${scheme}1"
	gpart modify -i 1 -t linux-data $target_dev || \
		{ echo "$target_dev part 1 relabel failed" ; exit 1 ; }
fi


#######################
# MUST MOUNT HANDLING #
#######################

# Recall that advanced preparation was required and would have
# prepared memory devices, detected file systems  etc.

echo ; echo Status: Checking mount_required
if [ "$mount_required" = 1 ] ; then

	mount | grep "on ${mount_point:?}" && \
		{ echo "${mount_point:?} mount point in use" ; exit 1 ; }

	if [ "$root_fs" = "freebsd-ufs" ] ; then
		mount $root_dev ${mount_point:?} || \
			{ echo "mount failed" ; exit 1 ; }

	elif [ "$root_fs" = "linux-data" ] ; then
		kldstat -q -m fusefs || kldload fusefs
		kldstat -q -m fusefs || \
			{ echo fusefs.ko failed to load ; exit 1 ; }
		fuse-ext2 $root_dev ${mount_point:?} -o rw+ || \
			{ echo "$root_dev fuse-ext2 mount failed" ; exit 1 ; }

#	elif [ "$root_fs" = "freebsd-zfs" ] ; then
	elif [ "$fs_type" = "zfs" ] ; then

		echo ; echo "Importing zpool $zpool_name for mounting"
		# Device path not required
		zpool import -R ${mount_point:?} $zpool_name || \
			{ echo "$zpool_name failed to import" ; exit 1 ; }
		zpool status -v $zpool_name

		# Might not have been mouting the root dataset which is
		# set to canmount=noauto

		zfs mount ${zpool_name}/ROOT/default || \
		{ echo "${zpool_name}/ROOT/default failed to mount" ; exit 1 ; }

		echo ; echo Mounting child datasets
                # Syntax from propagate.sh for fully-nested datasets
                # Inspired by /etc/rc.d/zfsbe
                zfs list -rH -o mountpoint,name,canmount,mounted \
                        -s mountpoint ${zpool_name} | \
                while read _mp _name _canmount _mounted ; do
                        [ "$_mp" = "none" ] && continue
                        [ "$_name" = "$target_input" ] && continue
                        [ "$_canmount" = "off" ] && continue
                        [ "$_mounted" = "yes" ] && continue
			zfs mount $_name
                done

		if [ -f ${mount_point:?}/etc/fstab ] ; then
			echo ; echo Updating fstab
			cp ${mount_point:?}/etc/fstab \
				${mount_point:?}/etc/fstab.original
efi_label=$( grep efiboot ${mount_point:?}/etc/fstab | awk '{print $1}' | cut -d / -f 4  )
swap_label=$( grep swap ${mount_point:?}/etc/fstab | awk '{print $1}' | cut -d / -f 4  )
			sed -i -e "s/$swap_label/swapfs$label_id1/g" \
				${mount_point:?}/etc/fstab

			sed -i -e "s/$efi_label/efiboot$label_id1/g" \
				${mount_point:?}/etc/fstab

			echo ; echo Mounting EFI partition
			mount_msdosfs /dev/gpt/efiboot$label_id1 \
				${mount_point:?}/boot/efi || \
					{ echo "EFI mount failed" ; exit 1 ; }
		else
			echo ; echo "Creating empty fstab"
			touch ${mount_point:?}/etc/fstab
		fi

			echo ; echo "${mount_point:?}/etc/fstab reads:" 
			cat ${mount_point:?}/etc/fstab

		# YEP, we want an auto-swapper and maybe
		# a utility to mount the EFI partition for updating

		if [ $zpool_newname ] ; then
			# Must be double quotes for variable expansion
# DEBUG: sed: -I or -i may not be used with stdin
			sed -i -e "s/zroot/$zpool_newname/g" \
				${mount_point:?}/etc/rc.conf
		fi
	else
		echo "Unrecognized root file system"
		exit 1
	fi # End if root_fs


####################
# PACKAGE HANDLING #
####################

#########################
# POSSIBLE UPSTREAM BUG #
#########################

# Installing FreeBSD-set-src or one of its members appear to install but fail
# The written property does not increase, snapshotting and fsync do not help
# du -h -d1 output prior to unmounting:
# 400M	/media/usr/src/sys
# zfs get used output:
#NAME           PROPERTY  VALUE  SOURCE
#zroot/usr/src  used      420K   -

# Workaround:
zfs destroy ${zpool_name}/usr/src
zfs create ${zpool_name}/usr/src

	# Separating from selecting new packages to install
	if [ "$copy_package_cache" = "1" ] ; then
		echo ; echo "Copying /var/cache/pkg/ packages from the host"

		# NOT INCLUDED IN THE UPSTREAM IMAGE
		[ -d "${mount_point:?}/var/cache/pkg" ] || \
			mkdir -p "${mount_point:?}/var/cache/pkg"

		[ -d "${mount_point:?}/var/cache/pkg" ] || \
	{ echo "mkdir ${mount_point:?}/var/cache/pkg/ failed" ; exit 1 ; }

		cp /var/cache/pkg/* "${mount_point:?}/var/cache/pkg/" || \
			{ echo "Package copy failed" ; exit 1 ; }
	fi

	# Must mount would already be set
	if [ -n "$packages" ] ; then

		[ -f ${mount_point:?}/var/db/pkg/local.sqlite ] || \
			{ echo Target is not package bootstrapped ; exit 1 ; }

		[ -d ${mount_point:?}/usr/local/etc/pkg/repos ] || \
			mkdir -p ${mount_point:?}/usr/local/etc/pkg/repos

# Handled by RE
#		echo "Enabling base package repo"
#		echo "FreeBSD-base: { enabled: yes }" > \
#		${mount_point:?}/usr/local/etc/pkg/repos/FreeBSD-base.conf

		# Pulled from propagate.sh
		release_version=$( echo "$release_input" | cut -d "-" -f 1 )
		VERSION_MAJOR=$( echo "$release_version" | cut -d "." -f 1 )
		ABI="FreeBSD:${VERSION_MAJOR}:$cpu_arch"

		echo ; echo "Installing pkg"
		pkg \
			--option ABI="${ABI:?}" \
			--rootdir "${mount_point:?}" \
			--repo-conf-dir "${mount_point:?}/etc/pkg" \
			--option IGNORE_OSVERSION="yes" \
			install -y -- pkg || \
				{ echo "pkg install failed" ; exit 1 ; }

# Consider a package upgrade here if using RELEASE images!

		echo ; echo "Temporarily enabling base repo in /etc/pkg"
		sed -i -e "s/enabled: no/enabled: yes/g" \
			${mount_point:?}/etc/pkg/FreeBSD.conf

		echo ; echo "Updating existing base packages"
		pkg \
			--option ABI="${ABI:?}" \
			--rootdir "${mount_point:?}" \
			--repo-conf-dir "${mount_point:?}/etc/pkg" \
			--option IGNORE_OSVERSION="yes" \
			upgrade -y || \
				{ echo "Package upgrade failed" ; exit 1 ; }

		# Consider backing up FreeBSD.conf and restoring it
		echo ; echo "Installing $packages"
		pkg \
			--option ABI="${ABI:?}" \
			--rootdir "${mount_point:?}" \
			--repo-conf-dir "${mount_point:?}/etc/pkg" \
			--option IGNORE_OSVERSION="yes" \
			install -y $packages || \
				{ echo "Package install failed" ; exit 1 ; }

		# Consider backing up FreeBSD.conf and restoring it
		echo ; echo "Temporarily disabling base repo in /etc/pkg"
		sed -i -e "s/enabled: yes/enabled: no/g" \
			${mount_point:?}/etc/pkg/FreeBSD.conf
		echo ; echo "It is enabled in /usr/local/etc/pkg/repos"
	fi # End packages


#############
# ADD USERS #
#############

	if [ "$add_users" = 1 ] ; then

# Do we want the chroots of the original script?
# No. It will fail when installing to other architectures
# Pulling from release/tools/arm.sub arm_create_user() and vagrant.conf

# Only works on new users?
#       /usr/sbin/pw -R ${mount_point:?} usermod root -w yes

		# Pulling from rc.local.sh
		echo ; echo Setting root password
 		echo -n 'root' | /usr/sbin/pw -R ${mount_point:?} \
			usermod -n root -h 0

		echo ; echo Adding user freebsd
	        mkdir -p ${mount_point:?}/home/freebsd
		/usr/sbin/pw -R ${mount_point:?} groupadd freebsd -g 1001

# Note that csh is not installed by default, changing to /bin/sh
	        /usr/sbin/pw -R ${mount_point:?} useradd freebsd \
			-m -M 0755 -w yes -n freebsd -u 1001 -g 1001 -G 0 \
			-c 'FreeBSD User' -d '/home/freebsd' -s '/bin/sh'

		echo ; echo "Enabling sshd"
		echo 'sshd_enable="YES"' >> ${mount_point:?}/etc/rc.conf
	fi # End users


########################
# ENABLE CRASH DUMPING #
########################

	if [ "$enable_crash_dumping" = "1" ] ; then

		echo ; echo "Enabling debug.debugger_on_panic=1"
		echo "debug.debugger_on_panic=1" >> \
			${mount_point:?}/etc/sysctl.conf || \
			{ echo "Failed to configure sysctl.conf" ; exit 1 ; }
		echo ; echo "Crash dumping can be tested with:"
		echo "sysctl debug.kdb.panic=1"

		# NOT USING sysrc as it depends on platform-dependent chroot
#		if [ ! $(sysrc -R ${mount_point:?} -c dumpdev) ] ; then
#			echo ; echo "dumpdev not enabled in /etc/rc.conf"
#			echo "Enabling dumpdev=\"AUTO\""
#			sysrc -R ${mount_point:?} dumpdev=AUTO || \
#				{ echo "sysrc dumpdev=AUTO failed" ; exit 1 ; }
#		fi
			# KLUGE for now, may result in duplicate entries
			# Work out grep with string containing quotation marks
			echo "dumpdev=\"AUTO\"" >> ${mount_point:?}/etc/sysctl.conf || \
				{ echo "dumpdev enable failed" ; exit 1 ; }
	fi
fi # End mount_required


#########################
# OPTIONAL VMDK WRAPPER #
#########################

# These would want mirroring support but that would be a leap of faith
# if the mirroring has not been performed yet
# How would this behave if a hardware device was provided?

if [ "$vmdk" = 1 ] ; then
	vmdk_image="$target_path"
	vmdk_image_base="${vmdk_image%.raw}"

	# Assuming blocksize of 512
	size_bytes="$( stat -f %z "$vmdk_image" )"
	RW=$(( "$size_bytes" / 512 ))
	cylinders=$(( "$RW" / 255 / 63 ))

	cat << HERE > "$work_dir/${vmdk_image_base}.vmdk"
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
HERE

	echo ; echo Renaming "$vmdk_image" to "${vmdk_image_base}-flat.vmdk"
	mv "$vmdk_image" "${vmdk_image_base}-flat.vmdk"
fi


################
# BOOT SCRIPTS #
################

echo ; echo Status: Checking boot_scripts
if [ "$boot_scripts" = 1 ] ; then

# One could pull from /usr/obj and point at a hardware device
# which would not create a working directory
	[ -d "$work_dir" ] || mkdir -p "$work_dir"
	[ -d "$work_dir" ] || { echo "mkdir -p $work_dir failed" ; exit 1 ; }

	if [ -n "$target_path" ] ; then
		if [ "$vmdk" = 1 ] ; then
			vm_device="${vmdk_image_base}-flat.vmdk"
		else
			vm_device="$target_path"
		fi
	elif [ "$target_dev" ] ; then
		vm_device="$target_dev"
	elif [ "$release_name" = "windows" ] ; then
		echo "Preparing Windows ISO and boot script"
	else
		echo "Something went wrong"
		exit 1
	fi


#########
# BHYVE #
#########

	case "$hw_platform" in
		amd64|i386)

			if [ "$release_name" = "custom" ] ; then
				# Used for "path" release input
				bhyve_script="bhyve-${custom_image_file}.sh"
			else
	bhyve_script="bhyve-${release_input}-${hw_platform}-${fs_type}.sh"
			fi

if [ -n "$mirror_path" ] ; then
	case "$target_type" in
	img)
	storage_string="-s 2,nvme,$vm_device -s 3,nvme,${target_path}.mirror"
	;;
	dev)
		storage_string="-s 2,nvme,$vm_device -s 3,nvme,$target_dev2"
	;;
	*)
		echo Something went wrong
		exit 1
	;;
	esac
else
	storage_string="-s 2,nvme,$vm_device"
fi

			cat << HERE > "${work_dir}/$bhyve_script"
#!/bin/sh
[ \$( id -u ) = 0 ] || { echo "Must be root" ; exit 1 ; } 
[ -e /dev/vmm/$vm_name ] && { bhyvectl --destroy --vm=$vm_name ; sleep 1 ; }
[ -f /usr/local/share/uefi-firmware/BHYVE_UEFI.fd ] || \\
	{ echo \"BHYVE_UEFI.fd missing\" ; exit 1 ; }

kldstat -q -m vmm || kldload vmm
sleep 1

bhyve -c $vm_cores -m $vm_ram -A -H -l com1,stdio -s 31,lpc -s 0,hostbridge \\
	-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd \\
	$storage_string \\
        $fbuf_string \\
	$network_string \\
        $vm_name

# Devices to consider:

# -s 4,virtio-net,tap0 \\
# -s 4,e1000,tap0 \\

sleep 2
bhyvectl --destroy --vm=$vm_name
reset
HERE
			echo Note: $work_dir/$bhyve_script


########
# QEMU #
########

			if [ "$custom_image_file" ] ; then
				qemu_script="qemu-${custom_image_file}.sh"
			else
		qemu_script="qemu-${release_input}-${hw_platform}-${fs_type}.sh"
			fi

# DEBUG: QEMU needs help when used with hardware devices
#+ qemu_script=qemu-/tmp/propagate/src/release/scripts/vm.zfs.img-amd64-zfs.sh
#+ storage_string='-drive file=/dev/da4,format=raw -drive file=.mirror,format=raw'
#imagine.sh: cannot create /root/imagine-work/qemu-/tmp/propagate/src/release/scripts/vm.zfs.img-amd64-zfs.sh: No such file or directory

if [ -n "$mirror_path" ] ; then
	storage_string="-drive file=${vm_device},format=raw -drive file=${target_path}.mirror,format=raw"
else
	storage_string="-drive file=${vm_device},format=raw"
fi
			cat << HERE > $work_dir/$qemu_script
#!/bin/sh
[ -f /usr/local/bin/qemu-system-x86_64 ] || \\
	{ echo qemu-system-x86_64 not found ; exit ; }
[ -f /usr/local/share/edk2-qemu/QEMU_UEFI-x86_64.fd ] || \\
	{ echo edk2-qemu-x64 not found ; exit ; }
/usr/local/bin/qemu-system-x86_64 -m $vm_ram \\
-bios /usr/local/share/edk2-qemu/QEMU_UEFI-x86_64.fd \\
$storage_string \\
-nographic \\
--no-reboot
HERE

			echo Note: $work_dir/$qemu_script


#######
# XEN #
#######

# DEBUG: Need help with mirrored hardware devices
# imagine.sh: cannot create /root/imagine-work/xen-/tmp/propagate/src/release/scripts/vm.zfs.img-amd64-zfs.cfg: No such file or directory
#imagine.sh: cannot create /root/imagine-work/xen-/tmp/propagate/src/release/scripts/vm.zfs.img-amd64-zfs.sh: No such file or directory
#imagine.sh: cannot create /root/imagine-work/xen-/tmp/propagate/src/release/scripts/vm.zfs.img-amd64-zfs.sh: No such file or directory

# Should be conditional to not generate if mirrored
# Solution appears to be two comma-separated strings in "disk"

# DEBUG YOU SURE THIS IS A THING?
			if [ "$custom_image_file" ] ; then
				qemu_script="qemu-${custom_image_file}.sh"
				xen_cfg="xen-${custom_image_file}.cfg"
				xen_script="xen-${custom_image_file}.sh"
			xen_destroy="xen-destroy-${custom_image_file}.sh"

			else
	xen_cfg="xen-${release_input}-${hw_platform}-${fs_type}.cfg"
	xen_script="xen-${release_input}-${hw_platform}-${fs_type}.sh"
	xen_destroy="xen-destroy-${release_input}-${hw_platform}-${fs_type}.sh"
			fi

			cat << HERE > $work_dir/$xen_cfg
type = "hvm"
memory = $vm_ram
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


			echo "xl list | grep $vm_name && xl destroy $vm_name" \
				> $work_dir/$xen_script
			echo "xl create -c $work_dir/$xen_cfg" \
				>> $work_dir/$xen_script

			echo "xl shutdown $vm_name ; xl destroy $vm_name ; xl list" > \
				$work_dir/$xen_destroy

			echo Note: $work_dir/$xen_script
		;;

		arm64)
			bhyve_script=bhyve-${release_input}-${hw_platform}-${fs_type}.sh

                        cat << HERE > "${work_dir}/$bhyve_script"
#!/bin/sh
[ \$( id -u ) = 0 ] || { echo "Must be root" ; exit 1 ; }
[ -e /dev/vmm/$vm_name ] && { bhyvectl --destroy --vm=$vm_name ; sleep 1 ; }
[ -f /usr/local/share/u-boot/u-boot-bhyve-arm64/u-boot.bin ] || \\
        { echo \"u-boot-bhyve-arm64 not installed\" ; exit 1 ; }

kldstat -q -m vmm || kldload vmm
sleep 1
# GENERATE THIS ABOVE
bhyve -c $vm_cores -m $vm_ram -o console=stdio \\
        -o bootrom=/usr/local/share/u-boot/u-boot-bhyve-arm64/u-boot.bin \\
        -s 2,virtio-blk,$vm_device \\
        $vm_name

# Devices to consider:

# -s 4,virtio-net,tap0 \\
# -s 4,e1000,tap0 \\

sleep 2
bhyvectl --destroy --vm=$vm_name
reset
HERE
			echo Note: $work_dir/$bhyve_script

			qemu_script=qemu-${release_input}-${hw_platform}-${fs_type}.sh

			cat << HERE > $work_dir/$qemu_script
#!/bin/sh
[ -f /usr/local/bin/qemu-system-aarch64 ] || \
	{ echo qemu package not installed ; exit 1 ; }
[ -f /usr/local/share/u-boot/u-boot-qemu-arm64/u-boot.bin ] || \\
{ echo \"u-boot-qemu-arm64 package not installed\" ; exit 1 ; }
# pkg install qemu u-boot-qemu-arm64
/usr/local/bin/qemu-system-aarch64 -m $vm_ram \\
-cpu cortex-a57 -M virt \\
-drive file=${vm_device},format=raw \\
-bios /usr/local/share/u-boot/u-boot-qemu-arm64/u-boot.bin \\
-nographic \\
--no-reboot
HERE
			echo Note: $work_dir/$qemu_script
		;;

		riscv)
			qemu_script=qemu-${release_input}-${hw_platform}-${fs_type}.sh

			cat << HERE > $work_dir/$qemu_script
#!/bin/sh
[ -f /usr/local/bin/qemu-system-riscv64 ] || \
	{ echo qemu-system-riscv64 missing ; exit 1 ; }
[ -f /usr/local/share/opensbi/lp64/generic/firmware/fw_jump.elf ] || \\
	{ echo "opensbi and u-boot-qemu-riscv64 packages not instsalled" ; exit 1 ; }

/usr/local/bin/qemu-system-riscv64 -machine virt -m $vm_ram -nographic \\
-bios /usr/local/share/opensbi/lp64/generic/firmware/fw_jump.elf \\
-kernel /usr/local/share/u-boot/u-boot-qemu-riscv64/u-boot.bin \\
-drive file=${vm_device},format=raw,id=hd0 \\
-device virtio-blk-device,drive=hd0
HERE
			echo Note: $work_dir/$qemu_script
		;;
	esac
fi # End boot scripts


##################################
# UNMOUNT OR REMIND OF THE MOUNT #
##################################

echo ; echo Status: Checking keep_mounted and mount_required on the way out
if [ "$keep_mounted" = 0 ] ; then
	# Confirm the checks
	if [ "$mount_required" = 1 ] ; then
		# Putting this here in case someone does something clever
		if [ "$clean_package_cache" = 1 ] ; then
			echo ; echo "Cleaning ${mount_point:?}/var/cache/pkg/"
			find -s -f "${mount_point:?}/var/cache/pkg/" \
				-- -mindepth 1 -delete
		fi

		if [ "$root_fs" = "freebsd-ufs" ] ; then
			echo ; echo "Unmounting ${mount_point:?}"
			umount ${mount_point:?} || \
				{ echo "umount failed" ; exit 1 ; }
			# Going from custom image to a hardware device might
			# skip work_dir, no? Where would a umount script go?
#			echo ; echo "Generating ${mount_point:?} umount script"
#echo "umount ${mount_point:?} || { echo umount failed ; exit 1 ; }" > 

		elif [ "$fs_type" = "zfs" ] ; then
			# Trying to do the right thing rather than export -f
			# The EFI partition will not be caught by that and will
			# trip up the dataset umount - umount EFI first
		echo ; echo "Unmounting child datasets and directories"
		# Just in case
		sleep 3
		umount $(mount|grep "on $mount_point"|grep efi|cut -w -f 1) || \
			{ echo "umount EFI partition failed" ; exit 1 ; }

		mount | grep "on $mount_point" | cut -w -f 1 | \
        	       	while read _mp ; do
				umount $_mp || \
					{ echo "umount $_mp failed" ; exit 1 ; }
			done

			echo ; echo "Exporting $zpool_name"
			echo ; echo "Sleeping 10 seconds to be safe"
			sleep 10
			zpool export $zpool_name || \
				{ echo "zpool export failed" ; exit 1 ; }
		fi

	fi # End mount_required

	if [ "$attachment_required" = 1 ] ; then
		if [ "$target_type" = "img" ] ; then
			echo ; echo "Destroying $target_dev"
			mdconfig -du $md_id || \
	{ echo "$target_dev mdconfig -du failed" ; mdconfig -lv ; exit 1 ; }

			if [ -n "$mirror_path" ] ; then
				echo ; echo "Destroying $target_dev2"
				mdconfig -du "$md_id2"
			fi
		fi
	fi # End attachment_required
else
	# Prompt the user with how to unmount
	if [ "$root_fs" = "freebsd-ufs" ] ; then
		# Consider printf
		echo : echo Unmount child directories and datasets and 
		echo run 'umount ${mount_point:?}' when finished
	fi

#	if [ "$root_fs" = "freebsd-zfs" -o "$root_fs" = "apple-zfs" ] ; then
	if [ "$fs_type" = "zfs" ] ; then
		echo ; echo "Run 'zpool export $zpool_name' when finished"
	fi

	if [ "$target_type" = "img" ] ; then
		echo "Run 'mdconfig -du $md_id' when finished"
		if [ -n "$mirror_path" ] ; then
			echo ; echo "Run 'mdconfig -du $md_id2' when finished"
		fi
	fi
fi # End keep_mounted

# Could be very helpful when round-tripping disk images and physical devices
if [ ! "$release_name" = "windows" ] ; then
	if [ "$target_type" = "img" ] ; then
		echo ; echo "Saving off image size as ${target_path}.size"
		stat -f %z $target_path > ${target_path}.size || \
			{ echo image size stat failed ; exit 1 ; }
	fi
fi
