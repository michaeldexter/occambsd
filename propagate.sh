#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause-FreeBSD
#
# Copyright 2024, 2025, 2026 Michael Dexter
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

# Version v.0.99

# propagate.sh - Packaged Base installer to boot environments and jails


##############
# MOTIVATION #
##############

# The "p" and "g" in propagate are for "pkg", obviously.
#
# The 2018 propagate.sh installed upstream FreeBSD distribution sets or
# custom-built binaries to boot environments, and this incarnation does
# the same with upstream or OccamBSD-built FreeBSD base packages.

#########
# USAGE #
#########

# propagate.sh must be run with root privileges and has three modes of operation
# to install a given release to:
#
# * A pre-existing directory or mounted dataset for use with jail(8)
# * A new boot environment that it will create based on the name provided
#
# The package selection aims to be a minimum-viable selection for a Jail or
# host that is supplanted by -p additional packages. Selection strategies:
#
# * Meta Packages
# * Long lists
# * grep -vE exclusions
# * pkg query/rquery -e evaluation
#
# Use the -G switch to graph them; view the graph using Graphviz.


#####################
# NOTES AND CAVEATS #
#####################

# This syntax aims to be consistent with occambsd.sh and imagine.sh
#
# That the directory/dataset distinction is made by the leading slash
#
# Cleanup is left to the reader but 'zpool export -f' is your friend
#
# Q: How to choose a PkgBase kernel such as nodebug?
# pkg search -g "FreeBSD-kernel-*"
# echo 'kernel="kernel.<special>"' >> /boot/loader.conf
# Q: Where did FreeBSD-kernel-minimal go?


#########
# USAGE #
#########

f_usage() {
	echo ; echo "USAGE:"
	echo "-r <release> (i.e. 15.0-RELEASE or 16.0-CURRENT Default: Host)"
	echo "-a <architecture> [ amd64 | arm64 ] (Default: Host)"
	echo "-t <target root> (Boot environment or Jail path - Required)"
	echo "   i.e. zroot/ROOT/pkgbase15, zroot/jails/pkgbase15 datasets or"
	echo "   /jails/myjail directory Default: /tmp/propagate/root)"
	echo "-n Create fully-nested datasets"
	echo "-q (quarterly package branch rather than latest)"
	echo "-m (Keep boot environment mounted for further configuration)"
	echo "-p \"<additional packages>\" (Quoted space-separated list)"
	echo "-s (Perform best-effort sideload of the current configuration)"
	echo "-c (Copy cached packages from the host to the target)"
	echo "-C (Clean package cache after installation)"
        echo "-G (Write a graph of base package selections and dependencies)"
	echo "-b (Install boot code)"
	echo "-d (Enable crash dumping)"
	echo "-u (Add root/root and freebsd/freebsd users and enable sshd)"
	echo "-o <output directory/work> (Default: /tmp/propagate)"
	echo
	exit 0
}

###################################
# INTERNAL VARIABLES AND DEFAULTS #
###################################

VERSION_MAJOR=""		# Upstream notation
VERSION_MINOR=""		# Upstream notation
release_input=$( uname -r | cut -d "-" -f1,2 )
release_branch=""
hw_platform=$( uname -m )	# i.e. amd64|arm64
cpu_arch=$( uname -p )		# i.e. amd64|aarch64
pkg_sets=""
target_prefix=""
target_type=""			# directory or dataset
zpool_name=""
zpool_bootfs=""
zpool_mountpoint=""
nested_datasets=0
package_branch="latest"
#FYI: "file:///usr/obj/usr/src/repo/FreeBSD:14:amd64/14.2/"
install_boot_code=0
enable_crash_dumping=0
add_users=0
keep_mounted=0


#############################
# USER-OVERRIDABLE DEFAULTS #
#############################

target_input="/tmp/propagate/root" # Default to a jail
mount_point="/tmp/propagate/root"  # at the default mount point
work_dir="/tmp/propagate"
additional_packages=""
sideload=0
packages=""
copy_package_cache=0
clean_package_cache=0
write_graph=0
configuration_script=""
efi_part=""
efi_mount=""
host_efi_loaders=""
dump_device=""

#Note empty files /etc/zfs/exports /etc/zfs/exports.lock


##############
# USER INPUT #
##############

while getopts r:a:t:nqmp:scCGbduo: opts ; do
	case $opts in
	r)
		[ "$OPTARG" ] || f_usage
		release_input="$OPTARG"
		echo "$release_input" | grep -q "\." || f_usage
		echo "$release_input" | grep -q "-" || f_usage

		# Perform more validation
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
	;;
	n)
		nested_datasets=1
	;;
	q)
		package_branch="quarterly"
	;;
	m)
		keep_mounted=1
	;;
	p)
		[ "$OPTARG" ] || f_usage
		additional_packages="$OPTARG"
	;;
	s)
		sideload=1
	;;
	c)
		copy_package_cache=1
	;;
	C)
		clean_package_cache=1
	;;
	G)
		write_graph=1
	;;
	b)
		install_boot_code=1
	;;
	d)
		enable_crash_dumping=1
	;;
	u)
		add_users=1
	;;
	o)
		[ "$OPTARG" ] || f_usage
		work_dir="$OPTARG"
	;;
	*)
		f_usage
	;;
	esac
done


#############################
# VALIDATIONS AND OVERRIDES #
#############################

target_prefix=$( printf %.1s "$target_input" )

if [ "$target_prefix" = "/" ] ; then
	if [ "$target_input" = "/" ] ; then
		echo "Target is / - Exiting"
		exit 1
	fi	

	target_type="directory"

	# Override default mount point with input
	# Awkward if setting default to default
	mount_point="$target_input"

else # target is a dataset

# DEBUG SHELLCHECK SUGGESTS QUOTING AFTER THE DOLLAR SIGN
	zpool_name="$( echo "$target_input" | cut -d "/" -f 1 )"
	#zpool get name "$( echo "$target_input" | cut -d "/" -f 1 )" \
	zpool get name $zpool_name \
		> /dev/null 2>&1 || \
		{ echo "Target $target_input likely invalid" ; exit 1 ; }

	zfs get name "$target_input" > /dev/null 2>&1 && \
		{ echo "Target exists - Exiting" ; exit 1 ; }

	zpool_bootfs=$( zpool get -pH -o value bootfs $zpool_name )
	zpool_mountpoint=$( zfs get -pH mountpoint -o value $zpool_bootfs )

echo ; echo DEBUG zpool_bootfs is $zpool_bootfs
echo zpool_mountpoint is $zpool_mountpoint


	target_type="dataset"

fi

# "15.0", "16.0"
release_version=$( echo "$release_input" | cut -d "-" -f 1 )

# "RELEASE", "STABLE", "CURRENT", "RC*",  etc.
release_branch=$( echo "$release_input" | cut -d "-" -f 2 )

# "15", "16"
VERSION_MAJOR="$( echo "$release_version" | cut -d "." -f 1 )"

# "0", "1"
# cut -d "." -f 2 only works with a .N
# 16.x moves to 16.0-CURRENT
VERSION_MINOR="$( echo "$release_version" | cut -d "." -f 2 )"

# Decide if riscv is supported
case "$hw_platform" in
	amd64)
		cpu_arch="amd64"
	;;
	arm64)
		cpu_arch="aarch64"
	;;
	*)
		echo "Invalid architecture"
		exit 1
	;;
esac

if [ "$target_type" = "directory" ] && [ "$nested_datasets" = "1" ] ; then
	echo "-n nested datasets only applies to datasets"
	exit 1
fi

if [ "$target_type" = "directory"] && [ "$copy_package_cache" = "1" ] ; then
	echo "-b boot code update only applies to datasets"
	exit 1
fi

if [ "$release_branch" = "CURRENT" ] && [ "$package_branch" = "quarterly" ] ; then
	echo $release_input cannot be used with quarterly packages
	exit 1 
fi

if [ "$install_boot_code" = "1" ] && [ ! "$target_type" = "dataset" ] ; then
	echo "Updating boot code only applicable to boot environments"
	exit 1
fi

if [ "$enable_crash_dumping" = "1" ] && [ ! "$target_type" = "dataset" ] ; then
	echo "Enagling kernel debugging only applicable to boot environments"
	exit 1
fi

[ "$hw_platform" = "arm64" ] && \
	pkg_sets="$pkg_sets FreeBSD-dtb"

if [ "$enable_crash_dumping" = "1" ] ; then
	dump_device=$(dumpon -l | head -1)
	[ "$dump_device" = "/dev/null" ] && \
		{ echo "No dump device configured" ; exit 1 ; }
	additional_packages="$additional_packages gdb"
fi

if [ "$sideload" = "1" ] && [ "$add_users" = "1" ] ; then
	echo "Sideloading and adding users are mutually exclusive"
	exit 1
fi


















############################
# DIRECTORIES AND DATASETS #
############################

# Moving to private --repo-conf-dir in pkg rather than etc/pkg
[ -d "${work_dir:?}/pkg" ] || \
	mkdir -p "${work_dir:?}/pkg"
[ -d "${work_dir:?}/pkg" ] || \
	{ echo mkdir failed ; exit 1 ; }

if [ "$target_type" = "directory" ] ; then
#	pkg_sets="FreeBSD-set-minimal-jail FreeBSD-set-base-jail"
	pkg_sets="FreeBSD-set-minimal-jail"

	echo Creating root directory
	[ -d "$target_input" ] || mkdir -p "$target_input"
	[ -d "$target_input" ] || \
		{ echo "mkdir $target_input failed" ; exit 1 ; }
	mount_point="$target_input"

elif [ "$target_type" = "dataset" ] ; then

	pkg_sets="FreeBSD-set-minimal FreeBSD-kernel-generic FreeBSD-bootloader"

	echo Creating root dataset
	zfs get name "$target_input" > /dev/null 2>&1 || \
	zfs create -o canmount=noauto -o mountpoint=/ \
		"$target_input"
	zfs get name "$target_input" > /dev/null 2>&1 || \
		{ echo "root dataset failed to create" ; exit 1 ; }

	mkdir -p "${mount_point:?}" || \
		{ echo mkdir $mount_point failed ; exit 1 ; }

	echo ; echo "Mounting root dataset"

	mount -t zfs "$target_input" "${mount_point:?}" || \
		{ echo "target boot environment mount failed" ; exit 1 ; }

	# Make directories as directories or nested mount points
	mkdir ${mount_point:?}/home || { echo mkdir failed ; exit 1 ; }
	mkdir ${mount_point:?}/tmp || { echo mkdir failed ; exit 1 ; }
	mkdir -p ${mount_point:?}/usr/ports ||  { echo mkdir failed ; exit 1 ; }
	mkdir ${mount_point:?}/usr/src || { echo mkdir failed ; exit 1 ; }
	mkdir ${mount_point:?}/usr/obj || { echo mkdir failed ; exit 1 ; }
	mkdir -p ${mount_point:?}/var/audit || { echo mkdir failed ; exit 1 ; }
	mkdir ${mount_point:?}/var/crash || { echo mkdir failed ; exit 1 ; }
	mkdir ${mount_point:?}/var/log || { echo mkdir failed ; exit 1 ; }
	mkdir ${mount_point:?}/var/mail || { echo mkdir failed ; exit 1 ; }
	mkdir ${mount_point:?}/var/tmp || { echo mkdir failed ; exit 1 ; }

	if [ "$nested_datasets" = "1" ] ; then

########################################################################
# Authoritative dataset layouts:                                       #
# /usr/libexec/bsdinstall/zfsboot which lacks /usr/obj                 #
# /usr/src/release/tools/vmimage.subr which lacks /media/var/cache/pkg #
########################################################################

# One approach:
# . /usr/libexec/bsdinstall/zfsboot || \
# 	{ echo "zfsboot failed to source" ; exit 1 ; }
# . /usr/share/bsdconfig/common.subr || \
# 	{ echo "common.subr failed to source" ; exit 1 ; }

		zfs create -o canmount=noauto -o mountpoint=/home \
			"$target_input/home" || \
				{ echo "dataset failed to create" ; exit 1 ; }
		zfs create -o canmount=noauto \
			-o mountpoint=/tmp -o exec=on -o setuid=off \
			"$target_input/tmp" || \
				{ echo "dataset failed to create" ; exit 1 ; }
# Determine correct canmount for nesting
		zfs create -o mountpoint=/usr -o canmount=off \
			"$target_input/usr" || \
				{ echo "dataset failed to create" ; exit 1 ; }
		zfs create -o canmount=noauto -o setuid=off \
			"$target_input/usr/ports" || \
				{ echo "dataset failed to create" ; exit 1 ; }
		zfs create -o canmount=noauto \
			"$target_input/usr/src" || \
				{ echo "dataset failed to create" ; exit 1 ; }
		zfs create -o canmount=noauto \
			"$target_input/usr/obj" || \
				{ echo "dataset failed to create" ; exit 1 ; }
# Determine correct canmount for nesting
		zfs create -o mountpoint=/var -o canmount=off \
			"$target_input/var" || \
				{ echo "dataset failed to create" ; exit 1 ; }
		zfs create -o canmount=noauto -o setuid=off -o exec=off \
			"$target_input/var/audit" || \
			{ echo "dataset failed to create" ; exit 1 ; }
		zfs create -o canmount=noauto -o setuid=off -o exec=off \
			"$target_input/var/crash" || \
				{ echo "dataset failed to create" ; exit 1 ; }
		zfs create -o canmount=noauto -o setuid=off -o exec=off \
			"$target_input/var/log" || \
				{ echo "dataset failed to create" ; exit 1 ; }
		zfs create -o canmount=noauto -o atime=on \
			"$target_input/var/mail" || \
				{ echo "dataset failed to create" ; exit 1 ; }
		zfs create -o canmount=noauto -o setuid=off \
			"$target_input/var/tmp" || \
				{ echo "dataset failed to create" ; exit 1 ; }


#######################################################################
# bectl(8) mount/umount Shortcoming: It works on the imported/mounted #
# boot pool but does not work on a second imported/mounted pool in    #
# the propagation context.                                            #
#######################################################################

# Works with datasets on the boot pool but not on imagine.sh pool:
# bectl mount "$( basename "$target_input" )" \

		echo ; echo "Mounting child datasets"

		# Syntax for flat for fully-nested datasets,
		# not default hybrid layout from bsdinstall or VM images
		# Inspired by /etc/rc.d/zfsbe
		zfs list -rH -o mountpoint,name,canmount,mounted \
			-s mountpoint $target_input | \
        	while read _mp _name _canmount _mounted ; do
			[ "$_name" = "$target_input" ] && continue
			[ "$_canmount" = "off" ] && continue
			[ "$_mounted" = "yes" ] && continue
		mount -t zfs $_name $mount_point/$( echo $_mp | cut -d / -f3-)
		done
	fi # End if nested

else
	echo "Something went very wrong with the target handling"
	exit 1
fi

# root directory and dataset should be agnostic at this point

# A dataset is assumed to be a boot environemnt BUT could be a jail
# A VM image is NOT a dataset...


################
# PACKAGE KEYS #
################

# Following bsdinstall 15.0 - 16.0 appears to use the package keys
# Note that a 15 Jail on 16 might fail for want of the pkgbase-15 keys

echo ; echo Making ${mount_point:?}/usr/share/keys
mkdir -p ${mount_point:?}/usr/share/keys

[ -d ${mount_point:?}/usr/share/keys ] || \
	{ echo ${mount_point:?}/usr/share/keys failed ; exit 1 ; }

# 16-proofing this
echo Coping host keys from /usr/share/keys/pkg to \
	${mount_point:?}/usr/share/keys
cp -R /usr/share/keys/pkg ${mount_point:?}/usr/share/keys/ || \
	{ echo keys copy failed ; exit 1 ; }

if [ -d /usr/share/keys/pkgbase-15 ] ; then
echo Copying host keys from /usr/share/keys/pkgbase-15 to \
	${mount_point:?}/usr/share/keys
	cp -R /usr/share/keys/pkgbase-15 ${mount_point:?}/usr/share/keys/ || \
		{ echo keys copy failed ; exit 1 ; }
fi


########################################
# FreeBSD.conf REPO CONFIGURATION FILE #
########################################

# Note that /etc/pkg/FreeBSD.conf will be overridden by FreeBSD-pkg-bootstrap
echo ; echo Generating "${work_dir:?}/pkg/FreeBSD.conf"

if [ "$release_branch" = "RELEASE" ] ; then
	package_string="${VERSION_MAJOR}:${cpu_arch}/$package_branch"
	kmods_string="${VERSION_MAJOR}:${cpu_arch}/kmods_${package_branch}_$VERSION_MINOR"
	base_string="${VERSION_MAJOR}:${cpu_arch}/base_release_$VERSION_MINOR"
elif [ "$release_branch" = "STABLE" ] ; then
	package_string="${VERSION_MAJOR}:${cpu_arch}/$package_branch"
	kmods_string="${VERSION_MAJOR}:${cpu_arch}/kmods_${package_branch}_$VERSION_MINOR"
	base_string="${VERSION_MAJOR}:${cpu_arch}/base_latest"
elif [ "$release_branch" = "CURRENT" ] ; then
	package_string="${VERSION_MAJOR}:${cpu_arch}/latest"
	kmods_string="${VERSION_MAJOR}:${cpu_arch}/kmods_latest"
	base_string="${VERSION_MAJOR}:${cpu_arch}/base_latest"
else
	# Observe the future behavior of ALPHAs, BETAs, and RCs - Treating like a RELEASE
	package_string="${VERSION_MAJOR}:${cpu_arch}/$package_branch"
	kmods_string="${VERSION_MAJOR}:${cpu_arch}/kmods_${package_branch}_$VERSION_MINOR"
	base_string="${VERSION_MAJOR}:${cpu_arch}/base_release_$VERSION_MINOR"
fi

#if [ "$release_branch" = "CURRENT" ] ; then
#	copy_glob="${abi_major}.snap"
#else
#	copy_glob="$release_version"
#fi

# UCL!
# <<- will strip tab indenting
# 'HERE' to not expand, allowing $ABI

if [ "$VERSION_MAJOR" = "15" ] ; then
	key_kluge="pkgbase-15"
else
	key_kluge="pkg"
fi

cat <<- HERE > "${work_dir:?}/pkg/FreeBSD.conf"
FreeBSD-ports: {
  url: "pkg+https://pkg.FreeBSD.org/FreeBSD:${package_string}",
  mirror_type: "srv",
  signature_type: "fingerprints",
  fingerprints: "/usr/share/keys/pkg",
  enabled: yes
}
FreeBSD-ports-kmods: {
  url: "pkg+https://pkg.FreeBSD.org/FreeBSD:${kmods_string}",
  mirror_type: "srv",
  signature_type: "fingerprints",
  fingerprints: "/usr/share/keys/pkg",
  enabled: yes
}
FreeBSD-base: {
  url: "pkg+https://pkg.FreeBSD.org/FreeBSD:${base_string}",
  mirror_type: "srv",
  signature_type: "fingerprints",
  fingerprints: "/usr/share/keys/${key_kluge}",
  enabled: yes
}
HERE

[ -f "${work_dir:?}/pkg/FreeBSD.conf" ] || \
	{ echo FreeBSD.conf generation failed ; exit 1 ; }

echo ; echo Enabling FreeBSD-base in /usr/local/etc/pkg/repos

[ -d ${mount_point:?}/usr/local/etc/pkg/repos ] || \
	mkdir -p ${mount_point:?}/usr/local/etc/pkg/repos

# create a /usr/local/etc/pkg/repos/FreeBSD.conf file, e.g.:
echo "FreeBSD-base: { enabled: yes }" > \
	${mount_point:?}/usr/local/etc/pkg/repos/FreeBSD-base.conf

[ -f "${mount_point:?}/usr/local/etc/pkg/repos/FreeBSD-base.conf" ] || \
	{ echo ${mount_point:?}/usr/local/etc/pkg/repos/FreeBSD-base.conf failed ; exit 1 ; }


########################
# Copy cached Packages #
########################

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

ls -l ${mount_point:?}/var/cache/pkg/ | tail
du -h -d1 ${mount_point:?}/var/cache/pkg/
echo DBUG HOW DID THAT GO? ; read go

###############
# Install pkg #
###############

echo ; echo "Installing pkg with pkg update"

# Manually setting this for installation - will be automatic at system runtime
ABI="FreeBSD:${VERSION_MAJOR}:${cpu_arch}"

pkg \
	--option ABI="${ABI:?}" \
	--rootdir "${mount_point:?}" \
	--repo-conf-dir "${work_dir:?}/pkg" \
	--option IGNORE_OSVERSION="yes" \
		update || \
		{ echo "pkg install failed" ; exit 1 ; }
#	install -y -- pkg || \

# Repeating to install pkg itself as it cannot be done with base package sets

pkg \
	--option ABI="${ABI:?}" \
	--rootdir "${mount_point:?}" \
	--repo-conf-dir "${work_dir:?}/pkg" \
	--option IGNORE_OSVERSION="yes" \
	install -y -- pkg || \
		{ echo "pkg install failed" ; exit 1 ; }


################
# BASE INSTALL #
################


echo ; echo "Installing base packages"

	pkg \
		--option ABI="${ABI:?}" \
		--rootdir "${mount_point:?}" \
		--repo-conf-dir "${work_dir:?}/pkg" \
		--option IGNORE_OSVERSION="yes" \
		install -U -y --repository FreeBSD-base \
		$pkg_sets || \
			{ echo pkg install failed ; exit 1 ; }	

if [ "$write_graph" = "1" ] ; then
	graph_filename="${work_dir:?}/dependency-graph.g"
        echo ; echo "Writing graphics/graphviz dependency graph $graph_filename"
	awk -f FreeBSD-pkgbase-dep-graph.awk \
	    -v pkg="pkg --option ABI=\"${ABI:?}\" \
	                --option IGNORE_OSVERSION=yes \
	                --rootdir \"${mount_point:?}\" \
	                --repo-conf-dir \"${work_dir:?}/pkg\"" \
	    -v repository=FreeBSD-base \
	    -v base_pkg_exclusions="$base_pkg_exclusions" \
	    > "$graph_filename"
	echo ; echo "This can be graphed with 'fdp -Tx11 ${work_dir:?}/dependency-graph.g' and similar"
fi

# Created by FreeBSD-pkg-bootstrap and no need to generate
echo DEBUG the post-installation"${mount_point:?}/etc/pkg/FreeBSD.conf" reads:
cat "${mount_point:?}/etc/pkg/FreeBSD.conf"

# Q: Remove the temporary one in tmp/pkg?


#######################
# ADDITIONAL PACKAGES #
#######################

# Removing quotation marks here - they are double quotes everywhere but became
# single on the ride

if [ "$additional_packages" ] ; then
	echo Installing additional packages
	pkg \
		--option ABI="${ABI:?}" \
		--option IGNORE_OSVERSION="yes" \
		--rootdir "${mount_point:?}" \
		--repo-conf-dir "${work_dir:?}/pkg" \
		install -y $additional_packages || \
			{ echo "Additional packages failed" ; exit 1 ; }
fi


#################
# CONFIGURATION #
#################

echo ; echo Establishing entropy
# Consider calling /usr/libexec/bsdinstall/entropy
umask 077
for i in /entropy /boot/entropy; do
	i="$mount_point/$i"
	dd if=/dev/random of="$i" bs=4096 count=1
	chown 0:0 "$i"
done

# Need /var/db/entropy/saved-entropy.1 ?
# /usr/libexec/save-entropy
#dd if=/dev/random of=saved-entropy.1 bs=4096 count=1
#chflags nodump saved-entropy.1
#fsync saved-entropy.1 .
#chmod 600 saved-entropy.1
#chflags nodump saved-entropy.1


# PULL FROM BSDINSTALL JAIL for entropy etc.

#/sbin/sysctl -n user.localbase
#/sbin/sysctl -n security.jail.jailed
#/usr/sbin/certctl -D/tmp/jail/ rehash
# pwd_mkdb – generate the password databases
#pwd_mkdb -i -p -d  ${PKG_ROOTDIR}/etc ${PKG_ROOTDIR}/etc/master.passwd
#services_mkdb – generate the services database
#   services_mkdb -l -q -o ${PKG_ROOTDIR}/var/db/services.db ${PKG_ROOTDIR}/
#pwd_mkdb -i -p -d /tmp/jail/etc /tmp/jail/etc/master.passwd
#services_mkdb -l -q -o /tmp/jail/var/db/services.db /tmp/jail/
#cap_mkdb -l /tmp/jail/etc/login.conf
#mkdir -p /tmp/jail/usr/local/etc/pkg/repos
#chroot /tmp/jail /usr/sbin/pw usermod root -h 0
#/usr/sbin/pw usermod root -h 0
#/usr/sbin/pwd_mkdb -C /etc/master.passwd
#pwd_mkdb -p -d /etc -u root /etc/pw.e7Yb1j

#chroot /tmp/jail /usr/bin/newaliases
#cp /etc/resolv.conf /tmp/jail/etc
#cp -P /etc/localtime /tmp/jail/etc
#cp /var/db/zoneinfo /tmp/jail/var/db


###############
# SIDELOADING #
###############

if [ "$sideload" = "1" ] ; then

# Push a working configuration to a fresh installation
	echo "Copying configuration files - missing ones will fail for now"
	[ -f /boot/loader.conf ] && cp /boot/loader.conf \
		"${mount_point:?}/boot/"
	[ -f /etc/fstab ] && cp /etc/fstab "${mount_point:?}/etc/"
	#touch "${mount_point:?}/etc/fstab"
	[ -f /etc/rc.conf ] && cp /etc/rc.conf "${mount_point:?}/etc/"
	[ -f /etc/sysctl.conf ] && cp /etc/sysctl.conf "${mount_point:?}/etc/"
	[ -f /etc/group ] && cp /etc/group "${mount_point:?}/etc/"
	[ -f /etc/pwd.db ] && cp /etc/pwd.db "${mount_point:?}/etc/"
	[ -f /etc/spwd.db ] && cp /etc/spwd.db "${mount_point:?}/etc/"
	[ -f /etc/master.passwd ] && cp /etc/master.passwd \
		"${mount_point:?}/etc/"
	[ -f /etc/passwd ] && cp /etc/passwd "${mount_point:?}/etc/"
	[ -f /etc/wpa_supplicant.conf ] && \
		cp /etc/wpa_supplicant.conf "${mount_point:?}/etc/"
	[ -f /etc/exports ] && \
		cp /etc/exports "${mount_point:?}/etc/"
	# Was failing on host keys
	cp -rp /etc/ssh/* "${mount_point:?}/etc/ssh/"
	cp -rp /root/.ssh "${mount_point:?}/root/"


# Possible base package sideload syntax
#        pkg prime-list | grep FreeBSD- | xargs -o \
#        pkg -o ABI=FreeBSD:16:amd64 --rootdir /tmp/jail \
#        --repo-conf-dir /tmp/jail/etc/pkg/ \
#        -o IGNORE_OSVERSION=yes install -n
#
#	echo "Sideloading packages"
#	pkg prime-list | xargs -o pkg \
#		--option ABI="${ABI:?}" \
#		--option IGNORE_OSVERSION="yes" \
#		--rootdir "${mount_point:?}" \
#		--repo-conf-dir "${work_dir:?}/pkg" \
#		install -y
### REMOVING the exit as 15 and 16 base package sets have changed
###		install -y -- || \
###		{ echo "Package installation failed" ; exit 1 ; }

	echo "Saving off list of installed prime packages to ${mount_point:?}/root/prime-packages.txt"
	pkg prime-list > "${mount_point:?}/root/prime-packages.txt"

else # Not sideloaded
	if [ "$target_type" = "dataset" ] ; then
	# Use sysrc when possible
	# These are pulled from the 15.0-RELEASE ZFS VM-IMAGE
	# Consider adding kern.geom.label.gptid.enable="0" Why?
	cat << HERE > ${mount_point:?}/boot/loader.conf
kern.geom.label.disk_ident.enable=0
zfs_load=YES
#kern.geom.label.gptid.enable="0"
HERE

		echo ; echo The loader.conf reads:
		cat ${mount_point:?}/boot/loader.conf
		echo

		# These are pulled from the 15.0-RELEASE ZFS VM-IMAGE
		cat << HERE > ${mount_point:?}/etc/rc.conf
hostname="propagate"
zfs_enable="YES"
#zpool_reguid="$zpool_name"
#zpool_upgrade="zpool_name"
ifconfig_DEFAULT="DHCP inet6 accept_rtadv"
growfs_enable="YES"
HERE

		echo ; echo The rc.conf reads:
		cat ${mount_point:?}/etc/rc.conf

		# This may easily trip up boot
		# These are pulled from the 14.2-RELEASE ZFS VM-IMAGE

		echo ; echo "Copying in zpool root fstab"
#		cp /etc/fstab ${mount_point:?}/etc/fstab || \
		cp ${zpool_mountpoint}/etc/fstab ${mount_point:?}/etc/fstab || \
			{ echo "fstab cp failed" ; exit 1 ; }
		echo ; echo The fstab reads:
		cat ${mount_point:?}/etc/fstab

	else # Not a dataset
		touch ${mount_point:?}/etc/fstab
	fi

fi # End if sideload

# Needs to be ARM64-aware
#if [ ! "$target_type" = "directory" ] ; then
#	echo Bootability smoke test
#	[ -f $mount_point/boot/loader_lua.efi ] || \
#		{ echo loader_lua.efi missing ; exit 1 ; }

#	[ -f $mount_point/boot/lua/loader.lua ] || \
#		{ echo loader.lua missing ; exit 1 ; }
#fi


###############
# CLEAN CACHE #
###############

#echo DEBUG checking the size of the pkg cache
#	du -h -d 1 "${mount_point:?}/var/cache/pkg"

if [ "$clean_package_cache" = "1" ] ; then
	echo "Cleaning ${mount_point:?}/var/cache/pkg/"
	find -s -f "${mount_point:?}/var/cache/pkg/" -- -mindepth 1 -delete
fi

#echo DEBUG checking the size of the pkg cache
#	du -h -d 1 "${mount_point:?}/var/cache/pkg"


##############
# BOOT CODE #
##############

# A preflight test would be nice but cannot be done if we are supporting
# imagine.sh images as the target will not exist yet for validation

if [ "$install_boot_code" = 1 ] ; then
# Note a review for a tool to perform this https://reviews.freebsd.org/D19588
# Note a "tool to do it" https://github.com/Emrion/uploaders

# Do we care about updating BIOS boot blocks or just the EFI firmware?
# Sources of truth:
# /usr/libexec/bsdinstall/zfsboot:GPART_BOOTCODE='gpart bootcode -b "%s" "%s"'
# /usr/libexec/bsdinstall/zfsboot:GPART_BOOTCODE_PART='gpart bootcode -b "%s" -p "%s" -i %s "%s"'
# Note /usr/src/release/tools/vmimage.subr
# Note src/tools/boot/install-boot.sh
# gpart bootcode [-N] [-b bootcode] [-p partcode -i index] [-f flags] geom
# /sbin/gpart bootcode -p /boot/gptboot -i 1 ada0
# /sbin/gpart bootcode -b /boot/boot0 ada0
# /sbin/gpart bootcode -b /boot/boot ada0s1

	echo ; echo Determining EFI device and partition

	# We have - hopefully - a 50/50 chance
	#/dev/gpt/efiboot0 on /boot/efi (msdosfs, local)
	#/dev/gpt/efiboot100 on /media/boot/efi (msdosfs, local)

	# First look for an imagine.sh-adjusted EFI partition
	if [ -e /dev/gpt/efiboot100 ] ; then
		efi_part="/dev/gpt/efiboot100"
	elif [ -e /dev/gpt/efiboot0 ] ; then
		efi_part="/dev/gpt/efiboot0"
	else
		echo "Cannot determine EFI partition"
		exit 1
	fi

	# Could each member of RAIDZ have an EFI partition? Using the first
	efi_mount=$(mount | grep $efi_part | tail -1 | cut -w -f 3)

	if [ -f ${efi_mount}/efi/freebsd/loader.efi ; then
		echo "Found ${efi_mount}/efi/freebsd/loader.efi"
		cp "${efi_mount}/efi/freebsd/loader.efi" \
			"${efi_mount}/efi/freebsd/loader.efi.bak"
		host_efi_loaders="${efi_mount}/efi/freebsd/loader.efi"
	fi

	if [ -f ${efi_mount}/EFI/BOOT/bootx64.efi ] ; then
		echo "Found ${efi_mount}/EFI/BOOT/bootx64.efi"
		cp "${efi_mount}/EFI/BOOT/bootx64.efi" \
			"${efi_mount}/EFI/BOOT/bootx64.efi.bak"
	host_efi_loaders="$host_efi_loaders ${efi_mount}/EFI/BOOT/bootx64.efi"
	fi

	if [ -f ${efi_mount}/efi/boot/bootaa64.efi ; then
		echo "Found ${efi_mount}/efi/boot/bootaa64.efi"
		cp "${efi_mount}/efi/boot/bootaa64.efi" \
			"${efi_mount}/efi/boot/bootaa64.efi.bak"
	host_efi_loaders="$host_efi_loaders ${efi_mount}/efi/boot/bootaa64.efi"
	fi

	# Could not determine a loader
	if [ ! "$host_efi_loaders" ] ; then
		echo "${efi_mount} not mounted for boot code update"
		exit 1
	fi

	echo ; echo Installing boot code

	for loader in $host_efi_loaders ; do

	cp -a ${mount_point:?}/boot/loader.efi $loader || \
		{ echo "loader.efi cp failed" ; exit 1 ; }
		
	cp -a ${mount_point:?}/boot/loader.efi $loader || \
		{ echo "bootx64.efi cp failed" ; exit 1 ; }
	done
fi


########################
# ENABLE CRASH DUMPING #
########################

if [ "$enable_crash_dumping" = 1 ] ; then

	echo ; echo Enabling crash dumping

	if [ ! $(sysrc -R ${mount_point:?} -c dumpdev) ] ; then
		echo "dumpdev not enabled in ${mount_point:?}/etc/rc.conf"
		echo "Enabling dumpdev=\"AUTO\""
		sysrc -R ${mount_point:?} dumpdev=AUTO || \
			{ echo "sysrc dumpdev=AUTO failed" ; exit 1 ; }
	fi

	if [ ! $(sysctl -n debug.debugger_on_panic) = "1" ] ; then
		echo "Enabling debug.debugger_on_panic=1"
echo "debug.debugger_on_panic=1" >> ${mount_point:?}/etc/sysctl.conf || \
			{ echo "Failed to configure sysctl.conf" ; exit 1 ; }
		echo "Crash dumping can be tested with:"
		echo "sysctl debug.kdb.panic=1"
	fi
fi


#############
# ADD USERS #
#############

if [ "$add_users" = 1 ] ; then

# Do we want the chroots of the original script?
# Pulling from release/tools/arm.sub arm_create_user() and vagrant.conf

# Only works on new users?
#	/usr/sbin/pw -R ${mount_point:?} usermod root -w yes

	# Pulling from rc.local.sh
	echo ; echo Setting root password
	echo -n 'root' | /usr/sbin/pw -R ${mount_point:?} usermod -n root -h 0

	echo ; echo Adding user freebsd
	mkdir -p ${mount_point:?}/home/freebsd
	/usr/sbin/pw -R ${mount_point:?} groupadd freebsd -g 1001

# Note that csh is not installed by default, changing to /bin/sh
	/usr/sbin/pw -R ${mount_point:?} useradd freebsd \
		-m -M 0755 -w yes -n freebsd -u 1001 -g 1001 -G 0 \
		-c 'FreeBSD User' -d '/home/freebsd' -s '/bin/sh'

	ehco ; echo "Enabling sshd"
	echo 'sshd_enable="YES"' >> ${mount_point:?}/etc/rc.conf
fi


###############
# JAIL SCRIPT #
###############

# Borrowed from OccamBSD
if [ "$target_type" = "directory" ] ; then
        echo ; echo "Generating $work_dir/jail.conf"
	cat << HERE > "$work_dir/jail.conf"
propagate {
	host.hostname = propagate;
	path = "$mount_point";
	mount.devfs;
	exec.start = "/bin/sh /etc/rc";
	exec.stop = "/bin/sh /etc/rc.shutdown jail";
}
HERE

	echo ; echo "Generating $work_dir/jail-boot.sh script"
	echo "jail -c -f $work_dir/jail.conf propagate" > \
		"$work_dir/jail-boot.sh"
	echo "jls" >> "$work_dir/jail-boot.sh"
	echo "$work_dir/jail-boot.sh"

[ -f "$work_dir/jail-boot.sh" ] || \
	{ echo "$work_dir/jail-boot.sh failed to create" ; exit 1 ; }

	echo ; echo "Generating $work_dir/jail-halt.sh script"
	echo "jail -r propagate" > "$work_dir/jail-halt.sh"
	echo "umount ${mount_point:?}/dev" >> "$work_dir/jail-halt.sh"
	echo "jls" >> "$work_dir/jail-halt.sh"
	echo "$work_dir/jail-halt.sh"

[ -f "$work_dir/jail-halt.sh" ] || \
	{ echo "$work_dir/jail-halt.sh failed to create" ; exit 1 ; }
fi # End jail


##################
# MOUNT HANDLING #
##################

# DEBUG DECIDE ON CORRECT BEHAVIOR IF A JAIL ETC.

if [ "$keep_mounted" = 0 ] ; then
	if [ "$target_type" = "dataset" ] ; then
		echo ; echo "Unmounting ${mount_point:?}"
#	[ -e "${mount_point:?}/dev/fd" ] && umount "${mount_point:?}/dev"
# Handling this manually to allow for nesting
#		bectl umount -f "$( basename "$target_input" )" || \
#			{ echo "target BE umount failed" ; exit 1 ; }

		# Current mount point will not match the mountpoint property!
		# From /etc/rc.d/zfsbe
		zfs list -rH -o mountpoint,name,mounted \
			-S mountpoint $target_input | \
       		while read _mp _name _mounted ; do
			[ "$_mounted" = "yes" ] && zfs umount $_name
		done
	fi
else
	echo ; echo "To unmount the target root, run:"
#	echo "umount ${mount_point:?}/dev"
	echo "umount ${mount_point:?}"
	echo
fi

# No closing exit for use wrapped by other scripts
