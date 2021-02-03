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

# Version 13.0-ALPHA3

# occambsd: An application of Occam's razor to FreeBSD
# a.k.a. "super svelte stripped down FreeBSD"

# This will create a kernel directories and disk images for bhyve and xen,
# a jail(8) root directory, and related load, boot, and cleanup scripts.

# The separate kernel directory is very useful for testing kernel changes
# while waiting for institutionalized VirtFS support.

# Variables

src_dir="/usr/src"
playground="/tmp/occambsd"		# This will be mounted tmpfs
imagesize="4G"				# More than enough room
bhyve_md_id="md42"			# Ask Douglas Adams for an explanation
xen_md_id="md43"
buildjobs="$(sysctl -n hw.ncpu)"

[ -f /usr/src/sys/amd64/conf/GENERIC ] || \
	{ echo Sources do not appear to be installed ; exit 1 ; }

# Cleanup - tmpfs mounts are not always dected by mount | grep tmpfs ...
#	They may also be mounted multiple times atop one another and
#	md devices may be attached multiple times. Proper cleanup would be nice

umount -f "$playground/bhyve-mnt" > /dev/null 2>&1
umount -f "$playground/xen-mnt" > /dev/null 2>&1
umount -f "$playground/jail/dev" > /dev/null 2>&1
umount -f "$playground" > /dev/null 2>&1
umount -f "$playground" > /dev/null 2>&1
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
mount | grep "$playground"
mount | grep "/usr/obj"
read clean

[ -d $playground ] || mkdir -p "$playground"

echo Mounting $playground tmpfs
mount -t tmpfs tmpfs "$playground" || {
	echo tmpfs mount failed
	exit 1
}

echo Making directories in $playground
mkdir -p "$playground/bhyve-kernel/boot"
mkdir -p "$playground/bhyve-kernel/etc"
mkdir -p "$playground/bhyve-mnt"
mkdir -p "$playground/xen-kernel/boot"
mkdir -p "$playground/xen-kernel/etc"
mkdir -p "$playground/xen-mnt"
mkdir -p "$playground/jail"

echo Mounting a tmpfs to /usr/obj/
mount -t tmpfs tmpfs /usr/obj/

mount | grep tmpfs

echo Generating /etc/src.conf
sh /usr/src/tools/tools/build_option_survey/listallopts.sh | grep -v WITH_ | sed 's/$/=YES/' | \
	grep -v WITHOUT_AUTO_OBJ | \
	grep -v WITHOUT_UNIFIED_OBJDIR | \
	grep -v WITHOUT_INSTALLLIB | \
	grep -v WITHOUT_BOOT | \
	grep -v WITHOUT_LOADER_LUA | \
	grep -v WITHOUT_LOCALES | \
	grep -v WITHOUT_ZONEINFO | \
	grep -v WITHOUT_VI \
	> $playground/src.conf

# WITHOUT_AUTO_OBJ and WITHOUT_UNIFIED_OBJDIR warn that they go in src-env.conf
# <broken build options>
# WITHOUT_LOADER_LUA is required for the lua boot code
# WITHOUT_BOOT is needed to install the LUA loader
# WITHOUT_LOCALES is necessary for a console
# WITHOUT_ZONEINFO is necessary for tzsetup on VM image with a userland
# WITHOUT_VI could come in handy

[ -f /etc/src.conf ] || { echo /etc/src.conf did not generate ; exit 1 ; }

cat /etc/src.conf

echo
echo Press the elusive ANY key to continue
read anykey

#echo Removing OCCAMBSD KERNCONF if present
#[ -f /usr/src/sys/amd64/conf/OCCAMBSD ] && rm /usr/src/sys/amd64/conf/OCCAMBSD

echo Creating new OCCAMBSD KERNCONF
#cat << HERE > /usr/src/sys/amd64/conf/OCCAMBSD
cat << HERE > $playground/OCCAMBSD

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

#Mounting from ufs:/dev/vtbd0p3 failed with error 2: unknown file system.
options 	FFS			# Berkeley Fast Filesystem

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
#options		 SMP		# Symmetric MultiProcessor Kernel
#options		 INET		# InterNETworking
#device		iflib
#device		em			# Intel PRO/1000 Gigabit Ethernet Family
HERE

echo The resulting OCCAMBSD KERNCONF is
cat $playground/OCCAMBSD

echo
echo Press the elusive ANY key to continue to buildworld
read anykey

echo Building world with
echo make -j$buildjobs buildworld SRCCONF=$playground/src.conf
\time -h make -C $src_dir -j$buildjobs buildworld || {
	echo buildworld failed
	exit 1
}

echo
echo Press the elusive ANY key to continue to buildkernel
read anykey

echo Building the kernel with
echo make -C $src_dir -j$buildjobs buildkernel KERNCONFDIR=$playground KERNCONF=OCCAMBSD
\time -h make -C $src_dir -j$buildjobs buildkernel KERNCONFDIR=$playground KERNCONF=OCCAMBSD || {
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
truncate -s "$imagesize" "$playground/bhyve.raw" || {
	echo image truncation failed
	exit 1
}

[ -f $playground/bhyve.raw ] || \
	{ echo $playground/bhyve.raw did not create ; exit 1 ; }


echo
echo Truncating xen VM image - consider -t malloc and tmpfs
truncate -s "$imagesize" "$playground/xen.raw" || {
		echo image truncation failed
		exit 1
}

[ -f $playground/xen.raw ] || \
	{ echo $playground/xen.raw did not create ; exit 1 ; }

echo Attaching bhyve VM image
mdconfig -a -u "$bhyve_md_id" -f "$playground/bhyve.raw"

[ -e /dev/$bhyve_md_id ] || { echo $bhyve_md_id did not attach ; exit 1 ; }

echo Attaching Xen VM image
mdconfig -a -u "$xen_md_id" -f "$playground/xen.raw"

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
echo Mounting ${bhyve_md_id}p3 with mount /dev/${bhyve_md_id}p3 $playground/bhyve-mnt
mount /dev/${bhyve_md_id}p3 $playground/bhyve-mnt || {
	echo bhyve image mount failed
	exit 1
}

echo Mounting ${xen_md_id}p3 with mount /dev/${xen_md_id}p3 $playground/xen-mnt
mount /dev/${xen_md_id}p3 $playground/xen-mnt || {
	echo Xen image mount failed
	exit 1
}

# WORLD

echo Installing world to $playground/bhyve-mnt
\time -h make -C $src_dir installworld SRCCONF=$playground/src.conf DESTDIR=$playground/bhyve-mnt

echo Installing world to $playground/xen-mnt
\time -h make -C $src_dir installworld SRCCONF=$playground/src.conf DESTDIR=$playground/xen-mnt

# Alternative: use a known-good full userland
#cat /usr/freebsd-dist/base.txz | tar -xf - -C $playground/xen-mnt

echo Installing world to $playground/jail
\time -h make -C $src_dir installworld SRCCONF=$playground/src.conf DESTDIR=$playground/jail

# KERNEL

echo Installing the kernel to $playground/bhyve-mnt
\time -h make -C $src_dir installkernel KERNCONFDIR=$playground KERNCONF=OCCAMBSD DESTDIR=$playground/bhyve-mnt/
[ -f $playground/bhyve-mnt/boot/kernel/kernel ] || \
	{ echo bhyve-mnt kernel failed to install ; exit 1 ; }

echo Installing the kernel to $playground/bhyve-kernel/
\time -h make -C $src_dir installkernel KERNCONFDIR=$playground KERNCONF=OCCAMBSD DESTDIR=$playground/bhyve-kernel/
[ -f $playground/bhyve-kernel/boot/kernel/kernel ] || \
	{ echo bhyve-kernel kernel failed to install ; exit 1 ; }

echo Installing the kernel to $playground/xen-mnt
\time -h make -C $src_dir installkernel KERNCONFDIR=$playground KERNCONF=OCCAMBSD DESTDIR=$playground/xen-mnt/
[ -f $playground/xen-mnt/boot/kernel/kernel ] || \
	{ echo xen-mnt kernel failed to install ; exit 1 ; }

echo Installing the kernel to $playground/xen-kernel/
\time -h make -C $src_dir installkernel KERNCONFDIR=$playground KERNCONF=OCCAMBSD DESTDIR=$playground/xen-kernel/
[ -f $playground/xen-kernel/boot/kernel/kernel ] || \
	{ echo xen-kernel kernel failed to install ; exit 1 ; }

echo Seeing how big the resulting installed kernel is
ls -lh $playground/bhyve-mnt/boot/kernel/kernel

# DISTRIBUTION

echo Installing distribution to $playground/bhyve-mnt
\time -h make -C $src_dir distribution SRCCONF=$playground/src.conf DESTDIR=$playground/bhyve-mnt

echo Type y to prune locales and timezones saving 28M?
read response

if [ "$response" = "y" ]; then
	echo Deleting unused locales
	cd $playground/bhyve-mnt/usr/share/locale/
	rm -rf a* b* c* d* e* f* g* h* i* j* k* l* m* n* p* r* s* t* u* z*
	echo Deleting unused timezone data
	cd $playground/bhyve-mnt/usr/share/zoneinfo
	rm -rf A* B* C* E* F* G* H* I* J* K* L* M* N* P* R* S* T* UCT US W* Z*
fi

# DEBUG Probably far more than needed
echo Installing distribution to $playground/bhyve-kernel
\time -h make -C $src_dir distribution SRCCONF=$playground/src.conf DESTDIR=$playground/bhyve-kernel

echo Installing distribution to $playground/xen-mnt
\time -h make -C $src_dir distribution SRCCONF=$playground/src.conf DESTDIR=$playground/xen-mnt

if [ "$response" = "y" ]; then
	echo Deleting unused locales
	cd $playground/xen-mnt/usr/share/locale/
	rm -rf a* b* c* d* e* f* g* h* i* j* k* l* m* n* p* r* s* t* u* z*
	echo Deleting unused timezone data
	cd $playground/xen-mnt/usr/share/zoneinfo
	rm -rf A* B* C* E* F* G* H* I* J* K* L* M* N* P* R* S* T* UCT US W* Z*
fi

# DEBUG Probably far more than needed
echo Installing distribution to $playground/xen-kernel
\time -h make -C $src_dir distribution SRCCONF=$playground/src.conf DESTDIR=$playground/xen-kernel

echo Installing distribution to $playground/jail
\time -h make -C $src_dir distribution SRCCONF=$playground/src.conf DESTDIR=$playground/jail

if [ "$response" = "y" ]; then
	echo Deleting unused locales
	cd $playground/jail/usr/share/locale/
	rm -rf a* b* c* d* e* f* g* h* i* j* k* l* m* n* p* r* s* t* u* z*
	echo Deleting unused timezone data
	cd $playground/jail/usr/share/zoneinfo
	rm -rf A* B* C* E* F* G* H* I* J* K* L* M* N* P* R* S* T* UCT US W* Z*
fi

echo Copying boot components from the mounted device to the root kernel device
cp -rp $playground/bhyve-mnt/boot/defaults $playground/bhyve-kernel/boot/
cp -rp $playground/bhyve-mnt/boot/lua $playground/bhyve-kernel/boot/
cp -p $playground/bhyve-mnt/boot/device.hints $playground/bhyve-kernel/boot/

cp -rp $playground/xen-mnt/boot/defaults $playground/xen-kernel/boot/
cp -rp $playground/xen-mnt/boot/lua $playground/xen-kernel/boot/
cp -p $playground/xen-mnt/boot/device.hints $playground/xen-kernel/boot/

#echo
#echo DEBUG directory listings
#echo ls $playground/bhyve-mnt
#ls $playground/bhyve-mnt
#echo ls $playground/bhyve-mnt/boot
#ls $playground/bhyve-mnt/boot
#echo ls $playground/bhyve-mnt/boot/lua
#ls $playground/bhyve-mnt/boot/lua
#echo
#echo ls $playground/bhyve-kernel
#ls $playground/bhyve-kernel
#echo ls $playground/bhyve-kernel/boot
#ls $playground/bhyve-kernel/boot
#echo ls $playground/bhyve-kernel/boot/lua
#ls $playground/bhyve-kernel/boot/lua
#echo
#echo ls $playground/xen-kernel
#ls $playground/xen-kernel
#echo ls $playground/xen-kernel/boot
#ls $playground/xen-kernel/boot
#echo ls $playground/xen-kernel/boot/lua
#ls $playground/xen-kernel/boot/lua

echo
echo Press the elusive ANY key to continue to configuration
read anykey

echo
echo Generating bhyve rc.conf

echo
tee -a $playground/bhyve-mnt/etc/rc.conf <<EOF
hostname="occambsd"
ifconfig_DEFAULT="DHCP inet6 accept_rtadv"
growfs_enable=YES
EOF

echo
echo Generating Xen rc.conf

echo
tee -a $playground/xen-mnt/etc/rc.conf <<EOF
hostname="occambsd-xen"
ifconfig_DEFAULT="DHCP inet6 accept_rtadv"
growfs_enable=YES
EOF

echo
echo Generating Xen kernel rc.conf
        
echo
tee -a $playground/xen-kernel/etc/rc.conf <<EOF
hostname="occambsd-xen"
ifconfig_DEFAULT="DHCP inet6 accept_rtadv"
growfs_enable=YES
EOF

echo
echo Generating jail rc.conf
echo
tee -a $playground/jail/etc/rc.conf <<EOF
hostname="occambsd-jail"
ifconfig_DEFAULT="DHCP inet6 accept_rtadv"
growfs_enable=YES
EOF

echo
echo Generating bhyve fstab

echo
echo "/dev/vtbd0p3	/	ufs	rw,noatime	1	1" \
	> "$playground/bhyve-mnt/etc/fstab"
echo "/dev/vtbd0p2	none	swap	sw	1	1" \
	>> "$playground/bhyve-mnt/etc/fstab"
cat "$playground/bhyve-mnt/etc/fstab" || \
	{ echo bhyve-mnt fstab generation failed ; exit 1 ; }

echo
echo "/dev/vtbd0p3	/	ufs	rw,noatime	1	1" \
	> "$playground/bhyve-kernel/etc/fstab"
echo "/dev/vtbd0p2	none	swap	sw	1	1" \
	>> "$playground/bhyve-kernel/etc/fstab"
cat "$playground/bhyve-kernel/etc/fstab" || \
	{ echo bhyve-kernel fstab generation failed ; exit 1 ; }

echo
echo Generating Xen fstab

echo
echo "/dev/ada0p3	/	ufs	rw,noatime	1	1" \
	> "$playground/xen-mnt/etc/fstab"
echo "/dev/ada0p2	none	swap	sw	1	1" \
	>> "$playground/xen-mnt/etc/fstab"
cat "$playground/xen-mnt/etc/fstab" || \
	{ echo xen-mnt fstab generation failed ; exit 1 ; }

echo "/dev/ada0p3	/	ufs	rw,noatime	1	1" \
		> "$playground/xen-kernel/etc/fstab"
echo "/dev/ada0p2	none	swap	sw	1	1" \
		>> "$playground/xen-kernel/etc/fstab"
cat "$playground/xen-kernel/etc/fstab" || \
		{ echo xen-kernel fstab generation failed ; exit 1 ; }

echo
echo Touching firstboot files

echo
touch "$playground/bhyve-mnt/firstboot"
touch "$playground/bhyve-kernel/firstboot"
touch "$playground/xen-kernel/firstboot"

echo
echo Generating bhyve VM image loader.conf

echo
tee -a $playground/bhyve-mnt/boot/loader.conf <<EOF
kern.geom.label.disk_ident.enable="0"
kern.geom.label.gptid.enable="0"
autoboot_delay="3"
bootverbose="1"
EOF

cat $playground/bhyve-mnt/boot/loader.conf || \
	{ echo bhyve-mnt loader.conf generation failed ; exit 1 ; }

echo
echo Generating bhyve kernel loader.conf

echo
tee -a $playground/bhyve-kernel/boot/loader.conf <<EOF
kern.geom.label.disk_ident.enable="0"
kern.geom.label.gptid.enable="0"
autoboot_delay="3"
bootverbose="1"
EOF

cat $playground/bhyve-kernel/boot/loader.conf || \
	{ echo bhyve-kernel loader.conf generation failed ; exit 1 ; }

echo
echo Generating Xen VM image loader.conf

echo
tee -a $playground/xen-mnt/boot/loader.conf <<EOF
kern.geom.label.disk_ident.enable="0"
kern.geom.label.gptid.enable="0"
autoboot_delay="3"
bootverbose="1"
boot_serial="YES"
comconsole_speed="115200"
console="comconsole"
EOF

cat $playground/xen-mnt/boot/loader.conf || \
	{ echo xen-mnt loader.conf generation failed ; exit 1 ; }

echo
echo Generating Xen kernel loader.conf

echo
tee -a $playground/xen-kernel/boot/loader.conf <<EOF
kern.geom.label.disk_ident.enable="0"
kern.geom.label.gptid.enable="0"
autoboot_delay="3"
bootverbose="1"
boot_serial="YES"
comconsole_speed="115200"
console="comconsole"
EOF

cat $playground/xen-kernel/boot/loader.conf || \
	{ echo xen-kernel loader.conf generation failed ; exit 1 ; }

echo
echo Configuring the Xen serial console
printf "%s" "-h -S115200" >> $playground/xen-mnt/boot.config
printf "%s" "-h -S115200" >> $playground/xen-kernel/boot.config
echo 'xc0     "/usr/libexec/getty Pc"         xterm   onifconsole  secure' \
	>> $playground/xen-kernel/etc/ttys

# DEBUG Is it needed there?
# tzsetup will fail on separated kernel/userland - point at userland somehow
# Could not open /mnt/usr/share/zoneinfo/UTC: No such file or directory

echo
echo Setting the timezone
# DEBUG Need to set on in the kernel directories?
tzsetup -s -C $playground/bhyve-mnt UTC
tzsetup -s -C $playground/xen-mnt UTC
tzsetup -s -C $playground/jail UTC

echo
echo Running df -h | grep $bhyve_md_id
df -h | grep $bhyve_md_id

echo
echo Finding all files over 1M in size
find $playground/bhyve-mnt -size +1M -exec ls -lh {} +

echo
echo Generating jail.conf

cat << HERE > $playground/jail.conf
exec.start = "/bin/sh /etc/rc";
exec.stop = "/bin/sh /etc/rc.shutdown";
exec.clean;
mount.devfs;
occam {
	path = "$playground/jail";
	host.hostname = "occambsd";
#	ip4.addr = 10.0.0.99;
	exec.start = "/bin/sh /etc/rc";
	exec.stop = "/bin/sh /etc/rc.shutdown jail";
	}
HERE

echo Generating xen-occambsd-vm.cfg
cat << HERE > $playground/xen-occambsd.cfg
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

echo Generating xen-occambsd-kernel.cfg
cat << HERE > $playground/xen-occambsd-kernel.cfg
type = "pvh"
memory = 2048
vcpus = 2
name = "OccamBSD"
kernel = "$playground/xen-kernel/boot/kernel/kernel"
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
echo $playground/bhyve.raw
echo $playground/xen.raw
echo
echo Note these setup and tear-down scripts:

echo
echo "kldload vmm" > $playground/load-bhyve-vmm-module.sh
echo $playground/load-bhyve-vmm-module.sh
echo "bhyveload -h $playground/bhyve-kernel/ -m 1024 occambsd" \
	> $playground/load-bhyve-directory.sh
echo $playground/load-bhyve-directory.sh
echo "bhyveload -d $playground/bhyve.raw -m 1024 occambsd" \
	> $playground/load-bhyve-disk-image.sh
echo $playground/load-bhyve-disk-image.sh
echo "bhyve -m 1024 -H -A -s 0,hostbridge -s 2,virtio-blk,$playground/bhyve.raw -s 31,lpc -l com1,stdio occambsd" \
	> $playground/boot-occambsd-bhyve.sh
echo $playground/boot-occambsd-bhyve.sh
echo "bhyvectl --destroy --vm=occambsd" \
	> $playground/destroy-occambsd-bhyve.sh
echo $playground/destroy-occambsd-bhyve.sh

echo
echo "xl create -c $playground/xen-occambsd.cfg" \
	> $playground/boot-occambsd-xen.sh
echo $playground/boot-occambsd-xen.sh
echo "xl create -c $playground/xen-occambsd-kernel.cfg" \
	> $playground/boot-occambsd-xen-kernel.sh
echo $playground/boot-occambsd-xen-kernel.sh
echo "xl destroy OccamBSD" > $playground/destroy-occambsd-xen.sh
echo $playground/destroy-occambsd-xen.sh

# Notes while debugging
#xl console -t pv OccamBSD
#xl console -t serial OccamBSD

echo
echo "jail -c -f $playground/jail.conf command=/bin/sh" \
	> $playground/boot-occambsd-jail.sh
echo $playground/boot-occambsd-jail.sh

echo
echo The VM disk image is still mounted and you could
echo exit and rebuild the kernel with:
echo cd /usr/src
echo make -C $src_dir -j$buildjobs buildkernel KERNCONFDIR=$playground KERNCONF=OCCAMBSD
echo make installkernel KERNCONFDIR=$playground DESTDIR=$playground/\< jail mnt or root \>

echo
echo Press the elusive ANY key to unmount the VM disk image for use
read anykey

echo
echo Unmounting $playground/bhyve-mnt
umount $playground/bhyve-mnt

echo
echo Unmounting $playground/xen-mnt
umount $playground/xen-mnt

echo
echo Unmounting /usr/obj
umount /usr/obj

echo
echo Destroying $bhyve_md_id and $xen_md_id
mdconfig -du $bhyve_md_id
mdconfig -du $xen_md_id
mdconfig -lv
exit 0
