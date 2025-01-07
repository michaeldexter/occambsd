#!/bin/sh

# Desired/required packages: bhyve-firmware qemu8 edk2-qemu-x64 u-boot-qemu-arm64 opensbi u-boot-qemu-riscv64 u-boot-qemu-riscv64

# Hello!
#
# This is a series of exercises of occambsd.sh, propagate.sh, and imagine.sh 
#
# It relies entirely on the default locations such as /usr/src, /usr/obj,
# /tmp/occambsd, /tmp/propagate, and /root/imagine-work
#
# Accordingly, it will do intrusive things like rm -rfing them and you should
# plan accordingly, such as dedicating a system to this
#
# Note that as with all things in OccamBSD, it relies on the default FreeBSD
# zpool name "zroot" and this will likely conflict.
#
# This simply offers a description of the test, it command it would run, and
# if to continue (y/n)
#
# Hopefully the relationship of the tools is becoming clean, and this is good
# ad pointing out insconsistent script names and the like. Some of these
# pick up where the prvious one leaves off, such as building a VM image in
# OccamBSD and using it as Imagine input
#
# If you enter single user mode on boot, there is a good chance that /etc/fstab
# is invalid, often because of the EFI partition, which you probably do not
# want mounted in the first place. Swapping and dumping is another conversation.
#
# A quick way to resolve this situation is to run:
#
# mount -uw /
# mv /etc/fstab /etc/fstab.disabled
# touch /etc/fstab
# exit
#
# Note that VM boot may disrupt the flow of the script
#
# Note that Xen is only slowly being framed in but you can try Xenomorph!
#
# There is a dumping ground of incomplete tests at the bottom that generally
# need updated flags/syntax, boot script names, etc.
#
# The Windows tests are there as they depend on an ISO, which we cannot retrieve

f_clean_occambsd () {
	[ -d /tmp/occambsd ] && rm -rf /tmp/occambsd
	if [ -d /usr/obj/usr/src/amd64.amd64 ] ; then
		chflags -R 0 /usr/obj/usr/src/amd64.amd64
		rm -rf /usr/obj/usr/src/amd64.amd64
	fi
	if [ -d /usr/obj/usr/src/repo ] ; then
		chflags -R 0 /usr/obj/usr/src/repo
		rm -rf /usr/obj/usr/src/repo
	fi
}

f_clean_propagate () {
	# Add a test
	umount /tmp/propagate/tmp/propagate/src/amd64.amd64/release/vm/dev
	if [ -f /tmp/propagate ] ; then
		chflags -R 0 /tmp/propagate
		rm -rf /tmp/propagate
	fi
}

f_clean_imagine () {
#	zpool export zroot
	rm /root/imagine-work/*.raw.*
	rm /root/imagine-work/*.sh
	rm /root/imagine-work/*.vmdk
	rm /root/imagine-work/*.cfg
	mdconfig -du 42
	mdconfig -du 43
}

f_ask () {
	echo -n "Test is: " ; echo "$the_test"
	echo -n "Proceed? (y/n): " ; read response
	if [ "$response" = "y" ] ; then
		return 0
	else
		return 1
	fi
}

f_boot () {
echo DEBUG boot_bhyve is $boot_bhyve
echo DEBUG boot_qemu is $boot_qemu
	echo -n "Boot in bhyve? (y/n): " ; read response
	[ "$response" = "y" -o "$response" = "n" ] || \
		{ echo Invalid input ; exit 1 ; }
	if [ "$response" = "y" ] ; then
		if [ -n "$boot_bhyve" ] && [ -f "$boot_bhyve" ] ; then
			sh "$boot_bhyve"
			sleep 5
			reset
		else
			echo "boot_bhyve script missing"
		fi
	fi
	echo -n "Boot in QEMU? (y/n): " ; read response
	[ "$response" = "y" -o "$response" = "n" ] || \
		{ echo Invalid input ; exit 1 ; }
	if [ "$response" = "y" ] ; then
		if [ -n "$boot_qemu" ] && [ -f "$boot_qemu" ] ; then
			sh "$boot_qemu"
			sleep 5
			reset
		else
			echo "boot_qemu script missing"
		fi
	fi
}

f_build () {
	echo DEBUG the_test is $the_test
	# Execute the string
#	sh "$the_test"
	eval "$the_test"
}

# Works
# Note: root/<no password>
echo ; echo "Synopsis: Create a 15.0-CURRENT PkgBase VM-IMAGE"
the_test="sh propagate.sh -r 15.0-CURRENT -d -c -C -v"
boot_bhyve="/tmp/propagate/src/release/scripts/boot-vm.sh"
boot_qemu=""
boot_xen=""
f_ask && { f_clean_propagate ; f_build && f_boot ; }


# Works
ncho ; echo "Synopsis: Build a minimum 14.2 system with PkgBase, and VM boot"
the_test="sh occambsd.sh -p profile-amd64-zfs14.txt -z -v -b"
boot_bhyve="/tmp/occambsd/bhyve-boot-vmimage.sh"
boot_qemu="/tmp/occambsd/qemu-boot-vmimage.sh"
boot_xen="/tmp/occambsd/xen-boot-vmimage.sh"
f_ask && { f_clean_occambsd ; f_build && f_boot ; }

# Works
echo ; echo "Synopsis: OMG Propagate the PkgBase packages of the last build!"
the_test="sh propagate.sh -r 14.2-RELEASE -v -u file:///usr/obj/usr/src/repo/FreeBSD:14:amd64/14.2/"
boot_bhyve="/tmp/propagate/src/release/scripts/boot-vm.sh"
f_ask && { f_clean_propagate ; f_build && f_boot ; }

# Works
echo ; echo "Synopsis: Create a minimum /usr/src system with and VM boot"
the_test="sh occambsd.sh -p profile-amd64-minimum14.txt -v"
boot_bhyve="/tmp/occambsd/bhyve-boot-vmimage.sh"
boot_qemu="/tmp/occambsd/qemu-boot-vmimage.sh"
boot_xen="/tmp/occambsd/xen-boot-vmimage.sh"
f_ask && { f_clean_occambsd ; f_build && f_boot ; }

echo ; echo "Synopsis: Build a minimum 14.x system with ZFS, and VM boot"
the_test="sh occambsd.sh -p profile-amd64-zfs14.txt -z -v"
boot_bhyve="/tmp/occambsd/bhyve-boot-vmimage.sh"
boot_qemu=""
boot_xen=""
f_ask && { f_clean_occambsd ; f_build && f_boot ; }

# Error: Solaris: NOTICE: Cannot find the pool label for 'zroot'
echo ; echo "Synopsis: Build a ZFS image based on OccamBSD object directory"
the_test="sh imagine.sh -r obj -z -t img -v"
boot_bhyve="/root/imagine-work/bhyve-vm.raw.sh"
boot_qemu="/root/imagine-work/qemu-vm.raw.sh"
boot_xen="/root/imagine-work/xen-vm.raw.sh"
f_ask && { f_clean_imagine ; f_build && f_boot ; }

# Note: root/<no password>
echo ; echo "Synopsis: Retrieve a 14.2 stock UFS VM-IMAGE and VM boot"
the_test="sh imagine.sh -r 14.2-RELEASE -v"
boot_bhyve="/root/imagine-work/bhyve-14.2-RELEASE-amd64-ufs.sh"
boot_qemu="/root/imagine-work/xen-14.2-RELEASE-amd64-ufs.sh"
boot_xen="/root/imagine-work/qemu-14.2-RELEASE-amd64-ufs.sh"
f_ask && { f_clean_imagine ; f_build && f_boot ; }

# Note: root/<no password>
echo ; echo "Synopsis: Retrieve a 14.2 stock ZFS VM-IMAGE and VM boot"
the_test="sh imagine.sh -r 14.2-RELEASE -z -v"
boot_bhyve="/root/imagine-work/bhyve-14.2-RELEASE-amd64-zfs.sh"
boot_qemu="/root/imagine-work/qemu-14.2-RELEASE-amd64-zfs.sh"
boot_xen="/root/imagine-work/xen-14.2-RELEASE-amd64-zfs.sh"
f_ask && { f_clean_imagine ; f_build && f_boot ; }

# Works
# Note: root/<no password>
echo ; echo "Synopsis: Retrieve a 14.2 stock ARM64 ZFS VM-IMAGE and VM boot"
the_test="sh imagine.sh -r 14.2-RELEASE -z -v -a arm64"
boot_bhyve=""
boot_qemu=""/root/imagine-work/qemu-14.2-RELEASE-arm64-zfs.sh"
boot_xen=""
f_ask && { f_clean_imagine ; f_build && f_boot ; }

# Works
# Note: root/<no password>
echo ; echo "Synopsis: Retrieve a 14.2 stock RISC-V ZFS VM-IMAGE and VM boot"
the_test="sh imagine.sh -r 14.2-RELEASE -z -v -a riscv"
boot_bhyve=""
boot_qemu="/root/imagine-work/qemu-14.2-RELEASE-riscv-zfs.sh"
boot_xen=""
f_ask && { f_clean_imagine ; f_build && f_boot ; }

# Note: root/<no password>
echo ; echo "Synopsis: Retrieve a 15.0 ZFS VM-IMAGE, grow to 10G, and VM boot"
the_test="sh imagine.sh -r 15.0-CURRENT -z -v -g 10"
boot_bhyve="/root/imagine-work/bhyve-15.0-CURRENT-amd64-zfs.sh"
boot_qemu="/root/imagine-work/qemu-15.0-CURRENT-amd64-zfs.sh"
boot_xen="/root/imagine-work/xen-15.0-CURRENT-amd64-zfs.sh"
f_ask && { f_clean_imagine ; f_build && f_boot ; }

# bhyve works
# Note: root/<no password>
echo ; echo "Synopsis: Retrieve an OmniOS VM-IMAGE and VM boot"
the_test="sh imagine.sh -r omnios -v"
boot_bhyve="/root/imagine-work/bhyve-omnios-amd64-zfs.sh"
boot_qemu="/root/imagine-work/qemu-omnios-amd64-zfs.sh"
boot_xen="/root/imagine-work/xen-omnios-amd64-zfs.sh"
f_ask && { f_clean_imagine ; f_build && f_boot ; }

# bhyve works
# Note: root/<no password>
echo ; echo "Synopsis: Retrieve a Debian VM-IMAGE and VM boot"
the_test="sh imagine.sh -r debian -v"
boot_bhyve="/root/imagine-work/bhyve-debian-amd64-ext4.sh"
boot_qemu="/root/imagine-work/qemu-debian-amd64-ext4.sh"
boot_xen="/root/imagine-work/xen-debian-amd64-ext4.sh"
f_ask && { f_clean_imagine ; f_build && f_boot ; }

# Note: admin/<no password>
echo ; echo "Synopsis: Retrieve a RouterOS VM-IMAGE and VM boot"
the_test="sh imagine.sh -r routeros -v"
boot_bhyve="/root/imagine-work/bhyve-routeros-amd64-ext4.sh"
boot_qemu="/root/imagine-work/qemu-routeros-amd64-ext4.sh"
boot_xen="/root/imagine-work/xen-routeros-amd64-ext4.sh"
f_ask && { f_clean_imagine ; f_build && f_boot ; }

# Configure an OccamBSD profile with UEFI for handoff to Propagate
# Fails: Assumes UEFI and the VM wants bhyveload
echo ; echo "Synopsis: imagine.sh the an OccamBSD VM-IMAGE, and VM boot"
the_test="sh imagine.sh -r /usr/obj/usr/src/amd64.amd64/release/vm.ufs.raw -t /tmp/boot.raw -v -b"
boot_bhyve="/root/imagine-work/bhyve-vm.raw.sh"
boot_qmeu="/root/imagine-work/qemu-vm.raw.sh"
boot_xen="/root/imagine-work/xen-vm.raw.sh"
f_ask && { f_clean_imagine ; f_build && f_boot ; }


exit

# Test dumping ground

#"img not found"
echo Synopsis: Build a mirrored 14.2 Imagine system
imagine.sh -r 14.2-RELEASE -z -v -T img
/root/imagine-work/boot-bhyve.sh

# Try mirroring
imagine.sh -r 14.2-RELEASE -z -v -g 10 -T img
imagine.sh -r obj -v
/root/imagine-work/boot-bhyve.sh

# Windows!

imagine.sh -x autounattend_xml/win10.xml -i /lab/iso/winserver/win10.iso -g 20
cat /root/imagine-work/boot-windows-iso.sh
/root/imagine-work/boot-windows-iso.sh

sh imagine.sh -x autounattend_xml/win10.xml -i /lab/iso/winserver/win10.iso
echo That was supposed to fail because -g is required

occambsd.sh -p profile-arm64-minimum14-zfs.txt -v -z

imagine.sh -r /tmp/occambsd/vm.raw -t /tmp/boot.raw -g 10 -v

occambsd.sh -p profile-riscv-minimum.txt -w -v -z
imagine.sh -r obj -a riscv -v -z

occambsd.sh -p profile-amd64-zfs.txt -v -z
imagine.sh -r obj -v -z

imagine.sh -r obj -v
imagine.sh -w /tmp/imagine -r obj -v

ls -lh /root/imagine-work/boot.raw
/root/imagine-work/boot-bhyve.sh

ls -lh /tmp/vm.raw
/root/imagine-work/boot-bhyve.sh

imagine.sh -r 15.0-CURRENT -v
cat /root/imagine-work/boot-bhyve.sh
cat /root/imagine-work/boot-xen.sh
cat /root/imagine-work/xen.cfg
/root/imagine-work/boot-bhyve.sh
# Some way to sleep and pkill?

imagine.sh -r 15.0-CURRENT -t /dev/md0 -v
