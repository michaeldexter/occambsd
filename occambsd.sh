#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause-FreeBSD
#
# Copyright 2021, 2022, 2023 Michael Dexter
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

# Version v0.7.0

f_usage() {
        echo ; echo "USAGE:"
	echo "-p <profile file> (required)"
	echo "-s <source directory override>"
	echo "-o <object directory override>"
	echo "-O <output directory override>"
	echo "-w (Reuse the previous world objects)"
	echo "-W (Reuse the previous world objects without cleaning)"
	echo "-k (Reuse the previous kernel objects)"
	echo "-K (Reuse the previous kernel objects without cleaning)"
	echo "-G (Use the GENERIC/stock world)"
	echo "-g (Use the GENERIC kernel)"
	echo "-j (Build for Jail boot)"
	echo "-v (Generate vm-image)"
	echo "-z (Generate ZFS vm-image)"
	echo "-Z <size> (vm-image siZe i.e. 500m - default is 5g)"
	echo "-S <size> (vm-image Swap size i.e. 500m - default is 1g)"
	echo "-i (Generate disc1 and bootonly.iso ISOs)"
	echo "-m (Generate mini-memstick image)"
	echo "-n (No-op dry-run only generating configuration files)"
	echo
        exit 0
}

# occambsd: An application of Occam's razor to FreeBSD
# a.k.a. "super svelte stripped down FreeBSD"

# This script creates a customized FreeBSD "VM-IMAGE" based on a profile that includes build option and kernel configuration parameters

# DEFAULT VARIABLES

working_directory=$( pwd )		# Used after cd for cleanup
kernconf="OCCAMBSD"			# Can be overridden with GENERIC
vmfs="ufs"				# Can be overridden with zfs
src_dir="/usr/src"			# Can be overridden
obj_dir="/usr/obj"			# Can be overridden
work_dir="/tmp/occambsd"
kernconf_dir="$work_dir"
src_conf="$work_dir/src.conf"
buildjobs="$(sysctl -n hw.ncpu)"

# Should any be left unset for use of environment variables?
profile="0"
reuse_world="0"
reuse_world_dirty="0"
reuse_kernel="0"
reuse_kernel_dirty="0"
generate_vm_image="0"
zfs_vm_image="0"
vm_image_size="400m"
vm_swap_size="100m"
dry_run="0"

while getopts p:s:o:O:wWkGgzjvzZ:S:imn opts ; do
	case $opts in
	p)
		# REQUIRED
		[ "$OPTARG" ] || f_usage
		profile="$OPTARG"
		[ -f "$profile" ] || \
		{ echo "Profile file $profile not found" ; exit 1 ; }
		. "$profile" || \
	        { echo "Profile file $profile failed to source" ; exit 1 ; }
		# target and target_arch are obtained from sourcing
		[ "$target" ] || \
		{ "You must specify target in the profile" ; exit 1 ; }
		[ "$target_arch" ] || \
		{ "You must specify target_arch in the profile" ; exit 1 ; }
		;;
	s)
		# Optionally override source directory
		src_dir="$OPTARG"
		[ -d "$src_dir" ] || { echo "$src_dir not found" ; exit 1 ; }
		;;
	o)
		# Optionally override object directory
		obj_dir="$OPTARG"
		[ -d "$obj_dir" ] || { echo "$obj_dir not found" ; exit 1 ; }
		;;
	O)
		work_dir="$OPTARG"
		;;
	w)
		reuse_world="1"
		;;
	W)
		reuse_world_dirty="1"
		;;
	k)
		reuse_kernel="1"
		;;
	K)
		reuse_kernel_dirty="1"
		;;
	G)
		generic_world="1"
		;;
	g)
		generic_kernel="1"
		;;
	j)
		generate_jail="1"
		;;
	v)
		generate_vm_image="1"
		;;
	z)
		vmfs="zfs"
		;;
	Z)
		# Validate input?
		vm_image_size="$OPTARG"
		;;
	S)
		vm_swap_size="$OPTARG"
		;;
	i)
		generate_isos="1"
		;;
	m)
		generate_memstick="1"
		;;
	n)
		dry_run="1"
		;;
	*)
		f_usage
		exit 1
		;;
	esac
done

# A profile must be specified
[ "$profile" = "0" ] && f_usage

log_dir="$work_dir/logs"		# Lives under work_dir for mkdir -p

# target is populated by the required profile file
[ -f $src_dir/sys/${target}/conf/GENERIC ] || \
	{ echo "Sources do not appear to be installed or specified" ; exit 1 ; }

# Do not perform in opt args in case there is a positional issue
if [ "$generic_kernel" = "1" ] ; then
	kernconf_dir="${src_dir}/sys/${target}/conf"
	kernconf="GENERIC"
fi

if [ "$vmfs" = "zfs" ] ; then
	if [ "$generate_vm_image" = "0" ] ; then
		echo "-z flag is only valid with -v"
		exit 1
	fi
fi


# PREPARATION

[ -d ${work_dir}/jail/dev ] && umount ${work_dir}/jail/dev

if ! [ -d $work_dir ] ; then
	echo Creating $work_dir
	# Creating log_dir includes parent directory work_dir
	mkdir -p "$log_dir" || \
		{ echo Failed to create $work_dir ; exit 1 ; }
else # work_dir exists
	echo ; echo Cleansing $work_dir
	rm -rf $work_dir/*
	mkdir -p $log_dir
fi

if ! [ -d $obj_dir ] ; then
	mkdir -p "$obj_dir" || { echo Failed to make $obj_dir ; exit 1 ; }
fi

echo ; echo Removing previous generated images if present

[ -f "$obj_dir/$src_dir/${target}.$target_arch/release/vm.raw" ] && \
	rm "$obj_dir/$src_dir/${target}.$target_arch/release/vm.raw"

[ -f "$obj_dir/$src_dir/${target}.$target_arch/release/raw.img" ] && \
	rm "$obj_dir/$src_dir/${target}.$target_arch/release/raw.img"

[ -d "$obj_dir/$src_dir/${target}.$target_arch/release/vm-image" ] && \
	chflags -R 0 "$obj_dir/$src_dir/${target}.$target_arch/release/vm-image"

[ -d "$obj_dir/$src_dir/${target}.$target_arch/release/vm-image" ] && \
	rm -rf "$obj_dir/$src_dir/${target}.$target_arch/release/vm-image"

[ -d "$obj_dir/$src_dir/${target}.$target_arch/release/disc1" ] && \
	chflags -R 0  "$obj_dir/$src_dir/${target}.$target_arch/release/disc1"

# Note asterisk to take image with it
[ -d "$obj_dir/$src_dir/${target}.$target_arch/release/disc1" ] && \
	rm -rf "$obj_dir/$src_dir/${target}.$target_arch/release/disc1*"

[ -d "$obj_dir/$src_dir/${target}.$target_arch/release/bootonly" ] && \
	chflags -R 0 "$obj_dir/$src_dir/${target}.$target_arch/release/bootonly"

[ -d "$obj_dir/$src_dir/${target}.$target_arch/release/bootonly" ] && \
	rm -rf "$obj_dir/$src_dir/${target}.$target_arch/release/bootonly*"

# Kernel first depending on how aggresively we clean the object directory
if [ "$reuse_kernel" = "0" ] ; then
	echo ; echo Cleaning kernel object directory
	# Only clean the requested kernel
	if [ -d $obj_dir/$src_dir/${target}.$target_arch/sys/$kernconf ] ; then
		chflags -R 0 $obj_dir/$src_dir/${target}.$target_arch/sys/$kernconf
		rm -rf  $obj_dir/$src_dir/${target}.$target_arch/sys/$kernconf
	fi
	# This would collide with a mix of kernels
	# cd $src_dir/sys
	# make clean
else
	echo ; echo Reuse kernel requested
	[ -f "$obj_dir/$src_dir/${target}.$target_arch/sys/${kernconf}/kernel" ] || \
		{ echo Kernel objects not found for resuse ; exit 1 ; }
fi

if [ "$reuse_world" = "0" ] ; then
	echo ; echo Cleaning world object directory
	# This would take kernels with it
	# chflags -R 0 $obj_dir/$src_dir/${target}.$target_arch
	# rm -rf  $obj_dir/$src_dir/${target}.$target_arch/*

	# Only clean if there is something to clean, saving time
	if [ -d "$obj_dir/$src_dir/${target}.$target_arch" ] ; then
		cd $src_dir
		make cleandir > $log_dir/cleandir.log 2>&1
	fi
else
	[ -d "$obj_dir/$src_dir/${target}.$target_arch/bin/sh" ] || \
		{ echo World objects not found for reuse ; exit 1 ; }
fi
	
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
	without_options=$( echo $without_options | grep -v $option )
done

echo $without_options > $work_dir/src.conf

#echo ; echo The generated $work_dir/src.conf tails:
#tail $work_dir/src.conf

ls ${src_dir}/sys/modules | grep -v "Makefile" > $work_dir/all_modules.txt
echo ; echo All modules are listed in $work_dir/all_modules.txt

# Kernel configuration parameters

# A space-separated profile file must have:
# $kernel_modules	i.e. makeoptions	MODULES_OVERRIDE="*module*..."
# $kernel_options	i.e. options		*SCHED_ULE*
# $kernel_devices	i.e. device		*pci*

# cpu, kernel_modules, and kernel_options, are read from the profile
echo "cpu	$cpu" > $work_dir/OCCAMBSD
echo "ident	OCCAMBSD" >> $work_dir/OCCAMBSD

if [ "$kernel_modules" ] ; then
	echo "makeoptions	MODULES_OVERRIDE=\"$kernel_modules\"" \
		>> $work_dir/OCCAMBSD
fi

IFS=" "
if [ "$kernel_options" ] ; then
	for kernel_option in $kernel_options ; do
		echo "options	$kernel_option" >> $work_dir/OCCAMBSD
	done
fi

IFS=" "
if [ "$kernel_devices" ] ; then
	for kernel_device in $kernel_devices ; do
		echo "device	$kernel_device" >> $work_dir/OCCAMBSD
	done
fi

# Disabling until the value is determined
# This caused more harm than good on AMD64
#IFS=" "
#if [ "$kernel_includes" ] ; then
#	for kernel_include in $kernel_includes ; do
#		echo "include	\"$kernel_include\"" >> $work_dir/OCCAMBSD
#	done
#fi

#echo ; echo The resulting OCCAMBSD KERNCONF is
#cat $work_dir/OCCAMBSD

cd $working_directory

echo ; echo Copying profile $profile file to $work_dir

cp $profile ${work_dir}/ || \
	{ echo "$profile failed to copy to $work_dir" ; exit 1 ; }

# DRY RUN
[ "$dry_run" = "1" ] && { echo "Configuration generation complete" ; exit 1 ; }

# "GENERIC"/stock world for testing
echo ; echo "Overriding build options with stock ones"
if [ "$generic_world" = "1" ] ; then
	src_conf="/dev/null"
fi


# BUILD THE WORLD/USERLAND

# World was either cleaned or preserved above with reuse_world=1

if [ "$reuse_world" = "1" ] ; then
	if [ "$reuse_world_dirty" = "0" ] ; then
		echo ; echo "Using existing world build objects"
	fi
else
	echo ; echo Building world - logging to $log_dir/build-world.log
	\time -h env MAKEOBJDIRPREFIX=$obj_dir make -C $src_dir \
		-j$buildjobs SRCCONF=$src_conf buildworld \
		TARGET=$target TARGET_ARCH=$target_arch $makeoptions \
		> $log_dir/build-world.log 2>&1 || \
			{ echo buildworld failed ; exit 1 ; }
fi


# BUILD THE KERNEL

if [ "$reuse_kernel" = "1" ] ; then
	if [ "$reuse_kernel_dirty" = "0" ] ; then
		echo ; echo "Using existing kernel build objects"
	fi
else
	echo ; echo Building kernel - logging to $log_dir/build-kernel.log
	\time -h env MAKEOBJDIRPREFIX=$obj_dir \
		make -C $src_dir -j$buildjobs \
		buildkernel KERNCONFDIR=$kernconf_dir KERNCONF=$kernconf \
		TARGET=$target TARGET_ARCH=$target_arch $makeoptions \
			> $log_dir/build-kernel.log 2>&1 || \
				{ echo buildkernel failed ; exit 1 ; }
fi

# Humanize and fix this
#echo ; echo -n "Size of the resulting kernel: "
#	ls -s $obj_dir/$src_dir/${target}.$target_arch/sys/$kernconf/kernel \
#		 | cut -d " " -f1


# GENERATE JAIL

if [ "$generate_jail" = "1" ] ; then
	[ -d ${work_dir}/jail ] || mkdir ${work_dir}/jail

	jls | grep -q occambsd && jail -r occambsd

	echo ; echo Installing Jail world - logging to $log_dir/install-jail-world.log

	\time -h env MAKEOBJDIRPREFIX=$obj_dir make -C $src_dir \
	installworld SRCCONF=$src_conf $makeoptions \
	DESTDIR=${work_dir}/jail/ \
	NO_FSCHG=YES \
		> $log_dir/install-jail-world.log 2>&1

echo ; echo Installing Jail distribution - logging to $log_dir/jail-distribution.log

	\time -h env MAKEOBJDIRPREFIX=$obj_dir make -C $src_dir distribution \
	SRCCONF=$src_conf DESTDIR=${work_dir}/jail \
		> $log_dir/jail-distribution.log 2>&1

        echo ; echo Generating jail.conf

cat << HERE > $work_dir/jail.conf
occambsd {
	host.hostname = occambsd;
	path = "$work_dir/jail";
	mount.devfs;
	exec.start = "/bin/sh /etc/rc";
	exec.stop = "/bin/sh /etc/rc.shutdown jail";
}
HERE

	echo ; echo "Generating $work_dir/jail-boot.sh script"
	echo "jail -c -f $work_dir/jail.conf occambsd" > \
		$work_dir/jail-boot.sh
	echo "jls" >> $work_dir/jail-boot.sh
	echo $work_dir/jail-boot.sh

[ -f "$work_dir/jail-boot.sh" ] || \
	{ echo "$work_dir/jail-boot.sh failed to create" ; exit 1 ; }

	echo ; echo "Generating $work_dir/jail-halt.sh script"
	echo "jail -r occambsd" > $work_dir/jail-halt.sh
	echo "jls" >> $work_dir/jail-halt.sh
	echo $work_dir/jail-halt.sh

[ -f "$work_dir/jail-halt.sh" ] || \
	{ echo "$work_dir/jail-halt.sh failed to create" ; exit 1 ; }
fi


# GENERATE IMAGES

# VM-IMAGE

if [ "$generate_vm_image" = "1" ] ; then
	cd $src_dir/release || { echo cd release failed ; exit 1 ; }

	# Confirm if this uses KERNCONFDIR

	[ -n "$vm_image_size" ] && vm_size_string="VMSIZE=$vm_image_size"
	[ -n "$vm_swap_size" ] && vm_swap_string="SWAPSIZE=$vm_swap_size"

	echo ; echo Building vm-image - logging to $log_dir/vm-image.log
	\time -h env MAKEOBJDIRPREFIX=$obj_dir make -C $src_dir/release \
		SRCCONF=$src_conf \
		KERNCONFDIR=$kernconf_dir KERNCONF=$kernconf \
		vm-image WITH_VMIMAGES=YES VMFORMATS=raw \
			VMFS=$vmfs $vm_size_string $vm_swap_string \
			TARGET=$target TARGET_ARCH=$target_arch $makeoptions \
			> $log_dir/vm-image.log 2>&1 || \
				{ echo vm-image failed ; exit 1 ; }

	echo ; echo Copying $obj_dir/$src_dir/${target}.$target_arch/release/vm.raw to $work_dir
	cp $obj_dir/$src_dir/${target}.$target_arch/release/vm.raw $work_dir/

# Verify if vm-image would be re-using ${target}.$target_arch/release/dist/

	echo ; echo Generating VM scripts

	echo "kldload vmm" \
		> $work_dir/bhyve-boot-vmimage.sh
	echo "[ -e /dev/vmm/occambsd ] && bhyvectl --destroy --vm=occambsd" \
		> $work_dir/bhyve-boot-vmimage.sh
	echo "sleep 1" >> $work_dir/bhyve-boot-vmimage.sh
	echo "bhyveload -d $work_dir/vm.raw -m 1024 occambsd" \
		>> $work_dir/bhyve-boot-vmimage.sh
	echo "bhyve -m 1024 -H -A -s 0,hostbridge -s 2,virtio-blk,$work_dir/vm.raw -s 31,lpc -l com1,stdio occambsd" \
		>> $work_dir/bhyve-boot-vmimage.sh
	echo $work_dir/bhyve-boot-vmimage.sh

	echo "bhyvectl --destroy --vm=occambsd" \
		> $work_dir/bhyve-cleanup-vmimage.sh
	echo $work_dir/bhyve-cleanup-vmimage.sh

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

	echo "xl list | grep OccamBSD && xl destroy OccamBSD" \
		> $work_dir/xen-boot-vmimage.sh
	echo "xl create -c $work_dir/xen.cfg" \
	>> $work_dir/xen-boot-vmimage.sh
	echo $work_dir/xen-boot-vmimage.sh

	echo "xl shutdown OccamBSD ; xl destroy OccamBSD ; xl list" > $work_dir/xen-cleanup.sh
	echo $work_dir/xen-cleanup.sh

# Notes while debugging
#xl console -t pv OccamBSD
#xl console -t serial OccamBSD

	if [ "$target" = "amd64" ] ; then
cat << HERE > $work_dir/qemu-boot.sh
[ \$( which qemu-system-x86_64 ) ] || { echo "qemu-system-x86-64 not installed" ; exit 1 ; }
qemu-system-x86_64 -m 1024M -nographic -object rng-random,id=rng0,filename=/dev/urandom -device virtio-rng-pci,rng=rng0 -rtc base=utc -drive file=/tmp/occambsd/vm.raw,format=raw,index=0,media=disk 
HERE
	echo $work_dir/qemu-boot.sh
	fi

	if [ "$target" = "arm64" ] ; then
cat << HERE > $work_dir/qemu-boot.sh
[ \$( which qemu-system-aarch64 ) ] || { echo "qemu-system-aarch64 not installed" ; exit 1 ; }
qemu-system-aarch64 -m 1024M -cpu cortex-a57 -machine virt -bios edk2-aarch64-code.fd -nographic -object rng-random,id=rng0,filename=/dev/urandom -device virtio-rng-pci,rng=rng0 -rtc base=utc -drive file=/tmp/occambsd/vm.raw,format=raw,index=0,media=disk 
HERE
	echo $work_dir/qemu-boot.sh
	fi

fi # End: generate_vm_image


# ISOs

if [ "$generate_isos" = "1" ] ; then
	echo ; echo Building CD-ROM ISO images - logging to $log_dir/isos.log
	\time -h env MAKEOBJDIRPREFIX=$obj_dir make -C $src_dir/release \
		SRCCONF=$src_conf \
		KERNCONFDIR=$kernconf_dir KERNCONF=$kernconf \
		TARGET=$target TARGET_ARCH=$target_arch $makeoptions \
		cdrom \
			> $log_dir/isos.log 2>&1 || \
				{ echo "Build ISOs failed" ; exit 1 ; }

	echo ; echo Copying $obj_dir/$src_dir/${target}.$target_arch/release/disc1.iso to $work_dir
	cp $obj_dir/$src_dir/${target}.$target_arch/release/disc1.iso $work_dir/

	echo ; echo Copying $obj_dir/$src_dir/${target}.$target_arch/release/bootonly.iso to $work_dir
	cp $obj_dir/$src_dir/${target}.$target_arch/release/bootonly.iso $work_dir/

	echo ; echo "Generating ISO scripts"

	echo "sh /usr/share/examples/bhyve/vmrun.sh -d /tmp/occambsd/disc1.iso disc1" >> $work_dir/bhyve-boot-disc1.sh 
	echo $work_dir/bhyve-boot-disc1.sh

	echo "bhyvectl --destroy --vm=disc1" \
		> $work_dir/bhyve-cleanup-disc1.sh
	echo $work_dir/bhyve-cleanup-disc1.sh

	echo "sh /usr/share/examples/bhyve/vmrun.sh -d /tmp/occambsd/bootonly.iso bootonly" >> $work_dir/bhyve-boot-bootonly.sh 
	echo $work_dir/bhyve-boot-bootonly.sh

	echo "bhyvectl --destroy --vm=bootonly" \
		> $work_dir/bhyve-cleanup-bootonly.sh
	echo $work_dir/bhyve-cleanup-bootonly.sh

fi


# MEMSTICK

if [ "$generate_memstick" = "1" ] ; then
	echo ; echo Building mini-memstick image - logging to $log_dir/mini-memstick.log
	\time -h env MAKEOBJDIRPREFIX=$obj_dir make -C $src_dir/release \
		SRCCONF=$src_conf \
		KERNCONFDIR=$kernconf_dir KERNCONF=$kernconf \
		TARGET=$target TARGET_ARCH=$target_arch \
		mini-memstick \
			> $log_dir/mini-memstick.log 2>&1 || \
				{ echo mini-memstick failed ; exit 1 ; }

	echo ; echo Copying $obj_dir/$src_dir/${target}.$target_arch/release/mini-memstick.img to $work_dir
	cp $obj_dir/$src_dir/${target}.$target_arch/release/mini-memstick.img $work_dir/

	echo ; echo "Generating mini-memstick scripts"

	echo "sh /usr/share/examples/bhyve/vmrun.sh -d /tmp/occambsd/mini-memstick.img mini-memstick" >> $work_dir/bhyve-boot-mini-memstick.sh 
	echo $work_dir/bhyve-boot-mini-memstick.sh

	echo "bhyvectl --destroy --vm=mini-memstick" \
		> $work_dir/bhyve-cleanup-mini-memstick.sh
	echo $work_dir/bhyve-cleanup-mini-memstick.sh
fi

echo
exit 0
