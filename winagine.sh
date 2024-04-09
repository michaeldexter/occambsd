#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause-FreeBSD
#
# Copyright 2022, 2023, 2024 Michael Dexter
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

# Version v1.0.1


# EXAMPLES

# To remaster a Windows ISO with a given autounattend.xml file
#
# sh winmagine.sh -i win2025.iso -x autounattend_xml/win2025.iso 

# To wait before remastering, allowing for a password or system name change
#
# sh winmagine.sh -i win2025.iso -x autounattend_xml/win2025.iso -w


# VARIABLES - NOTE THE VERSIONED ONE

work_dir="/root/imagine-work"

which 7z || pkg install -y 7-zip
which mkisofs || pkg install -y cdrtools
which xmllint || pkg install -y libxml2

vm_name="windows0"
target_input="img"		# Default
force=0
wait=0
#key=""
iso=""
isofile=""
xmlfile=""

echo ; echo USAGE: -i ISO file -x XML file

while getopts i:x:w opts ; do
	case $opts in
	i)
		iso="$OPTARG"
		[ -f $iso ] || { echo Requested ISO $iso not found ; exit 1 ; }
		isofile=$( basename $iso )
	;;
	x)
		xmlfile="$OPTARG"
		[ -f $xmlfile ] || \
			{ echo Requested XML $xmlfile not found ; exit 1 ; }
	;;              
	w)
		wait=1
	;;
	esac
done

# Consider proper f_usage
[ -n "$isofile" ] || { echo must enter -i ; exit 1 ; }
[ -n "$xmlfile" ] || { echo must enter -x ; exit 1 ; }

echo ; echo Cleansing $work_dir/windows as needed

# Removing previous tmpfs mounts
mount | grep -q $work_dir/windows/iso && umount $work_dir/windows/iso
#[ -f $work_dir/windows/iso/setup.exe ] && rm -rf $work_dir/windows/iso/*
[ -f $work_dir/windows/iso/setup.exe ] && umount $work_dir/windows/iso

mount | grep -q $work_dir/windows/iso && umount $work_dir/windows/iso

[ -f $work_dir/windows/windows.iso ] && rm $work_dir/windows/windows.iso
[ -f $work_dir/windows/windows.raw ] && rm $work_dir/windows/windows.raw

[ -f $work_dir/windows/boot-windows-iso.sh ] && \
	rm $work_dir/windows/boot-windows-iso.sh

[ -f $work_dir/windows/boot-windows-raw.sh ] && \
	rm $work_dir/windows/boot-windows-raw.sh

# If greenfield
[ -d $work_dir/windows/iso ] || mkdir -p $work_dir/windows/iso

[ -d $work_dir/windows/iso ] || \
	{ echo Making $work_dir/windows/iso failed ; exit 1 ; }

# Using tmpfs 1. For privacy editing passwords in autounattend.xml 2. Speed
echo ; echo Mounting tmpfs $work_dir/windows/iso
mount -t tmpfs tmpfs $work_dir/windows/iso || \
	{ echo Failed to mount tmpfs $work_dir/windows/iso ; exit 1 ; }

# Copy before changing directory and to validate early

echo ; echo Copying in $work_dir/windows/iso/autounattend.xml
cp $xmlfile $work_dir/windows/iso/autounattend.xml || \
	{ echo $xmlfile copy failed ; exit 1 ; }

echo ; echo Validating $work_dir/windows/iso/autounattend.xml
xmllint --noout $work_dir/windows/iso/autounattend.xml || 
{ echo $work_dir/windows/iso/autounattend.xml failed to validate ; exit 1 ; }

# NOTE THAT UDF IS NOT SUPPORTED by libarchive!
#tar -xf $iso -C $work_dir/windows/iso
#tar -xf $iso -C $work_dir/windows/iso

# Does 7z support a detination directory?
cd $work_dir/windows/iso
echo ; echo Extracting $iso to $work_dir/windows/iso with 7z
7z x $iso || { echo UDF extraction failed ; exit 1 ; }

# Did not work
#echo Generating $work_dir/windows/iso/sources/ei.cfg
#cat << HERE > $work_dir/windows/iso/sources/ei.cfg
#[EditionID]
#[Channel]
#Retail
#[VL]
#0
#HERE
#cat $work_dir/windows/iso/sources/ei.cfg

#echo "[PID]" > $work_dir/windows/iso/sources/PID.txt
#echo "Value=$key" >> $work_dir/windows/iso/sources/PID.txt
#cat $work_dir/windows/sources/PID.txt

echo ; ls $work_dir/windows/iso

if [ "$wait" = "1" ] ; then
	echo ; echo Pausing to allow manual configuration in anoter console
	echo Press any key when ready to re-master the ISO
	read waiting
fi

[ -f $work_dir/windows/iso/setup.exe ] || \
	{ echo $work_dir/windows/iso/Setup.exe missing ; exit 1 ; }

echo ; echo Remastering ISO

mkisofs \
	-quiet \
	-b boot/etfsboot.com -no-emul-boot -c BOOT.CAT \
	-iso-level 4 -J -l -D \
	-N -joliet-long \
	-relaxed-filenames \
	-V "Custom" -udf \
	-boot-info-table -eltorito-alt-boot -eltorito-platform 0xEF \
	-eltorito-boot efi/microsoft/boot/efisys_noprompt.bin \
	-no-emul-boot \
	-o $work_dir/windows/windows.iso $work_dir/windows/iso || \
		{ echo mkisofs failed ; exit 1 ; }

echo ; echo The resulting ISO image is $work_dir/windows/install.iso

echo ; echo Unmounting $work_dir/windows/iso
cd -
umount $work_dir/windows/iso || \
	{ echo $work_dir/windows/iso unmount failed ; exit 1 ; }

# Generate boot scripts

# One time installation boot to windows.iso

cat << HERE > $work_dir/windows/boot-windows-iso.sh
#!/bin/sh
[ -e /dev/vmm/$vm_name ] && { bhyvectl --destroy --vm=$vm_name ; sleep 1 ; }
[ -f /usr/local/share/uefi-firmware/BHYVE_UEFI.fd ] || \\
	{ echo \"BHYVE_UEFI.fd missing\" ; exit 1 ; }
kldstat -q -m vmm || kldload vmm

echo ; echo Removing previous $work_dir/windows/windows.raw if present
[ -f $work_dir/windows/windows.raw ] && \\
rm $work_dir/windows/iso/windows.raw

echo ; echo truncating 32GB $work_dir/windows/windows.raw
truncate -s 32g $work_dir/windows/windows.raw

bhyve -c 2 -m 4G -H -A -D \\
	-l com1,stdio \\
	-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd \\
	-s 0,hostbridge \\
	-s 1,ahci-cd,$work_dir/windows/windows.iso \\
	-s 2,nvme,$work_dir/windows/windows.raw \\
	-s 29,fbuf,tcp=0.0.0.0:5900,w=1024,h=768 \\
	-s 30,xhci,tablet \\
	-s 31,lpc \\
	$vm_name

# Devices you may want to add:
#       -s 3,e1000,tap3 \\

sleep 2
bhyvectl --destroy --vm=$vm_name
HERE


# Post-installation boot to windows.raw

cat << HERE > $work_dir/windows/boot-windows-raw.sh
#!/bin/sh
[ -e /dev/vmm/$vm_name ] && { bhyvectl --destroy --vm=$vm_name ; sleep 1 ; }
[ -f /usr/local/share/uefi-firmware/BHYVE_UEFI.fd ] || \\
	{ echo \"BHYVE_UEFI.fd missing\" ; exit 1 ; }
kldstat -q -m vmm || kldload vmm

bhyve -c 2 -m 4G -H -A -D \\
	-l com1,stdio \\
	-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd \\
	-s 0,hostbridge \\
	-s 2,nvme,$work_dir/windows/windows.raw \\
	-s 29,fbuf,tcp=0.0.0.0:5900,w=1024,h=768 \\
	-s 30,xhci,tablet \\
	-s 31,lpc \\
	$vm_name

# Devices you may want to add:
#	-s 3,e1000,tap3 \\

sleep 2
bhyvectl --destroy --vm=$vm_name
HERE

echo ; echo Note $work_dir/windows/boot-windows-iso.sh to boot the VM once for installation, which will be on 0.0.0.0:5900 for VNC attachment

echo ; echo Note $work_dir/windows/boot-windows-raw.sh for post-installation boot

echo ; echo Note that the resulting $work_dir/windows/windows.raw image can be imaged to a hardware device with the dd\(1\) command
