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

# Version v1.0


# MAJOR CAVEAT

# FreeBSD RE makefs -t zfs VM-IMAGES use the pool name 'zroot', with is the
# default suggestion in the installer


# CONDITIONS TO NAVIGATE

# Source: obj|ftp - Is the VM image built or downloaded?
#	obj: /usr/obj/usr/src/amd64.amd64/release/vm.raw
#
#	ftp: i.e. https://download.freebsd.org/ftp/snapshots/VM-IMAGES/14.0-CURRENT/amd64/Latest/FreeBSD-14.0-CURRENT-amd64.raw.xz is downloaded to:
#	/root/imagine-work/current/FreeBSD-14.0-CURRENT-amd64.raw
#	The downloaded raw.xz image is preserved for re-use
#
# Target: dev|img - Is the VM image imaged using dd(1) or does it stay a file?
#	dev: A hardware device is used such as /dev/da1
#
#	img: Disk image files stay files, optionally grown in size
#		/root/imagine-work/vm.raw or
#		i.e. /root/imagine-work/current/FreeBSD-14.0-CURRENT-amd64.raw
#
# Options: Grow the disk image (devices are grown automatically)
#	obj: Optionally copy in /usr/src
#	img: Optionally copy in src.txz and distribution sets
#	img: Generate simple bhyve and Xen configuration and boot files 
#	img: Create a VMDK wrapper for the image, compress the image

# TO DO

# A better check if /media is in use
# Validate that a target hardware device is over 6G in size
# Validate disk size inputs i.e. "10G"
# Consider reordering the questions BUT, they set flags like mustgrow
# Consider command line arguments

# VARIABLES - NOTE THE VERSIONED ONES

work_dir="/root/imagine-work"
vm_name="vm0"


# RELEASE URLS

release_img_url="https://download.freebsd.org/ftp/releases/VM-IMAGES/13.0-RELEASE/amd64/Latest/FreeBSD-13.0-RELEASE-amd64.raw.xz"

release_dist_url="https://download.freebsd.org/ftp/releases/amd64/13.0-RELEASE"


# STABLE URLS

stable_img_url=""
stable_dist_url=""


# CURRENT URLS

current_img_url="https://download.freebsd.org/ftp/snapshots/VM-IMAGES/14.0-CURRENT/amd64/Latest/FreeBSD-14.0-CURRENT-amd64.raw.xz"
#current_img_url="file:///root/imagine-work/current/mirror/FreeBSD-14.0-CURRENT-amd64.raw.xz"

current_dist_url="https://download.freebsd.org/ftp/snapshots/amd64/amd64/14.0-CURRENT"
#current_dist_url="file:///root/imagine-work/current/mirror/freebsd-dist"


# USER INTERACTION: ANSWER ALL QUESTIONS IN ADVANCE

mustgrow="no"
mustmount="no"

echo ; echo What VM-IMAGE origin? /usr/obj or ftp.freebsd.org?
echo -n "(obj/ftp): " ; read origin 
[ "$origin" = "obj" -o "$origin" = "ftp" ] || { echo Invalid input ; exit 1 ; }

echo ; echo Install matching sources in /usr/src on the destination?
echo -n "(y/n): " ; read src
[ "$src" = "y" -o "$src" = "n" ] || { echo Invalid input ; exit 1 ; }
[ "$src" = "y" ] && mustgrow="yes"
[ "$src" = "y" ] && mustmount="yes"

# Think this feature through with regard to nested boot scripts
#echo ; echo Copy the VM image into the destination?
#echo -n "(y/n): " ; read vmimg
#[ "$vmimg" = "y" -o "$vmimg" = "n" ] || { echo Invalid input ; exit 1 ; }
#[ "$vmimg" = "y" ] && mustgrow="yes"
#[ "$vmimg" = "y" ] && mustmount="yes"

if [ "$origin" = "obj" ] ; then
	if ! [ -f /usr/obj/usr/src/amd64.amd64/release/vm.raw ] ; then
		echo "/usr/obj/usr/src/amd64.amd64/release/vm.raw missing"
		exit 1
	fi
else # ftp
	# These questions only apply to ftp origin
	echo ; echo What version of FreeBSD would you like to configure?
	echo -n "(release/stable/current): " ; read version
		[ "$version" = "release" -o "$version" = "stable" -o "$version" = "current" ] || \
			{ echo Invalid input ; exit 1 ; }

	echo ; echo Install all distribution sets to /usr/freebsd-dist ?
	echo -n "(y/n): " ; read dist
	[ "$dist" = "y" -o "$dist" = "n" ] || { echo Invalid input ; exit 1 ; }

	[ "$dist" = "y" ] && mustgrow="yes"

	if [ "$version" = "release" ] ; then
		img_url="$release_img_url"
		dist_url="$release_dist_url"
	elif [ "$version" = "stable" ] ; then
		img_url="$stable_img_url"
		dist_url="$stable_dist_url"
	elif [ "$version" = "current" ] ; then
		img_url="$current_img_url"
		dist_url="$current_dist_url"
	else
		echo Invalid input
		exit 1
	fi

	xzimg="$( basename "$img_url" )"
	img="${xzimg%.xz}"
	img_base="${img%.raw}"
fi

echo ; echo Is the target a disk image or hardware device?
echo -n "(img/dev): " ; read target
[ "$target" = "img" -o "$target" = "dev" ] || { echo Invalid input ; exit 1 ; }

if [ "$target" = "img" ] ; then

# NOTE: POSSIBLE FIRST USE OF work_dir bun

	# work_dir will be used for most if not all operations - handle versioned freebsd-dist separately
	[ -d "${work_dir}" ] || mkdir -p "${work_dir}"	

	if [ "$mustgrow" = "no" ] ; then
		echo ; echo Grow the root partition from from the default 5G?
		echo -n "(y/n): " ; read grow
		[ "$grow" = "y" -o "$grow" = "n" ] || \
			{ echo Invalid input ; exit 1 ; }
		[ "$grow" = "y" ] && mustgrow="yes"
	fi

	if [ "$mustgrow" = "yes" ] ; then
		echo ; echo Grow the VM image to how many G from 5G? i.e. 10G
		echo Matching sources require + 2G
		echo Distribution sets require + 1G
		echo ; echo -n "New VM image size: " ; read newsize
# Would be nice to valildate this input
	fi
else # dev
	mustgrow="yes"
	devices=$( sysctl -n kern.disks )
	for device in $devices ; do
		echo
		echo $device
		diskinfo -v $device | grep descr
		diskinfo -v $device | grep bytes
		echo
	done

	echo ; echo What device would you like to dd the VM image to?
	echo -n "(Device): " ; read target_device

	echo ; echo WARNING! ; echo
	echo Writing to $target_device is destructive!
	echo ; echo Continue?
	echo -n "(y/n): " ; read warning
	[ "$warning" = "y" -o "$warning" = "n" ] || \
		{ echo Invalid input ; exit 1 ; }
	if [ "$warning" = "y" ] ; then
# Add a check if the devices is mounted
		echo "Running zpool labelclear ${target_device}p4"
		zpool labelclear -f ${target_device}p4 > /dev/null 2>&1
	fi
fi

if [ "$target" = "img" ] ; then
	echo ; echo Generate bhyve VM guest boot scripts?
	echo -n "(y/n): " ; read bhyve
	[ "$bhyve" = "y" -o "$bhyve" = "n" ] || { echo Invalid input ; exit 1 ; }

	echo ; echo Generate Xen DomU VM guest boot script?
	echo -n "(y/n): " ; read domu
	[ "$domu" = "y" -o "$domu" = "n" ] || { echo Invalid input ; exit 1 ; }

	echo ; echo Create a VMDK wrapper for the image?
	echo WARNING: This will break bhyve and xen script device paths!
	echo -n "(y/n): " ; read vmdk
	[ "$vmdk" = "y" -o "$vmdk" = "n" ] || { echo Invalid input ; exit 1 ; }

# Rethink this in the context of raw and pseudo-vmdk images
#	echo ; echo gzip compress the configured image file?
#	echo Remember to uncompress the image before use!
#	echo -n "(y/n): " ; read gzip
#	[ "$gzip" = "y" -o "$gzip" = "n" ] || { echo Invalid input ; exit 1 ; }
fi


# QUESTIONS ANSWERED, ON TO SLOW OPERATIONS

if [ "$mustmount" = "yes" ] ; then
# FIND A RELIABLE TEST FOR BEFORE AND AFTER
	echo Unmouting /media
	mount | grep "media" && umount -f /media # || \
#		{ echo /media failed to unmount ; exit 1 ; }
fi

if [ "$origin" = "ftp" ] ; then


# Decide if creating freebsd-dist, even if not used bun



	[ -d "${work_dir}/$version/freebsd-dist" ] ||  mkdir -p "${work_dir}/$version/freebsd-dist"
	[ -d "${work_dir}/$version/freebsd-dist" ] || \
		{ echo "mkdir -p $work_dir/$version/freebsd-dist failed" ; exit 1 ; }

	if [ -f "$work_dir/$version/$xzimg" ] ; then
		echo ; echo $xzimg exists. Fetch fresh?
		echo -n "(y/n): " ; read freshimg
		[ "$freshimg" = "y" -o "$freshimg" = "n" ] || 
			{ echo Invalid input ; exit 1 ; }
		if [ "$freshimg" = "y" ] ; then
			echo ; echo Moving "$work_dir/$version/$xzimg" to \
				"$work_dir/$version/${xzimg}.prev"
			mv "$work_dir/$version/$xzimg" \
				"$work_dir/$version/${xzimg}.prev"
		fi
	else
		freshimg="y"
	fi

	if [ "$freshimg" = "y" ] ; then
		echo ; echo Fetching $img from $img_url
		cd "$work_dir/$version"
		# Any need for fetch -i?
		fetch "$img_url" || \
			{ echo fetch failed ; exit 1 ; }
	fi
fi

# Additional Cleanup - do not remove the compressed images

# Without versions... THESE ARE QUITE WRONG FOR ALL FTP ORIGINS

# IN FACT, the vmdk handling might be wrong given that a vmdk can be vm.raw or versioned...


# IS $version EVEN SET AT THIS POINT?

[ -f "$work_dir/vm.raw" ] && \
	rm "$work_dir/vm.raw"
[ -f "$work_dir/$version/$img" ] && \
	rm "$work_dir/$version/$img"
[ -f "$work_dir/$version/$img" ] && rm "$work_dir/$version/$img"
rm $work_dir/*.sh > /dev/null 2>&1
rm $work_dir/*.cfg > /dev/null 2>&1
rm $work_dir/$version/*.sh > /dev/null 2>&1
rm $work_dir/$version/*.cfg > /dev/null 2>&1
rm $work_dir/*.vmdk > /dev/null 2>&1
rm $work_dir/$version/*.vmdk > /dev/null 2>&1
rm $work_dir/*.gz > /dev/null 2>&1
rm $work_dir/$version/*.gz > /dev/null 2>&1

if [ "$target" = "dev" ] ; then
	if [ "$origin" = "obj" ] ; then
		echo Imaging vm.raw to /dev/$target_device
		\time -h dd of=/dev/$target_device bs=1m status=progress \
			if=/usr/obj/usr/src/amd64.amd64/release/vm.raw || \
				{ echo "dd failed" ; exit 1 ; }
		echo ; echo Recovering $target_device partitioning
		gpart recover $target_device
	else # ftp
# Should exist and not need a test?
		[ -f $work_dir/$version/$xzimg ] || \
			{ echo $work_dir/$version/$xzimg missing ; exit 1 ; }
		echo Imaging $work_dir/$version/$xzimg to /dev/$target_device
		\time -h cat $work_dir/$version/$xzimg | \
			xz -d -k | \
			dd of=/dev/$target_device bs=1m status=progress \
				iflag=fullblock || \
					{ echo unxz/dd failed ; exit 1 ; }
		echo ; echo Recovering $target_device partitioning
		gpart recover $target_device
	fi
else # img
	if [ "$origin" = "obj" ] ; then

# NOTE: POSSIBLE FIRST USE OF work_dir bun
# ONLY NEED TO COPY IF TARGET IS IMG

		cp /usr/obj/usr/src/amd64.amd64/release/vm.raw $work_dir/

# SKIP THIS STEP IF GOING DIRECTLY FROM OBJ TO IMG?



	else # ftp
		cd "$work_dir/$version"
		echo ; echo Uncompressing "$work_dir/$version/$xzimg"
# Uncompressed image will be $work_dir/$version/$img with no .xz suffix
		\time -h unxz --verbose --keep "$work_dir/$version/$xzimg"
	fi
fi

# BARE MINIMUM EFFORT IS COMPLETE


# EXPAND TARGET IF TYPE DEV AND ADD OPTIONAL CONTENTS

if [ "$mustgrow" = "yes" ] ; then
# target-image is already set for a target type dev
	if [ "$target" = "img" ] ; then
		if [ "$origin" = "obj" ] ; then
			echo ; echo Truncating $work_dir/vm.raw
			truncate -s $newsize $work_dir/vm.raw || \
				{ echo truncate failed ; exit 1 ; }
			echo ; echo Attaching $work_dir/vm.raw 
			target_device=$( mdconfig -af $work_dir/vm.raw ) || \
				{ echo mdconfig failed ; exit 1 ; }
			mdconfig -lv
		else # ftp
			echo ; echo Truncating $work_dir/$version/$img
			truncate -s $newsize $work_dir/$version/$img || \
				{ echo truncate failed ; exit 1 ; }
			echo ; echo Attaching $work_dir/$version/$img
		target_device=$( mdconfig -af $work_dir/$version/$img ) || \
				{ echo mdconfig failed ; exit 1 ; }
			mdconfig -lv
		fi
# Already performed on target type dev
		echo ; echo Recovering $target_device partitioning
		gpart recover $target_device || \
			{ echo gpart recover failed ; exit 1 ; }
	fi

# (/dev/)${target_device}p4 is now dev/img agnostic at this point

	echo ; echo Resizing ${target_device}p4
	gpart resize -i 4 "$target_device"
	gpart show "$target_device"

rootfs="$( gpart show $target_device | tail -2 | head -1 | awk '{print $4}' )"

	if [ "$rootfs" = "freebsd-ufs" ] ; then
		echo ; echo Growing /dev/${target_device}p4
		growfs -y "/dev/${target_device}p4"

		if [ "$mustmount" = "yes" ] ; then
			mount /dev/${target_device}p4 /media || \
				{ echo mount failed ; exit 1 ; }
			df -h | grep media
		fi
	else
		zpool list
		# SAFETY TEST GIVEN HOW MANY FREEBSD ZPOOLS ARE NAMED \"ZROOT\"
		# HOWEVER that is our /usr/obj zpool name. Offer to export it?
		zpool get name zroot > /dev/null 2>&1 && \
			{ echo zpool zroot in use and will conflict ; exit 1 ; }
# -f does not appear to be needed
		if [ "$mustmount" = "yes" ] ; then
			zpool import -R /media zroot
			df -h | grep media
		else
			zpool import -N zroot
		fi
		zpool list
		zpool status zroot

		zpool set autoexpand=on zroot

		# Will be prefixed with gptid/
		rootdev="$( zpool status zroot | grep gptid | awk '{print $1}' )"
		zpool online -e zroot /dev/$rootdev
		zpool list
	fi
fi


# OPTIONAL SOURCES

if [ "$src" = "y" ] ; then
	if [ "$origin" = "obj" ] ; then
		echo Copying /usr/src to /media/usr/src
# Watch those paths
		tar cf - /usr/src | tar xf - -C /media || \
			{ echo /usr/src failed to copy ; exit 1 ; }
			df -h | grep media
	else
		if [ "$freshimg" = "y" -o ! -f "$work_dir/$version/freebsd-dist/src.txz" ] ; then
			cd $work_dir/$version/freebsd-dist/
			[ -f "$work_dir/$version/freebsd-dist/src.txz" ] &&
				rm src.txz
			echo Fetching $dist_url/src.txz
			fetch $dist_url/src.txz || \
				{ echo fetch failed ; exit 1 ; }
			srcisfresh=1
		fi

		# Should have src.txz at this point

	[ -f "$work_dir/$version/freebsd-dist/src.txz" ] || \
			{ echo "SOMETHING WENT VERY WRONG DOWNLOADING src.txz" ; exit 1 ; }

		cd $work_dir/$version/freebsd-dist/
		echo ; echo Extracting src.txz to /media
		cat src.txz | tar -xf - -C /media/

		df -h | grep media
	fi

	echo ; echo Listing /media/usr/src ; ls /media/usr/src
fi


# OPTIONAL DISTRIBUTION SETS
#	CONSIDER LOOKING FOR THEM FOR VM.RAW, BUT THIS FUNDAMENTALLY SIDE STEPS THEM

if [ "$dist" = "y" ] ; then
	if [ "$origin" = "obj" ] ; then
# Could loop on .txz files in the release directory
#		[ -f /usr/obj/usr/src/amd64.amd64/release/base.txz ] && \ 
#			cp /usr/obj/usr/src/amd64.amd64/release/base.txz \
#				/media/usr/freebsd-dist/
		echo Distribution sets not supported for build images ; sleep 3
	else # ftp
		if [ "$freshdist" = "y" -o ! -f "$work_dir/$version/freebsd-dist/base.txz" ] ; then
			cd $work_dir/$version/freebsd-dist/
			echo Fetching distributions sets
			rm MANIFEST
			fetch $dist_url/MANIFEST || \
				{ echo fetch failed ; exit 1 ; }
			rm base*
			fetch $dist_url/base-dbg.txz || \
				{ echo fetch failed ; exit 1 ; }
			fetch $dist_url/base.txz || \
				{ echo fetch failed ; exit 1 ; }
			rm kernel*
			fetch $dist_url/kernel-dbg.txz || \
				{ echo fetch failed ; exit 1 ; }
			fetch $dist_url/kernel.txz || \
				{ echo fetch failed ; exit 1 ; }
			rm lib32*
			fetch $dist_url/lib32-dbg.txz || \
				{ echo fetch failed ; exit 1 ; }
			fetch $dist_url/lib32.txz || \
				{ echo fetch failed ; exit 1 ; }
			rm ports.txz
			fetch $dist_url/ports.txz || \
				{ echo fetch failed ; exit 1 ; }
			rm tests.txz
			fetch $dist_url/tests.txz || \
				{ echo fetch failed ; exit 1 ; }
			if ! [ "$srcisfresh" = "1" ] ; then
				rm src.txz
				fetch $dist_url/src.txz
			fi
		fi

		echo Copying distributions sets
		cp -rp $work_dir/$version/freebsd-dist /media/usr/

		df -h | grep media
	fi
fi


# Feature on hold
## OPTIONAL VM IMAGE COPY
#
#if [ "$vmimg" = "y" ] ; then
#
#	if [ "$origin" = "obj" ] ; then
#		cp /usr/obj/usr/src/amd64.amd64/release/vm.raw \
#			/media/root/ || \
#			{ echo "VM image copy failed" ; exit 1 ; }
#	else
#		xz -d -k -c "$work_dir/$version/$xzimg" > /media/root/$img || \
#			{ echo "VM image copy failed" ; exit 1 ; }
#	fi
#fi


# OPTIONAL bhyve VM SUPPORT

if [ "$bhyve" = "y" ] ; then
	if [ "$origin" = "obj" ] ; then
		bhyve_img="$work_dir/vm.raw"
	else # ftp
		bhyve_img="$work_dir/$version/$img"
	fi

#	if [ "$target" = "img" ] ; then
		bhyve_path="$work_dir/$version"
#	else # dev
#		bhyve_path="/media/root"
#	fi

# Provide some vmm.ko loading code
	cat << EOF > "${bhyve_path}/boot-bhyve.sh"
[ -e /dev/vmm/$vm_name ] && { bhyvectl --destroy --vm=$vm_name ; sleep 1 ; }
kldstat -q -m vmm || kldload vmm
sleep 1
bhyveload -d $bhyve_img -m 1024 $vm_name
sleep 1
bhyve -m 1024 -H -A -s 0,hostbridge -s 2,virtio-blk,$bhyve_img -s 31,lpc -l com1,stdio $vm_name
sleep 2
bhyvectl --destroy --vm=$vm_name
EOF
	echo ; echo Note: ${bhyve_path}/boot-bhyve.sh
fi


# OPTIONAL XEN DOMU SUPPORT

if [ "$domu" = "y" ] ; then
	if [ "$origin" = "obj" ] ; then
		xen_img="$work_dir/vm.raw"
	else # ftp
		xen_img="$work_dir/$version/$img"
	fi

#	if [ "$target" = "img" ] ; then
		xen_path="$work_dir$version"
#	else # dev
#		xen_path="/media/root"
#	fi

cat << HERE > $xen_path/xen.cfg
type = "hvm"
memory = 1024
vcpus = 1
name = "$vm_name"
disk = [ '$xen_img,raw,hda,w' ]
boot = "c"
serial = 'pty'
on_poweroff = 'destroy'
on_reboot = 'restart'
on_crash = 'restart'
#vif = [ 'bridge=bridge0' ]
HERE

echo ; echo Note: $xen_path/xen.cfg

	echo "xl list | grep $vm_name && xl destroy $vm_name" \
		> $xen_path/boot-xen.sh
	echo "xl create -c $xen_path/xen.cfg" \
		>> $xen_path/boot-xen.sh
	echo ; echo Note: $xen_path/boot-xen.sh

	echo "xl shutdown $vm_name ; xl destroy $vm_name ; xl list" > \
		$xen_path/destroy-xen.sh
	echo ; echo Note: $xen_path/destroy-xen.sh
fi


# OPTIONAL VMDK WRAPPER

# THIS WILL RENAME THE DISK IMAGE AND BREAK BHYVE/XEN

if [ "$vmdk" = "y" ] ; then
	if [ "$origin" = "obj" ] ; then
		vmdk_img="$work_dir/vm.raw"
	else # ftp
		vmdk_img="$work_dir/$version/$img"
	fi

	vmdk_img_base="${vmdk_img%.raw}"

	# Assuming blocksize of 512
	size_bytes="$( stat -f %z "$vmdk_img" )"
	RW=$(( "$size_bytes" / 512 ))
	cylinders=$(( "$RW" / 255 / 63 ))

cat << EOF > "${vmdk_img_base}.vmdk"
# Disk DescriptorFile
version=1
CID=12345678
parentCID=ffffffff
createType="vmfs"

RW $(( "$size_bytes" / 512 )) VMFS "${vmdk_img_base}-flat.vmdk"

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
	echo ; echo The resulting "${vmdk_img_base}.vmdk" wrapper reads: ; echo
	cat "${vmdk_img_base}.vmdk"
	echo ; echo Renaming "$vmdk_img" to "${vmdk_img_base}-flat.vmdk"

	mv "$vmdk_img" "${vmdk_img_base}-flat.vmdk"
fi


## OPTIONAL VM-IMAGE GZIP COMPRESSION
## gzip is more portable/compatible and will not override the upstream image
#
#if [ "$gzip" = "y" ] ; then
#	if [ "$vmdk" = "y" ] ; then
#		\time -h gzip "${img_base}-flat.vmdk" || \
#			{ echo gzip failed ; exit 1 ; }
## Consider progress feedback
#	else
#		\time -h gzip "$img" || { echo gzip failed ; exit 1 ; }
#	fi
#fi


# FINAL REVIEW BEFORE UNMOUNTING/EXPORTING

if [ "$mustmount" = "yes" ] ; then
	echo ; echo About to unmount /media
	echo Last chance to make final changes to the mounted image at /media
	echo ; echo Unmount /media ?
	echo -n "(y/n): " ; read umount
	[ "$umount" = "y" -o "$umount" = "n" ] || \
		{ echo Invalid input ; exit 1 ; }
	if [ "$umount" = "y" ] ; then
		if [ "$rootfs" = "freebsd-ufs" ] ; then
			echo ; echo Unmounting /media
			umount /media || { echo umount failed ; exit 1 ; }
		else
			zpool export zroot || \
				{ echo zpool export failed ; exit 1 ; }
		fi
		if [ "$target" = "img" ] ; then
			echo ; echo Destroying $target_device
			mdconfig -du $target_device || \
		{ echo $target_device destroy failed ; mdconfig -lv ; exit 1 ; }
		fi
	else
		echo ; echo "You can manually run \'umount /media\' or"
		echo "\'zpool export zroot\' and"
		echo "\'mdconfig -du $target_device\' as needed"
	fi
else
	if [ "$rootfs" = "freebsd-zfs" ] ; then
		zpool export zroot || { echo zpool export failed ; exit 1 ; }
	fi
fi

mdconfig -lv

exit 0
