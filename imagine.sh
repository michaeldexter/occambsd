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

# Version v.0.5.0beta

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
# The canonical /media temporary mount point is hard-coded for now.
# The canonical /usr/src directory is hard-coded when using -r obj or a path.
# 'fetch -i' only checks date stamps, allow for false matches on interrupted downloads.
# Xen boot scripts do not support mirrored devices yet
# Running imagine.sh in the working directory will cause existing release versions to be misinterpreted as image paths to be copied.
# This will clean up previous images but not boot scripts.
# /etc/fstab is moved to fstab.original and replaced with an empty file on any
# runs that include advanced zpool handling


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
# sh imagine.sh -a riscv -r 14.0-RELEASE -z -g 10 -b
#
# Add '-v' to generate a VMDK that is VMware compatible, because you can


# USAGE

f_usage() {
	echo ; echo "USAGE:"
	echo "-w <working directory> (Default: /root/imagine-work)"
	echo "-a <architecture> [ amd64 | arm64 | i386 | riscv ] (Default: Host)"
	echo "-r [ obj | /path/to/image | <version> | omnios | debian ]"

# HOW ARE obj and path any different? ONE TRIGGERS SRC - obj calculates the
# object directory path, for better or for worse

	echo "obj i.e. /usr/obj/usr/src/<target>.<target_arch>/release/vm.ufs.raw"
	echo "/path/to/image.raw for an existing image"
	echo "<version> i.e. 14.0-RELEASE | 15.0-CURRENT | 15.0-ALPHAn|BETAn|RCn"
	echo "-o (Offline mode to re-use fetched releases and src.txz)"
	echo "-t <target> [ img | /dev/device | /path/myimg ] (Default: img)"
	echo "-T <mirror target> [ img | /dev/device ]"
	echo "-f (FORCE imaging to a device without asking)"
	echo "-g <gigabytes> (grow image to gigabytes i.e. 10)"
	echo "-s (Include src.txz or /usr/src as appropriate)"
	echo "-m (Mount image and keep mounted for further configuration)"
	echo "-v (Generate VMDK image wrapper)"
	echo "-b (Generate VM boot scripts)"
	echo "-z (Use a 14.0-RELEASE or newer root on ZFS image)"
	echo "-Z <new zpool name>"
	echo "-x <autounattend.xml file for Windows> (Requires -i and -g)"
	echo "-i <Installation ISO file for Windows> (Requires -x and -g)"
	echo
	exit 0
}


# INTERNAL VARIABLES AND DEFAULTS

work_dir=~/imagine-work		# Default - fails if quoted
hw_platform=$( uname -m )	# i.e. arm64
cpu_arch=$( uname -p )		# i.e. aarch64
arch_string=""
release_input=""
offline_mode=0
release_type=""
release_name=""
release_image_url=""
release_image_file=""
#release_image_xz=""
release_branch=""
fs_type="ufs"
omnios_amd64_url="https://us-west.mirror.omnios.org/downloads/media/stable/omnios-r151050.cloud.raw.zst"

debian_amd64_url="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-amd64.raw"
debian_arm64_url="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-arm64.raw"
#debian_amd64_url="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.raw"
#debian_arm64_url="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-arm64.raw"

routeros_amd64_url="https://download.mikrotik.com/routeros/7.15.3/chr-7.15.3.img.zip"
routeros_arm64_url="https://download.mikrotik.com/routeros/7.15.3/chr-7.15.3-arm64.img.zip"

attachment_required=0
root_fs=""
root_part=""
root_dev=""
scheme=""
root_part=""
zpool_name=""
zpool_rename=""
zpool_newname=""
#target_input="raw"		# Default not helpful if -x
target_input="img"		# Default not helpful if -x
target_dev=""
target_dev2=""
target_type=""
target_path=""
target_prefix=""
target_size=""
mirror_path=""
mirror_size=""
force=0
grow_required=0
grow_size=""
include_src=0
mount_required=0
keep_mounted=0
xml_file=""
iso_file=""
vmdk=0
boot_scripts=0
vm_device=""
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


# USER INPUT AND VARIABLE OVERRIDES

while getopts w:a:r:zZ:t:T:ofg:smvbx:i: opts ; do
	case $opts in
	w)
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

	z)
		# Set for download, only modify if getting fancy
		fs_type="zfs"
		# Not attachment_required if only copying to an image file 
	;;

	t)
		[ "$( id -u )" = 0 ] || { echo "Must be root" ; exit 1 ; } 
		[ "$OPTARG" ] || f_usage
		target_input="$OPTARG"
		target_prefix=$( printf %.5s "$target_input" )
	;;
	f)
		# Write to a device without prompting for confirmation
		force=1
	;;

	v)
		# Could simply add a wrapper to an existing image
		vmdk=1
	;;

	b)
		# root required to execute bhyve and Xen boot scripts
		boot_scripts=1
	;;

	g)
		grow_required=1
		grow_size="$OPTARG"
		# Implied numeric validation
		[ "$grow_size" -gt 7 ] || \
			{ echo "-g must be a number larger than 7" ; exit 1 ; }
		attachment_required=1
	;;

	Z)
		[ "$( id -u )" = 0 ] || { echo "Must be root" ; exit 1 ; } 
		zpool_newname="$OPTARG"
		# Consider validation
		# Implying this for use as shorthand
		fs_type="zfs"
		zpool_rename=1
		attachment_required=1
	;;

	T)
		[ "$( id -u )" = 0 ] || { echo "Must be root" ; exit 1 ; } 
		[ "$OPTARG" ] || f_usage
		mirror_path="$OPTARG"
		[ "$mirror_path" = "img" ] || [ -c "$mirror_path" ] || \
			{ echo "Likely invalid -T input" ; exit 1 ; }
		# Mounting is required for fstab modifications
		mount_required=1
		attachment_required=1
	;;

	s)
		[ "$( id -u )" = 0 ] || { echo "Must be root" ; exit 1 ; } 
		include_src=1
		grow_required=1
		mount_required=1
		attachment_required=1
	;;

	m)
		# root required to mount the image for extracting in src.txz
		mount_required=1
		keep_mounted=1
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
		release_input="windows" # Mutually exclusive  with release_input
		framebuffer_required=1
		target_type="oneboot"
		fs_type="ntfs"
	;;

	i)
		iso_file="$OPTARG"
		[ -r "$iso_file" ] || \
			{ echo "$iso_file missing or unreadable" ; exit 1 ; }
		target_type="oneboot"
	;;

	*)
		f_usage
	;;
	esac
done

# Get the hardware device write warnings out of the way early

if [ "$target_prefix" = "/dev/" ] ; then
	[ -c "$target_input" ] || { echo "$target_input not found" ; exit 1 ; }
	if [ "$force" = 0 ] ; then
		echo "WARNING! Writing to $target_input !"
		diskinfo -v $target_input
		echo -n "Continue? (y/n): " ; read confirmation
		[ "$confirmation" = "y" ] || exit 0
	fi
fi

if [ "$mirror_path" ] && [ "$mirror_path" = "img" ] ; then
	[ -c "$mirror_path" ] || { echo "$mirror_path not found" ; exit 1 ; }
	if [ "$force" = 0 ] ; then
		echo "WARNING! Writing to $mirror_path !"
		diskinfo -v $mirror_path
		echo -n "Continue? (y/n): " ; read confirmation2
		[ "$confirmation2" = "y" ] || exit 0
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

# Needed for ZFS fstab sins
if [ "$fs_type" = "zfs" ] && [ "$grow_required" = 1 ] ; then
	mount_required=1
fi

if [ "$fs_type" = "ufs" ] && [ -n "$mirror_path" ] ; then
	echo Device mirroring only works with ZFS
fi

# TESTS - FAIL EARLY

if [ $zpool_newname ] ; then
	zpool get name $zpool_newname > /dev/null 2>&1 && \
{ echo zpool $zpool_newname in use and will conflict - use -Z ; exit 1 ; }
fi

if [ "$target_prefix" = "/dev/" ] ; then
	[ "$vmdk" = 0 ] || { echo "-v does not support devices" ; exit 1 ; }
fi

if [ "$xml_file" ] ; then
	[ "$iso_file" ] || { echo "-x requires -i" ; exit 1 ; }
	[ "$include_src" = 0 ] || { echo "-s not supported with -x" ; exit 1 ; }
	# Disable this as a second boot does the installation
	grow_required=0
	[ "$target_input" ] || \
		target_input="${work_dir}/windows-${hw_platform}-${fs_type}.raw"
fi

if [ "$iso_file" ] ; then
	[ "$xml_file" ] || { echo "-i requires -x" ; exit 1 ; }
fi

[ -n "$release_input" ] || [ -n "$xml_file" ] || \
	{ echo "-r <release> or -x/-i are required" ; f_usage ; exit 1 ; }

f_fetch_image () # $1 release_image_file $2 release_image_url
{
	# fetch is not idempotent - check if exists before with fetch -i
	if [ -r "$1" ] ; then
		if [ "$offline_mode" = 0 ] ; then
			cp $1 ${1}.previous
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
	zpool labelclear "$1" >/dev/null 2>&1

	echo Clearing partitions from $1
	gpart recover "$1"
	gpart destroy -F "$1"
	gpart create -s gpt "$1"
	gpart destroy -F "$1"

#	Required to avoid corrupt zpool metadata (!)
	dd if=/dev/zero of=$1 bs=1m count=1 # 1048576 bytes
	dd if=/dev/zero of=$1 bs=1m oseek=`diskinfo $1 \
		| awk '{print int($3 / (1024*1024)) - 4;}'`
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
	[ "$include_src" = 1 ] && \
		{ echo "-s src not available with OmniOS images" ; exit 1 ; }

	[ "$zpool_rename" = 0 ] || \
		{ echo "-Z renaming not yet supported" ; exit 1 ; } 

	[ -n "$mirror_path" ] && \
		{ echo "-T mirroring not yet supported" ; exit 1 ; }

	release_image_url="$omnios_amd64_url"
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
	[ "$include_src" = 1 ] && \
		{ echo "-s src not available with Debian images" ; exit 1 ; }

	[ "$fs_type" = "zfs" ] && \
		{ echo "-z ZFS not available with Debian images" ; exit 1 ; }

	[ -n "$mirror_path" ] && \
			{ echo "-T mirroring not supported" ; exit 1 ; }

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
	[ "$include_src" = 1 ] && \
		{ echo "-s src not available with RouterOS images" ; exit 1 ; }

	[ "$fs_type" = "zfs" ] && \
		{ echo "-z ZFS not available with RouterOS images" ; exit 1 ; }

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

elif [ -f "$release_input" ] ; then # if a path to an image

	# Arbitrary image may have arbitrary sources - manual copy needed
	[ "$include_src" = 1 ] && \
		{ echo "-s src not available with a custom image" ; exit 1 ; }

	custom_image_file="$( basename $release_input )"

	release_image_file="$release_input"
	custom_image_file="$( basename $release_input )"
	release_name="custom"
	release_type="raw"
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
# Do we want to harmonize release_name="freebsd"?
	release_name="$release_input"
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
	release_image_url="https://download.freebsd.org/${release_branch}/VM-IMAGES/${release_name}/${cpu_arch}/Latest/FreeBSD-${release_name}-${arch_string}-${fs_type}.raw.xz"

	release_image_file="$( basename $release_image_url )"

	[ -d "${work_dir}/${release_name}" ] || \
		mkdir -p "${work_dir}/${release_name}"
	[ -d "${work_dir}/${release_name}" ] || \
		{ echo "mkdir ${work_dir}/${release_name} failed" ; exit 1 ; }

	# Needed for fetch to save the upstream file name
	cd "${work_dir}/${release_name}"

	f_fetch_image "$release_image_file" "$release_image_url"

release_dist_url="https://download.freebsd.org/${release_branch}/$arch_string/$release_name"
src_url="https://download.freebsd.org/${release_branch}/${hw_platform}/${cpu_arch}/${release_name}/src.txz"

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
fi # End -r RELEASE HEAVY LIFTING


################################
# HEAVY LIFTING FLAG -t TARGET #
################################

# Default is img which can be user specified, a device under /dev/, or
# a path to a file

echo ; echo Status: Beginning -t target handling
if [ "$target_input" = "img" ] ; then
	target_type="img"

	[ -d "$work_dir" ] || mkdir -p "$work_dir"
	[ -d "$work_dir" ] || { echo "mkdir -p $work_dir failed" ; exit 1 ; }

	if [ -n "$mirror_path" ] ; then
		[ "$mirror_path" = "img" ] || \
			{ echo "-t and -T must both be images" ; exit 1 ; }
	fi

	if [ "$release_name" = "omnios" ] ; then
		fs_type="zfs"
		target_path="${work_dir}/omnios-${hw_platform}-${fs_type}.raw"
	elif [ "$release_name" = "debian" ] ; then
		fs_type="ext4"
		target_path="${work_dir}/debian-${hw_platform}-${fs_type}.raw"
	elif [ "$release_name" = "routeros" ] ; then
		fs_type="ext4"
		target_path="${work_dir}/routeros-${hw_platform}-${fs_type}.raw"
	elif [ "$release_name" = "windows" ] ; then
		fs_type="ntfs"
		target_path="${work_dir}/windows-${hw_platform}-${fs_type}.raw"
	elif [ "$release_name" = "custom" ] ; then
		fs_type=""
		target_path="${work_dir}/$custom_image_file"
	else
		# Challenge: FreeBSD does not have a notion of release_name
		# TEST with "path" because that might get inserted
		target_path="${work_dir}/FreeBSD-${hw_platform}-${release_input}-${fs_type}.raw"
	fi

elif [ "$target_prefix" = "/dev/" ] ; then

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

elif [ "$target_type" = "oneboot" ] ; then
	echo "Preparing for installation upon oneboot"
else # Input is a path to an image or invalid
	# Validate parent directory
	[ -d $( dirname "$target_input" ) ] || \
		{ echo "-t directory path does not exist" ; exit 1 ; }
	[ -w $( dirname "$target_input" ) ] || \
		{ echo "-t directory path is not writable" ; exit 1 ; }
	# Not true if Windows...
	target_type="path"
	target_path="$target_input"

fi # End -t TARGET HEAVY LIFTING


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
	include_src=0
	attachment_required=0

	which 7z > /dev/null 2>&1 || \
		{ echo "7-zip package not installed" ; exit 1 ; }
	which mkisofs > /dev/null 2>&1 || \
		{ echo "cdrtools  package not installed" ; exit 1 ; }
	which xmllint > /dev/null 2>&1 || \
		{ echo "libxml2 package not installed" ; exit 1 ; }

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

	echo ; echo The resulting ISO image is $work_dir/windows/install.iso

	cd -

# GENERATE WINDOWS ONE-TIME BOOT SCRIPTS

# Consider a warning that it will be writing to a device
# boot-windows-iso.sh to boot once to the ISO for auto-installation

#########
# BHYVE #
#########
	# Used here and below
	fbuf_string="-s 29,fbuf,tcp=0.0.0.0:5900,w=1024,h=768 -s 30,xhci,tablet"
	cat << HERE > $work_dir/bhyve-windows-iso.sh
#!/bin/sh
[ -e /dev/vmm/$vm_name ] && { bhyvectl --destroy --vm=$vm_name ; sleep 1 ; }
[ -f /usr/local/share/uefi-firmware/BHYVE_UEFI.fd ] || \\
        { echo \"BHYVE_UEFI.fd missing\" ; exit 1 ; }

kldstat -q -m vmm || kldload vmm
HERE

	if [ "$target_type" = "img" ] ; then
		# Needed now and for later bhyve boot scripts use
		vm_device="$target_path"

	# Note the >> to not overwrite
	cat << HERE >> $work_dir/bhyve-windows-iso.sh
echo ; echo Removing previous $vm_device if present
[ -f $vm_device ] && rm $vm_device

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
        $fbuf_string \\
	-s 31,lpc \\
	$vm_name

sleep 2
bhyvectl --destroy --vm=$vm_name
HERE

	echo Note: bhyve-windows-iso.sh

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

	echo Note: qemu-windows-iso.sh

	echo ; echo "Note $work_dir/bhyve|qemu-windows-iso.sh to boot the VM once for installation, which will be on 0.0.0.0:5900 for VNC attachment for monitoring."

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
	oneboot)
		echo "Preparing for installation upon oneboot"
		;;

	img|path)
		# Delete existing target image if present
		[ -f "$target_path" ] && rm "$target_path"

		# A cp -p would be ideal for unmodified images
		f_extract "$release_image_file" > "$target_path" || \
		{ echo "$release_image_file extraction failed" ; exit 1 ; }
		echo ; echo "Output boot image is $target_path"

# Might not have the ending .raw? .img?
		;; # End image|path

	dev)
		if [ "$xml_file" ] ; then
			echo "Still preparing for installation upon oneboot"
		else
			if [ "$release_name" = "custom" ] ; then
				# Used for "path" release input
				file_to_extract="$release_input"
			else
	file_to_extract="${work_dir}/${release_name}/$release_image_file"
			fi

			f_extract "$file_to_extract" > "$target_dev" || \
				{ echo "Extraction failed" ; exit 1 ; }
				zpool import

				gpart recover $target_dev || \
					{ echo gpart recover failed ; exit 1 ; }
				gpart show $target_dev
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

#	MITIGATING LABEL CONFLICTS
#	WHICH MEAN FSTAB ISSUES, SOMETIMES REGARDLESS OF OUR APPROACH
#	WHY THE HECK TO FREEBSD MULTI-DISK SYSTEMS LOVE TO CHOKE ON efipart?
#	"Why did my production system fail to boot because of something I do
#		not need?

# Image/device attachment is needed for:
# -g Growth required (implied on hardware devices)
# -Z Rename zpool
# -T Mirror zfs device
# -s Add Sources (FreeBSD)
# -m Mount rquired
# Detected target type device (grow at the file system level for additions)
#	Relable for UFS?
# -x Windows

# Three stages
# Download or locate the source boot image
# Make images and hardware devices equal, unless only an unmodified copy
# Image single or mirrored images or files
# Goal: NO FIRST BOOT STEPS

# NO MD DEVICES... clean up if advanced


echo ; echo Status: Checking attachment_required
if [ "$attachment_required" = "1" ] ; then

	if [ "$target_type" = "img" -o "$target_type" = "path" ] ; then

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

		mdconfig -lv

		gpart recover $target_dev || \
			{ echo gpart recover failed ; exit 1 ; }
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

	# gpart root_fs will fail without relabling the "linux-data" EFI part
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
		echo ; echo Obtaining zpool guid from $root_dev
zpool_name=$( zdb -l $root_dev | grep " name:" | awk '{print $2}' | tr -d "'" )

		echo ; echo Obtaining zpool guid from $root_dev
	zpool_guid=$( zdb -l $root_dev | grep pool_guid | awk '{print $2}' )

	# Needed for fstab handling if attaching and relabling
	mount_required=1
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
		echo "Still preparing for installation upon oneboot"
	else
		echo ; echo "Resizing $root_dev with gpart"
		# Should be file system-agnostic

		gpart resize -i "$root_part" "$target_dev" || \
			{ echo "gpart resize failed" ; exit 1 ; }
		gpart show "$target_dev"

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
#if [ "$root_fs" = "freebsd-zfs" -o "$root_fs" = "apple-zfs" ] ; then
if [ "$fs_type" = "zfs" -a "$attachment_required" = 1 ] ; then

# Save much potential headache: plan for rootfs1 and rootfs2 being on the host
# and always relabling the partitions if:
# -g Growing - attachement required/relabel required
# -Z Renaming - attachment required/relabel required
# -T Mirroring - attachment required/relabel required - mount required for fstab
# -s Sources - attachment required/relabel required - mount required
# -m Mounting - attachment required - mount required

# LARGELY PREP AS IF MIRRORING BECAUSE OF LABELING, MIRROR FOR MIRRORING

	if [ -n "$mirror_path" ] ; then

		[ "$vmdk" = 1 ] && \
			{ echo "Mirroring does not support VMDK" ; exit 1 ; }

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
# The device for now but needs to be the file for the boot script
			target_dev2="/dev/md$md_id2"

		fi # End if type=img or dev

	fi # End if mirror_path PREP of images that are now equally devices

# Relabel the first, always-existing device, image or hardware

	echo Relabeling $target_dev
	# Remove digits from default labels and add a new ID
	# The host could have root-on-RaidZ with many devices
	# Using 100 and 200
	# Glob to avoid the sub-shell?

# SHOULD THIS BE relabel_required? Possibly a function?

# Challenge: Free space handling - fortunately, it is probably at the end
	gpart show -l $target_dev | tail -n+2 | grep . \
		| awk '{print $1,$2,$3,$4}' | \
		while read _start _stop _id _label ; do
			_label=$( echo $_label | tr -d "[:digit:]" )
			[ "$_label" = "null" -o "$_label" = "free" ] && break
			gpart modify -i $_id -l ${_label}100 $target_dev || \
			{ echo $target_dev part $_id relabel failed ; exit 1 ; }
		done
		gpart show -l $target_dev

	if [ -n "$mirror_path" ] ; then

# FYI data partitions: FreeBSD = 4 OmniOS = 2

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
			gpart modify -i $_id -l ${_label}200 $target_dev2 || \
			{ echo $target_dev2 $_id relabel failed ; exit 1 ; }
		done
		gpart show -l $target_dev

		# Is there any reason this should be by label or is this safer?
		# That could avoid {scheme}
		echo Mirroring the first partition
#		dd if=${target_dev}p1 of=${target_dev2}p1 bs=512 \
		dd if=${target_dev}${scheme}1 of=${target_dev2}{scheme}1 \
			status=progress conv=sync || \
				{ echo "p{scheme} dd failed" ; exit 1 ; }

		echo Mirroring the second partition
#		dd if=${target_dev}p2 of=${target_dev2}p2 bs=512 \
		dd if=${target_dev}{scheme}2 of=${target_dev2}{scheme}2 \
			status=progress conv=sync || \
				{ echo "p{scheme} dd failed" ; exit 1 ; }

	fi # End mirror_path partition mirroring and relabeling

	if [ "$zpool_rename" = 1 ] && [ "$grow_required" = 1 ] ; then
		echo ; echo Importing and expanding zpool with guid $zpool_guid
		zpool import -o autoexpand=on -N -f \
			-d /dev/gpt/rootfs100 $zpool_guid $zpool_newname || \
			{ echo "$zpool_newname failed to import" ; exit 1 ; }
		zpool status -v $zpool_name

		zpool online -e $zpool_newname /dev/gpt/rootfs100 || \
			{ echo "$zpool_newname failed to online -e" ; exit 1 ; }
		zpool_name="$zpool_newname"
		zpool status -v $zpool_name

	elif [ "$zpool_rename" = 1 ] ; then
		echo ; echo Importing zpool with new name $zpool_newname
		zpool import -N -f \
			-d /dev/gpt/rootfs100 $zpool_guid $zpool_newname || \
			{ echo "$zpool_newname failed to import" ; exit 1 ; }
		zpool status -v $zpool_name

		zpool_name="$zpool_newname"

	elif [ "$grow_required" = 1 ] ; then
		echo ; echo Importing and expanding zpool $zpool_name
		zpool import -o autoexpand=on -N -f \
			-d /dev/gpt/rootfs100 $zpool_name || \
			{ echo "$zpool_name failed to import" ; exit 1 ; }
		zpool status -v $zpool_name

		zpool online -e $zpool_name /dev/gpt/rootfs100 || \
			{ echo "$zpool_name failed to online -e" ; exit 1 ; }

	else
		# Import without expansion or rename
		zpool import -N -f -d /dev/gpt/rootfs100 $zpool_name || \
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

	if [ -n "$mirror_path" ] ; then
		echo Attaching the mirror device
		zpool attach $zpool_name \
			/dev/gpt/rootfs100 /dev/gpt/rootfs200 || \
			{ echo "zpool device attachment failed" ; exit 1 ; }
		zpool status -v $zpool_name

		echo Waiting 20 seconds for the attachment to complete
		sleep 10
		zpool status -v $zpool_name
		sleep 10
		zpool status -v $zpool_name
		echo Consider a zpool scrub

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
	echo RouterOS: Relabeling /dev/md${md_id}${scheme}1 
	gpart modify -i 1 -t linux-data $target_dev || \
		{ echo $target_dev part 1 relabel failed ; exit 1 ; }
fi


#######################
# MUST MOUNT HANDLING #
#######################

# Recall that advanced preparation was required and would have
# prepared memory devices, detected file systems  etc.

echo ; echo Status: Checking mount_required
if [ "$mount_required" = 1 ] ; then

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

#	elif [ "$root_fs" = "freebsd-zfs" ] ; then
	elif [ "$fs_type" = "zfs" ] ; then

		echo ; echo Importing zpool $zpool_name for mounting
		# Device path not required
		zpool import -R /media $zpool_name || \
			{ echo "$zpool_name failed to import" ; exit 1 ; }
		zpool status -v $zpool_name

		echo ; echo Modifying the fstab 
		# This is a sin and why TrueNAS uses UUIDs
		mv /media/etc/fstab /media/etc/fstab.original
		touch /media/etc/fstab
		# YEP, we want an auto-swapper and maybe
		# a utility to mount the EFI parition for updating

		if [ $zpool_newname ] ; then
			# Must be double quotes for variable expansion
			sed -i -e "s/zroot/$zpool_newname/g" /media/etc/rc.conf
		fi
	else
		echo "Unrecognized root file system"
		exit 1
	fi # End if root_fs


###################
# SOURCE HANDLING #
###################

	# Must mount would already be set
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
	fi # End include_src

	df -h | grep media
	ls /media
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
	elif [ -n "$target_dev" ] ; then
		vm_device="$target_dev"
	elif [ "$target_type" = "oneboot" ] ; then
		echo "Preparing for installation upon oneboot"
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
		img|path)
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

$loader_string
bhyve -c $vm_cores -m $vm_ram -A -H -l com1,stdio -s 31,lpc -s 0,hostbridge \\
	-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd \\
	$storage_string \\
        $fbuf_string \\
        $vm_name

# Devices to consider:

# -s 3,virtio-net,tap0 \\
# -s 3,e1000,tap0 \\

sleep 2
bhyvectl --destroy --vm=$vm_name
HERE
			echo Note: $work_dir/$bhyve_script

########
# QEMU #
########
			if [ "$target_type" = "path" ] ; then
				qemu_script="qemu-${custom_image_file}.sh"
			else
		qemu_script="qemu-${release_input}-${hw_platform}-${fs_type}.sh"
			fi

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

# Should be conditional to not generate if mirrored
# Solution appears to be two comma-separated strings in "disk"

			if [ "$target_type" = "path" ] ; then
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
$loader_string
bhyve -c $vm_cores -m $vm_ram -o console=stdio \\
        -o bootrom=/usr/local/share/u-boot/u-boot-bhyve-arm64/u-boot.bin \\
        -s 2,virtio-blk,$vm_device \\
        $vm_name

# Devices to consider:

# -s 3,virtio-net,tap0 \\
# -s 3,e1000,tap0 \\

sleep 2
bhyvectl --destroy --vm=$vm_name
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

		if [ "$root_fs" = "freebsd-ufs" ] ; then
			echo ; echo "Unmounting /media"
			umount /media || { echo "umount failed" ; exit 1 ; }
#	elif [ "$root_fs" = "freebsd-zfs" -o "$root_fs" = "apple-zfs" ] ; then
	elif [ "$fs_type" = "zfs" ] ; then

			echo ; echo "Exporting $zpool_name"
			zpool export $zpool_name || \
				{ echo "zpool export failed" ; exit 1 ; }
		fi

	fi # End mount_required

	if [ "$attachment_required" = 1 ] ; then
		if [ "$target_type" = "img" -o "$target_type" = "path" ] ; then
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
		echo ; echo Run 'umount /media' when finished
	fi

#	if [ "$root_fs" = "freebsd-zfs" -o "$root_fs" = "apple-zfs" ] ; then
	if [ "$fs_type" = "zfs" ] ; then
		echo ; echo "Run 'zpool export $zpool_name' when finished"
	fi

	if [ "$target_type" = "img" -o "$target_type" = "path" ] ; then
		echo Run 'mdconfig -du $md_id' when finished
		if [ -n "$mirror_path" ] ; then
			echo ; echo "Run 'mdconfig -du $md_id2' when finished"
		fi
	fi
fi # End keep_mounted

exit 0
