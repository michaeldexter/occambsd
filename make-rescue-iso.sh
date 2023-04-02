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

# Version v0.1


# USAGE

# This can be run after a stock or OccamBSD 'make cdrom' in ~/usr/src/release
# Note that the disc1 and bootonly ISO images cannot be built independently
# as memstick and mini-memstick can. By default the disc1 steps are disabled.


# ISSUES

# Adding a tmpfs mount for / does not work in /etc/fstab
# Stock fstab: /dev/iso9660/14_0_CURRENT_AMD64_CD / cd9660 ro 0 0
#	Solution: Possibly working but needs tmpfs module loaded
#	Workaround: kldload tmpfs ; mount -t tmpfs tmpfs /tmp
# Utilities from packages must be executed with their full paths
#	Solution: Set the $PATH
# Note that ipmitool requires the ipmi kernel module mounted

#echo Installing packages to disc1
#pkg -r /usr/obj/usr/src/amd64.amd64/release/disc1 install -y \
#	tmux ipmitool sedutil dmidecode cmdwatch acpica-tools \
#	smartmontools rsync fio jq

echo Installing packages to bootonly
pkg -r /usr/obj/usr/src/amd64.amd64/release/bootonly install -y \
	tmux ipmitool sedutil dmidecode cmdwatch acpica-tools \
	smartmontools rsync fio jq

echo Rebuiling shared library cache
#chroot /usr/obj/usr/src/amd64.amd64/release/disc1 /etc/rc.d/ldconfig start
chroot /usr/obj/usr/src/amd64.amd64/release/bootonly /etc/rc.d/ldconfig start

echo Looking for the results
#ls -l /usr/obj/usr/src/amd64.amd64/release/disc1/var/run/ld-elf.so.hints
ls -l /usr/obj/usr/src/amd64.amd64/release/bootonly/var/run/ld-elf.so.hints

#echo Generating fstab (disabled until tmpfs.ko support is added)
# This might work if tmpfs.ko is set to be loaded: test
#echo "tmpfs /tmp tmpfs rw 0 0" >> /usr/obj/usr/src/amd64.amd64/release/disc1/etc/fstab
#cat /usr/obj/usr/src/amd64.amd64/release/disc1/etc/fstab

#echo "tmpfs /tmp tmpfs rw 0 0" >> \
#	/usr/obj/usr/src/amd64.amd64/release/bootonly/etc/fstab
#cat /usr/obj/usr/src/amd64.amd64/release/bootonly/etc/fstab

echo Generating ISOs # Make this smarter with version detection or override it
#sh /usr/src/release/amd64/mkisoimages.sh -b 14_0_CURRENT_amd64_CD \
#sh /usr/src/release/amd64/mkisoimages.sh -b RESCUE \
#	/tmp/occambsd/rescue-disc1.iso \
#	/usr/obj/usr/src/amd64.amd64/release/disc1

sh /usr/src/release/amd64/mkisoimages.sh -b RESCUE \
	/tmp/occambsd/rescue.iso \
	/usr/obj/usr/src/amd64.amd64/release/bootonly

echo Note this syntax:
#echo sh /usr/share/examples/bhyve/vmrun.sh -d /tmp/occambsd/rescue-disc1.iso ipmi
echo sh /usr/share/examples/bhyve/vmrun.sh -d /tmp/occambsd/rescue.iso ipmi
echo

exit 0
