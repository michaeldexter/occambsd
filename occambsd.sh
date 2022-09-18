#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause-FreeBSD
#
# Copyright 2021, 2022 Michael Dexter
# All rights reserved
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted providing that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#	notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#	notice, this list of conditions and the following disclaimer in the
#	documentation and/or other materials provided with the distribution.
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

# Version v5.6

f_usage() {
        echo "USAGE:"
	echo "-p <profile file> (required)"
	echo "-s <source directory override>"
	echo "-o <object directory override>"
	echo "-z (Use ZFS)"
	echo "-x (Use Xen)"
	echo "-j (Use Jail)"
	echo "-u (Use an artisinal userland in place of buildworld"
	echo "-r (Also make release)"
	echo "-d <device> (Use specific device <device>)"
	echo "-q (Quiet mode: Do not ask to proceed at every stage)"
	echo "-k (Keep and reuse build output in quiet mode)"
        exit 1
}

f_quiet() (
	if [ "$quiet" = "0" ] ; then
		echo ; echo "Press ANY key to continue"
		read anykey
	fi
)

# occambsd: An application of Occam's razor to FreeBSD
# a.k.a. "super svelte stripped down FreeBSD"

# This will create a kernel directories and disk images for bhyve and xen,
# a jail(8) root directory, and related load, boot, and cleanup scripts.

# The default target is the bhyve hypervisor but Xen can be specified with
# -x and Jail with -j

# The separate kernel directory is very useful for testing kernel changes
# while waiting for institutionalized VirtFS support.

# The -u option will build and install a minimal, artisanal userland,
# rather than building and installing world


# DEFAULT VARIABLES

profile="0"
target="bhyve"
quiet="0"
keep="0"
zfsroot="0"
release="0"
hardware_device="0"
artisanal_userland="0"
device="md42"				# Ask Douglas Adams for an explanation
src_dir="/usr/src"			# Can be overridden
obj_dir="/usr/obj"			# Can be overridden
work_dir="/tmp/occambsd"
log_dir="$work_dir/logs"		# Must stay under work_dir
imagesize="4G"
buildjobs="$(sysctl -n hw.ncpu)"

while getopts p:s:o:zxjurd:qk opts ; do
	case $opts in
	p)
		# REQUIRED
		[ "${OPTARG}" ] || f_usage
		profile="${OPTARG}"
		. "${OPTARG}" || \
	        { echo "Profile file ${OPTARG} failed to source" ; exit 1 ; }
		;;
	s)
		# Override source directory
		src_dir="${OPTARG}"
		[ -d "$src_dir" ] || { echo "$src_dir not found" ; exit 1 ; }
		;;
	o)
		# Override source directory
		obj_dir="${OPTARG}"
		[ -d "$obj_dir" ] || { echo "$obj_dir not found" ; exit 1 ; }
		;;
	z)
		zfsroot="1"
		;;
	x)
		target="xen"
		;;
	j)
		target="jail"
		;;
	u)
		artisanal_userland="1"
		;;
	r)
		release="1"
		;;
	d)
		# Override memory device
		device="${OPTARG}"
		# Needed to distinguish hardware devices from md for setup
		device="$( basename "$device" )"
		[ -e "/dev/$device" ] || \
			{ echo "${1}: Device $device not found" ; exit 1 ; }
		gpart show "$device" > /dev/null 2>&1 && \
			{ echo "${1}: $device is partitioned" ; exit 1 ; }
		hardware_device="1"
		;;
	q)
		quiet="1"
		;;
	k)
		keep="1"
		;;
	*)
		f_usage
		exit 1
		;;
	esac
done

# If no profile specified (rquired)
[ "$profile" = "0" ] && f_usage

[ -f $src_dir/sys/amd64/conf/GENERIC ] || \


# CLEANUP

# Policy: Always cleanse target media but offer to cleanse build objects,
# allowing reuse

# Note: mount | grep name is not a reliable verification is something is mounted
# Note: The same mount can exist multiple times

# First clean up mounts, devices, and pool outside the world directory

jls | grep -q occambsd && jail -r occambsd
[ -e /dev/vmm/occambsd ] && bhyvectl --destroy --vm=occambsd

[ -d "$work_dir/device-mnt" ] && \
	umount -f "$work_dir/device-mnt" > /dev/null 2>&1
[ -d "$work_dir/jail-mnt/dev" ] && \
	umount -f "$work_dir/jail-mnt/dev" > /dev/null 2>&1

if [ $( which xl ) ]; then
	xl list | grep OccamBSD && xl destroy OccamBSD
	xl list | grep OccamBSD && \
		{ echo "OccamBSD DomU failed to destroy" ; exit 1 ; }
fi
 
zpool get name occambsd && zpool export -f occambsd > /dev/null 2>&1
zpool get name occambsd > /dev/null 2>&1 && \
	{ echo "zpool occambsd failed to export" ; exit 1 ; }

if [ "$hardware_device" = "0" ] ; then
	echo Using a md device
	mdconfig -du "$device" > /dev/null 2>&1
	mdconfig -du "$device" > /dev/null 2>&1
	mdconfig -lv

	if [ "$quiet" = "0" ] ; then 
		echo ; echo is md42 listed? If so, go destroy it manually
		echo ; echo Press ANY key to continue ; read anykey
	fi
fi


# PREPARATION

# Create fresh if greenfield, conditionally cleanse if existing

# Condition 1: Greenfield
if ! [ -d $obj_dir ] ; then
	mkdir -p "$obj_dir" || { echo Failed to make $obj_dir ; exit 1 ; }
fi

if ! [ -d $work_dir ] ; then
	echo Creating $work_dir
	# Creating log_dir includes parent directory work_dir
	mkdir -p "$log_dir" || \
		{ echo Failed to create $work_dir ; exit 1 ; }

	# Assume obj_dir is external to work_dir and should be cleansed
	if [ -d $obj_dir ] ; then
		echo ; echo Cleaning object directory
#		Note: env MAKEOBJDIRPREFIX=$obj_dir make -C $src_dir clean
		chflags -R 0 $obj_dir
		rm -rf $obj_dir/*
	fi
else # work_dir exists and we want to keep the build artifacts
	if [ "$keep" = "0" ] ; then
		echo ; echo Cleansing $work_dir
		rm -rf $work_dir/*
		mkdir -p $log_dir
		if [ -d $obj_dir ] ; then
			echo ; echo Cleaning object directory
			chflags -R 0 $obj_dir
			rm -rf $obj_dir/*
		fi
	else # PRESERVE and selectively remove target-specific artifacts
		[ -f $work_dir/occambsd.raw ] && rm $work_dir/occambsd.raw
		[ -f $work_dir/filetree.txt ] && rm $work_dir/filetree.txt
		[ -f $work_dir/diskusage.txt ] && rm $work_dir/diskusage.txt
		[ -f $work_dir/logs/install-dist.log ] && \
			rm $work_dir/logs/install-dist.log
		[ -f $work_dir/logs/install-world.log ] && \
			rm $work_dir/logs/install-world.log
		[ -f $work_dir/logs/install-kernel.log ] && \
			rm $work_dir/logs/install-kernel.log
	fi
fi


# MAKE SRC.CONF/KERNCONF CONDITIONAL ON PRESERVING
# Shame to make it a MASSIVE long indentation


if [ "$keep" = "0" ] ; then
	echo ; echo Generating $work_dir/all-options.txt

	all_options=$( make -C $src_dir showconfig \
		__MAKE_CONF=/dev/null SRCCONF=/dev/null \
		| sort \
		| sed '
			s/^MK_//
			s/=//
		' | awk '
		$2 == "yes"	{ printf "WITHOUT_%s=YES\n", $1 }
		$2 == "no"	{ printf "WITH_%s=YES\n", $1 }
		'
	)

	echo "$all_options" > $work_dir/all_options.conf

	#echo ; echo DEBUG all_options.conf reads:
	#cat $work_dir/all_options.conf


	echo ; echo Generating $work_dir/src.conf

	# Prune WITH_ options leaving only WITHOUT_ options
	IFS=" "
	without_options=$( echo $all_options | grep -v WITH_ )
	#echo ; echo without_options reads
	#echo $without_options

	# Remove enabled_options to result in the desired src.conf
	IFS=" "
	for option in $build_options ; do
#		echo DEBUG looking at $option
		without_options=$( echo $without_options | grep -v $option )
	done

	echo $without_options > $work_dir/src.conf

	echo ; echo The generated $work_dir/src.conf tails:
	tail $work_dir/src.conf

f_quiet


# MODULES

	ls /usr/src/sys/modules/ | cat > $work_dir/all_modules.txt
	echo ; echo All modules are listed in $work_dir/all_modules.txt


# DO YOU WANNA BUILD A KERN CONF?

# A space-separated profile file must have:
# $kernel_modules	i.e. makeoptions	MODULES_OVERRIDE="*module*..."
# $kernel_options	i.e. options		*SCHED_ULE*
# $kernel_devices	i.e. device		*pci*
# $packages		i.e. tmux

	echo "cpu	HAMMER" > $work_dir/OCCAMBSD
	echo "ident	OCCAMBSD" >> $work_dir/OCCAMBSD
	echo "makeoptions	MODULES_OVERRIDE=\"$kernel_modules\"" \
		>> $work_dir/OCCAMBSD

	IFS=" "
	for kernel_option in $kernel_options ; do
		echo "options	$kernel_option" >> $work_dir/OCCAMBSD
	done

	IFS=" "
	for kernel_device in $kernel_devices ; do
		echo "device	$kernel_device" >> $work_dir/OCCAMBSD
	done

	echo cat $work_dir/OCCAMBSD

	echo ; echo The resulting OCCAMBSD KERNCONF is
	cat $work_dir/OCCAMBSD

	f_quiet

fi # End if keep condition


# DIRECTORIES, DISK IMAGES, AND PARTITIONING

# SHOULD THIS BE IN THE DIRECTORY SETUP?
# NO CONDITIONAL CREATION: ONLY CREATE NEW

echo ; echo Setting up storage target - watch for errors

if [ "$target" = "jail" ] ; then
	mkdir -p "$work_dir/jail-mnt"
else
	mkdir -p "$work_dir/kernel/boot"
	mkdir -p "$work_dir/kernel/etc"
	mkdir -p "$work_dir/device-mnt"

	if [ "$hardware_device" = "0" ] ; then
		echo ; echo Truncating occambsd.raw image

		# Consider -t malloc and tmpfs
		truncate -s "$imagesize" "$work_dir/occambsd.raw" || \
		{ echo truncate $work_dir/occambsd.raw image failed ; exit 1 ; }

		echo ; echo Attaching occambsd.raw VM image
		mdconfig -a -u "$device" -f "$work_dir/occambsd.raw"

		[ -e /dev/$device ] || \
			{ echo $device did not attach ; exit 1 ; }
	fi

f_quiet

echo ; echo Partitioning and formating $device
	echo Creating GPT partition layout
	gpart create -s gpt $device

	echo ; echo Adding freebsd-boot partition
#	[ -e /dev/gpt/gptboot0 ] && \
	[ -e /dev/gpt/gptoccamboot0 ] && \
		{ echo "/dev/gpt/gptoccamboot0 already in use" ; exit 1 ; }
	#gpart add -t freebsd-boot -l bootfs -b 128 -s 128K $device
#	gpart add -a 4k -s 512k -t freebsd-boot /dev/$device
#	gpart add -a 4k -s 512k -l gptboot0 -t freebsd-boot /dev/$device
	gpart add -a 4k -s 512k -l gptoccamboot0 -t freebsd-boot $device
#	sleep 1
	echo ; echo Verifying freebsd-boot partition label gptoccamboot0
	[ -e /dev/gpt/gptoccamboot0 ] || \
		{ echo "/dev/gpt/gptoccamboot0 not found" ; exit 1 ; }

	echo Adding freebsd-swap partition
	[ -e /dev/gpt/occamswap0 ] && \
		{ echo "/dev/gpt/occamswap0 already in use" ; exit 1 ; }
	gpart add -l occamswap0 -t freebsd-swap -s 1G $device
#	sleep 1
	echo ; echo Verifying freebsd-boot partition label occamswap0
	[ -e /dev/gpt/occamswap0 ] || \
		{ echo "/dev/gpt/occamswap0 not found" ; exit 1 ; }

gpart show $device

	if [ "$zfsroot" = "1" ] ; then

# Note that boot code is in stand and must be built before installation

		echo Adding freebsd-zfs partition
		[ -e /dev/gpt/occamroot0 ] && \
			{ echo "/dev/gpt/occamroot0 already in use" ; exit 1 ; }
		gpart add -l occamroot0 -t freebsd-zfs $device || \
			{ echo "gpart add -t freebsd-zfs failed" ; exit 1 ; }
#		sleep 1
		echo ; echo Verifying freebsd-root partition label occamroot0
		[ -e /dev/gpt/occamroot0 ] || \
			{ echo "/dev/gpt/occamroot0 not found" ; exit 1 ; }

		gpart show -l $device

		echo ; echo Creating occambsd zpool

		# Disabling compression while testing -O compress=lz4
		# Note: copies=2
		zpool create -R $work_dir/device-mnt \
			-O atime=off -m none occambsd /dev/gpt/occamroot0 || \
			{ echo zpool create failed ; exit 1 ; }

		zpool list

		echo Creating boot environment dataset
		zfs create -o mountpoint=none occambsd/ROOT || \
			{ echo "zfs create ROOT failed" ; exit 1 ; }

		echo Creating default dataset
		zfs create -o mountpoint=/ occambsd/ROOT/default || \
			{ echo "zfs create default failed" ; exit 1 ; }

		# Consider far more to-be-read-only datasets here

		echo setting bootfs
		zpool set bootfs=occambsd/ROOT/default occambsd || \
			{ echo "zpool set bootfs failed" ; exit 1 ; }

		# Not needed for kernel-in-image boot, not helpful with kernel
		#zpool set cachefile=$device-mnt/boot/zfs/zpool.cache occambsd
	else
		gpart add -l occamroot0 -t freebsd-ufs /dev/$device
		newfs -U /dev/gpt/occamroot0 || \
			{ echo "/dev/gpt/occamroot0 newfs failed" ; exit 1 ; }
		echo ; echo Mounting /dev/gpt/occamroot0
		mount /dev/gpt/occamroot0 $work_dir/device-mnt || \
			{ echo "/dev/gpt/occamroot0 mount failed" ; exit 1 ; }
	fi
fi

f_quiet


# USERLAND

if [ "$target" = "jail" ] ; then
	dest_dir="$work_dir/jail-mnt"
else
	dest_dir="$work_dir/device-mnt"
fi

if [ "$keep" = "0" ] ; then
	if [ "$artisanal_userland" = "0" ] ; then
		echo ; echo Building world - logging to $log_dir/build-world.log
		\time -h env MAKEOBJDIRPREFIX=$obj_dir make -C $src_dir \
		-j$buildjobs SRCCONF=$work_dir/src.conf buildworld \
        	> $log_dir/build-world.log || \
		{ echo buildworld failed ; exit 1 ; }
	fi
fi

if [ "$artisanal_userland" = "0" ] ; then
	echo ; echo Installing world - logging to $log_dir/install-world.log
	\time -h env MAKEOBJDIRPREFIX=$obj_dir make -C $src_dir \
	installworld SRCCONF=$work_dir/src.conf \
	DESTDIR=$dest_dir \
	NO_FSCHG=YES \
	> $log_dir/install-world.log 2>&1

response="n"
[ "$quiet" = "0" ] && \
{ echo Press y to prune locales and timezones saving 28M? ; read response ; }

if [ "$response" = "y" ]; then
	echo Deleting unused locales from $dest_dir
#	cd $work_dir/kernel/usr/share/locale/
	cd $dest_dir/usr/share/locale/
	rm -rf a* b* c* d* e* f* g* h* i* j* k* l* m* n* p* r* s* t* u* z*
	echo Deleting unused timezone data from $dest_dir
#	cd $work_dir/kernel/usr/share/zoneinfo
	cd $dest_dir/usr/share/zoneinfo
	rm -rf A* B* C* E* F* G* H* I* J* K* L* M* N* P* R* S* T* UCT US W* Z*
fi

fi # End install non-artisinal world

# Set up the artisanal userland environment
if [ "$artisanal_userland" = "1" ] ; then

	echo ; echo Building and installing an artisanal userland

	echo ; echo Making essential userland directories
	mkdir -p $dest_dir/bin
	mkdir -p $dest_dir/sbin
	mkdir -p $dest_dir/usr/bin
	mkdir -p $dest_dir/usr/sbin
	mkdir -p $dest_dir/lib
	mkdir -p $dest_dir/libexec
	mkdir -p $dest_dir/usr/lib
	mkdir -p $dest_dir/usr/libexec
	mkdir -p $dest_dir/boot/defaults
	mkdir -p $dest_dir/boot/lua
	mkdir -p $dest_dir/boot/zfs
	mkdir -p $dest_dir/dev
	mkdir -p $dest_dir/tmp
	mkdir -p $dest_dir/usr/share/locale/C.UTF-8
	mkdir -p $dest_dir/usr/share/zoneinfo

# These items will be built statically/NO_SHARED=YES
# The paths are below $src_dir which is /usr/src by default
# Add components here or to the list of dynamically-built components below

statics="bin/sh
sbin/init
sbin/mount
bin/stty
bin/cat
bin/chflags
bin/date
bin/kenv
bin/cp
bin/ls
bin/ps
bin/rm
bin/sleep
sbin/devfs
sbin/fsck
sbin/shutdown
sbin/sysctl
libexec/getty
usr.sbin/service
stand
cddl/sbin/zfs
cddl/sbin/zpool
usr.bin/env
usr.bin/locale
usr.bin/chpass
usr.bin/host
usr.bin/id
usr.bin/less
usr.bin/ldd
usr.bin/random
usr.bin/stat
usr.bin/tar
usr.bin/touch
usr.bin/tr
usr.bin/tty
usr.bin/wall"

# These items will be built dynamically
# The paths are below $src_dir which is /usr/src by default

dynamics="usr.bin/login
lib/libnetbsd
lib/libc
libexec/rtld-elf
lib/libcrypt
lib/libypclnt
lib/libpam
lib/libpam/libpam
lib/libpam/modules
lib/libypclnt
lib/libbsm
lib/libopie
lib/libutil
lib/liby
lib/libmd"

fi # End setup artisanal userland environment


# ARTISANAL BUILDS

if [ "$artisanal_userland" = "1" ] ; then
	if [ "$keep" = "0" ] ; then
		echo ; echo Static builds!

#IFS="
#"
		for static in $statics ; do
			util=$(basename $static )
			echo Making $src_dir/$static
			env MAKEOBJDIRPREFIX=$obj_dir \
			make -j$buildjobs -C $src_dir/$static \
			NO_SHARED=YES WITHOUT_MAN=YES \
			WITHOUT_MANCOMPRESS=YES \
			> $log_dir/make-$util.log 2>&1 || \
			{ echo make $static failed ; exit 1 ; }
		done

		echo ; echo Dynamic builds!

#IFS="
#"
		for dynamic in $dynamics ; do
			dyn=$(basename $dynamic )
			echo Making $src_dir/$dynamic
        		env MAKEOBJDIRPREFIX=$obj_dir \
			make -j$buildjobs -C $src_dir/$dynamic \
			WITHOUT_MAN=YES WITHOUT_MANCOMPRESS=YES \
			> $log_dir/make-$dyn.log 2>&1 || \
			{ echo make $dynamic failed ; exit 1 ; }
		done

		echo ; echo Building share/ctypedef
		env MAKEOBJDIRPREFIX=$obj_dir \
		make -C $src_dir/share/ctypedef \
		> $log_dir/make-ctypedef.log 2>&1 || \
			{ echo make /share/ctypedef failed ; exit 1 ; }

		echo ; echo Building /usr/share/zoneinfo 
		env MAKEOBJDIRPREFIX=$obj_dir \
		make -C $src_dir/share/zoneinfo \
		> $log_dir/make-zoneinfo.log 2>&1 || \
			{ echo make /share/zoneinfo failed ; exit 1 ; }
	fi # End if keep
fi # End if artisanal


# ARTISNAL INSTALLS

if [ "$artisanal_userland" = "1" ] ; then
	for static in $statics ; do
		echo ; echo Installing $static
		env MAKEOBJDIRPREFIX=$obj_dir \
		make -C $src_dir/$static install \
		DESTDIR=$dest_dir \
		WITHOUT_MAN=YES WITHOUT_MANCOMPRESS=YES \
		SRCCONF=$work_dir/src.conf > \
			$log_dir/install-$util.log 2>&1 || \
			{ echo install $static failed ; exit 1 ; }
	done

	for dynamic in $dynamics ; do
		echo ; echo Installing $dynamic
		env MAKEOBJDIRPREFIX=$obj_dir \
		make -C $src_dir/$dynamic install \
		DESTDIR=$dest_dir \
		WITHOUT_MAN=YES WITHOUT_MANCOMPRESS=YES \
		SRCCONF=$work_dir/src.conf > $log_dir/install-$dyn.log 2>&1 || \
			{ echo install $dynamic failed ; exit 1 ; }
	done
fi


# LOCALES MAY NEED LOVE

echo ; echo "Configuring locale information"
mkdir -p $dest_dir/usr/share/locale/C.UTF-8

#cp $obj_dir/$src_dir/amd64.amd64/share/ctypedef/C.UTF-8/LC_CTYPE \

# COPYING FROM THE HOST FOR NOW

cp /usr/share/locale/C.UTF-8/LC_CTYPE \
	$dest_dir/usr/share/locale/C.UTF-8/ || \
		{ echo "C.UTF-8/LC_CTYPE copy from $obj_dir failed" ; exit 1 ; }

[ -f $dest_dir/usr/share/locale/C.UTF-8/LC_CTYPE ] || \
	{ echo "C.UTF-8/LC_CTYPE copy from $obj_dir failed" ; exit 1 ; }

mkdir -p $dest_dir/usr/share/zoneinfo
mkdir -p $dest_dir/usr/share/zoneinfo/Etc

#cp $obj_dir/$src_dir/amd64.amd64/share/zoneinfo/builddir/Etc/UTC \

# COPYING FROM THE HOST FOR NOW

cp /usr/share/zoneinfo/UTC \
	$dest_dir/usr/share/zoneinfo/ || \
		{ echo "/share/zoneinfo/UTC copy failed" ; exit 1 ; }

cp /usr/share/zoneinfo/Etc/UTC \
	$dest_dir/usr/share/zoneinfo/Etc/ || \
		{ echo "/share/zoneinfo/Etc/UTC copy failed" ; exit 1 ; }

# Alternative: use a known-good full userland
#cat /usr/freebsd-dist/base.txz | tar -xf - -C $dest_dir


# BOOT CODE - Must be performed after stand is built

echo ; echo Adding boot code

if ! [ "$target" = "jail" ] ; then
	if [ "$zfsroot" = "1" ] ; then
		echo ; echo Adding gptzfsboot boot code
		gpart bootcode -b $dest_dir/boot/pmbr -p \
		$dest_dir/boot/gptzfsboot -i 1 /dev/$device || \
			{ echo gpart bootcode failed ; exit 1 ; }
	else
		gpart bootcode -b $dest_dir/boot/pmbr \
		-p $dest_dir/boot/gptboot -i 1 /dev/$device
	fi
fi

# Alternatively install from the host
# gpart bootcode -b /boot/pmbr -p /boot/gptboot -i 1 /dev/$device

f_quiet


# KERNEL

if ! [ "$target" = "jail" ] ; then

	if [ "$keep" = "0" ] ; then
		echo ; echo Building kernel - \
			logging to $log_dir/build-kernel.log
		\time -h env MAKEOBJDIRPREFIX=$obj_dir \
		make -C $src_dir -j$buildjobs \
		buildkernel KERNCONFDIR=$work_dir KERNCONF=OCCAMBSD \
		> $log_dir/build-kernel.log || \
			{ echo buildkernel failed ; exit 1 ; }

		echo ; echo Seeing how big the resulting kernel is
		ls -lh $obj_dir/$src_dir/amd64.amd64/sys/OCCAMBSD/kernel

		f_quiet

	fi # End keep

echo ; echo Installing the kernel to $dest_dir - \
	logging to $log_dir/install-kernel.log
	\time -h env MAKEOBJDIRPREFIX=$obj_dir make -C $src_dir installkernel \
	KERNCONFDIR=$work_dir KERNCONF=OCCAMBSD DESTDIR=$dest_dir \
	> $log_dir/install-kernel.log 2>&1
	[ -f $dest_dir/boot/kernel/kernel ] || \
		{ echo kernel failed to install to $dest_dir ; exit 1 ; }

	# Need not be nested but the familiar location is familiar
	echo Copying the kernel to $work_dir/kernel/
	cp -rp $work_dir/device-mnt/boot/kernel \
		$work_dir/kernel/boot/
	[ -f $work_dir/kernel/boot/kernel/kernel ] || \
		{ echo $work_dir/kernel failed to copy ; exit 1 ; }

	echo Seeing how big the resulting installed kernel is
	ls -lh $work_dir/device-mnt/boot/kernel/kernel
fi


# DISTRIBUTION

echo ; echo Installing distribution to $dest_dir - \
	logging to $log_dir/install-dist.log
\time -h env MAKEOBJDIRPREFIX=$obj_dir make -C $src_dir distribution \
	SRCCONF=$work_dir/src.conf DESTDIR=$dest_dir \
		> $log_dir/install-dist.log 2>&1


# CONFIGURATION

if ! [ "$target" = "jail" ] ; then
	echo
	echo Copying boot directory from mounted device to root kernel device
	[ -d $dest_dir/boot/defaults ] && \
		cp -rp $dest_dir/boot/defaults $work_dir/kernel/boot/
	[ -d $dest_dir/boot/lua ] && \
		cp -rp $dest_dir/boot/lua $work_dir/kernel/boot/
	[ -f $dest_dir/boot/device.hints ] && \
		cp -p $dest_dir/boot/device.hints $work_dir/kernel/boot/
	[ -d $dest_dir/boot/zfs ] && \
		cp -rp $dest_dir/boot/zfs* $work_dir/kernel/boot/
fi

# DEBUG Determine if this is needed - obviously not needed for jail
#echo Installing distribution to $work_dir/kernel - \
#	$log_dir/kernel-distribution.log
#\time -h env MAKEOBJDIRPREFIX=$obj_dir make -C $src_dir distribution \
# SRCCONF=$work_dir/src.conf DESTDIR=$work_dir/kernel \
#	> $log_dir/kernel-distribution.log 2>&1


f_quiet

if [ "$target" = "jail" ] ; then

	# sendmail ss flags etc?
	echo ; echo Generating jail rc.conf and fstab
	echo
tee -a $work_dir/jail-mnt/etc/rc.conf <<HERE
hostname="occambsd-jail"
ifconfig_DEFAULT="DHCP inet6 accept_rtadv"
growfs_enable="YES"
HERE

	touch $dest_dir/etc/fstab
else
	echo ; echo Generating image rc.conf

	echo
tee -a $work_dir/device-mnt/etc/rc.conf <<HERE
hostname="occambsd"
ifconfig_DEFAULT="DHCP inet6 accept_rtadv"
growfs_enable="YES"
HERE

	if [ "$zfsroot" = 1 ] ; then
		echo Adding rc.conf ZFS entry
		echo "zfs_enable=\"YES\"" >> $work_dir/device-mnt/etc/rc.conf
		echo "zfs_enable=\"YES\"" >> $work_dir/kernel/etc/rc.conf
	fi

	echo ; echo Generating fstab

# root fstab entry for UFS
	if [ "$zfsroot" = 0 ] ; then
#echo "/dev/${root_dev}0p3	/	ufs	rw,noatime	1	1" \
echo "/dev/gpt/occamroot0	/	ufs	rw,noatime	1	1" \
		> "$dest_dir/etc/fstab"
	fi

# Add swap regardless of if UFS or ZFS
#	echo "/dev/${root_dev}0p2	none	swap	sw	0	0" \
	echo "/dev/gpt/occamswap0	none	swap	sw	0	0" \
		>> "$dest_dir/etc/fstab"
	cat "$dest_dir/etc/fstab" || \
		{ echo $dest_dir/etc/fstab generation failed ; exit 1 ; }

	# Copy for if bhyve boots with -e, superflous for UFS boot
	cp "$dest_dir/etc/fstab" "$work_dir/kernel/etc/"

fi # End if target = jail

echo ; echo Touching firstboot files

touch "$dest_dir/firstboot"

# loader.conf configuration
if ! [ "$target" = "jail" ] ; then
	echo ; echo Generating generic device loader.conf

	echo
	tee -a $work_dir/device-mnt/boot/loader.conf <<HERE
kern.geom.label.disk_ident.enable="0"
kern.geom.label.gptid.enable="0"
kern.geom.label.gpt.enable="1"
autoboot_delay="3"
#boot_verbose="1"
HERE

	echo ; echo Generating generic kernel loader.conf

	echo
	tee -a $work_dir/kernel/boot/loader.conf <<HERE
kern.geom.label.disk_ident.enable="0"
kern.geom.label.gptid.enable="0"
kern.geom.label.gpt.enable="1"
autoboot_delay="3"
#boot_verbose="1"
HERE

	if [ "$zfsroot" = "1" ] ; then
		echo ; echo Adding ZFS loader entries
		echo "cryptodev_load=\"YES\"" >> \
			$work_dir/device-mnt/boot/loader.conf
		echo "zfs_load=\"YES\"" >> \
			$work_dir/device-mnt/boot/loader.conf

		# Could copy it over...
		echo "cryptodev_load=\"YES\"" >> \
			$work_dir/kernel/boot/loader.conf
		echo "zfs_load=\"YES\"" >> \
			$work_dir/kernel/boot/loader.conf
		echo "vfs.root.mountfrom=\"zfs:occambsd/ROOT/default\"" >> \
			$work_dir/kernel/boot/loader.conf
	fi

	if [ "$target" = "xen" ] ; then
		echo ; echo Adding Xen loader.conf entries

		echo "boot_serial=\"YES\"" >> \
			$work_dir/device-mnt/boot/loader.conf
		echo "comconsole_speed=\"115200\"" >> \
			$work_dir/device-mnt/boot/loader.conf
		echo "console=\"comconsole\"" >> \
			$work_dir/device-mnt/boot/loader.conf
	
		echo "boot_serial=\"YES\"" >> \
			$work_dir/kernel/boot/loader.conf
		echo "comconsole_speed=\"115200\"" >> \
			$work_dir/kernel/boot/loader.conf
		echo "console=\"comconsole\"" >> \
			$work_dir/kernel/boot/loader.conf

		echo ; echo Configuring the Xen VM image serial console
		printf "%s" "-h -S115200" >> $work_dir/device-mnt/boot.config

		echo ; echo Configuring the Xen kernel serial console
		printf "%s" "-h -S115200" >> $work_dir/kernel/boot.config

		# Needed for PVH but not HVM?
echo 'xc0	"/usr/libexec/getty Pc"	xterm	onifconsole	secure' \
		>> $work_dir/device-mnt/etc/ttys

		echo $work_dir/device-mnt/boot/loader.conf reads:
		cat $work_dir/device-mnt/boot/loader.conf || \
			{ echo loader.conf generation failed ; exit 1 ; }

		echo $work_dir/kernel/boot/loader.conf reads:
		cat $work_dir/kernel/boot/loader.conf || \
			{ echo kernel loader.conf generation failed ; exit 1 ; }
	fi
fi # End loader.conf acrobatics

# DEBUG Is it needed there?
# tzsetup will fail on separated kernel/userland - point at userland somehow
# Could not open /mnt/usr/share/zoneinfo/UTC: No such file or directory

#echo ; echo Setting the timezone three times - Press ENTER 2X
#sleep 2
# DEBUG Need to set on in the kernel directories?
#tzsetup -s -C $dest_dir UTC


# PACKAGES

	echo ; echo Installing packages
	pkg -r $work_dir/device-mnt install -y $packages

	echo ; echo Running pkg -r $work_dir/device-mnt info
	pkg -r $work_dir/device-mnt info || \
		{ echo Package installation failed ; exit 1 ; }

# STATISTICS

echo ; echo Running df -h | grep $device
df -h | grep $device

echo ; echo Finding all files over 1M in size
find $work_dir/device-mnt -size +1M -exec ls -lh {} +

echo df -h just ran... did you see $device
df -h

if ! [ "$target" = "jail" ] ; then
#	cat << HERE >> "$work_dir/device-mnt/etc/rc.local"
# rc.local appears to be too early, log is short, MS=0
	cat << HERE >> "$work_dir/device-mnt/collect-ts-data.sh"
TSCEND=\`sysctl -n debug.tslog_user | grep sh | head -1 | cut -f 4 -d ' '\`
TSCFREQ=\`sysctl -n machdep.tsc_freq\`
MS=\$((TSCEND * 1000 / TSCFREQ));

echo \$MS > /root/ts-ms.var
sysctl -b debug.tslog > /root/ts.log
HERE

	cat $work_dir/device-mnt/collect-ts-data.sh
fi

if [ "$target" = "jail" ] ; then
	echo ; echo Generating jail.conf

cat << HERE > $work_dir/jail.conf
occambsd {
	host.hostname = occambsd;
	path = "$work_dir/jail-mnt";
	mount.devfs;
	exec.start = "/bin/sh /etc/rc";
	exec.stop = "/bin/sh /etc/rc.shutdown jail";
	}
HERE

elif [ "$target" = "xen" ] ; then

echo ; echo Generating xen.cfg
cat << HERE > $work_dir/xen.cfg
type = "hvm"
memory = 2048
vcpus = 2
name = "OccamBSD"
disk = [ '$work_dir/occambsd.raw,raw,hda,w' ]
boot = "c"
serial = 'pty'
on_poweroff = 'destroy'
on_reboot = 'restart'
on_crash = 'restart'
#vif = [ 'bridge=bridge0' ]
HERE

echo ; echo Generating xen-kernel.cfg
cat << HERE > $work_dir/xen-kernel.cfg
type = "pvh"
memory = 2048
vcpus = 2
name = "OccamBSD"
kernel = "$work_dir/kernel/boot/kernel/kernel"
cmdline = "vfs.root.mountfrom=ufs:/dev/ada0p3"
disk = [ '$work_dir/occambsd.raw,raw,hda,w' ]
boot = "c"
serial = 'pty'
on_poweroff = 'destroy'
on_reboot = 'restart'
on_crash = 'restart'
#vif = [ 'bridge=bridge0' ]
HERE

fi

echo ; echo The resulting disk image is $work_dir/occambsd.raw


# SCRIPTS

echo ; echo Note these setup and tear-down scripts:

if [ "$target" = "bhyve" ] ; then
	echo ; echo "kldload vmm" > $work_dir/load-bhyve-vmm-module.sh
	echo $work_dir/load-bhyve-vmm-module.sh
	echo "[ -e /dev/vmm/occambsd ] && bhyvectl --destroy --vm=occambsd" \
		> $work_dir/load-bhyve-directory.sh
	echo "sleep 1" >> $work_dir/load-bhyve-directory.sh
	echo "bhyveload -h $work_dir/kernel/ -m 1024 occambsd" \
		>> $work_dir/load-bhyve-directory.sh
	echo $work_dir/load-bhyve-directory.sh

	echo "[ -e /dev/vmm/occambsd ] && bhyvectl --destroy --vm=occambsd" \
		> $work_dir/load-bhyve-disk-image.sh
	echo "sleep 1" >> $work_dir/load-bhyve-disk-image.sh
	echo "bhyveload -d $work_dir/occambsd.raw -m 1024 occambsd" \
		>> $work_dir/load-bhyve-disk-image.sh
	echo $work_dir/load-bhyve-disk-image.sh

	echo "bhyve -m 1024 -H -A -s 0,hostbridge -s 2,virtio-blk,$work_dir/occambsd.raw -s 31,lpc -l com1,stdio occambsd" \
		> $work_dir/boot-bhyve-disk-image.sh
	echo $work_dir/boot-bhyve-disk-image.sh
	echo "bhyvectl --destroy --vm=occambsd" \
b
		> $work_dir/destroy-bhyve.sh
	echo $work_dir/destroy-bhyve.sh
elif [ "$target" = "xen" ] ; then
	echo "xl list | grep OccamBSD && xl destroy OccamBSD" \
		> $work_dir/boot-xen-directory.sh
	echo ; echo "xl create -c $work_dir/xen-kernel.cfg" \
		>> $work_dir/boot-xen-directory.sh
	echo $work_dir/boot-xen-directory.sh

	echo "xl list | grep OccamBSD && xl destroy OccamBSD" \
		> $work_dir/boot-xen-disk-image.sh
	echo "xl create -c $work_dir/xen.cfg" \
		>> $work_dir/boot-xen-disk-image.sh
	echo $work_dir/boot-xen-disk-image.sh

	echo "xl shutdown OccamBSD ; xl destroy OccamBSD ; xl list" > $work_dir/destroy-xen.sh
	echo $work_dir/destroy-xen.sh

	# Notes while debugging
	#xl console -t pv OccamBSD
	#xl console -t serial OccamBSD
else # Assume jail
	echo "jail -c -f $work_dir/jail.conf occambsd" > \
		$work_dir/boot-jail.sh
	echo "jls" >> $work_dir/boot-jail.sh
	echo $work_dir/boot-jail.sh
	echo "jail -r occambsd" > $work_dir/stop-jail.sh
	echo "jls" >> $work_dir/stop-jail.sh
	echo $work_dir/stop-jail.sh
fi

#[ $( which tree > /dev/null 2>&1 ) ] && tree $dest_dir > $work_dir/filetree.txt
[ $( which tree ) ] && tree $dest_dir > $work_dir/filetree.txt

du -h $dest_dir > $work_dir/diskusage.txt

if ! [ "$target" = "jail" ] ; then
	echo ; echo The disk device is still mounted and you could
	echo exit and rebuild the kernel with:
	echo ; echo env MAKEOBJDIRPREFIX=$obj_dir make -C $src_dir -j$buildjobs buildkernel KERNCONFDIR=$work_dir KERNCONF=OCCAMBSD
	echo ; echo env MAKEOBJDIRPREFIX=$obj_dir make installkernel KERNCONFDIR=$work_dir DESTDIR=$work_dir/\< jail mnt or root \>

	if [ "$zfsroot" = "1" ] ; then
		echo Exporting occambsd zpool
		zpool export -f occambsd
	else
		sleep 3
		echo ; echo Unmounting $dest_dir
		umount $dest_dir
	fi


	if [ "$hardware_device" = "0" ] ; then
		echo ; echo Destroying $device
		mdconfig -du $device
		mdconfig -lv
	fi
fi

if [ "$release" = "1" ] ; then

	echo ; echo Building release - logging to $log_dir/release.log
	cd $src_dir/release || { echo cd release failed ; exit 1 ; }

	\time -h env MAKEOBJDIRPREFIX=$obj_dir make -C $src_dir/release \
		SRCCONF=$work_dir/src.conf \
		KERNCONFDIR=$work_dir KERNCONF=OCCAMBSD release \
		> $log_dir/release.log 2>&1 \
			|| { echo release failed ; exit 1 ; }

	echo ; echo Generating bhyve boot scripts for disc1.iso and memstick.img

	echo "[ -e /dev/vmm/occambsd ] && bhyvectl --destroy --vm=occambsd" \
		> $work_dir/load-bhyve-disc1.iso.sh
	echo "sleep 1" >> $work_dir/load-bhyve-disc1.iso.sh
	echo "bhyveload -d $obj_dir/$src_dir/amd64.amd64/release/disc1.iso -m 1024 occambsd" \
		>> $work_dir/load-bhyve-disc1.iso.sh

	echo "bhyve -m 1024 -H -A -s 0,hostbridge -s 2,virtio-blk,$obj_dir/$src_dir/amd64.amd64/release/disc1.iso -s 31,lpc -l com1,stdio occambsd" \
		> $work_dir/boot-bhyve-disc1.iso.sh

	echo "[ -e /dev/vmm/occambsd ] && bhyvectl --destroy --vm=occambsd" \
		> $work_dir/load-bhyve-memstick.img.sh
	echo "sleep 1" >> $work_dir/load-bhyve-memstick.img.sh
	echo "bhyveload -d $obj_dir/$src_dir/amd64.amd64/release/memstick.img -m 1024 occambsd" \
		>> $work_dir/load-bhyve-memstick.img.sh

	echo "bhyve -m 1024 -H -A -s 0,hostbridge -s 2,virtio-blk,$obj_dir/$src_dir/amd64.amd64/release/memstick.img -s 31,lpc -l com1,stdio occambsd" \
		> $work_dir/boot-bhyve-memstick.img.sh

	echo ; echo Release contents are in $obj_dir
fi


# Also skip on ZFS
	if [ "$hardware_device" = "0" ] ; then
		if ! [ "$target" = "jail" ] ; then
			cat << HERE >> "$work_dir/attach.img.sh"
mdconfig -a -u "$device" -f "$work_dir/occambsd.raw" || \
	{ echo image mdconfig attach failed ; exit 1 ; }
mount /dev/${device}p3 $work_dir/device-mnt || \
	{ echo image mount failed ; exit 1 ; }
HERE

			cat << HERE >> "$work_dir/detach.img.sh"
umount -f "$work_dir/device-mnt" || \
	{ echo image umount failed ; exit 1 ; }
mdconfig -d -u "$device" || \
	{ echo image mdconfig detach failed ; exit 1 ; }
HERE
		fi
	fi
exit 0
