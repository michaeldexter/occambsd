#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause-FreeBSD
#
# Copyright 2021 Michael Dexter
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

# Version 13.0-RELEASE v3-beta

# occambsd: An application of Occam's razor to FreeBSD
# a.k.a. "super svelte stripped down FreeBSD"

# This will create a kernel directories and disk images for bhyve and xen,
# a jail(8) root directory, and related load, boot, and cleanup scripts.

# The default target is the bhyve hypervisor but Xen can be specified with
# -x and Jail with -j

# The separate kernel directory is very useful for testing kernel changes
# while waiting for institutionalized VirtFS support.

# The -u option will built and install a minimal userland,
# rather than building and installing world


# VARIABLES

zfsroot="0"
target="bhyve"
userland="0"
release="0"
quiet="0"

while getopts zxjurq opts ; do
	case $opts in
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
		userland="1"
		;;
	r)
		release="1"
		;;
	q)
		quiet="1"
		;;
	esac
done

src_dir="/usr/src"
work_dir="/tmp/occambsd"		# This will be mounted tmpfs
log_dir="$work_dir/logs"
imagesize="4G"				# More than enough room
md_id="md42"				# Ask Douglas Adams for an explanation
buildjobs="$(sysctl -n hw.ncpu)"
enabled_options="WITHOUT_AUTO_OBJ WITHOUT_UNIFIED_OBJDIR WITHOUT_INSTALLLIB WITHOUT_BOOT WITHOUT_LOADER_LUA WITHOUT_LOCALES WITHOUT_ZONEINFO WITHOUT_EFI WITHOUT_VI"
enabled_zfs_options="WITHOUT_LOADER_ZFS WITHOUT_ZFS WITHOUT_CDDL WITHOUT_CRYPT WITHOUT_OPENSSL"

if [ "$zfsroot" = "1" ] ; then
	enabled_options="$enabled_options $enabled_zfs_options"
fi

# The world will be built WITH these build options:
# WITHOUT_AUTO_OBJ and WITHOUT_UNIFIED_OBJDIR warn that they go in src-env.conf
# <broken or complex build options>
# WITHOUT_LOADER_LUA is required for the lua boot code
# WITHOUT_BOOT is needed to install the LUA loader
# WITHOUT_LOCALES is necessary for a console
# WITHOUT_ZONEINFO is necessary for tzsetup on VM image with a userland
# WITHOUT_EFI to support make release, specifically for loader.efi
# WITHOUT_VI could come in handy
# Required for ZFS support:
# WITHOUT_LOADER_ZFS WITHOUT_ZFS WITHOUT_CDDL WITHOUT_CRYPT WITHOUT_OPENSSL


# PREFLIGHT CHECKS

[ -f $src_dir/sys/amd64/conf/GENERIC ] || \
	{ echo Sources do not appear to be installed ; exit 1 ; }

[ -f ./lib_occambsd.sh ] || { echo lib_occambsd.sh not found ; exit 1 ; }
. ./lib_occambsd.sh || { echo lib_occambsd.sh failed to source ; exit 1 ; }


# CLEANUP

# tmpfs mounts are not always dected by mount | grep tmpfs ...
#	They may also be mounted multiple times atop one another and
#	md devices may be attached multiple times. Proper cleanup would be nice

umount -f "$work_dir/image-mnt" > /dev/null 2>&1
umount -f "$work_dir/jail-mnt/dev" > /dev/null 2>&1
umount -f "$work_dir" > /dev/null 2>&1
umount -f "$work_dir" > /dev/null 2>&1
umount -f "/usr/obj" > /dev/null 2>&1
umount -f "/usr/obj" > /dev/null 2>&1
zpool export -f occambsd > /dev/null 2>&1
mdconfig -du "$md_id" > /dev/null 2>&1
mdconfig -du "$md_id" > /dev/null 2>&1

echo ; echo Do any memory devices or tmpfs mounts need to be cleaned up?
echo Press ANY key if you do not see any to continue ; echo

zpool list | grep occambsd
mdconfig -lv
mount | grep "$work_dir"
mount | grep "/usr/obj"
read areweclean


# PREPARATION

[ -d $work_dir ] || mkdir -p "$work_dir"
[ "$?" -ne "0" ] && { echo Failed to make $work_dir ; exit 1 ; }

echo ; echo Mounting $work_dir tmpfs
mount -t tmpfs tmpfs "$work_dir" || { echo tmpfs mount failed ; exit 1 ; }

mkdir -p "$log_dir" || { echo Failed to create $log_dir ; exit 1 ; }

echo ; echo Mounting a tmpfs to /usr/obj/
mount -t tmpfs tmpfs /usr/obj/

mount | grep tmpfs


# SRC.CONF

echo ; echo Generating $work_dir/src.conf with f_occam_options

f_occam_options $src_dir "$enabled_options" > $work_dir/src.conf || \
	{ echo f_occam_options function failed ; exit 1 ; }

echo ; echo The src.conf options that exclude components reads: ; echo

cat $work_dir/src.conf

[ "$quiet" = "0" ] && { echo ; echo Press ANY key to continue ; read anykey ; }


# KERNCONF

# FUTURE: Could build bhyve and Xen-specific kernel configuration files
# No point if for a jail but it is quick

echo ; echo Creating new OCCAMBSD KERNCONF
#cat << HERE > $src_dir/sys/amd64/conf/OCCAMBSD
cat << HERE > $work_dir/OCCAMBSD

cpu		HAMMER
ident		OCCAMBSD

# Sync with the devices below? Have not needed virtio_blk etc.
makeoptions	MODULES_OVERRIDE="virtio opensolaris zfs cryptodev acl_nfs4 xdr zlib crypto"

# crypto fails without xdr

# Pick a scheduler - Required
options 	SCHED_ULE		# ULE scheduler
#options	SCHED_4BSD

device		pci
# The tribal elders say that the loopback device was not always required
device		loop			# Network loopback
# The modern kernel will not build without ethernet
device		ether			# Ethernet support
# The kernel should build at this point

# Do boot it in bhyve, you will want to see serial output
device		uart			# Generic UART driver

#panic: running without device atpic requires a local APIC
device		atpic			# 8259A compatability

# To get past mountroot
device		ahci			# AHCI-compatible SATA controllers
device		scbus			# SCSI bus (required for ATA/SCSI)

# Throws an error but works - Investigate
options		GEOM_PART_GPT		# GUID Partition Tables.

# Mounting from ufs:/dev/vtbd0p3 failed with error 2: unknown file system.
options 	FFS			# Berkeley Fast Filesystem

# Add labling handling to support booting from disc1.iso and memstick.img
options		GEOM_LABEL		# Provides labelization

# Add CD-ROM file system support for booting from disc1.iso
device		cd			# CD
options		CD9660			# ISO 9660 Filesystem

# Appears to work with only "virtio" synchronized above with MODULES_OVERRIDE
# Investigate
device		virtio			# Generic VirtIO bus (required)
device		virtio_pci		# VirtIO PCI device
device		virtio_blk		# VirtIO Block device

# Needed for Xen
options		XENHVM			# Xen HVM kernel infrastructure
device		xenpci			# Xen HVM Hypervisor services driver
device		acpi
#device		da			# Direct Access (disks)

# Apparently not needed if virtio device and MODULE_OVERRIDE are specified
#device		vtnet			# VirtIO Ethernet device
#device		virtio_scsi		# VirtIO SCSI device
#device		virtio_balloon		# VirtIO Memory Balloon device

# Luxurious options - sync with build options
#options	SMP			# Symmetric MultiProcessor Kernel
#options	INET			# InterNETworking
#device		iflib
#device		em			# Intel PRO/1000 Gigabit Ethernet Family

# Requested/required by the zfs kernel
device		crypto			# core crypto support
device		aesni			# AES-NI OpenCrypto module
HERE

echo ; echo The resulting OCCAMBSD KERNCONF is
cat $work_dir/OCCAMBSD

[ "$quiet" = "0" ] && { echo ; echo Press ANY key to continue ; read anykey ; }


# DIRECTORIES, DISK IMAGES, AND PARTITIONING

if [ "$target" = "jail" ] ; then
	mkdir -p "$work_dir/jail-mnt"
else
	mkdir -p "$work_dir/kernel/boot"
	mkdir -p "$work_dir/kernel/etc"
	mkdir -p "$work_dir/image-mnt"

	echo ; echo Truncating occambsd.raw image - consider -t malloc and tmpfs
	truncate -s "$imagesize" "$work_dir/occambsd.raw" || \
	{ echo $work_dir/occambsd.raw image truncation failed ; exit 1 ; }

	echo ; echo Attaching occambsd.raw VM image
	mdconfig -a -u "$md_id" -f "$work_dir/occambsd.raw"

	[ -e /dev/$md_id ] || \
		{ echo $md_id did not attach ; exit 1 ; }

[ "$quiet" = "0" ] && { echo ; echo Press ANY key to continue ; read anykey ; }

echo ; echo Partitioning and formating $md_id
	gpart create -s gpt $md_id
	#gpart add -t freebsd-boot -l bootfs -b 128 -s 128K $md_id
	gpart add -a 4k -s 512k -t freebsd-boot /dev/$md_id
	gpart add -t freebsd-swap -s 1G $md_id

	if [ "$zfsroot" = "1" ] ; then
# Moved until after world/stand are built
#		echo Adding gptzfsboot boot code
#		gpart bootcode -b $dest_dir/boot/pmbr -p \
#			$dest_dir/boot/gptzfsboot -i 1 /dev/$md_id || \
#			{ echo gpart bootcode failed ; exit 1 ; }

		echo Adding freebsd-zfs partition
		gpart add -t freebsd-zfs /dev/$md_id || \
			{ echo gpart add -t freebsd-zfs failed ; exit 1 ; }

		echo Creating occambsd zpool
		# altroot does not appear to be required
#		zpool create -o altroot=$work_dir/image-mnt \
		zpool create -O compress=lz4 -R $work_dir/image-mnt \
			-O atime=off -m none occambsd /dev/${md_id}p3 || \
			{ echo zpool create failed ; exit 1 ; }

		echo Creating boot environment dataset
		zfs create -o mountpoint=none occambsd/ROOT || \
			{ echo first zfs create failed ; exit 1 ; }

		echo Creating default dataset
		zfs create -o mountpoint=/ occambsd/ROOT/default || \
			{ echo default zfs create failed ; exit 1 ; }

		echo setting bootfs
		zpool set bootfs=occambsd/ROOT/default occambsd || \
			{ echo zpool set bootfs failed ; exit 1 ; }

		# Not needed for kernel-in-image boot, not helpful with kernel
		#zpool set cachefile=$image-mnt/boot/zfs/zpool.cache occambsd
	else
# Moved until after world/stand are built
#		gpart bootcode -b /boot/pmbr -p /boot/gptboot -i 1 /dev/$md_id
		gpart add -t freebsd-ufs /dev/$md_id
		newfs -U /dev/${md_id}p3 || \
			{ echo /dev/${md_id}p3 VM newfs failed ; exit 1 ; }
		echo ; echo Mounting ${md_id}p3 with \
		mount /dev/${md_id}p3 $work_dir/image-mnt
		mount /dev/${md_id}p3 $work_dir/image-mnt || \
			{ echo image mount failed ; exit 1 ; }
	fi
fi

[ "$quiet" = "0" ] && { echo ; echo Press ANY key to continue ; read anykey ; }


# USERLAND

if [ "$target" = "jail" ] ; then
	dest_dir="$work_dir/jail-mnt"
else
	dest_dir="$work_dir/image-mnt"
fi

if [ "$userland" = "0" ] ; then
        echo ; echo Building world - logging to $log_dir/build-world.log
        \time -h make -C $src_dir -j$buildjobs \
        SRCCONF=$work_dir/src.conf buildworld \
        > $log_dir/build-world.log || { echo buildworld failed ; exit 1 ; }

[ "$quiet" = "0" ] && { echo ; echo Press ANY key to continue ; read anykey ; }

	echo ; echo Installing world - logging to $log_dir/install-world.log
	\time -h make -C $src_dir installworld SRCCONF=$work_dir/src.conf \
		DESTDIR=$dest_dir \
	> $log_dir/install-world.log 2>&1

response="n"
[ "$quiet" = "0" ] && \
{ echo Press y to prune locales and timezones saving 28M? ; read response ; }

if [ "$response" = "y" ]; then
	echo Deleting unused locales from $dest_dir
	cd $dest_dir/usr/share/locale/
	rm -rf a* b* c* d* e* f* g* h* i* j* k* l* m* n* p* r* s* t* u* z*
	echo Deleting unused timezone data from $dest_dir
	cd $dest_dir/usr/share/zoneinfo
	rm -rf A* B* C* E* F* G* H* I* J* K* L* M* N* P* R* S* T* UCT US W* Z*

#	echo Deleting unused locales from $work_dir/kernel
#	cd $work_dir/kernel/usr/share/locale/
#	rm -rf a* b* c* d* e* f* g* h* i* j* k* l* m* n* p* r* s* t* u* z*
#	echo Deleting unused timezone data from $work_dir/kernel
#	cd $work_dir/kernel/usr/share/zoneinfo
#	rm -rf A* B* C* E* F* G* H* I* J* K* L* M* N* P* R* S* T* UCT US W* Z*
fi


else
	echo ; echo Building and installing an artisanal userland!

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

echo ; echo Static builds!

IFS="
"
for static in $statics ; do
	util=$(basename $static )
	echo Making $src_dir/$static
	make -j$buildjobs -C $src_dir/$static NO_SHARED=YES \
	WITHOUT_MAN=YES WITHOUT_MANCOMPRESS=YES \
	> $log_dir/make-$util.log 2>&1 || \
		{ echo make $static failed ; exit 1 ; }

#	SRCCONF=$work_dir/src.conf || \

	echo Installing $static
	make -C $src_dir/$static install DESTDIR=$dest_dir \
	WITHOUT_MAN=YES WITHOUT_MANCOMPRESS=YES \
	SRCCONF=$work_dir/src.conf > $log_dir/install-$util.log 2>&1 || \
		{ echo install $static failed ; exit 1 ; }
done

echo ; echo Dynamic builds!

#IFS="
#"
for dynamic in $dynamics ; do
        dyn=$(basename $dynamic )
        echo Making $src_dir/$dynamic
        make -j$buildjobs -C $src_dir/$dynamic \
        WITHOUT_MAN=YES WITHOUT_MANCOMPRESS=YES \
        > $log_dir/make-$dyn.log 2>&1 || \
                { echo make $dynamic failed ; exit 1 ; }

#       SRCCONF=$work_dir/src.conf || \

        echo Installing $dynamic
        make -C $src_dir/$dynamic install DESTDIR=$dest_dir \
        WITHOUT_MAN=YES WITHOUT_MANCOMPRESS=YES \
        SRCCONF=$work_dir/src.conf > $log_dir/install-$dyn.log 2>&1 || \
                { echo install $dynamic failed ; exit 1 ; }
done

echo Building share/ctypedef
make -C $src_dir/share/ctypedef > $log_dir/make-ctypedef.log 2>&1 || \
	{ echo make /share/ctypedef failed ; exit 1 ; }

echo Copying /usr/share/locale/C.UTF-8/LC_CTYPE
cp /usr/obj/$src_dir/amd64.amd64/share/ctypedef/C.UTF-8.LC_CTYPE \
	$dest_dir/usr/share/locale/C.UTF-8/ || \
		{ echo C.UTF-8.LC_CTYPE copy from $obj_dir failed ; exit 1 ; }

echo Building /usr/share/zoneinfo 
make -C $src_dir/share/zoneinfo > $log_dir/make-zoneinfo.log 2>&1 || \
	{ echo make /share/zoneinfo failed ; exit 1 ; }

echo Copying /usr/share/zoneinfo/UTC
cp /usr/obj/$src_dir/amd64.amd64/share/zoneinfo/builddir/Etc/UTC \
	$dest_dir/usr/share/zoneinfo/ || \
		{ echo make /share/zoneinfo/UTC failed ; exit 1 ; }

fi # End world

# Alternative: use a known-good full userland
#cat /usr/freebsd-dist/base.txz | tar -xf - -C $dest_dir


# BOOT CODE - Must be performed after stand is built

echo ; echo Adding boot code

if [ "$zfsroot" = "1" ] ; then
	echo Adding gptzfsboot boot code
	gpart bootcode -b $dest_dir/boot/pmbr -p \
	$dest_dir/boot/gptzfsboot -i 1 /dev/$md_id || \
		{ echo gpart bootcode failed ; exit 1 ; }
else
	gpart bootcode -b $dest_dir/boot/pmbr \
	-p $dest_dir/boot/gptboot -i 1 /dev/$md_id
fi

# Alternatively install from the host
#	gpart bootcode -b /boot/pmbr -p /boot/gptboot -i 1 /dev/$md_id


# KERNEL

if [ ! "$target" = "jail" ] ; then

[ "$quiet" = "0" ] && { echo ; echo Press ANY key to continue ; read anykey ; }

	echo ; echo Building kernel - logging to $log_dir/build-kernel.log
	\time -h make -C $src_dir -j$buildjobs buildkernel \
		KERNCONFDIR=$work_dir KERNCONF=OCCAMBSD \
		> $log_dir/build-kernel.log || \
			{ echo buildkernel failed ; exit 1 ; }

	echo ; echo Seeing how big the resulting kernel is
	ls -lh /usr/obj/$src_dir/amd64.amd64/sys/OCCAMBSD/kernel

[ "$quiet" = "0" ] && { echo ; echo Press ANY key to continue ; read anykey ; }

	echo ; echo Installing the kernel to $dest_dir - \
		logging to $log_dir/install-kernel.log
	\time -h make -C $src_dir installkernel KERNCONFDIR=$work_dir \
		KERNCONF=OCCAMBSD DESTDIR=$dest_dir \
		> $log_dir/install-kernel.log 2>&1
	[ -f $dest_dir/boot/kernel/kernel ] || \
		{ echo kernel failed to install to $dest_dir ; exit 1 ; }

	# Need not be nested but the familiar location is familiar
	echo Copying the kernel to $work_dir/kernel/
	cp -rp $work_dir/image-mnt/boot/kernel \
		$work_dir/kernel/boot/
	[ -f $work_dir/kernel/boot/kernel/kernel ] || \
		{ echo $work_dir/kernel failed to copy ; exit 1 ; }

	echo Seeing how big the resulting installed kernel is
	ls -lh $work_dir/image-mnt/boot/kernel/kernel
fi


# DISTRIBUTION

echo Installing distribution to $dest_dir - \
	logging to $log_dir/distribution.log
\time -h make -C $src_dir distribution SRCCONF=$work_dir/src.conf \
	DESTDIR=$dest_dir \
	> $log_dir/distribution.log 2>&1

# CONFIGURATION

if [ ! "$target" = "jail" ] ; then
	echo
	echo Copying boot directory from mounted device to root kernel device
	cp -rp $dest_dir/boot/defaults $work_dir/kernel/boot/
	cp -rp $dest_dir/boot/lua $work_dir/kernel/boot/
	cp -rp $dest_dir/boot/device.hints $work_dir/kernel/boot/
	cp -rp $dest_dir/boot/zfs* $work_dir/kernel/boot/
fi

# DEBUG Determine if this is needed - obviously not needed for jail
#echo Installing distribution to $work_dir/kernel - \
#	$log_dir/kernel-distribution.log
#\time -h make -C $src_dir distribution SRCCONF=$work_dir/src.conf \
#	DESTDIR=$work_dir/kernel \
#		> $log_dir/kernel-distribution.log 2>&1


[ "$quiet" = "0" ] && { echo ; echo Press ANY key to continue ; read anykey ; }

if [ "$target" = "jail" ] ; then

	# sendmail ss flags etc?
	echo ; echo Generating jail rc.conf and fstab
	echo
tee -a $work_dir/jail-mnt/etc/rc.conf <<EOF
hostname="occambsd-jail"
ifconfig_DEFAULT="DHCP inet6 accept_rtadv"
growfs_enable="YES"
EOF

	touch $dest_dir/etc/fstab
else
	echo ; echo Generating image rc.conf

	echo
tee -a $work_dir/image-mnt/etc/rc.conf <<EOF
hostname="occambsd"
ifconfig_DEFAULT="DHCP inet6 accept_rtadv"
growfs_enable="YES"
EOF

	if [ "$zfsroot" = 1 ] ; then
		echo Adding rc.conf ZFS entry
		echo "zfs_enable=\"YES\"" >> $work_dir/image-mnt/etc/rc.conf
		echo "zfs_enable=\"YES\"" >> $work_dir/kernel/etc/rc.conf
	fi

	echo ; echo Generating fstab

	if [ "$target" = "bhyve" ] ; then
		root_dev="vtbd"
	else
		root_dev="ada"
	fi
	
	if [ "$zfsroot" = 0 ] ; then
echo "/dev/${root_dev}0p3	/	ufs	rw,noatime	1	1" \
	> "$dest_dir/etc/fstab"
	fi

	echo "/dev/${root_dev}0p2	none	swap	sw	1	1" \
		>> "$dest_dir/etc/fstab"
	cat "$dest_dir/etc/fstab" || \
		{ echo $dest_dir/etc/fstab generation failed ; exit 1 ; }
fi

echo ; echo Touching firstboot files

touch "$dest_dir/firstboot"
touch "$work_dir/kernel/firstboot"


# VM loader.conf acrobatics
if [ ! "$target" = "jail" ] ; then
	echo ; echo Generating genernic VM image loader.conf

	echo
	tee -a $work_dir/image-mnt/boot/loader.conf <<EOF
#kern.geom.label.disk_ident.enable="0"
#kern.geom.label.gptid.enable="0"
autoboot_delay="3"
boot_verbose="1"
EOF

	echo ; echo Generating generic kernel loader.conf

	echo
	tee -a $work_dir/kernel/boot/loader.conf <<EOF
kern.geom.label.disk_ident.enable="0"
kern.geom.label.gptid.enable="0"
autoboot_delay="3"
boot_verbose="1"
EOF

	if [ "$zfsroot" = "1" ] ; then
		echo ; echo Adding ZFS loader entries
		echo "cryptodev_load=\"YES\"" >> \
			$work_dir/image-mnt/boot/loader.conf
		echo "zfs_load=\"YES\"" >> \
			$work_dir/image-mnt/boot/loader.conf

		# Could copy it over...
		echo "cryptodev_load=\"YES\"" >> \
			$work_dir/kernel/boot/loader.conf
		echo "zfs_load=\"YES\"" >> \
			$work_dir/kernel/boot/loader.conf
		echo "vfs.root.mountfrom=\"zfs:occambsd/ROOT/default\"" >> \
			$work_dir/kernel/boot/loader.conf
#	else
#		echo "vfs.root.mountfrom=\"ufs:/dev/ada0p3\"" >> \
#			$work_dir/kernel/boot/loader.conf
	fi

	if [ "$target" = "xen" ] ; then
		echo ; echo Adding Xen loader.conf entries

		echo "boot_serial=\"YES\"" >> \
			$work_dir/image-mnt/boot/loader.conf
		echo "comconsole_speed=\"115200\"" >> \
			$work_dir/image-mnt/boot/loader.conf
		echo "console=\"comconsole\"" >> \
			$work_dir/image-mnt/boot/loader.conf
	
		echo "boot_serial=\"YES\"" >> \
			$work_dir/kernel/boot/loader.conf
		echo "comconsole_speed=\"115200\"" >> \
			$work_dir/kernel/boot/loader.conf
		echo "console=\"comconsole\"" >> \
			$work_dir/kernel/boot/loader.conf

		echo ; echo Configuring the Xen VM image serial console
		printf "%s" "-h -S115200" >> $work_dir/image-mnt/boot.config

		echo ; echo Configuring the Xen kernel serial console
		printf "%s" "-h -S115200" >> $work_dir/kernel/boot.config

# Needed for PVH but not HVM?
echo 'xc0	"/usr/libexec/getty Pc"	xterm	onifconsole	secure' \
		>> $work_dir/image-mnt/etc/ttys

	echo $work_dir/image-mnt/boot/loader.conf reads:
	cat $work_dir/image-mnt/boot/loader.conf || \
		{ echo image-mnt loader.conf generation failed ; exit 1 ; }

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

if [ "$target" = "xen" ] ; then
	# Naturally this may be an issue if the host differs from the sources
	echo ; echo Installing xen-guest-tools to Xen image
	pkg -r $work_dir/image-mnt install -y xen-guest-tools

	echo ; echo Running pkg -r $work_dir/image-mnt info
	pkg -r $work_dir/image-mnt info || \
		{ echo Package installation failed ; exit 1 ; }
fi

echo ; echo Running df -h | grep $md_id
df -h | grep $md_id

echo ; echo Finding all files over 1M in size
find $work_dir/image-mnt -size +1M -exec ls -lh {} +

if [ "$target" = "jail" ] ; then
	echo ; echo Generating jail.conf

cat << HERE > $work_dir/jail.conf
exec.start = "/bin/sh /etc/rc";
exec.stop = "/bin/sh /etc/rc.shutdown";
exec.clean;
mount.devfs;
occambsd {
	path = "$work_dir/jail-mnt";
	host.hostname = "occambsd";
#	ip4.addr = 10.0.0.99;
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

echo ; echo Note these setup and tear-down scripts:

if [ "$target" = "bhyve" ] ; then
	echo ; echo "kldload vmm" > $work_dir/load-bhyve-vmm-module.sh
	echo $work_dir/load-bhyve-vmm-module.sh
	echo "bhyveload -h $work_dir/kernel/ -m 1024 occambsd" \
		> $work_dir/load-bhyve-directory.sh
	echo $work_dir/load-bhyve-directory.sh
	echo "bhyveload -d $work_dir/occambsd.raw -m 1024 occambsd" \
		> $work_dir/load-bhyve-disk-image.sh
	echo $work_dir/load-bhyve-disk-image.sh
	echo "bhyve -m 1024 -H -A -s 0,hostbridge -s 2,virtio-blk,$work_dir/occambsd.raw -s 31,lpc -l com1,stdio occambsd" \
		> $work_dir/boot-bhyve-disk-image.sh
	echo $work_dir/boot-bhyve-disk-image.sh
	echo "bhyvectl --destroy --vm=occambsd" \
		> $work_dir/destroy-bhyve.sh
	echo $work_dir/destroy-bhyve.sh
elif [ "$target" = "xen" ] ; then
	echo ; echo "xl create -c $work_dir/xen-kernel.cfg" \
		> $work_dir/boot-xen-directory.sh
	echo $work_dir/boot-xen-directory.sh
	echo "xl create -c $work_dir/xen.cfg" \
		> $work_dir/boot-xen-disk-image.sh
	echo $work_dir/boot-xen-disk-image.sh
	echo "xl shutdown OccamBSD ; xl destroy OccamBSD ; xl list" > $work_dir/destroy-xen.sh
	echo $work_dir/destroy-xen.sh

	# Notes while debugging
	#xl console -t pv OccamBSD
	#xl console -t serial OccamBSD
else
	echo ; echo "jail -c -f $work_dir/jail.conf" \
		> $work_dir/boot-jail.sh
	echo $work_dir/boot-jail.sh
fi

if [ ! "$target" = "jail" ] ; then
	echo ; echo The VM disk image is still mounted and you could
	echo exit and rebuild the kernel with:
	echo ; echo make -C $src_dir -j$buildjobs buildkernel KERNCONFDIR=$work_dir KERNCONF=OCCAMBSD
	echo make installkernel KERNCONFDIR=$work_dir DESTDIR=$work_dir/\< jail mnt or root \>

	echo ; echo Press ANY key to unmount the VM disk image ; read anykey

	if [ "$zfsroot" = "1" ] ; then
		echo Exporting occambsd zpool
		zpool export -f occambsd
	else
		echo ; echo Unmounting $dest_dir
		umount $dest_dir
	fi

	echo ; echo Destroying $md_id
	mdconfig -du $md_id
	mdconfig -lv
fi

if [ "$release" = "1" ] ; then

	echo ; echo Building release - logging to $log_dir/release.log
	cd $src_dir/release || { echo cd release failed ; exit 1 ; }

	\time -h make -C $src_dir/release SRCCONF=$work_dir/src.conf \
		KERNCONFDIR=$work_dir KERNCONF=OCCAMBSD release \
		> $log_dir/release.log 2>&1 \
			|| { echo release failed ; exit 1 ; }

	echo ; echo Generating bhyve boot scripts for disc1.iso and memstick.img

	echo "bhyveload -d /usr/obj/$src_dir/amd64.amd64/release/disc1.iso -m 1024 occambsd" \
		> $work_dir/load-bhyve-disc1.iso.sh

	echo "bhyve -m 1024 -H -A -s 0,hostbridge -s 2,virtio-blk,/usr/obj/$src_dir/amd64.amd64/release/disc1.iso -s 31,lpc -l com1,stdio occambsd" \
		> $work_dir/boot-bhyve-disc1.iso.sh

	echo "bhyveload -d /usr/obj/$src_dir/amd64.amd64/release/memstick.img -m 1024 occambsd" \
		> $work_dir/load-bhyve-memstick.img.sh

	echo "bhyve -m 1024 -H -A -s 0,hostbridge -s 2,virtio-blk,/usr/obj/$src_dir/amd64.amd64/release/memstick.img -s 31,lpc -l com1,stdio occambsd" \
		> $work_dir/boot-bhyve-memstick.img.sh

	echo ; echo Release contents are in /usr/obj
else
	echo ; echo Unmounting /usr/obj
	umount /usr/obj
fi

echo ; echo Running df -h \| grep tmpfs to see how big the results are
df -h | grep tmpfs

exit 0
