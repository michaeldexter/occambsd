#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause-FreeBSD
#
# Copyright 2021, 2022, 2023, 2024, 2025 Michael Dexter
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

# Version v0.9

f_usage() {
        echo ; echo "USAGE:"
	echo "-p <profile file> (Required)"
	echo "-s <source directory> (Default: /usr/src)"
	echo "-o <object directory> (Default: /usr/obj)"
	echo "-O <output directory> (Default: /tmp/occambsd)"
	echo "-w (Reuse the previous world objects)"
	echo "-W (Reuse the previous world objects without cleaning)"
	echo "-k (Reuse the previous kernel objects)"
	echo "-K (Reuse the previous kernel objects without cleaning)"
# Need reuse PkgBase?
	echo "-a <additional build option to exclude>"
	echo "-b (Package base - runs 'make packages')"
	echo "-G (Use the GENERIC/stock world - increase image size as needed)"
	echo "-g (Use the GENERIC kernel)"
	echo "-P <patch directory> (NB! This will modify your sources!)"
	echo "-j (Build for Jail boot)"
	echo "-9 (Build for 9pfs boot - 15.0-CURRENT only)"
	echo "-v (Generate VM image and boot scripts)"
	echo "-z (Generate ZFS VM image and boot scripts)"
	echo "-Z <size> (VM image siZe i.e. 500m - default is 5g)"
	echo "-S <size> (VM image Swap size i.e. 500m - default is 1g)"
	echo "-i (Generate disc1 and bootonly.iso ISOs)"
	echo "-m (Generate mini-memstick image)"
	echo "-n (No-op dry-run only generating configuration files)"
	echo
        exit 0
}

# occambsd: An application of Occam's razor to FreeBSD
# a.k.a. "super svelte stripped down FreeBSD"

# This script creates a customized FreeBSD "VM-IMAGE" based on a profile that includes build option and kernel configuration parameters


#####################
# DEFAULT VARIABLES #
#####################

# Should any be left unset for use of environment variables?
working_directory=$( pwd )		# Used after cd for cleanup
kernconf="OCCAMBSD"			# Can be overridden with GENERIC
vmfs="ufs"				# Can be overridden with zfs
src_dir="/usr/src"			# Can be overridden
obj_dir="/usr/obj"			# Can be overridden
work_dir="/tmp/occambsd"
kernconf_dir="$work_dir"
src_conf="$work_dir/src.conf"
buildjobs="$(sysctl -n hw.ncpu)"
reuse_world=0
reuse_world_dirty=0
reuse_kernel=0
reuse_kernel_dirty=0
additional_option=""
package_base=0
generic_world=0
generic_kernel=0
patch_dir=""
generate_jail=0
generate_9pfs=0
generate_vm_image=0
generate_isos=0
generate_memstick=0
dry_run=0
vm_image_size="500m"
vm_swap_size="100m"

# Defaults that are sourced from the profile but are initializing here

# "build_options" is fundamentally confusing as it is the disabled "WITHOUT"s,
# meaning that the components are INCLUDED in the build. OccamBSD disables ALL
# build options by default and enables desired ones by inverting "WITHOUT"s.

profile=""
target=""
target_arch=""
cpu=""
build_options=""
kernel_devices=""
kernel_modules=""
kernel_options=""

all_options=""
without_options=""
with_options=""
src_conf_options=""

while getopts p:s:o:O:wWkKa:bGgP:zj9vzZ:S:imn opts ; do
	case $opts in
	p)
		# REQUIRED
		[ "$OPTARG" ] || f_usage
		profile="$OPTARG"
		[ -f "$profile" ] || \
		{ echo "Profile file $profile not found" ; exit 1 ; }
		sh -n "$profile" || \
	        { echo "Profile file $profile failed to validate" ; exit 1 ; }
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
  		kernconf_dir="$OPTARG"
                src_conf="$work_dir/src.conf"
		;;
	w)
		reuse_world=1
		;;
	W)
# Possibly ambiguous
		reuse_world=1
		reuse_world_dirty=1
		;;
	k)
		reuse_kernel=1
		;;
	K)
# Possibly ambiguous
		reuse_kernel=1
		reuse_kernel_dirty=1
		;;
	a)
		additional_option="$OPTARG"
		;;
	b)
		package_base=1
		;;
	G)
		generic_world=1
		;;
	g)
		generic_kernel=1
		;;
	P)
		patch_dir="$OPTARG"
		[ -d "$patch_dir" ] || \
			{ echo "$patch_dir not found" ; exit 1 ; }

		;;
	j)
		generate_jail=1
		;;
	9)
		generate_9pfs=1
		;;
	v)
		generate_vm_image=1
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
		generate_isos=1
		;;
	m)
		generate_memstick=1
		;;
	n)
		dry_run=1
		;;
	*)
		f_usage
		;;
	esac
done

[ "$profile" ] || { echo "-p <profile> is required" ; f_usage ; }

log_dir="$work_dir/logs"		# Lives under work_dir for mkdir -p

# target is populated by the required profile file
[ -d "$src_dir/sys" ] || \
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


###############
# PREPARATION #
###############

[ -d "${work_dir}/root/dev" ] && umount "${work_dir}/root/dev"

if ! [ -d "$work_dir" ] ; then
	echo "Creating $work_dir"
	# Creating log_dir includes parent directory work_dir
	mkdir -p "$log_dir" || \
		{ echo "Failed to create $work_dir" ; exit 1 ; }
else # work_dir exists
	# Consider a finer-grained cleanse to preserve kernel and world logs
	# when re-using kernel and world artifacts

	echo "$work_dir exists and must be moved or deleted by the user"
	exit 1
#	echo ; echo "Cleansing $work_dir"
#	rm -rf $work_dir/*
#	mkdir -p $log_dir
fi

if [ ! -d "$obj_dir" ] ; then
	mkdir -p "$obj_dir" || { echo "Failed to make $obj_dir" ; exit 1 ; }
fi

echo ; echo "Checking for previous generated images if present"

mount -t devfs | \
	grep "${target}.$target_arch/release/vm-image/dev" && \
	umount "$obj_dir/$src_dir/${target}.$target_arch/release/vm-image/dev"

if [ -d "$obj_dir/$src_dir/${target}.$target_arch/release" ] ; then
	echo "$obj_dir/$src_dir/${target}.$target_arch/release exists and must be moved or deleted by the user"
	exit 1
#	chflags -R 0 "$obj_dir/$src_dir/${target}.$target_arch/release"
#	rm -rf "$obj_dir/$src_dir/${target}.$target_arch/release/*"
fi

# Kernel first depending on how aggressively we clean the object directory
if [ "$reuse_kernel" = "0" ] ; then
	echo ; echo "Cleaning kernel object directory"
	# Only clean the requested kernel
if [ -d "$obj_dir/$src_dir/${target}.${target_arch}/sys/$kernconf" ] ; then
		echo "$obj_dir/$src_dir/${target}.$target_arch/sys exists and must be moved or deleted by the user"
		exit 1
#	chflags -R 0 "$obj_dir/$src_dir/${target}.$target_arch/sys/$kernconf"
#		rm -rf  "$obj_dir/$src_dir/${target}.$target_arch/sys/$kernconf"
	fi
	# This would collide with a mix of kernels
	# cd $src_dir/sys
	# make clean
else
	echo ; echo "Reuse kernel requested"
[ -f "$obj_dir/$src_dir/${target}.$target_arch/sys/${kernconf}/kernel" ] || \
		{ echo "Kernel objects not found for reuse" ; exit 1 ; }
fi

if [ "$reuse_world" = "0" ] ; then
	echo ; echo "Cleaning world object directory"
	# This would take kernels with it
	# chflags -R 0 $obj_dir/$src_dir/${target}.$target_arch
	# rm -rf  $obj_dir/$src_dir/${target}.$target_arch/*

	# Only clean if there is something to clean, saving time
	if [ -d "$obj_dir/$src_dir/${target}.$target_arch" ] ; then
		cd "$src_dir" || { echo "cd $src_dir failed" ; exit 1 ; }
		make cleandir > "$log_dir/cleandir.log" 2>&1
	fi
else
	[ -d "$obj_dir/$src_dir/${target}.$target_arch/bin/sh" ] || \
		{ echo "World objects not found for reuse" ; exit 1 ; }
fi

if [ -d "$obj_dir$src_dir/repo" ] ; then
	echo ; echo "Cleaning package repo directory"
	echo "$obj_dir$src_dir/repo exists and must be moved or deleted by the user"
	exit 1
#	chflags -R 0 "$obj_dir$src_dir/repo"
#	rm -rf "$obj_dir$src_dir/repo/*"
fi


############
# SRC.CONF #
############

echo ; echo "Generating $work_dir/all-options.txt"

all_options=$( make -C "$src_dir" showconfig \
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

echo "$all_options" > "$work_dir/all-options.txt"

echo ; echo "Generating $work_dir/src.conf"

# Prune WITH_ options leaving only WITHOUT_ options
IFS=" "
without_options=$( echo "$all_options" | grep -v WITH_ )
#echo ; echo "without_options reads"
#echo "$without_options"

# Save off all WITHOUT_s
echo ; echo "Generating $work_dir/all-withouts.txt"
echo "$without_options" > "$work_dir/all-withouts.txt"

# Remove enabled_options to result in the desired src.conf

# This user-contributed test is failing and hopefully is mitigated by the sh -n
#IFS=" "
#for option in $without_options ; do
#	num_words_before=$( echo $without_options | wc -w )
#
#	# -w: search for whole words; e.g. do not strike
#	# WITHOUT_FOO_BAR if WITHOUT_FOO is written
#	without_options=$( echo $without_options | grep -v -w $option )
#
#	num_words_after=$( echo $without_options | wc -w )
#	num_words_removed=$(( $num_words_before - $num_words_after ))
#	if [ $num_words_removed -ne 1 ]; then
#		echo "Word $option in build_options has stricken $num_words_removed WITHOUTs, not 1"
#		exit 1
#	fi
#done

# Origial syntax
IFS=" "
for option in $build_options ; do
        without_options=$( echo $without_options | grep -v -w $option )
done

echo "$without_options" > "$work_dir/src.conf"

echo ; echo Resulting statistics: ; echo

echo -n "All options : " ; wc -l $work_dir/all-options.txt ; echo
echo -n "All WITHOUT options : " ; wc -l $work_dir/all-withouts.txt ; echo
echo -n "The src.conf options : " ; wc -l $work_dir/src.conf ; echo

echo "The build_options from the profile:"
echo "$build_options"

#echo DEBUG all-options.txt reads: ; cat $work_dir/all-options.txt
#echo DEBUG all-withouts.txt reads: ; cat $work_dir/all-withouts.txt
#echo DEBUG src.conf reads: ; cat $work_dir/src.conf

# Addition option, added for build_option_survey-like abilities
if ! [ "$additional_option" = "" ] ; then
echo "The additional_option is $additional_option"
echo "Running grep -v $additional_option $work_dir/src.conf"
	grep -v "$additional_option" "$work_dir/src.conf" > \
		"$work_dir/src.conf.additional"
#echo DEBUG tail of $work_dir/src.conf.additional
#	mv $work_dir/src.conf.additional $work_dir/src.conf
fi

#echo ; echo "The generated $work_dir/src.conf tails:"
#tail $work_dir/src.conf

#ls "${src_dir}/sys/modules" | grep -v "Makefile" > "$work_dir/all_modules.txt"

find "${src_dir}/sys/modules" -type d -maxdepth 1 -exec basename {} + \
	> "$work_dir/all_modules.txt"
echo ; echo "All modules are listed in $work_dir/all_modules.txt"

# Kernel configuration parameters

# A space-separated profile file must have:
# $kernel_modules	i.e. makeoptions	MODULES_OVERRIDE="*module*..."
# $kernel_options	i.e. options		*SCHED_ULE*
# $kernel_devices	i.e. device		*pci*

# cpu, kernel_modules, and kernel_options, are read from the profile

echo "cpu	$cpu" > "$work_dir/OCCAMBSD"
echo "ident	OCCAMBSD" >> "$work_dir/OCCAMBSD"

if [ "$kernel_modules" ] ; then
	echo "makeoptions	MODULES_OVERRIDE=\"$kernel_modules\"" \
		>> "$work_dir/OCCAMBSD"
fi

IFS=" "
if [ "$kernel_options" ] ; then
	for kernel_option in $kernel_options ; do
		echo "options	$kernel_option" >> "$work_dir/OCCAMBSD"
	done
fi

IFS=" "
if [ "$kernel_devices" ] ; then
	for kernel_device in $kernel_devices ; do
		echo "device	$kernel_device" >> "$work_dir/OCCAMBSD"
	done
fi

# Disabling until the value is determined
# This caused more harm than good on AMD64
#IFS=" "
#if [ "$kernel_includes" ] ; then
#	for kernel_include in $kernel_includes ; do
#		echo "include	\"$kernel_include\"" >> "$work_dir/OCCAMBSD"
#	done
#fi

#echo ; echo "The resulting OCCAMBSD KERNCONF is"
#cat $work_dir/OCCAMBSD

cd "$working_directory" || { echo "cd $working_directory failed" ; exit 1 ; }

echo ; echo "Copying profile $profile file to $work_dir"

cp "$profile" "${work_dir}/" || \
	{ echo "$profile failed to copy to $work_dir" ; exit 1 ; }

# DRY RUN
[ "$dry_run" = "1" ] && { echo "Configuration generation complete" ; exit 1 ; }

# "GENERIC"/stock world for testing
if [ "$generic_world" = "1" ] ; then
	echo ; echo "Overriding build options with stock ones"
	src_conf="/dev/null"
fi


############################
# Patch Directory Handling #
############################

if [ -n "$patch_dir" ] ; then
	# This step is "destructive" and would need source reversion/rollback

	if [ "$( find "$patch_dir" -maxdepth 0 -empty )" ]; then
		echo "No patches in ${patch_dir} to apply"
	else
		echo "Changing directory to ${src_dir}"
		cd "${src_dir}" || { echo "cd $src_dir" failed ; exit 1 ; }
		# Moving to make -C ${src_dir}/release syntax elsewhere
		# Trickier here
		pwd
		echo "The contents of patch_dir are"
		echo "${patch_dir}/*"
		echo
		echo "Applying patches"
#		for diff in $( echo "${patch_dir}/*" ) ; do
# Use find? shellcheck wants quote it and then warns it will break it
		for diff in ${patch_dir}/*  ; do
			echo "Running a dry run diff of $diff"
			echo "patch -C \< $diff"
#			if [ $( patch -C < "$diff" ) ] ; then
			patch -C < "$diff"
			return_value=$?
			if [ "$return_value" = 0 ] ; then
				echo "Diff $diff passed the dry run"
				diff_basename=$( basename "$diff" )
				echo "Running patch \< $diff"
				echo "Applying diff $diff"
				patch < "$diff"
			else
				echo "Diff $diff_basename failed to apply"
				exit 1
			fi
		done
	fi # End if patch_dir empty
fi # End if patch_dir


#########################
# WORLD/USERLAND BUILDS #
#########################

# World was either cleaned or preserved above with reuse_world=1

if [ "$reuse_world" = "1" ] ; then
	if [ "$reuse_world_dirty" = "0" ] ; then
		echo ; echo "Using existing world build objects"
	fi
else
	echo ; echo "Building world - logging to $log_dir/build-world.log"
	/usr/bin/time -h env MAKEOBJDIRPREFIX="$obj_dir" make -C "$src_dir" \
		-j"$buildjobs" SRCCONF="$src_conf" buildworld \
		TARGET="$target" TARGET_ARCH="$target_arch" \
		> "$log_dir/build-world.log" 2>&1 || \
			{ echo "buildworld failed" ; exit 1 ; }
fi


################
# KERNEL BUILD #
################

# Exclude for a jail? Would need to see if excluding everything else

if [ "$reuse_kernel" = "1" ] ; then
	if [ "$reuse_kernel_dirty" = "0" ] ; then
		echo ; echo "Using existing kernel build objects"
	fi
else
	echo ; echo "Building kernel - logging to $log_dir/build-kernel.log"
	/usr/bin/time -h env MAKEOBJDIRPREFIX="$obj_dir" \
		make -C "$src_dir" -j"$buildjobs" \
		buildkernel KERNCONFDIR="$kernconf_dir" KERNCONF="$kernconf" \
		TARGET="$target" TARGET_ARCH="$target_arch" \
			> "$log_dir/build-kernel.log" 2>&1 || \
				{ echo "buildkernel failed" ; exit 1 ; }
fi

# Humanize and fix this
#echo ; echo -n "Size of the resulting kernel: "
#	ls -s $obj_dir/$src_dir/${target}.$target_arch/sys/$kernconf/kernel \
#		 | cut -d " " -f1

if [ "$package_base" = "1" ] ; then
	echo ; echo "Packaging base - logging to $log_dir/build-packages.log"
	/usr/bin/time -h env MAKEOBJDIRPREFIX="$obj_dir" \
		make -C "$src_dir" -j"$buildjobs" packages \
		SRCCONF="$src_conf" KERNCONFDIR="$kernconf_dir" \
		KERNCONF="$kernconf" \
		TARGET="$target" TARGET_ARCH="$target_arch" \
			> "$log_dir/build-packages.log" 2>&1 || \
				{ echo "make packages failed" ; exit 1 ; }
fi


#################
# GENERATE JAIL #
#################

if [ "$generate_jail" = "1" ] ; then
	[ -d "${work_dir}/root" ] || mkdir "${work_dir}/root"

	jls | grep -q occambsd && jail -r occambsd

	echo ; echo "Installing Jail world - logging to $log_dir/install-jail-world.log"

	/usr/bin/time -h env MAKEOBJDIRPREFIX="$obj_dir" make -C "$src_dir" \
	installworld SRCCONF="$src_conf" \
	DESTDIR="${work_dir}/root/" \
	NO_FSCHG=YES \
		> "$log_dir/install-jail-world.log" 2>&1

echo ; echo "Installing Jail distribution - logging to $log_dir/jail-distribution.log"

	/usr/bin/time -h env MAKEOBJDIRPREFIX="$obj_dir" make -C "$src_dir" \
	distribution \
	SRCCONF="$src_conf" DESTDIR="${work_dir}/root" \
		> "$log_dir/jail-distribution.log" 2>&1

        echo ; echo "Generating jail.conf"

cat << HERE > "$work_dir/jail.conf"
occambsd {
	host.hostname = occambsd;
	path = "$work_dir/root";
	mount.devfs;
	exec.start = "/bin/sh /etc/rc";
	exec.stop = "/bin/sh /etc/rc.shutdown jail";
}
HERE

	echo ; echo "Generating $work_dir/jail-boot.sh script"
	echo "jail -c -f $work_dir/jail.conf occambsd" > \
		"$work_dir/jail-boot.sh"
	echo "jls" >> "$work_dir/jail-boot.sh"
	echo "$work_dir/jail-boot.sh"

[ -f "$work_dir/jail-boot.sh" ] || \
	{ echo "$work_dir/jail-boot.sh failed to create" ; exit 1 ; }

	echo ; echo "Generating $work_dir/jail-halt.sh script"
	echo "jail -r occambsd" > "$work_dir/jail-halt.sh"
	echo "jls" >> "$work_dir/jail-halt.sh"
	echo "$work_dir/jail-halt.sh"

[ -f "$work_dir/jail-halt.sh" ] || \
	{ echo "$work_dir/jail-halt.sh failed to create" ; exit 1 ; }
fi # End jail


######################
# GENERATE 9PFS ROOT #
######################

if [ "$generate_9pfs" = "1" ] ; then
	[ -d "${work_dir}/9pfs" ] || mkdir "${work_dir}/9pfs"

	echo ; echo "Installing 9pfs world - logging to $log_dir/install-9pfs-world.log"

	/usr/bin/time -h env MAKEOBJDIRPREFIX="$obj_dir" make -C "$src_dir" \
	installworld SRCCONF="$src_conf" \
	DESTDIR="${work_dir}/9pfs/" \
	NO_FSCHG=YES \
		> "$log_dir/install-9pfs-world.log" 2>&1

echo ; echo "Installing 9pfs distribution - logging to $log_dir/9pfs-distribution.log"

	/usr/bin/time -h env MAKEOBJDIRPREFIX="$obj_dir" \
	make -C "$src_dir distribution" \
	SRCCONF="$src_conf" DESTDIR="${work_dir}/9pfs" \
		> "$log_dir/9pfs-distribution.log" 2>&1


	echo ; echo Installing "9pfs kernel - logging to $log_dir/install-9pfs-kernel.log"

	/usr/bin/time -h env MAKEOBJDIRPREFIX="$obj_dir" make -C "$src_dir" \
	installkernel SRCCONF="$src_conf" \
	KERNCONFDIR="$kernconf_dir" KERNCONF="$kernconf" \
	DESTDIR="${work_dir}/9pfs/" \
	NO_FSCHG=YES \
		> "$log_dir/install-9pfs-kernel.log" 2>&1

	echo "virtio_p9fs_load=\"YES\"" > "${work_dir}/9pfs/boot/loader.conf"

	echo "vfs.root.mountfrom=\"p9fs:occambsd\"" \
		>> "${work_dir}/9pfs/boot/loader.conf"

	echo "occambsd / p9fs rw 0 0" > "${work_dir}/9pfs/etc/fstab"
fi # End 9pfs


#############
# VM IMAGES #
#############

if [ "$generate_vm_image" = "1" ] ; then
	cd "$src_dir/release" || \
		{ echo "cd $src_dir/release failed" ; exit 1 ; }

	# Confirm if this uses KERNCONFDIR

	[ -n "$vm_image_size" ] && vm_size_string="VMSIZE=$vm_image_size"
	[ -n "$vm_swap_size" ] && vm_swap_string="SWAPSIZE=$vm_swap_size"

	echo ; echo "Building VM image - logging to $log_dir/vm-image.log"
	/usr/bin/time -h env MAKEOBJDIRPREFIX="$obj_dir" \
		make -C "$src_dir/release" \
		SRCCONF="$src_conf" \
		KERNCONFDIR="$kernconf_dir" KERNCONF="$kernconf" \
		vm-image WITH_VMIMAGES=YES VMFORMATS=raw \
			VMFS="$vmfs" "$vm_size_string" "$vm_swap_string" \
			TARGET="$target" TARGET_ARCH="$target_arch" \
					> "$log_dir/vm-image.log" 2>&1 || \
					{ echo "VM image failed" ; exit 1 ; }

if [ -f "$obj_dir/$src_dir/${target}.$target_arch/release/vm.raw" ] ; then
	echo ; echo "Copying $obj_dir/$src_dir/${target}.$target_arch/release/vm.raw to $work_dir"
	cp "$obj_dir/$src_dir/${target}.$target_arch/release/vm.raw" \
		"$work_dir/" || { echo "VM image copy failed" ; exit 1 ; }
else
#	echo ; echo "Copying $obj_dir/$src_dir/${target}.$target_arch/release/vm.${vmfs}.raw to $work_dir"


# DEBUG TRY THE VARIOUS VM IMAGE NAMES - WILL BE HARD FOR VM BOOT

# I sure hope this has not changed: 14.2/15-CURRENT = raw.zfs.img
	echo ; echo "Copying $obj_dir/$src_dir/${target}.$target_arch/release/vm.${vmfs}.raw to $work_dir"

output_imgage_size=$( stat -f %z "$obj_dir/$src_dir/${target}.$target_arch/release/vm.${vmfs}.raw" )

[ "$output_imgage_size" = 0 ] && \
	{ echo "Resulting image is 0 bytes - verify profile" ; exit 1 ; }

	cp "$obj_dir/$src_dir/${target}.$target_arch/release/vm.${vmfs}.raw" \
		"$work_dir/vm.raw" || { echo "VM image copy failed" ; exit 1 ; }

fi

# DEBUG: ZFS syntax changed? mkimg: partition 1: No such file or directory

# Verify if VM image would be re-using ${target}.$target_arch/release/dist/

	echo ; echo "Generating VM scripts"


	if [ "$target" = "amd64" ] ; then

		cat << HERE > "$work_dir/bhyve-boot-vmimage.sh"
#!/bin/sh
[ \$( id -u ) = 0 ] || { echo "Must be root" ; exit 1 ; } 
[ -e /dev/vmm/occambsd ] && { bhyvectl --destroy --vm=occambsd ; sleep 1 ; }
[ -f /usr/local/share/uefi-firmware/BHYVE_UEFI.fd ] || \\
	{ echo "BHYVE_UEFI.DD missing" ; exit 1 ; }

kldstat -q -m vmm || kldload vmm
sleep 1
#bhyveload -m 1024 -d $work_dir/vm.raw occambsd
bhyve -m 1024 -A -H -l com1,stdio -s 31,lpc -s 0,hostbridge \\
	-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd \\
        -s 2,virtio-blk,$work_dir/vm.raw \\
        occambsd

sleep 2
bhyvectl --destroy --vm=occambsd
HERE

		echo "$work_dir/bhyve-boot-vmimage.sh"

		cat << HERE > "$work_dir/xen.cfg"
type = "hvm"
memory = 1024
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
		echo "$work_dir/xen.cfg"

		echo "xl list | grep OccamBSD && xl destroy OccamBSD" \
			> "$work_dir/xen-boot-vmimage.sh"
		echo "xl create -c $work_dir/xen.cfg" \
			>> "$work_dir/xen-boot-vmimage.sh"
		echo "$work_dir/xen-boot-vmimage.sh"

		echo "xl shutdown OccamBSD ; xl destroy OccamBSD ; xl list" > \
			"$work_dir/xen-cleanup.sh"
		echo "$work_dir/xen-cleanup.sh"

# Notes while debugging
#xl console -t pv OccamBSD
#xl console -t serial OccamBSD


		cat << HERE > "$work_dir/qemu-boot-vmimage.sh"
[ \$( which qemu-system-x86_64 ) ] || \\
	{ echo "qemu-system-x86-64/qemu not installed" ; exit 1 ; }
qemu-system-x86_64 -m 1024M -nographic -object rng-random,id=rng0,filename=/dev/urandom -device virtio-rng-pci,rng=rng0 -rtc base=utc -drive file=/tmp/occambsd/vm.raw,format=raw,index=0,media=disk 
HERE
		echo "$work_dir/qemu-boot-vmimage.sh"
	fi

	if [ "$target" = "arm64" ] ; then
		cat << HERE > "$work_dir/bhyve-boot-vmimage.sh"
#!/bin/sh
[ \$( id -u ) = 0 ] || { echo "Must be root" ; exit 1 ; } 
[ -e /dev/vmm/occambsd ] && { bhyvectl --destroy --vm=occambsd ; sleep 1 ; }
[ -f /usr/local/share/u-boot/u-boot-bhyve-arm64/u-boot.bin ] || \\
	{ echo "u-boot-bhyve-arm64 not installed" ; exit 1 ; }

kldstat -q -m vmm || kldload vmm
sleep 1
bhyve -m 1024 -o console=stdio \\
	-o bootrom=/usr/local/share/u-boot/u-boot-bhyve-arm64/u-boot.bin \\
        -s 2,virtio-blk,$work_dir/vm.raw \\
        occambsd

sleep 2
bhyvectl --destroy --vm=occambsd
HERE
		echo "$work_dir/bhyve-boot-vmimage.sh"

		cat << HERE > "$work_dir/qemu-boot-vmiage.sh"
[ \$( which qemu-system-aarch64 ) ] || { echo "qemu-system-aarch64 not installed" ; exit 1 ; }
[ -f /usr/local/share/qemu/edk2-aarch64-code.fd ] || \\
	{ echo "edk2-qemu-x64 not installed" ; exit 1 ; }
qemu-system-aarch64 -m 1024M -cpu cortex-a57 -machine virt -bios edk2-aarch64-code.fd -nographic -object rng-random,id=rng0,filename=/dev/urandom -device virtio-rng-pci,rng=rng0 -rtc base=utc -drive file=/tmp/occambsd/vm.raw,format=raw,index=0,media=disk 
HERE
		echo "$work_dir/qemu-boot-vmimage.sh"
	fi

fi # End: generate_vm_image


if [ "$generate_9pfs" = "1" ] ; then

	cat << HERE > "$work_dir/bhyve-boot-9pfs.sh"
#!/bin/sh
[ \$( id -u ) = 0 ] || { echo "Must be root" ; exit 1 ; }
[ -e /dev/vmm/occambsd ] && { bhyvectl --destroy --vm=occambsd ; sleep 1 ; }

kldstat -q -m vmm || kldload vmm
sleep 1
bhyveload -m 1024 -h $work_dir/9pfs occambsd   
bhyve -m 1024 -A -H -l com1,stdio -s 31,lpc -s 0,hostbridge \\
	-s 2,virtio-9p,occambsd=$work_dir/9pfs \\
	occambsd

sleep 2
bhyvectl --destroy --vm=occambsd
HERE

	echo "$work_dir/bhyve-boot-9pfs.sh"

fi # End 9pfs


#######
# ISO #
#######

if [ "$generate_isos" = "1" ] ; then
	echo ; echo "Building CD-ROM ISO images - logging to $log_dir/isos.log"
	/usr/bin/time -h env MAKEOBJDIRPREFIX="$obj_dir" \
		make -C "$src_dir/release" \
		SRCCONF=$src_conf \
		KERNCONFDIR="$kernconf_dir" KERNCONF="$kernconf" \
		TARGET="$target" TARGET_ARCH="$target_arch" \
		cdrom \
			> "$log_dir/isos.log" 2>&1 || \
				{ echo "Build ISOs failed" ; exit 1 ; }

	echo ; echo "Copying $obj_dir/$src_dir/${target}.$target_arch/release/disc1.iso to $work_dir"
	cp "$obj_dir/$src_dir/${target}.$target_arch/release/disc1.iso" \
		"$work_dir/"

	echo ; echo "Copying $obj_dir/$src_dir/${target}.$target_arch/release/bootonly.iso to $work_dir"
cp "$obj_dir/$src_dir/${target}.$target_arch/release/bootonly.iso" "$work_dir/"

	echo ; echo "Generating ISO scripts"

	echo "sh /usr/share/examples/bhyve/vmrun.sh -d /tmp/occambsd/disc1.iso disc1" >> "$work_dir/bhyve-boot-disc1.sh"
	echo "$work_dir/bhyve-boot-disc1.sh"

	echo "bhyvectl --destroy --vm=disc1" \
		> "$work_dir/bhyve-cleanup-disc1.sh"
	echo "$work_dir/bhyve-cleanup-disc1.sh"

	echo "sh /usr/share/examples/bhyve/vmrun.sh -d /tmp/occambsd/bootonly.iso bootonly" >> "$work_dir/bhyve-boot-bootonly.sh"
	echo "$work_dir/bhyve-boot-bootonly.sh"

	echo "bhyvectl --destroy --vm=bootonly" \
		> "$work_dir/bhyve-cleanup-bootonly.sh"
	echo "$work_dir/bhyve-cleanup-bootonly.sh"

fi


############
# MEMSTICK #
############

if [ "$generate_memstick" = "1" ] ; then
	echo ; echo "Building mini-memstick image - logging to $log_dir/mini-memstick.log"
	/usr/bin/time -h env MAKEOBJDIRPREFIX="$obj_dir" \
		make -C "$src_dir/release" \
		SRCCONF="$src_conf" \
		KERNCONFDIR="$kernconf_dir" KERNCONF="$kernconf" \
		TARGET="$target" TARGET_ARCH="$target_arch" \
		mini-memstick \
			> "$log_dir/mini-memstick.log" 2>&1 || \
				{ echo "mini-memstick failed" ; exit 1 ; }

	echo ; echo "Copying $obj_dir/$src_dir/${target}.$target_arch/release/mini-memstick.img to $work_dir"
cp "$obj_dir/$src_dir/${target}.$target_arch/release/mini-memstick.img" \
 "${work_dir}"

	echo ; echo "Generating mini-memstick scripts"

	echo "sh /usr/share/examples/bhyve/vmrun.sh -d /tmp/occambsd/mini-memstick.img mini-memstick" >> "$work_dir/bhyve-boot-mini-memstick.sh"
	echo "$work_dir/bhyve-boot-mini-memstick.sh"

	echo "bhyvectl --destroy --vm=mini-memstick" \
		> "$work_dir/bhyve-cleanup-mini-memstick.sh"
	echo "$work_dir/bhyve-cleanup-mini-memstick.sh"
fi

echo
exit 0
