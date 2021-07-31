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

# Version 13.0-RELEASE

# occambsd: An application of Occam's razor to FreeBSD
# a.k.a. "super svelte stripped down FreeBSD"

# This will create a kernel directories and disk images for bhyve and xen,
# a jail(8) root directory, and related load, boot, and cleanup scripts.

# The separate kernel directory is very useful for testing kernel changes
# while waiting for institutionalized VirtFS support.

# Variables

src_dir="/usr/src"
workdir="/tmp/occambsd"			# This will be mounted tmpfs
imagesize="4G"				# More than enough room
bhyve_md_id="md42"			# Ask Douglas Adams for an explanation
xen_md_id="md43"
buildjobs="$(sysctl -n hw.ncpu)"

[ -f $src_dir/sys/amd64/conf/GENERIC ] || \
	{ echo Sources do not appear to be installed ; exit 1 ; }

# Cleanup - tmpfs mounts are not always dected by mount | grep tmpfs ...
#	They may also be mounted multiple times atop one another and
#	md devices may be attached multiple times. Proper cleanup would be nice

umount -f "$workdir/bhyve-mnt" > /dev/null 2>&1
umount -f "$workdir/xen-mnt" > /dev/null 2>&1
umount -f "$workdir/jail/dev" > /dev/null 2>&1
umount -f "$workdir" > /dev/null 2>&1
umount -f "$workdir" > /dev/null 2>&1
umount -f "/usr/obj" > /dev/null 2>&1
umount -f "/usr/obj" > /dev/null 2>&1
mdconfig -du "$bhyve_md_id" > /dev/null 2>&1
mdconfig -du "$bhyve_md_id" > /dev/null 2>&1
mdconfig -du "$xen_md_id" > /dev/null 2>&1
mdconfig -du "$xen_md_id" > /dev/null 2>&1

echo
echo Do any memory devices or tmpfs mounts need to be cleaned up? Listing...
echo Press the elusive ANY key if you do not see any to continue
echo

mdconfig -lv
mount | grep "$workdir"
mount | grep "/usr/obj"
read clean

[ -d $workdir ] || mkdir -p "$workdir"

echo Mounting $workdir tmpfs
mount -t tmpfs tmpfs "$workdir" || {
	echo tmpfs mount failed
	exit 1
}

echo Making directories in $workdir
mkdir -p "$workdir/bhyve-kernel/boot"
mkdir -p "$workdir/bhyve-kernel/etc"
mkdir -p "$workdir/bhyve-mnt"
mkdir -p "$workdir/xen-kernel/boot/kernel"
mkdir -p "$workdir/xen-mnt"
mkdir -p "$workdir/jail"

echo Mounting a tmpfs to /usr/obj/
mount -t tmpfs tmpfs /usr/obj/

mount | grep tmpfs

cd $src_dir
echo Generating $workdir/all_options.txt
make showconfig __MAKE_CONF=/dev/null SRCCONF=/dev/null |
	sort |
	sed '
		s/^MK_//
		s/=//
	' | awk '
	$2 == "yes"     { printf "WITHOUT_%s=YES\n", $1 }
	' > $workdir/all_options.txt

echo All available src.conf options on this OS release are:
echo
cat $workdir/all_options.txt
echo

echo Generating $workdir/src.conf
	cat $workdir/all_options.txt | \
	grep -v WITHOUT_AUTO_OBJ | \
	grep -v WITHOUT_UNIFIED_OBJDIR | \
	grep -v WITHOUT_INSTALLLIB | \
	grep -v WITHOUT_BOOT | \
	grep -v WITHOUT_LOADER_LUA | \
	grep -v WITHOUT_LOCALES | \
	grep -v WITHOUT_ZONEINFO | \
	grep -v WITHOUT_EFI | \
	grep -v WITHOUT_VI \
	> $workdir/src.conf

# WITHOUT_AUTO_OBJ and WITHOUT_UNIFIED_OBJDIR warn that they go in src-env.conf
# <broken build options>
# WITHOUT_LOADER_LUA is required for the lua boot code
# WITHOUT_BOOT is needed to install the LUA loader
# WITHOUT_LOCALES is necessary for a console
# WITHOUT_ZONEINFO is necessary for tzsetup on VM image with a userland
# WITHOUT_EFI to support make release, specifically for loader.efi
# WITHOUT_VI could come in handy

[ -f $workdir/src.conf ] || { echo $workdir/src.conf did not generate ; exit 1 ; }

cat $workdir/src.conf

echo
echo Press the elusive ANY key to continue
read anykey

#echo Removing OCCAMBSD KERNCONF if present
#[ -f $src_dir/sys/amd64/conf/OCCAMBSD ] && rm $src_dir/sys/amd64/conf/OCCAMBSD

echo Creating new OCCAMBSD KERNCONF
#cat << HERE > $src_dir/sys/amd64/conf/OCCAMBSD
cat << HERE > $workdir/OCCAMBSD

cpu		HAMMER
ident		OCCAMBSD

# Sync with the devices below? Have not needed virtio_blk etc.
makeoptions	MODULES_OVERRIDE="virtio"

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
device		atpic		 # 8259A compatability

# To get past mountroot
device		ahci			# AHCI-compatible SATA controllers
device		scbus			# SCSI bus (required for ATA/SCSI)

# Throws an error but works - Investigate
options		 GEOM_PART_GPT		# GUID Partition Tables.

# Mounting from ufs:/dev/vtbd0p3 failed with error 2: unknown file system.
options 	FFS			# Berkeley Fast Filesystem

# Add labling handling to support booting from disc1.iso and memstick.img
options         GEOM_LABEL              # Provides labelization

# Add CD-ROM file system support for booting from disc1.iso
device          cd                      # CD
options         CD9660                  # ISO 9660 Filesystem

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
HERE

echo The resulting OCCAMBSD KERNCONF is
cat $workdir/OCCAMBSD

echo
echo Press the elusive ANY key to continue to buildworld
read anykey

echo Building world - logging to $workdir/buildworld.log
\time -h make -C $src_dir -j$buildjobs SRCCONF=$workdir/src.conf buildworld \
	> $workdir/buildworld.log || {
	echo buildworld failed
	exit 1
	}

echo
echo Press the elusive ANY key to continue to buildkernel
read anykey

echo Building kernel - logging to $workdir/buildkernel.log
\time -h make -C $src_dir -j$buildjobs buildkernel KERNCONFDIR=$workdir KERNCONF=OCCAMBSD \
	> $workdir/buildkernel.log || {
	echo buildkernel failed
	exit 1
	}

echo
echo Press the elusive ANY key to continue to VM image creation
read anykey

echo Seeing how big the resulting kernel is
ls -lh /usr/obj/usr/src/amd64.amd64/sys/OCCAMBSD/kernel

echo
echo Truncating bhyve VM image - consider -t malloc and tmpfs
truncate -s "$imagesize" "$workdir/bhyve.raw" || {
	echo image truncation failed
	exit 1
}

[ -f $workdir/bhyve.raw ] || \
	{ echo $workdir/bhyve.raw did not create ; exit 1 ; }


echo
echo Truncating xen VM image - consider -t malloc and tmpfs
truncate -s "$imagesize" "$workdir/xen.raw" || {
		echo image truncation failed
		exit 1
}

[ -f $workdir/xen.raw ] || \
	{ echo $workdir/xen.raw did not create ; exit 1 ; }

echo Attaching bhyve VM image
mdconfig -a -u "$bhyve_md_id" -f "$workdir/bhyve.raw"

[ -e /dev/$bhyve_md_id ] || { echo $bhyve_md_id did not attach ; exit 1 ; }

echo Attaching Xen VM image
mdconfig -a -u "$xen_md_id" -f "$workdir/xen.raw"

[ -e /dev/$xen_md_id ] || { echo $xen_md_id did not attach ; exit 1 ; }

echo
echo Partitioning and formating $bhyve_md_id
gpart create -s gpt "$bhyve_md_id"
gpart add -t freebsd-boot -l bootfs -b 128 -s 128K "$bhyve_md_id"
gpart bootcode -b /boot/pmbr -p /boot/gptboot -i 1 "$bhyve_md_id"
gpart add -t freebsd-swap -s 1G "$bhyve_md_id"
gpart add -t freebsd-ufs "$bhyve_md_id"

echo The bhyve.raw partitioning is:
gpart show "$bhyve_md_id"
newfs -U /dev/${bhyve_md_id}p3 || {
	echo bhyve VM image newfs failed
	exit 1
}

echo
echo Partitioning and formating $xen_md_id
gpart create -s gpt "$xen_md_id"
gpart add -t freebsd-boot -l bootfs -b 128 -s 128K "$xen_md_id"
gpart bootcode -b /boot/pmbr -p /boot/gptboot -i 1 "$xen_md_id"
gpart add -t freebsd-swap -s 1G "$xen_md_id"
gpart add -t freebsd-ufs "$xen_md_id"

echo The xen.raw partitioning is:
gpart show "$xen_md_id"
newfs -U /dev/${xen_md_id}p3 || {
	echo Xen VM image newfs failed
	exit 1
}

echo
echo Mounting ${bhyve_md_id}p3 with mount /dev/${bhyve_md_id}p3 $workdir/bhyve-mnt
mount /dev/${bhyve_md_id}p3 $workdir/bhyve-mnt || {
	echo bhyve image mount failed
	exit 1
}

echo Mounting ${xen_md_id}p3 with mount /dev/${xen_md_id}p3 $workdir/xen-mnt
mount /dev/${xen_md_id}p3 $workdir/xen-mnt || {
	echo Xen image mount failed
	exit 1
}

# WORLD

echo Installing world to $workdir/bhyve-mnt - logging to $workdir/bhyve-installworld.log
\time -h make -C $src_dir installworld SRCCONF=$workdir/src.conf DESTDIR=$workdir/bhyve-mnt \
	> $workdir/bhyve-installworld.log 2>&1

echo Installing world to $workdir/xen-mnt - logging to $workdir/bhyve-installworld.log
\time -h make -C $src_dir installworld SRCCONF=$workdir/src.conf DESTDIR=$workdir/xen-mnt \
	> $workdir/xen-installworld.log 2>&1

# Alternative: use a known-good full userland
#cat /usr/freebsd-dist/base.txz | tar -xf - -C $workdir/xen-mnt

echo Installing world to $workdir/jail - logging to $workdir/jail-installworld.log
\time -h make -C $src_dir installworld SRCCONF=$workdir/src.conf DESTDIR=$workdir/jail \
	> $workdir/jail-installworld.log 2>&1

# KERNEL

echo Installing the kernel to $workdir/bhyve-mnt - logging to $workdir/bhyve-disk-image-installkernel.log
\time -h make -C $src_dir installkernel KERNCONFDIR=$workdir KERNCONF=OCCAMBSD DESTDIR=$workdir/bhyve-mnt/ \
	> $workdir/bhyve-disk-image-installkernel.log 2>&1
[ -f $workdir/bhyve-mnt/boot/kernel/kernel ] || \
	{ echo bhyve-mnt kernel failed to install ; exit 1 ; }

echo Installing the kernel to $workdir/bhyve-kernel/ - logging to $workdir/bhyve-directory-installkernel.log
\time -h make -C $src_dir installkernel KERNCONFDIR=$workdir KERNCONF=OCCAMBSD DESTDIR=$workdir/bhyve-kernel/ \
	> $workdir/bhyve-directory-installkernel.log 2>&1
[ -f $workdir/bhyve-kernel/boot/kernel/kernel ] || \
	{ echo bhyve-kernel kernel failed to install ; exit 1 ; }

echo Installing the kernel to $workdir/xen-mnt - logging to $workdir/xen-disk-image-installkernel.log
\time -h make -C $src_dir installkernel KERNCONFDIR=$workdir KERNCONF=OCCAMBSD DESTDIR=$workdir/xen-mnt/ \
	> $workdir/xen-disk-image-installkernel.log 2>&1
[ -f $workdir/xen-mnt/boot/kernel/kernel ] || \
	{ echo xen-mnt kernel failed to install ; exit 1 ; }

# Need not be nested but the familiar location is... familiar.
echo Installing the kernel to $workdir/xen-kernel/
cp -p $workdir/xen-mnt/boot/kernel/kernel $workdir/xen-kernel/boot/kernel/
[ -f $workdir/xen-kernel/boot/kernel/kernel ] || \
	{ echo xen-kernel kernel failed to install ; exit 1 ; }

echo Seeing how big the resulting installed kernel is
ls -lh $workdir/bhyve-mnt/boot/kernel/kernel

# DISTRIBUTION

echo Installing distribution to $workdir/bhyve-mnt - logging to $workdir/bhyve-distribution.log
\time -h make -C $src_dir distribution SRCCONF=$workdir/src.conf DESTDIR=$workdir/bhyve-mnt \
	> $workdir/bhyve-disk-image-distribution.log 2>&1

echo Press y to prune locales and timezones saving 28M?
read response

if [ "$response" = "y" ]; then
	echo Deleting unused locales
	cd $workdir/bhyve-mnt/usr/share/locale/
	rm -rf a* b* c* d* e* f* g* h* i* j* k* l* m* n* p* r* s* t* u* z*
	echo Deleting unused timezone data
	cd $workdir/bhyve-mnt/usr/share/zoneinfo
	rm -rf A* B* C* E* F* G* H* I* J* K* L* M* N* P* R* S* T* UCT US W* Z*
fi

# DEBUG Probably far more than needed
echo Installing distribution to $workdir/bhyve-kernel - $workdir/bhyve-distribution.log
\time -h make -C $src_dir distribution SRCCONF=$workdir/src.conf DESTDIR=$workdir/bhyve-kernel \
	> $workdir/bhyve-directory-distribution.log 2>&1

echo Installing distribution to $workdir/xen-mnt - logging to $workdir/xen-disk-image-distribution.log
\time -h make -C $src_dir distribution SRCCONF=$workdir/src.conf DESTDIR=$workdir/xen-mnt \
	> $workdir/xen-disk-image-distribution.log 2>&1

if [ "$response" = "y" ]; then
	echo Deleting unused locales
	cd $workdir/xen-mnt/usr/share/locale/
	rm -rf a* b* c* d* e* f* g* h* i* j* k* l* m* n* p* r* s* t* u* z*
	echo Deleting unused timezone data
	cd $workdir/xen-mnt/usr/share/zoneinfo
	rm -rf A* B* C* E* F* G* H* I* J* K* L* M* N* P* R* S* T* UCT US W* Z*
fi

echo Installing distribution to $workdir/jail - logging to $workdir/jail-distribution.log
\time -h make -C $src_dir distribution SRCCONF=$workdir/src.conf DESTDIR=$workdir/jail \
	> $workdir/jail-distribution.log 2>&1

if [ "$response" = "y" ]; then
	echo Deleting unused locales
	cd $workdir/jail/usr/share/locale/
	rm -rf a* b* c* d* e* f* g* h* i* j* k* l* m* n* p* r* s* t* u* z*
	echo Deleting unused timezone data
	cd $workdir/jail/usr/share/zoneinfo
	rm -rf A* B* C* E* F* G* H* I* J* K* L* M* N* P* R* S* T* UCT US W* Z*
fi

echo Copying boot components from the mounted device to the root kernel device
cp -rp $workdir/bhyve-mnt/boot/defaults $workdir/bhyve-kernel/boot/
cp -rp $workdir/bhyve-mnt/boot/lua $workdir/bhyve-kernel/boot/
cp -p $workdir/bhyve-mnt/boot/device.hints $workdir/bhyve-kernel/boot/

echo
echo Press the elusive ANY key to continue to configuration
read anykey

echo
echo Generating bhyve rc.conf

echo
tee -a $workdir/bhyve-mnt/etc/rc.conf <<EOF
hostname="occambsd"
ifconfig_DEFAULT="DHCP inet6 accept_rtadv"
growfs_enable=YES
EOF

echo
echo Generating Xen rc.conf

echo
tee -a $workdir/xen-mnt/etc/rc.conf <<EOF
hostname="occambsd-xen"
ifconfig_DEFAULT="DHCP inet6 accept_rtadv"
growfs_enable=YES
EOF

echo
echo Generating jail rc.conf
echo
tee -a $workdir/jail/etc/rc.conf <<EOF
hostname="occambsd-jail"
ifconfig_DEFAULT="DHCP inet6 accept_rtadv"
growfs_enable=YES
EOF

echo
echo Generating bhyve fstab

echo
echo "/dev/vtbd0p3	/	ufs	rw,noatime	1	1" \
	> "$workdir/bhyve-mnt/etc/fstab"
echo "/dev/vtbd0p2	none	swap	sw	1	1" \
	>> "$workdir/bhyve-mnt/etc/fstab"
cat "$workdir/bhyve-mnt/etc/fstab" || \
	{ echo bhyve-mnt fstab generation failed ; exit 1 ; }

echo
echo "/dev/vtbd0p3	/	ufs	rw,noatime	1	1" \
	> "$workdir/bhyve-kernel/etc/fstab"
echo "/dev/vtbd0p2	none	swap	sw	1	1" \
	>> "$workdir/bhyve-kernel/etc/fstab"
cat "$workdir/bhyve-kernel/etc/fstab" || \
	{ echo bhyve-kernel fstab generation failed ; exit 1 ; }

echo
echo Generating Xen fstab

echo
echo "/dev/ada0p3	/	ufs	rw,noatime	1	1" \
	> "$workdir/xen-mnt/etc/fstab"
echo "/dev/ada0p2	none	swap	sw	1	1" \
	>> "$workdir/xen-mnt/etc/fstab"
cat "$workdir/xen-mnt/etc/fstab" || \
	{ echo xen-mnt fstab generation failed ; exit 1 ; }

echo
echo Touching firstboot files

echo
touch "$workdir/bhyve-mnt/firstboot"
touch "$workdir/bhyve-kernel/firstboot"

echo
echo Generating bhyve VM image loader.conf

echo
tee -a $workdir/bhyve-mnt/boot/loader.conf <<EOF
kern.geom.label.disk_ident.enable="0"
kern.geom.label.gptid.enable="0"
autoboot_delay="3"
bootverbose="1"
EOF

cat $workdir/bhyve-mnt/boot/loader.conf || \
	{ echo bhyve-mnt loader.conf generation failed ; exit 1 ; }

echo
echo Generating bhyve kernel loader.conf

echo
tee -a $workdir/bhyve-kernel/boot/loader.conf <<EOF
kern.geom.label.disk_ident.enable="0"
kern.geom.label.gptid.enable="0"
autoboot_delay="3"
bootverbose="1"
EOF

cat $workdir/bhyve-kernel/boot/loader.conf || \
	{ echo bhyve-kernel loader.conf generation failed ; exit 1 ; }

echo
echo Generating Xen VM image loader.conf

echo
tee -a $workdir/xen-mnt/boot/loader.conf <<EOF
kern.geom.label.disk_ident.enable="0"
kern.geom.label.gptid.enable="0"
autoboot_delay="3"
bootverbose="1"
boot_serial="YES"
comconsole_speed="115200"
console="comconsole"
EOF

cat $workdir/xen-mnt/boot/loader.conf || \
	{ echo xen-mnt loader.conf generation failed ; exit 1 ; }

echo
echo Configuring the Xen serial console
printf "%s" "-h -S115200" >> $workdir/xen-mnt/boot.config
# Needed for PVH but not HVM?
echo 'xc0     "/usr/libexec/getty Pc"         xterm   onifconsole  secure' \
	>> $workdir/xen-mnt/etc/ttys

# DEBUG Is it needed there?
# tzsetup will fail on separated kernel/userland - point at userland somehow
# Could not open /mnt/usr/share/zoneinfo/UTC: No such file or directory

echo
echo Setting the timezone three times - Press ENTER 3X
sleep 2
# DEBUG Need to set on in the kernel directories?
tzsetup -s -C $workdir/bhyve-mnt UTC
tzsetup -s -C $workdir/xen-mnt UTC
tzsetup -s -C $workdir/jail UTC

echo
echo Installing xen-guest-tools to Xen image
pkg -r $workdir/xen-mnt install -y xen-guest-tools
echo Running pkg -r $workdir/xen-mnt info
pkg -r $workdir/xen-mnt info || \
	{ echo Package installation failed ; exit 1 ; }

echo
echo Running df -h | grep $bhyve_md_id
df -h | grep $bhyve_md_id

echo
echo Finding all files over 1M in size
find $workdir/bhyve-mnt -size +1M -exec ls -lh {} +

echo
echo Generating jail.conf

cat << HERE > $workdir/jail.conf
exec.start = "/bin/sh /etc/rc";
exec.stop = "/bin/sh /etc/rc.shutdown";
exec.clean;
mount.devfs;
occam {
	path = "$workdir/jail";
	host.hostname = "occambsd";
#	ip4.addr = 10.0.0.99;
	exec.start = "/bin/sh /etc/rc";
	exec.stop = "/bin/sh /etc/rc.shutdown jail";
	}
HERE

echo Generating xen.cfg
cat << HERE > $workdir/xen.cfg
type = "hvm"
memory = 2048
vcpus = 2
name = "OccamBSD"
disk = [ '/tmp/occambsd/xen.raw,raw,hda,w' ]
boot = "c"
serial = 'pty'
on_poweroff = 'destroy'
on_reboot = 'restart'
on_crash = 'restart'
#vif = [ 'bridge=bridge0' ]
HERE

echo Generating xen-kernel.cfg
cat << HERE > $workdir/xen-kernel.cfg
type = "pvh"
memory = 2048
vcpus = 2
name = "OccamBSD"
kernel = "$workdir/xen-kernel/boot/kernel/kernel"
cmdline = "vfs.root.mountfrom=ufs:/dev/ada0p3"
disk = [ '/tmp/occambsd/xen.raw,raw,hda,w' ]
boot = "c"
serial = 'pty'
on_poweroff = 'destroy'
on_reboot = 'restart'
on_crash = 'restart'
#vif = [ 'bridge=bridge0' ]
HERE

echo
echo The resulting disk images are
echo $workdir/bhyve.raw
echo $workdir/xen.raw
echo
echo Note these setup and tear-down scripts:

echo
echo "kldload vmm" > $workdir/load-bhyve-vmm-module.sh
echo $workdir/load-bhyve-vmm-module.sh
echo "bhyveload -h $workdir/bhyve-kernel/ -m 1024 occambsd" \
	> $workdir/load-bhyve-directory.sh
echo $workdir/load-bhyve-directory.sh
echo "bhyveload -d $workdir/bhyve.raw -m 1024 occambsd" \
	> $workdir/load-bhyve-disk-image.sh
echo $workdir/load-bhyve-disk-image.sh
echo "bhyve -m 1024 -H -A -s 0,hostbridge -s 2,virtio-blk,$workdir/bhyve.raw -s 31,lpc -l com1,stdio occambsd" \
	> $workdir/boot-bhyve-disk-image.sh
echo $workdir/boot-bhyve-disk-image.sh
echo "bhyvectl --destroy --vm=occambsd" \
	> $workdir/destroy-bhyve.sh
echo $workdir/destroy-bhyve.sh

echo
echo "xl create -c $workdir/xen-kernel.cfg" \
	> $workdir/boot-xen-directory.sh
echo $workdir/boot-xen-directory.sh
echo "xl create -c $workdir/xen.cfg" \
	> $workdir/boot-xen-disk-image.sh
echo $workdir/boot-xen-disk-image.sh
echo "xl shutdown OccamBSD ; xl destroy OccamBSD ; xl list" > $workdir/destroy-xen.sh
echo $workdir/destroy-xen.sh

# Notes while debugging
#xl console -t pv OccamBSD
#xl console -t serial OccamBSD

echo
echo "jail -c -f $workdir/jail.conf command=/bin/sh" \
	> $workdir/boot-jail.sh
echo $workdir/boot-jail.sh

echo
echo The VM disk image is still mounted and you could
echo exit and rebuild the kernel with:
echo cd $src_dir
echo make -C $src_dir -j$buildjobs buildkernel KERNCONFDIR=$workdir KERNCONF=OCCAMBSD
echo make installkernel KERNCONFDIR=$workdir DESTDIR=$workdir/\< jail mnt or root \>

echo
echo Press the elusive ANY key to unmount the VM disk image for use
read anykey

echo Unmounting $workdir/bhyve-mnt
umount $workdir/bhyve-mnt

echo
echo Unmounting $workdir/xen-mnt
umount $workdir/xen-mnt

echo
echo Destroying $bhyve_md_id and $xen_md_id
mdconfig -du $bhyve_md_id
mdconfig -du $xen_md_id
mdconfig -lv

echo
echo Press y to make release
read response

if [ "$response" = "y" ]; then

	echo Building release - logging to $workdir/release.log
	cd $src_dir/release || { echo cd release failed ; exit 1 ; }
	\time -h make -C $src_dir/release SRCCONF=$workdir/src.conf \
		KERNCONFDIR=$workdir KERNCONF=OCCAMBSD release \
		> $workdir/release.log 2>&1 \
		|| {
			echo release failed
			exit 1
		}
	echo
	echo /usr/obj is mounted for release contents

echo Generating bhyve boot scripts for disc1.iso and memstick.img

echo "bhyveload -d /usr/obj/usr/src/amd64.amd64/release/disc1.iso -m 1024 occambsd" \
	> $workdir/load-bhyve-disc1.iso.sh

echo "bhyve -m 1024 -H -A -s 0,hostbridge -s 2,virtio-blk,/usr/obj/usr/src/amd64.amd64/release/disc1.iso -s 31,lpc -l com1,stdio occambsd" \
	> $workdir/boot-bhyve-disc1.iso.sh

echo "bhyveload -d /usr/obj/usr/src/amd64.amd64/release/memstick.img -m 1024 occambsd" \
	> $workdir/load-bhyve-memstick.img.sh

echo "bhyve -m 1024 -H -A -s 0,hostbridge -s 2,virtio-blk,/usr/obj/usr/src/amd64.amd64/release/memstick.img -s 31,lpc -l com1,stdio occambsd" \
	> $workdir/boot-bhyve-memstick.img.sh

else
	echo
	echo Unmounting /usr/obj
	umount /usr/obj
fi

echo Running df -h \| grep tmpfs to see how big the results are
df -h | grep tmpfs

exit 0
