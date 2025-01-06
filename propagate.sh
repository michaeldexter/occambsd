#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause-FreeBSD
#
# Copyright 2024, 2025 Michael Dexter
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

# Version v.0.0.7

# propagate.sh - Packaged Base installer to boot environments and VM-IMAGES 


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
# * A new PkgBase-based VM-IMAGE
#
# The package selection is currently determined by the base_pkg_exclusions
# variable below. Example sets are provided and the community needs to
# come up with a syntax/strategy for base package selection. Some options are:
#
# * Meta Packages
# * Long lists
# * grep -vE exclusions
# * pkg query/rquery -e evaluation
#
# Challenges: You probably want to exclude packages in case a new one
# appears or the base set is re-arranged. Dependencies may surprise you.
#
#
# To install 14.2-RELEASE to the default location of /tmp/propagate/root,
# copying in packages from the host (must also be 14.2-RELEASE), and clean the
# pkg cache on the destination:
#
# sh propagate.sh -r 14.2-RELEASE -c -C
#
# Cleaning up in advance is left to the user and remember to unmount the /dev
# directory of the destination if you want to delete the target root:
#
# umount /tmp/propagate/root/dev
#
#
# To install 14.2-RELEASE to a new boot environment "test" on the zpool "zroot":
#
# sh propagate.sh -r 14.2-RELEASE -c -C -t zroot/ROOT/test
#
# -m will keep it mounted for further configuration
# -d will install ALL base packages (you probably do not want that)
#
#
# To create a 14.2-RELEASE PkgBase VM-IMAGE:
#
# sh propagate.sh -r 14.2-RELEASE -d -c -C -v
#
# To install 15.0-CURRENT to a new boot environment "test" on the zpool "zroot":
#
# sh propagate.sh -r 15.0-CURRENT -C -t t14/ROOT/pb15


#####################
# NOTES AND CAVEATS #
#####################

# This syntax aims to be consistent with occambsd.sh and imagine.sh
#
# That the directory/dataset distinction is made by the leading slash
#
# Cleanup is left to the reader
#
# Q: How to choose a PkgBase kernel such as nodebug?
# A: A loader variable

#########
# USAGE #
#########

f_usage() {
	echo ; echo "USAGE:"
	echo "-r <release> (i.e. 14.2-RELEASE | 15.0-CURRENT - Required)"
	echo "-a <architecture> [ amd64 | arm64 ] (Default: Host)"
	echo "-t <target root directory> (Boot environment or Jail path"
	echo "   i.e. zroot/ROOT/pkgbase15, zroot/jails/pkgbase15 datasets or"
	echo "   /jails/myjail directory"
	echo "   Default: /tmp/propagate/root unless VM image is selected)"
	echo "-u <Custom Repo URL>"
	echo "-m (Keep boot environment mounted for further configuration)"
	echo "-d (Default FreeBSD installation package set with sources)"
	echo "-p \"<additional packages>\" (Quoted space-separated list)"
	echo "-s (Perform best-effort sideload of the current configuration)"
	echo "-c (Copy cached FreeBSD- packages from the host - must match!)"
	echo "-C (Clean package cache after installation)"
	echo "-v (Generate VM image and boot scripts)"
	echo "-O <output directory/work> (Default: /tmp/propagate)"
	echo
	exit 0
}

# Attic
#	echo "-j (Use Jail package set)"
#	echo "-q (quarterly package branch - default latest)"
#	echo "-3 (Install lib32 packages)"
#	echo "-z (Prepare target for ZFS boot)"

###################################
# INTERNAL VARIABLES AND DEFAULTS #
###################################

release_input=""
abi_major=""
abi_minor=""
copy_glob=""
hw_platform=$( uname -m )	# i.e. amd64|arm64
cpu_arch=$( uname -p )		# i.e. amd64|aarch64
target_input=""
target_prefix=""
target_type=""			# directory or dataset
base_repo_url=""
base_repo_string=""
signature_string=""
#FYI: "file:///usr/obj/usr/src/repo/FreeBSD:14:amd64/14.2/"
keep_mounted=0

#############################
# USER-OVERRIDABLE DEFAULTS #
#############################

mount_point="/tmp/propagate/root"
work_dir="/tmp/propagate"
default_packages=0

# A full-featured system, including src
#base_pkg_exclusions="dbg|dev|lib32|tests"

# A full-featured system, without src
base_pkg_exclusions="dbg|dev|lib32|tests|src|src-sys"

# Why does freebsd-ftpd slip in? ftp|ftpd dependency?
#	FreeBSD-zoneinfo: 14.2 [FreeBSD-base]
#	freebsd-ftpd: 20240719 [FreeBSD-latest]

# A lightweight jail system

# Why does this set install zfs no matter how much it is excluded? Dependency?

#base_pkg_exclusions="zfs|ufs-lib32|nfs|ipf|ipfw|telnet|sendmail|rcmds|dhclient|pf|kernel|kernel-generic|kernel-generic-mmccam|kernel-minimal|dbg|dev|lib32|man|tests|src|src-sys|acpi|apm|autofs|bhyve|bluetooth|bootloader|bsdinstall|bsnmp|ccdconfig|clang|cxgbe-tools|dtrace|efi-tools|elftoolchain|examples|fwget|games|geom|ggate|hast|hostapd|hyperv-tools|iscsi|lld|lldb|lp|mlx-tools|nvme-tools|ppp|rescue|rdma|smbutils|src|src-sys|tests|ufs|wpa|ftp|ftpd"

additional_packages=""
sideload=0
copy_cache=0
clean_cache=0
mkvm_image=0

# Check after boot/zfs with a full installation
# Drawing from /usr/src/release/tools/vmimage.subr
skel_dirs="boot/efi/EFI/BOOT
dev
etc/pkg
var/cache/pkg
var/db/pkg
usr/local/etc/pkg/repos
usr/share/keys/pkg/trusted
usr/share/keys/pkg/revoked
mnt
media
root
home
tmp
net
proc
usr/ports
usr/src
usr/obj
var/audit
var/crash
var/log
var/mail
var/tmp
boot/zfs
etc/zfs
boot/firmware
boot/modules
boot/images
boot/fonts
boot/uboot
etc/jail.conf.d
etc/profile.d
etc/rc.conf.d
etc/sysctl.kld.d
etc/zfs/compatibility.d
var/db/etcupdate
var/db/etcupdate/current
var/db/etcupdate/current/boot
var/db/etcupdate/current/etc
var/db/etcupdate/current/etc/autofs
var/db/etcupdate/current/etc/bluetooth
var/db/etcupdate/current/etc/cron.d
var/db/etcupdate/current/etc/defaults
var/db/etcupdate/current/etc/devd
var/db/etcupdate/current/etc/dma
var/db/etcupdate/current/etc/gss
var/db/etcupdate/current/etc/kyua
var/db/etcupdate/current/etc/mail
var/db/etcupdate/current/etc/mtree
var/db/etcupdate/current/etc/newsyslog.conf.d
var/db/etcupdate/current/etc/pam.d
var/db/etcupdate/current/etc/periodic
var/db/etcupdate/current/etc/periodic/daily
var/db/etcupdate/current/etc/periodic/monthly
var/db/etcupdate/current/etc/periodic/security
var/db/etcupdate/current/etc/periodic/weekly
var/db/etcupdate/current/etc/pkg
var/db/etcupdate/current/etc/ppp
var/db/etcupdate/current/etc/rc.d
var/db/etcupdate/current/etc/security
var/db/etcupdate/current/etc/ssh
var/db/etcupdate/current/etc/ssl
var/db/etcupdate/current/etc/syslog.d
var/db/etcupdate/current/root
var/db/etcupdate/current/usr
var/db/etcupdate/current/usr/share
var/db/etcupdate/current/usr/share/nls
var/db/etcupdate/current/var
var/db/etcupdate/current/var/crash
usr/libdata"

# Note permissions

#Note empty files /etc/zfs/exports /etc/zfs/exports.lock

#####################################
# USER INPUT AND VARIABLE OVERRIDES #
#####################################

while getopts r:a:t:u:mdp:scCvzO opts ; do
	case $opts in
	r)
		[ "$OPTARG" ] || f_usage
		release_input="$OPTARG"
		echo "$release_input" | grep -q "\." || f_usage
		echo "$release_input" | grep -q "-" || f_usage

		release_version=$( echo "$release_input" | cut -d "-" -f 1 )
		release_build=$( echo "$release_input" | cut -d "-" -f 2 )

		abi_major="$( echo "$release_version" | cut -d "." -f 1 )"
		# cut -d "." -f 2 only works with a .N
		abi_minor="$( echo "$release_version" | cut -d "." -f 2 )"

		if [ "$release_build" = "CURRENT" ] ; then
			abi_string="base_latest"
			copy_glob="${abi_major}.snap"
		else
			abi_string="base_release_${abi_minor}"
			copy_glob="$release_version"
		fi

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
		target_prefix=$( printf %.1s "$target_input" )

		if [ "$target_prefix" = "/" ] ; then
			if [ "$target_input" = "/" ] ; then
				echo "Target is / - Exiting"
				exit 1
			fi	

			echo Creating root directory
			[ -d "$target_input" ] || mkdir -p "$target_input"
			[ -d "$target_input" ] || \
				{ echo "mkdir $target_input failed" ; exit 1 ; }
			target_type="directory"
			mount_point="$target_input"
		else

# DEBUG SHELLCHECK SUGGESTS QUOTING AFTER THE DOLLAR SIGN
		zpool get name "$( echo "$target_input" | cut -d "/" -f 1 )" \
			> /dev/null 2>&1 || \
			{ echo "Target $target_input likely invalid" ; exit 1 ; }

			zfs get name "$target_input" > /dev/null 2>&1 && \
				{ echo "Target exists - Exiting" ; exit 1 ; }

			target_type="dataset"
			echo Creating root dataset
			zfs get name "$target_input" > /dev/null 2>&1 || \
			zfs create -o canmount=noauto -o mountpoint=/ \
				"$target_input"
			zfs get name "$target_input" > /dev/null 2>&1 || \
			{ echo "root dataset failed to create" ; exit 1 ; }

# PICK YOUR DATASET PROPERTY PARSING METHOD OF CHOICE FROM BSDINSTALL OR VMIAGE
			# From /usr/libexec/bsdinstall/zfsboot
#			echo Sourcing bsdconfig/bsdintall functions/variables
#			# Obtain default ZFSBOOT_DATASETS
#			. /usr/libexec/bsdinstall/zfsboot || \
#				{ echo "zfsboot failed to source" ; exit 1 ; }
#			. /usr/share/bsdconfig/common.subr || \
#			{ echo "common.subr failed to source" ; exit 1 ; }
# FOLLOWING /lab/github/occambsd/vmimage.subr
#			zfs create -o canmount=noauto -o mountpoint=/ \
#				"$target_input"

#                        -o fs=zroot/home\;mountpoint=/home \
			zfs create -o canmount=noauto \
				-o mountpoint=/home \
				"$target_input/home" || \
				{ echo "dataset failed to create" ; exit 1 ; }
#                        -o fs=zroot/tmp\;mountpoint=/tmp\;exec=on\;setuid=off \
			zfs create -o canmount=noauto \
				-o mountpoint=/tmp -o exec=on -o setuid=off \
				"$target_input/tmp" || \
				{ echo "dataset failed to create" ; exit 1 ; }
#                        -o fs=zroot/usr\;mountpoint=/usr\;canmount=off \
# OVERRIDING canmount=off with noauto for nesting
			zfs create \
				-o mountpoint=/usr -o canmount=noauto \
				"$target_input/usr" || \
				{ echo "dataset failed to create" ; exit 1 ; }
#                        -o fs=zroot/usr/ports\;setuid=off \
			zfs create -o canmount=noauto \
				-o setuid=off \
				"$target_input/usr/ports" || \
				{ echo "dataset failed to create" ; exit 1 ; }
#                        -o fs=zroot/usr/src \
			zfs create -o canmount=noauto \
				"$target_input/usr/src" || \
				{ echo "dataset failed to create" ; exit 1 ; }
#                        -o fs=zroot/usr/obj \
			zfs create -o canmount=noauto \
				"$target_input/usr/obj" || \
				{ echo "dataset failed to create" ; exit 1 ; }
#                        -o fs=zroot/var\;mountpoint=/var\;canmount=off \
# OVERRIDING canmount=off with noauto for nesting
			zfs create \
				-o mountpoint=/var -o canmount=noauto \
				"$target_input/var" || \
#                        -o fs=zroot/var/audit\;setuid=off\;exec=off \
			zfs create -o canmount=noauto \
				-o setuid=off -o exec=off \
				"$target_input/var/audit" || \
				{ echo "dataset failed to create" ; exit 1 ; }
#                        -o fs=zroot/var/crash\;setuid=off\;exec=off \
			zfs create -o canmount=noauto \
				-o setuid=off -o exec=off \
				"$target_input/var/crash" || \
				{ echo "dataset failed to create" ; exit 1 ; }
#                        -o fs=zroot/var/log\;setuid=off\;exec=off \
			zfs create -o canmount=noauto \
				-o setuid=off -o exec=off \
				"$target_input/var/log" || \
				{ echo "dataset failed to create" ; exit 1 ; }
#                        -o fs=zroot/var/mail\;atime=on \
			zfs create -o canmount=noauto \
				-o atime=on \
				"$target_input/var/mail" || \
				{ echo "dataset failed to create" ; exit 1 ; }
#                        -o fs=zroot/var/tmp\;setuid=off
			zfs create -o canmount=noauto \
				-o setuid=off \
				"$target_input/var/tmp" || \
				{ echo "dataset failed to create" ; exit 1 ; }

			# BECTL HANDLES OUR NESTING!
			echo "Mounting root dataset"
			bectl mount "$( basename "$target_input" )" \
				"${mount_point:?}" || \
				{ echo "target BE mount failed" ; exit 1 ; }
		fi # End dataset handling
	;;
	u)
		[ "$OPTARG" ] || f_usage
		base_repo_url="$OPTARG"
	;;
	m)
		keep_mounted=1
	;;
	d)
		default_packages=1
		# Not using this approach yet as it may trip up the regex
#		base_pkg_exclusions=""
	;;
	p)
		[ "$OPTARG" ] || f_usage
		additional_packages="$OPTARG"
	;;
	s)
		sideload=1
	;;
	c)
		copy_cache=1
	;;
	C)
		clean_cache=1
	;;
	v)
		mkvm_image=1
	;;
	O)
		[ "$OPTARG" ] || f_usage
		work_dir="$OPTARG"
# Verify that it auto-creates
#		[ -d "${work_dir:?}" ] || \
#			{ echo "${work_dir:?} not found" ; exit 1 ; }
	;;
	*)
		f_usage
	;;
	esac
done

[ "$release_input" ] || f_usage

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

ABI="FreeBSD:${abi_major}:${cpu_arch}"

###############
# DIRECTORIES #
###############

# Consider root_mount_point or even target_root_mount_point for clarity
# Likely a boot environment or jail, but could be a nested one for VM creation
mount_point="/tmp/propagate/root"

# At a minimum the parent of the default mount point
# Location of boot scripts, top root of deeply-nested VM tree 
work_dir="/tmp/propagate"

# root directory and dataset should be agnostic

# A dataset is assumed to be a boot environemnt BUT could be a jail
# A VM image is NOT a dataset...

#########
# TESTS #
#########

if [ "$target_input" = "dataset" ] && [ "$mkvm_image" = "1" ] ; then
	echo "A VM image assumes a work directory but not target directory"
	exit 1
fi

if [ "$target_type" = "dataset" ] && [ "$mkvm_image" = "1" ] ; then
	echo "A VM image assumes a transient directory"
	exit 1
fi

if [ "$mkvm_image" = "1" ] ; then
	# Need a work directory and prefixed parent directories
	# Either use the default or overridden work directory
	# work_dir="/tmp/propagate"

	# Only used by VM-IMAGES so set here
	fake_obj_dir="$work_dir"
	fake_src_dir="$work_dir/src"

	mount_point="$fake_obj_dir$fake_src_dir/amd64.amd64/release/vm"

	echo Making directories
	mkdir -p "$fake_src_dir/release/scripts" || { echo "failed" ; exit 1 ; }
	mkdir -p "$fake_src_dir/release/tools" || { echo "failed" ; exit 1 ; }
	mkdir -p "${mount_point:?}/dev"

	echo Fetching release script and tool

	fetch https://cgit.freebsd.org/src/plain/release/scripts/mk-vmimage.sh \
		-o "$fake_src_dir/release/scripts/mk-vmimage.sh" || \
			{ echo "mk-vmimage.sh fetch failed" ; exit 1 ; }

	fetch https://cgit.freebsd.org/src/plain/release/tools/vmimage.subr \
		-o "$fake_src_dir/release/tools/vmimage.subr" || \
			{ echo "vmimage.subr fetch failed" ; exit 1 ; }
fi # End extra VM scaffolding

echo Creating skeleton directories

for directory in $skel_dirs ; do
	mkdir -vp "${mount_point:?}/${directory:?}" || \
		{ echo "mkdir $directory failed" ; exit 1 ; }
done

#pkg-static: Cannot open dev/null
echo Mounting devfs for pkg-static
mount -t devfs -o ruleset=4 devfs "${mount_point:?}/dev" || \
	{ echo "mount devfs failed" ; exit 1 ; }

	mkdir -p "${mount_point:?}/usr/share/keys/pkg/trusted"
echo Generating pkg.freebsd.org.2013102301 key
cat <<- HERE > "${mount_point:?}/usr/share/keys/pkg/trusted/pkg.freebsd.org.2013102301"

function: "sha256"
fingerprint: "b0170035af3acc5f3f3ae1859dc717101b4e6c1d0a794ad554928ca0cbb2f438"
HERE

[ -f "${mount_point:?}/usr/share/keys/pkg/trusted/pkg.freebsd.org.2013102301" ] || { echo "pkg.freebsd.org.2013102301 failed" ; exit 1 ; }

#du -h ${mount_point:?}

########################################
# FreeBSD.conf REPO CONFIGURATION FILE #
########################################

echo ; echo Generating "${mount_point:?}/etc/pkg/FreeBSD-base.conf"

mkdir -p "${mount_point:?}/etc/pkg" || \
	{ echo "mkdir ${mount_point:?}/etc/pkg failed" ; exit ; }

# WILL WE NEED TO OVERWRITE $ABI when cross installing?

if [ -n "$base_repo_url" ] ; then
	base_repo_string="$base_repo_url"
else
	base_repo_string="pkg+https://pkg.FreeBSD.org/\${ABI}/${abi_string}"
	signature_string="fingerprints"
fi

# UCL!
# <<- will strip tab indenting
# 'HERE' to not expand, allowing $ABI

cat <<- HERE > "${mount_point:?}/etc/pkg/FreeBSD-base.conf"
FreeBSD-base: {
  priority: 10
  enabled: yes
  url: "$base_repo_string"
  mirror_type: "srv"
  signature_type: "$signature_string"
  fingerprints: "/usr/share/keys/pkg"
}
HERE

[ -f "${mount_point:?}/etc/pkg/FreeBSD-base.conf" ] || \
	{ echo FreeBSD-base.conf failed ; exit 1 ; }

echo ; echo Generating "${mount_point:?}/etc/pkg/FreeBSD-latest.conf"

# Priority overrides the default of quarterly
# 'HERE' = NO SHELL VARIABLE EXPANSION
#cat <<- 'HERE' > "${mount_point:?}/etc/pkg/FreeBSD-latest.conf"
cat <<- HERE > "${mount_point:?}/etc/pkg/FreeBSD-latest.conf"
FreeBSD-latest: {
  priority: 10
  enabled: yes
  url: "pkg+https://pkg.FreeBSD.org/\${ABI}/latest"
  mirror_type: "srv"
  signature_type: "fingerprints"
  fingerprints: "/usr/share/keys/pkg"
  enabled: yes
}
HERE

[ -f "${mount_point:?}/etc/pkg/FreeBSD-latest.conf" ] || \

mkdir -p "${mount_point:?}/usr/local/etc/pkg/repos" || \
{ echo "mkdir ${mount_point:?}/usr/local/etc/pkg/repos failed" ; exit 1 ; }

echo ; echo "Generating ${mount_point:?}/usr/local/etc/pkg/repos/FreeBSD-quarterly.conf"
cat <<- HERE > "${mount_point:?}/usr/local/etc/pkg/repos/FreeBSD-quarterly.conf"
FreeBSD: { enabled: no }
HERE

[ -f "${mount_point:?}/usr/local/etc/pkg/repos/FreeBSD-quarterly.conf" ] || \
	{ echo "FreeBSD-quarterly.conf failed" ; exit 1 ; }

echo "Installing pkg"

pkg \
	--option ABI="${ABI:?}" \
	--option IGNORE_OSVERSION="yes" \
	--rootdir "${mount_point:?}" \
	--repo-conf-dir "${mount_point:?}/etc/pkg" \
	install -y -- pkg || \
		{ echo "pkg install failed" ; exit 1 ; }

#####################
# INSTALL PREFLIGHT #
#####################

################
# BASE INSTALL #
################

if [ "$copy_cache" = "1" ] ; then
	echo ; echo "Copying /var/cache/pkg/FreeBSD- packages from the host"
#cp: /var/cache/pkg/FreeBSD-*14.2.pkg: No such file or directory
#    /var/cache/pkg/FreeBSD-vi-14.2.pkg

# This will fail if there is not a match
#	cp -p "/var/cache/pkg/FreeBSD-*${copy_glob}.pkg" \
	find /var/cache/pkg -type f | grep "$copy_glob" | xargs -I % cp % \
		"${mount_point:?}/var/cache/pkg/"
	
fi

#echo ; echo SMOKE TEST: Counting requested packages
#pkg \
#	--option ABI="${ABI:?}" \
#	--option IGNORE_OSVERSION="yes" \
#	--rootdir "${mount_point:?}" \
#	--repo-conf-dir "${mount_point:?}/etc/pkg" \
#	rquery --repository="FreeBSD-base" '%n' \
#	| grep -vE "($base_pkg_exclusions)" \
#	| wc -l

echo ; echo Installing base packages

if [ "$default_packages" = "1" ] || [ -n "$base_pkg_exclusion" ] ; then
# No special requests, install every available FreeBSD-* package
# Strong quoting required for egrep and variables

pkg \
	--option ABI="${ABI:?}" \
	--option IGNORE_OSVERSION="yes" \
	--rootdir "${mount_point:?}" \
	--repo-conf-dir "${mount_point:?}/etc/pkg" \
	rquery --repository="FreeBSD-base" '%n' \
	| grep -vE "($base_pkg_exclusions)" \
		| xargs -o pkg \
			--option ABI="${ABI:?}" \
			--option IGNORE_OSVERSION="yes" \
			--rootdir "${mount_point:?}" \
			--repo-conf-dir "${mount_point:?}/etc/pkg" \
			install \
			--
else

pkg \
	--option ABI="${ABI:?}" \
	--option IGNORE_OSVERSION="yes" \
	--rootdir "${mount_point:?}" \
	--repo-conf-dir "${mount_point:?}/etc/pkg" \
	rquery --repository="FreeBSD-base" '%n' \
	| grep -vE "($base_pkg_exclusions)" \
		| xargs -o pkg \
			--option ABI="${ABI:?}" \
			--option IGNORE_OSVERSION="yes" \
			--rootdir "${mount_point:?}" \
			--repo-conf-dir "${mount_point:?}/etc/pkg" \
			install \
			--
fi

#echo DEBUG checking the size of the result
#	du -h -d 1 "${mount_point:?}"

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
		--repo-conf-dir "${mount_point:?}/etc/pkg" \
		install -y "$additional_packages" || \
			{ echo "Additional packages failed" ; exit 1 ; }
fi

#################
# CONFIGURATION #
#################

if [ "$sideload" = "1" ] ; then

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
	# Was failing on host keys
	cp -rp /etc/ssh/* "${mount_point:?}/etc/ssh/"
	cp -rp /root/.ssh "${mount_point:?}/root/"

	echo "Sideloading packages"
	pkg prime-list | xargs -o pkg \
		--option ABI="${ABI:?}" \
		--option IGNORE_OSVERSION="yes" \
		--rootdir "${mount_point:?}" \
		--repo-conf-dir "${mount_point:?}/etc/pkg" \
		install -y -- || \
		{ echo "Package installation failed" ; exit 1 ; }

elif [ "$target_type" = "dataset" ] || [ "$mkvm_image" = "1" ] ; then
	# Use sysrc when possible
	cat << HERE > ${mount_point:?}/boot/loader.conf
kern.geom.label.disk_ident.enable="0"
kern.geom.label.gptid.enable="0"
cryptodev_load="YES"
zfs_load="YES"
HERE

	echo ; echo The loader.conf reads:
	cat ${mount_point:?}/boot/loader.conf
	echo

	cat << HERE > ${mount_point:?}/etc/rc.conf
hostname="propagate"
zfs_enable="YES"
HERE

	echo ; echo The rc.conf reads:
	cat ${mount_point:?}/etc/rc.conf
	echo
fi

###############
# CLEAN CACHE #
###############

#echo DEBUG checking the size of the pkg cache
#	du -h -d 1 "${mount_point:?}/var/cache/pkg"

if [ "$clean_cache" = "1" ] ; then
	echo "Cleaning ${mount_point:?}/var/cache/pkg/"
	find -s -f "${mount_point:?}/var/cache/pkg/" -- -mindepth 1 -delete
fi

#echo DEBUG checking the size of the pkg cache
#	du -h -d 1 "${mount_point:?}/var/cache/pkg"

#################
# UPDATE SCRIPT #
#################

cat << HERE > "${mount_point:?}/root/update-pkgbase.sh"
#!/bin/sh

pkg upgrade

if [ -f /etc/ssh/sshd_config.save ] ; then
	mv /etc/ssh/sshd_config /etc/ssh/sshd_config.default
	cp /etc/ssh/sshd_config.pkgsave /etc/ssh/sshd_config
# Check if running?
	service sshd restart
fi

if [ -f /etc/group.pkgsave ] ; then
	mv /etc/group /etc/group.default
	cp /etc/group.pkgsave /etc/group
fi

if [ -f /etc/master.passwd.save ] ; then
	mv /etc/master.passwd /etc/master.passwd.default
	cp /etc/master.passwd.pkgsave /etc/master.passwd
	pwd_mkdb -p /etc/master.passwd
fi

if [ -f /etc/sysctl.conf.pkgsave ] ; then
	mv /etc/sysctl.conf /etc/sysctl.conf.default
	cp /etc/sysctl.conf.pkgsave /etc/sysctl.conf
fi

if [ -f /etc/shells.pkgsave ] ; then
	mv /etc/shells /etc/shells.default
	cp /etc/shells.pkgsave /etc/shells
fi
HERE

[ -f "${mount_point:?}/root/update-pkgbase.sh" ] || \
	{ echo "update-packages.sh failed" ; exit 1 ; }

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

if [ "$mkvm_image" = 1 ] ; then

# Deleting if re-running
[ -f "${fake_src_dir}/release/scripts/propagate-mkvm-image.sh" ] && \
	rm "${fake_src_dir}/release/scripts/propagate-mkvm-image.sh"

	[ -e "${mount_point:?}/vm/fd" ] && umount "${mount_point:?}/vm/dev"

#################################################
# COPY FROM DESTINATION TO A FAKE SRC DIRECTORY #
#################################################

	# Satisfying dependencies in the order in which they failed
	mkdir -p "$fake_src_dir/stand/efi/loader_lua" || \
		{ echo "Failed to make loader_lua directory" ; exit 1 ; }

	cp "$mount_point/boot/loader_lua.efi" \
		"$fake_src_dir/stand/efi/loader_lua/" || \
			{ echo "loader_lua.efi failed to copy" ; exit 1 ; }

	mkdir -p "$fake_src_dir/stand/i386/pmbr" || \
		{ echo "pmbr directory failed to make" ; exit 1 ; }

	cp "$mount_point/boot/pmbr" \
		"$fake_src_dir/stand/i386/pmbr/" || \
			{ echo "pmbr failed to copy" ; exit 1 ; }

	mkdir -p "$fake_src_dir/stand/i386/gptzfsboot" || \
		{ echo "gptzfsboot directory failed to make" ; exit 1 ; }

	cp "$mount_point/boot/gptzfsboot" \
		"$fake_src_dir/stand/i386/gptzfsboot/" || \
			{ echo "gptzfsboot failed to copy" ; exit 1 ; }

	mkdir -p "$fake_src_dir/tools/boot" || \
		{ echo "$fake_src_dir/tools/boot failed to make" ; exit 1 ; }

	# ACTUAL HOST SOURCE DIRECTORY
	cp /usr/src/tools/boot/install-boot.sh \
		"$fake_src_dir/tools/boot/" || \
			{ echo "install-boot.sh failed to copy" ; exit 1 ; }

	[ -f "$fake_src_dir/release/scripts/propagate-mkvm-image.sh" ] && \
		rm "$fake_src_dir/release/scripts/propagate-mkvm-image.sh"

	cat << HERE > "$fake_src_dir/release/scripts/propagate-mkvm-image.sh"

# Trying this in an attempt to call from the original script
cd "$fake_src_dir/release/scripts/"

[ -e "${mount_point:?}/dev/fd" ] && umount "${mount_point:?}/dev"

# REQUIRED
WORLDDIR=$fake_src_dir
export MAKEOBJDIRPREFIX=$fake_obj_dir
VMSIZE=8g
#export VMFSLIST=zfs
VMFS=zfs
TARGET=amd64
TARGET_ARCH=amd64
VMFORMAT=raw
# THE IMAGE OR PARTITION?
#export VMIMAGE=$fake_obj_dir/../vm.zfs.img
VMBASE=raw.zfs.img
VMIMAGE=vm.zfs.img
# WHOOPS: SETTING VMROOT MAY BLOW UP makefs (core dump)
DESTDIR=$mount_point
#DESTDIR=$fake_obj_dir
SWAPSIZE=1g

. ../tools/vmimage.subr
vm_create_disk
HERE

	[ -f "$fake_src_dir/release/scripts/propagate-mkvm-image.sh" ] || \
		{ echo "$fake_src_dir/release/scripts/propagate-mkvm-image.sh failed" ; exit 1 ; }

	echo ; echo "Generating the VM-IMAGE"
	sh $fake_src_dir/release/scripts/propagate-mkvm-image.sh || \
		{ echo "sh $fake_src_dir/release/scripts/propagate-mkvm-image.sh failed" ; exit 1 ; }

	echo "Generating simple boot script"
cat << HERE > "$fake_src_dir/release/scripts/boot-vm.sh"
#!/bin/sh
[ \$( id -u ) = 0 ] || { echo "Must be root" ; exit 1 ; }
[ -e /dev/vmm/propagate ] && { bhyvectl --destroy --vm=propagate ; sleep 1 ; }
[ -f /usr/local/share/uefi-firmware/BHYVE_UEFI.fd ] || \\
	{ echo \"BHYVE_UEFI.fd missing\" ; exit 1 ; }

kldstat -q -m vmm || kldload vmm
sleep 1

bhyve -m 1G -A -H -l com1,stdio -s 31,lpc -s 0,hostbridge \\
	-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd \\
	-s 2,virtio-blk,$fake_src_dir/release/scripts/vm.zfs.img \\
	propagate

sleep 2
bhyvectl --destroy --vm=propagate
HERE

echo ; echo "To boot the VM image, run:"
echo ; echo "sh $fake_src_dir/release/scripts/boot-vm.sh"
echo

fi # End if VM-IMAGE

##################
# MOUNT HANDLING #
##################

# DEBUG DECIDE ON CORRECT BEHAVIOR

if [ "$keep_mounted" = 0 ] ; then
	if [ "$target_type" = "dataset" ] ; then
		echo ; echo "Unmounting ${mount_point:?}"
		umount "${mount_point:?}/dev" || \
			{ echo "${mount_point:?}/dev umount failed" ; exit 1 ; }
#		umount ${mount_point:?} || \
#			{ echo "${mount_point:?} failed to unmount" ; exit 1 ; }
			bectl umount "$( basename "$target_input" )" || \
				{ echo "target BE umount failed" ; exit 1 ; }

	else
		echo ; echo "To unmount the target root, run:"
		echo "umount ${mount_point:?}/dev"
		echo "umount ${mount_point:?}"
		echo
	fi
fi

# No closing exit for use wrapped by other scripts
