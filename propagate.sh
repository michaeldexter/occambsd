#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause-FreeBSD
#
# Copyright 2024 Michael Dexter
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

# Version v.0.0.3ALPHA

# propagate.sh - Packaged Base for OccamBSD and Imagine


##############
# MOTIVATION #
##############

# The "p" and "g" in propagate are for "pkg", obviously.
#
# The 2018 propagate.sh installed upstream FreeBSD distribution sets or
# custom-built binaries to boot environments, and this incarnation does
# the same with upstream or OccamBSD-built FreeBSD base packages.


##############################
# TESTING, NOTES, AND ISSUES #
##############################

# A bsdinstall "traditional" FreeBSD 14.1-RELEASE system can install 14.1 and
# 15.0 PkgBase installations with syntax such as:

# 14.1-RELEASE to a directory with jail package set from the quarterly branch
# sh propagate.sh -r 14.1 -t /tmp/pkgjail -j -q

# 15.0-CURRENT to a dataset configured like a boot environment with
# -o canmount=noauto -o mountpoint=/
# sh propagate.sh -r 15.0 -t zroot/ROOT/pkgbase15.0

# To do the same creating a VM-IMAGE /tmp/pkgbase15.0.vm.zfs.img
# sh propagate.sh -r 15.0 -t zroot/ROOT/pkgbase15.0 -v

# Note that the directory/dataset distinction is made by the leading slash!

# Issue: The resulting 15.0 system is not propagating 14.1 or 15.0, giving:
#pkg: Warning: Major OS version upgrade detected.  Running "pkg bootstrap -f" recommended
#pkg(8) is already installed. Forcing re-installation through pkg(7).
#Bootstrapping pkg from pkg+https://pkg.FreeBSD.org/FreeBSD:14:amd64/latest, please wait...
#Verifying signature with trusted certificate pkg.freebsd.org.2013102301... done
#Installing pkg-1.21.3...
#package pkg is already installed, forced install
#Extracting pkg-1.21.3: 100%

# Bootstrapping pkg from pkg+http://pkg.FreeBSD.org/FreeBSD:15:amd64/latest, please wait...
#pkg: Error fetching https://pkg.FreeBSD.org/FreeBSD:15:amd64/base_latest/Latest/pkg.txz: Not Found
# base_latest/Latest/pkg.txz
# This issue keeps showing up with and base_latest/Latest/pkg.txz is not a thing
# In some cases, requesting 14.1 gives FreeBSD:15:amd64

# Issue: PkgBase has strange dependencies to understand i.e. why some are
# fetched but not used  For example, why does the "jail" set of
# base packages pull in a few dependencies?
#14.1 on 14.1 with a "jail" set gets kernel, zfs, ufs...
#[52/88] Installing FreeBSD-zfs-14.1p1...
#[66/88] Installing FreeBSD-kernel-generic-mmccam-14.1p3...
# and fetches generic
#[87/88] Installing FreeBSD-ufs-lib32-14.1...

# Caveat: This leaves cleanup of previous runs to the reader

# Caveat: Currently this produces ZFS-friendly loader.conf and rc.conf files,
# given that one can generate a VM image from a directory. A jail that attempts
# to load zfs.ko will probably survive.

# Caveat: The sideloading steps are moved elsewhere.

# Question: How does base_weekly differ from base_latest ?
# 15.0 only has base_latest base_weekly and latest
# Add gdb to our favorite list of packages...
# Question: How to choose a PkgBase kernel such as NODEBUG?

# Idea: If installing sources and creating a VM image, change src_dir to
# within the mount_point


#########
# USAGE #
#########

f_usage() {
	echo ; echo "USAGE:"
	echo "-r <release> (Dot-separated version i.e. 14.1 or 15.0 - Required)"
	echo "-a <architecture> [ amd64 | arm64 ] (Default: Host)"
	echo "-t <target> (Boot environment or Jail path i.e. zroot/ROOT/pkgbase15 or /jails/pkgbase15 - Required)"
	echo "-q (quarterly package branch - default latest)"
	echo "-m (Keep boot environment mounted for further configuration)"
	echo "-M <Mount point> (Default: /media)"
	echo "-j (Jail package set)"
	echo "-d (Default FreeBSD installation package set with sources)"
	echo "-3 (Install lib32 packages)"
	echo "-p \"<additional packages>\" (Quoted space-separated list)"
	echo "-v (Generate VM image in /tmp)"
	echo
	exit 0
}


# INTERNAL VARIABLES AND DEFAULTS

release=""
major_version=""
minor_version=""
hw_platform=$( uname -m )       # i.e. amd64|arm64
cpu_arch=$( uname -p )          # i.e. amd64|aarch64
branch="latest"
target_input=""
target_prefix=""
target_type=""	# directory or dataset
keep_mounted=0
mount_point="/media"
pkg_exclusions="clang|lld|lldb|src|src-sys|tests"
special_pkg_exclusions="dbg|dev|lib32"			#Keep lib32 at the end
lib32=0
additional_packages=""
vm_image=0
#src_dir="/usr/src"
#obj_dir=""


# USER INPUT AND VARIABLE OVERRIDES

while getopts r:a:t:qmM:jd3p:v opts ; do
        case $opts in
        r)
		[ "$OPTARG" ] || f_usage
		release="$OPTARG"
		echo "$release" | grep -q "\." || f_usage
		major_version=$( echo $release | cut -d "." -f 1 )
		# cut -d "." -f 2 only works with a .N
		minor_version=$( echo $release | cut -d "." -f 2 )

		if [ "$major_version" -lt 14 ] ; then
			echo "Release is under 14 or invalid"
		fi

		if [ ! "$minor_version" ] ; then
			minor_version=0
		elif [ "$minor_version" -ge 0 ] ; then
			true
		else
			echo Invalid release input
			f_usage
		fi

	;;
	a)
		case "$OPTARG" in
			amd64)
				hw_platform="amd64"
		;;
			arm64)
				hw_platform="aarch64"
		;;
			*)
				echo "Invalid architecture"
				f_usage
		;;
		esac
	;;
	t)
		target_input="$OPTARG"
		target_prefix=$( printf %.1s "$target_input" )

		if [ "$target_prefix" = "/" ] ; then
			if [ "$target_input" = "/" ] ; then
				echo "Target is / - Exiting"
				exit 1
			fi	

			[ -d $target_input ] && \
				{ echo Target exists - Exiting ; exit 1 ; }
			echo Creating root directory
			[ -d $target_input ] || mkdir -p $target_input
			[ -d $target_input ] || \
				{ echo mkdir $target_input failed ; exit 1 ; }
			target_type="directory"
			mount_point="$target_input"
		else
		zpool get name $( echo $target_input | cut -d "/" -f 1 ) \
			> /dev/null 2>&1 || \
			{ echo Target $target_input appears invalid ; exit 1 ; }

			zfs get name $target_input > /dev/null 2>&1 && \
				{ echo Target exists - Exiting ; exit 1 ; }

			target_type="dataset"
			echo Creating root dataset
			zfs get name $target_input > /dev/null 2>&1 || \
		        zfs create -o canmount=noauto -o mountpoint=/ \
				$target_input
			zfs get name $target_input > /dev/null 2>&1 || \
        		{ echo root dataset failed to create ; exit 1 ; }
			echo Mounting root dataset
			# NOT using bectl - dataset may be a jail
			# bectl mount $target_input ${mount_point} || \
			mount -t zfs $target_input $mount_point || \
			{ echo root dataset mount failed ; exit 1 ; }
		fi
	;;
	q)
		branch="quarterly"
	;;
	m)
		keep_mounted=1
	;;
	M)
		[ "$OPTARG" ] || f_usage
                mount_point="$OPTARG"
                [ -d "$mount_point" ] || \
			{ echo "Mount point $mount_point missing" ; exit 1 ; }

	;;
	j)
special_pkg_exclusions="dbg|dev|kernel|man|lib32"

pkg_exclusions="acpi|apm|autofs|bhyve|bluetooth|bootloader|bsdinstall|bsnmp|ccdconfig|clang|cxgbe-tools|dtrace|efi-tools|elftoolchain|examples|fwget|games|geom|ggate|hast|hostapd|hyperv-tools|iscsi|kernel|lld|lldb|lp|mlx-tools|nvme-tools|ppp|rescue|rdma|smbutils|src|src-sys|tests|ufs|wpa|zfs"

	;;
	d)
		special_pkg_exclusions=""

		pkg_exclusions=""
	;;
	3)
		lib32=1
	;;
	p)
		[ "$OPTARG" ] || f_usage
		additional_packages="$OPTARG"
	;;
	v)
		vm_image=1
	;;
	esac
done

[ "$release" ] || f_usage
[ "$target_input" ] || f_usage

case "$hw_platform" in
        amd64)
                cpu_arch="amd64"
        ;;
        arm64)
                cpu_arch="aarch64"
        ;;
	*)
		echo Invalid architecture
		exit 1
	;;
esac

if [ "$lib32" = 1 ] ; then
	# Keep lib32 at the end for clean stripping
special_pkg_exclusions="$( echo $special_pkg_exclusions | sed 's/|lib32//' )"
fi

if [ "$branch" = "latest" ] ; then
	abi_major="$major_version"
	abi_minor="base_latest"
else
	abi_major="$major_version"
	abi_minor="base_release_$minor_version"

fi


#########################
# BOOT ENVIRONMENT ROOT #
#########################

# root directory and dataset should be agnostic

echo Creating ${mount_point}/dev
[ -d ${mount_point}/dev ] || mkdir -p $mount_point/dev 
[ -d ${mount_point}/dev ] || { echo root/dev failed to create ; exit 1 ; }

#pkg-static: Cannot open dev/null
echo Mounting devfs for pkg-static
mount -t devfs -o ruleset=4 devfs ${mount_point}/dev || \
	{ echo mount devfs failed; exit 1 ; }

echo Creating ${mount_point}/etc/pkg
[ -d ${mount_point}/etc/pkg ] || mkdir -p $mount_point/etc/pkg
[ -d ${mount_point}/etc/pkg ] || { echo root/etc failed to create ; exit 1 ; }

echo Copying in /etc/resolv.conf
cp /etc/resolv.conf ${mount_point}/etc/ || \
	{ echo resolv.conf failed to copy ; exit 1 ; }

# /var/cache/pkg
echo ; echo Creating /tmp/pkg directories
[ -d "${mount_point}/var/cache/pkg" ] || mkdir -p $mount_point/var/cache/pkg
[ -d "${mount_point}/var/cache/pkg" ] || { echo mkdir tmp/pkg failed ; exit 1 ; }

# ${mount_point}/var/db/pkg
[ -d "${mount_point}/var/db/pkg" ] || mkdir -p $mount_point/var/db/pkg
[ -d "${mount_point}/var/db/pkg" ] || { echo mkdir var/db/pkg failed ; exit 1 ; }

[ -d ${mount_point}/usr/share/keys/pkg ] || \
	mkdir -vp ${mount_point}/usr/share/keys/pkg
cp -av /usr/share/keys/pkg \
	${mount_point}/usr/share/keys || \
	{ echo pkg keys copy failed ; exit 1 ; }

[ -d ${mount_point}/usr/share/keys/pkg/trusted ] || \
	{ echo cp ${mount_point}/usr/share/keys/pkg/trusted failed ; exit 1 ; }

# Used by temporary pkg.conf and persistent pkg/repos
[ -d ${mount_point}/usr/local/etc/pkg/repos ] || \
	mkdir -p $mount_point/usr/local/etc/pkg/repos
[ -d ${mount_point}/usr/local/etc/pkg/repos ] || \
	{ echo mkdir usr/local/etc/pkg/repos failed ; exit 1 ; }

# /mnt and /media are not created by PkgBase!
[ -d ${mount_point}/mnt ] || mkdir -p $mount_point/mnt
[ -d ${mount_point}/mnt ] || { echo mkdir mnt failed ; exit 1 ; }

[ -d ${mount_point}/media ] || mkdir -p $mount_point/media
[ -d ${mount_point}/media ] || { echo mkdir media failed ; exit 1 ; }

[ -d ${mount_point}/root ] || mkdir -p $mount_point/root
[ -d ${mount_point}/root ] || { echo mkdir root failed ; exit 1 ; }

#du -h ${mount_point}

########################################
# FreeBSD.conf REPO CONFIGURATION FILE #
########################################

# NOTE THAT THIS WILL BE OVERRIDDEN BY THE RETRIEVED PACKAGES
echo ; echo Generating ${mount_point}/etc/pkg/FreeBSD.conf REPO file
cat << HERE > ${mount_point}/etc/pkg/FreeBSD.conf
FreeBSD: { 
  enabled: yes
  url: "pkg+https://pkg.FreeBSD.org/FreeBSD:${abi_major}:${cpu_arch}/$branch", 
  mirror_type: "srv",
  signature_type: "fingerprints",
  fingerprints: "${mount_point}/usr/share/keys/pkg"
}

FreeBSD-base: {
  enabled: yes
  url: "pkg+https://pkg.FreeBSD.org/FreeBSD:${abi_major}:${cpu_arch}/${abi_minor}", 
  mirror_type: "srv",
  signature_type: "fingerprints",
  fingerprints: "${mount_point}/usr/share/keys/pkg"
}
HERE

echo ; echo Copying ${mount_point}/etc/pkg/FreeBSD.conf to /root
# It will be overridden during the package installation
cp ${mount_point}/etc/pkg/FreeBSD.conf /${mount_point}/root/ || \
	{ echo cp FreeBSD.conf failed ; exit 1 ; }

# DO NOT PUT yes in quotation marks or it will fail!

# THIS WILL BE OVERRIDDEN UPON PACKAGE RETRIEVAL
# WORSE, it will be incorrectly prefixed if we do not modify it and the new
# system will not be able to retrieve packages
# Moving it to the root directory at the end

echo ; echo Generating ${mount_point}/usr/local/etc/pkg.conf PKG config file
cat << HERE > ${mount_point}/usr/local/etc/pkg.conf
  IGNORE_OSVERSION: yes
  INDEXFILE: INDEX-$major_version
  ABI: "FreeBSD:${abi_major}:${cpu_arch}"
  pkg_dbdir: "${mount_point}/var/db/pkg",
  pkg_cachedir: "${mount_point}/var/cache/pkg",
  handle_rc_scripts: no
  assume_always_yes: yes
  repos_dir: [
    "${mount_point}/etc/pkg"
  ]
  syslog: no
  developer_mode: no
HERE

[ -f ${mount_point}/usr/local/etc/pkg.conf ] || \
	{ echo pkg.conf generation failed ; exit 1 ; }

#echo ; cat ${mount_point}/etc/pkg/FreeBSD.conf
#echo ; cat ${mount_point}/usr/local/etc/pkg.conf

# Q: Can this get in the way? /usr/local/etc/pkg/repos/FreeBSD-base.conf

echo ; echo pkg -vv SMOKE TEST
pkg -vv -C ${mount_point}/usr/local/etc/pkg.conf


#############
# BOOTSTRAP #
#############

echo ; echo Running pkg bootstrap
echo

pkg \
	-C ${mount_point}/usr/local/etc/pkg.conf \
	bootstrap -f -y || \
		{ echo pkg bootstrap failed ; exit 1 ; }


# WHY IS IT NOT READING THE REQUESTED pkg and repo configs?
# To begin with... FreeBSD.conf was named pkg.conf
# BUT pkg -vv does not show repos at the bottom
# Does NOT show them if you specify
# -R ${mount_point}/etc/pkg/FreeBSD.conf

# SOUNDS WRONG
# INDEXFILE = "INDEX-15"; # NOW OVERRIDING with the major number
#ABI = "FreeBSD:14:${cpu_arch}";
#ALTABI = "freebsd:15:x86:64";

# INDEXFILE: string
# The filename of the ports index, searched for in INDEXDIR or PORTSDIR.  Default: INDEX-N where N is the OS major version number


##########
# UPDATE #
##########

echo ; echo Running pkg update 

echo ; echo pkg -vv SMOKE TEST
pkg -C ${mount_point}/usr/local/etc/pkg.conf -vv

pkg \
	-C ${mount_point}/usr/local/etc/pkg.conf \
	update -f || \
		{ echo pkg update failed ; exit 1 ; }

du -h ${mount_point}

echo ; echo pkg -vv SMOKE TEST
pkg -C ${mount_point}/usr/local/etc/pkg.conf -vv


#####################
# INSTALL PREFLIGHT #
#####################

echo ; echo Running pkg rquery

echo ; echo SMOKE TEST: Counting available packages
pkg \
	-C ${mount_point}/usr/local/etc/pkg.conf \
	rquery --repository="FreeBSD-base" '%n' \
		| wc -l

echo ; echo SMOKE TEST: Counting requested packages
pkg \
	-C ${mount_point}/usr/local/etc/pkg.conf \
	rquery --repository="FreeBSD-base" '%n' \
		| egrep -v \
		"FreeBSD-.*(.*-($special_pkg_exclusions)|($pkg_exclusions))$" \
		| wc -l

#cat ${mount_point}/etc/pkg/FreeBSD.conf


###########
# INSTALL #
###########

echo ; echo Installing base packages

# Strong quoting required for egrep and variables
pkg \
	-C ${mount_point}/usr/local/etc/pkg.conf \
	rquery --repository="FreeBSD-base" '%n' \
		| egrep -v \
		"FreeBSD-.*(.*-($special_pkg_exclusions)|($pkg_exclusions))$" \
		| xargs -o pkg \
			-C ${mount_point}/usr/local/etc/pkg.conf \
			--rootdir ${mount_point} \
			install \
			--

#			-o IGNORE_OSVERSION="yes" \

#######################
# ADDITIONAL PACKAGES #
#######################

if [ "$additional_packages" ] ; then
	echo Installing additional packages
	pkg \
		-C ${mount_point}/usr/local/etc/pkg.conf \
			--rootdir ${mount_point} \
			install "$additional_packages" || \
				{ echo Additional packages failed ; exit 1 ; }
fi

echo ; echo Generating persistent ${mount_point}/usr/local/etc/pkg/repos/FreeBSD-base.conf REPO file
cat << HERE > ${mount_point}/usr/local/etc/pkg/repos/FreeBSD-base.conf
FreeBSD-base: {
  enabled: yes
  url: "pkg+https://pkg.FreeBSD.org/\${ABI}/${abi_minor}", 
  mirror_type: "srv",
  signature_type: "fingerprints",
  fingerprints: "/usr/share/keys/pkg"
}
HERE

[ -f ${mount_point}/usr/local/etc/pkg/repos/FreeBSD-base.conf ] || \
	{ echo FreeBSD-base.conf generation failed ; exit 1 ; }

echo ; echo Moving the bootstrap FreeBSD.conf to the root directory
# Else pkg will not work upon BE boot
mv ${mount_point}/usr/local/etc/pkg/repos/FreeBSD-base.conf ${mount_point}/root/

echo ; echo Moving the bootstrap pkg.conf to the root directory
# Else pkg will not work upon BE boot
mv ${mount_point}/usr/local/etc/pkg.conf ${mount_point}/root/

if [ "$branch" = "latest" ] ; then
	echo Setting the default repo to "latest"
	sed -i '' -e "s/quarterly/latest/" ${mount_point}/etc/pkg/FreeBSD.conf
fi

###################################
# Minimum loader.conf and rc.conf #
###################################

# Challenge: You can create a ZFS VM image from a directory
# Removing the conditional for now

#if [ "$target_type" = "dataset" ] ; then
	cat << HERE > ${mount_point}/boot/loader.conf
kern.geom.label.disk_ident.enable="0"
kern.geom.label.gptid.enable="0"
cryptodev_load="YES"
zfs_load="YES"
HERE

	echo ; echo The loader.conf reads:
	cat ${mount_point}/boot/loader.conf
	echo

	cat << HERE > ${mount_point}/etc/rc.conf

hostname="propagate"
zfs_enable="YES"
HERE

	echo ; echo The rc.conf reads:
	cat ${mount_point}/etc/rc.conf
	echo
#fi


############
# VM-IMAGE #
############

# This with generate a script to generate a script to create a VM image
# A two-step process has the benefit of allowing configuration of the
# propagated system prior to creating the VM image.

# But acrobatics are required.

# /usr/src/release/scripts/mk-vmimage.sh exists to automate VM image creation.
# Unfortunately, it assumes installworld|installkernel|make distribution etc.

# /usr/src/release/tools/vmimage.subr is a library for VM image creation.
# Unfortunately, it has a hard requirement of being used by a script in /usr/src

# So we fake an object directory with three boot binaries, given that everything
# is already a binary, by definition. 

# We copy the resulting script into the source tree, but that would fail on a
# read-only source tree, and will obviously fail if sources are not available.

# Even a symlink will not work
#+ . ./release/tools/vmimage.subr
#+ realpath /usr/src/release/scripts/propagate-mkvm-image.sh
#+ dirname /tmp/pkgbase--mkvm-image.sh
#+ scriptdir=/tmp


if [ "$vm_image" = 1 ] ; then

if [ -d "${mount_point}/usr/src/release" ] ; then
	src_dir="${mount_point}/usr/src"
elif [ -d /usr/src/release ] ; then
	src_dir="/usr/src"
else
	echo VM build requires /usr/src/release
	exit 1
fi

cat << HERE > "/tmp/pkgbase-${release}-mkvm-image.sh"
#!/bin/sh
set -xe

cd ${src_dir}
pwd

mount | grep -q $mount_point/dev && umount $mount_point/dev

# The order in which they failed
mkdir -p $mount_point/usr/obj/usr/src/amd64.amd64/stand/efi/loader_lua || \\
	{ echo failed to make loader_lua directory ; exit 1 ; }

cp $work_dir/boot/loader_lua.efi \\
        $mount_point/usr/obj/usr/src/amd64.amd64/stand/efi/loader_lua/ || \\
		{ echo loader_lua.efi failed to copy ; exit 1 ; }

mkdir -p $mount_point/usr/obj/usr/src/amd64.amd64/stand/i386/pmbr || \\
	{ echo failed to make pmbr directory ; exit 1 ; }

cp $work_dir/boot/pmbr \\
	$mount_point/usr/obj/usr/src/amd64.amd64/stand/i386/pmbr/ || \\
		{ echo pmbr failed to copy ; exit 1 ; }

mkdir -p $mount_point/usr/obj/usr/src/amd64.amd64/stand/i386/gptzfsboot || \\
	{ echo failed to make gptzfsboot directory ; exit 1 ; }

cp $work_dir/boot/gptzfsboot \\
        $mount_point/usr/obj/usr/src/amd64.amd64/stand/i386/gptzfsboot/ || \\
		{ echo gptzfsboot failed to copy ; exit 1 ; }

export MAKEOBJDIRPREFIX=$mount_point/usr/obj
VMBASE=/tmp/pkgbase${release}.raw.zfs.img
WORLDDIR=/usr/src
DESTDIR=$mount_point
VMSIZE=8g
SWAPSIZE=1g
VMIMAGE=/tmp/pkgbase${release}.vm.zfs.img
VMFS=zfs
TARGET=${hw_platform}
TARGET_ARCH=${cpu_arch}
VMFORMAT=raw

# The heavy lifting
echo ; echo Building VM image

. ./release/tools/vmimage.subr
vm_create_disk

# Repeating this
echo ; echo The resulting VM images is:
echo /tmp/pkgbase${release}.vm.zfs.img
echo
echo ; echo To boot the VM image, run:
echo ; echo sh "/tmp/pkgbase-${release}-boot-image.sh"
echo
HERE

echo ; echo Copying /tmp/pkgbase-${release}-mkvm-image.sh to \
	${src_dir}/release/scripts/propagate-mkvm-image.sh

cp /tmp/pkgbase-${release}-mkvm-image.sh \
	${src_dir}/release/scripts/propagate-mkvm-image.sh || \
		{ echo Script copy failed ; exit ; }

echo ; echo To build the VM image, run:
echo ; echo sh ${src_dir}/release/scripts/propagate-mkvm-image.sh
echo

echo ; echo Generating a simple bhyve boot script

cat << HERE > "/tmp/pkgbase-${release}-boot-image.sh"
#!/bin/sh
[ \$( id -u ) = 0 ] || { echo "Must be root" ; exit 1 ; }
[ -e /dev/vmm/propagate ] && { bhyvectl --destroy --vm=propagate ; sleep 1 ; }
[ -f /usr/local/share/uefi-firmware/BHYVE_UEFI.fd ] || \\
        { echo \"BHYVE_UEFI.fd missing\" ; exit 1 ; }

kldstat -q -m vmm || kldload vmm
sleep 1

$loader_string
bhyve -m 2G -A -H -l com1,stdio -s 31,lpc -s 0,hostbridge \\
        -l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd \\
        -s 2,virtio-blk,/tmp/pkgbase${release}.vm.zfs.img \\
        propagate

sleep 2
bhyvectl --destroy --vm=propagate
HERE

echo ; echo To boot the VM image, run:
echo ; echo "/tmp/pkgbase-${release}-boot-image.sh"
echo

fi

##################
# MOUNT HANDLING #
##################

if [ "$keep_mounted" = 0 ] ; then
	if [ "$target_type" = "dataset" ] ; then
		echo ; echo Unmounting $mount_point
		umount $mount_point/dev ||
			{ echo $mount_point/dev failed to unmount ; exit 1 ; }
		umount $mount_point ||
			{ echo $mount_point failed to unmount ; exit 1 ; }
	else
		echo ; echo To unmount the boot environment, run:
		echo umount ${mount_point}/dev
		echo umount ${mount_point}
		echo
echo "Remember that $target_input is set to -o canmount=noauto -o mountpoint=/"
	fi
fi

exit 0
