#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause-FreeBSD
#
# Copyright 2024 Michael Dexter
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

# Version v.0.0.1BETA

# propagate.sh - Packaged Base for OccamBSD and Imagine

# MOTIVATION

# The "p" and "g" in propagate are for "pkg", obviously.
#
# The 2018 propagate.sh installed upstream FreeBSD distribution sets or
# custom-built binaries to boot environments, and this incarnation does
# the same with upstream or OccamBSD-built FreeBSD base packages.

# DRAFT USAGE - not yet interactive - edit the hard-coded variables for now

# -r revision or repo or directory of files or ???
# -b boot environment name
# -j jail path
# -p profile
# -m keep mounted
# -v VM-IMAGE

# Q: How to choose a PkgBase kernel such as NODEBUG?

# PERSONALIZE THESE VARIABLES

# The name of the new boot environment
boot_env="zroot/ROOT/pkgbase15"
# The mount point of the new boot environment
guest_root="/mnt"

# Pick a revision, 14.0 or newer
abi_major="15"
abi_minor="base_latest"

# Note that "release_1" indicates "14.1"
#abi_major="14"
#abi_minor="base_release_1"

# Additional packages beyond base packages to install
additional_packages="tmux"

########
# MAIN #
########

echo ; echo Cleansing ${guest_root} as needed
# Not a great test - existing mount point does not mean mounted
[ -d "${guest_root}/dev" ] && umount $guest_root/dev

# This can fail if all of your boot environments contain the same name
mount | grep -q $guest_root && umount $guest_root
mount | grep -q  $guest_root && \
	{ echo $guest_root failed to unmount ; exit 1 ; }

echo Creating boot environment if missing
zfs get name $boot_env || \
	zfs create -o canmount=noauto -o mountpoint=/ $boot_env
zfs get name $boot_env || \
	{ echo boot environment failed to create ; exit 1 ; }

echo Mounting the boot environment
echo mounting boot environment
bectl mount $boot_env ${guest_root} || \
	{ echo boot environment failed ; exit 1 ; }

#########################
# BOOT ENVIRONMENT ROOT #
#########################

echo Creating ${guest_root}/dev
[ -d ${guest_root}/dev ] || mkdir -p $guest_root/dev 
[ -d ${guest_root}/dev ] || { echo root/dev failed to create ; exit 1 ; }

echo Creating ${guest_root}/etc/pkg
[ -d ${guest_root}/etc/pkg ] || mkdir -p $guest_root/etc/pkg
[ -d ${guest_root}/etc/pkg ] || { echo root/etc failed to create ; exit 1 ; }

echo Copying in /etc/resolv.conf
cp /etc/resolv.conf ${guest_root}/etc/ || \
	{ echo resolv.conf failed to copy ; exit 1 ; }

#pkg-static: Cannot open dev/null
echo Mounting devfs for pkg-static
mount -t devfs -o ruleset=4 devfs ${guest_root}/dev || \
	{ echo mount devfs failed; exit 1 ; }

# /var/cache/pkg
echo ; echo Creating /tmp/pkg directories
[ -d "${guest_root}/var/cache/pkg" ] || mkdir -p $guest_root/var/cache/pkg
[ -d "${guest_root}/var/cache/pkg" ] || { echo mkdir tmp/pkg failed ; exit 1 ; }

# ${guest_root}/var/db/pkg
[ -d "${guest_root}/var/db/pkg" ] || mkdir -p $guest_root/var/db/pkg
[ -d "${guest_root}/var/db/pkg" ] || { echo mkdir var/db/pkg failed ; exit 1 ; }

[ -d ${guest_root}/usr/share/keys/pkg ] || \
	mkdir -vp ${guest_root}/usr/share/keys/pkg
cp -av /usr/share/keys/pkg \
	${guest_root}/usr/share/keys || \
	{ echo pkg keys copy failed ; exit 1 ; }

#echo keys source and desination
#ls /usr/share/keys/pkg
#ls ${guest_root}/usr/share/keys/pkg

[ -d ${guest_root}/usr/share/keys/pkg/trusted ] || \
	{ echo cp ${guest_root}/usr/share/keys/pkg/trusted failed ; exit 1 ; }

# Used by temporary pkg.conf and persistent pkg/repos
[ -d ${guest_root}/usr/local/etc/pkg/repos ] || \
	mkdir -p $guest_root/usr/local/etc/pkg/repos
[ -d ${guest_root}/usr/local/etc/pkg/repos ] || \
	{ echo mkdir usr/local/etc/pkg/repos failed ; exit 1 ; }

# /mnt and /media are not created by PkgBase!
[ -d ${guest_root}/mnt ] || mkdir -p $guest_root/mnt
[ -d ${guest_root}/mnt ] || { echo mkdir mnt failed ; exit 1 ; }

[ -d ${guest_root}/media ] || mkdir -p $guest_root/media
[ -d ${guest_root}/media ] || { echo mkdir media failed ; exit 1 ; }

[ -d ${guest_root}/root ] || mkdir -p $guest_root/root
[ -d ${guest_root}/root ] || { echo mkdir root failed ; exit 1 ; }

#du -h ${guest_root}

########################################
# FreeBSD.conf REPO CONFIGURATION FILE #
########################################

# NOTE THAT THIS WILL BE OVERRIDDEN BY THE RETRIEVED PACKAGES
echo ; echo Generating ${guest_root}/etc/pkg/FreeBSD.conf REPO file
cat << HERE > ${guest_root}/etc/pkg/FreeBSD.conf
FreeBSD: { 
  enabled: yes
  url: "pkg+https://pkg.FreeBSD.org/FreeBSD:${abi_major}:amd64/latest", 
  mirror_type: "srv",
  signature_type: "fingerprints",
  fingerprints: "${guest_root}/usr/share/keys/pkg"
}

FreeBSD-base: {
  enabled: yes
  url: "pkg+https://pkg.FreeBSD.org/FreeBSD:${abi_major}:amd64/${abi_minor}", 
  mirror_type: "srv",
  signature_type: "fingerprints",
  fingerprints: "${guest_root}/usr/share/keys/pkg"
}
HERE

echo ; echo Copying ${guest_root}/etc/pkg/FreeBSD.conf to /root
# It will be overidden during the package installation
cp ${guest_root}/etc/pkg/FreeBSD.conf /${guest_root}/root/ || \
	{ echo cp FreeBSD.conf failed ; exit 1 ; }

# DO NOT PUT yes in quotation marks or it will fail!

# THIS WILL BE OVERRIDDEN UPON PACKAGE RETRIEVAL
# WORSE, it will be incorrectly prefixed if we do not modify it and the new
# system will not be able to retrieve packages
# Moving it to the root directory at the end

echo ; echo Generating ${guest_root}/usr/local/etc/pkg.conf PKG config file
cat << HERE > ${guest_root}/usr/local/etc/pkg.conf
  IGNORE_OSVERSION: yes
  ABI: "FreeBSD:${abi_major}:amd64"
  pkg_dbdir: "${guest_root}/var/db/pkg",
  pkg_cachedir: "${guest_root}/var/cache/pkg",
  handle_rc_scripts: no
  assume_always_yes: yes
  repos_dir: [
    "${guest_root}/etc/pkg"
  ]
  syslog: no
  developer_mode: no
HERE

[ -f ${guest_root}/usr/local/etc/pkg.conf ] || \
	{ echo pkg.conf generation failed ; exit 1 ; }

#############
# BOOTSTRAP #
#############

echo ; echo Running pkg bootstrap
echo ; cat ${guest_root}/etc/pkg/FreeBSD.conf
echo

# Adding -o IGNORE_OSVERSION="yes" to remove the scary warning

pkg \
	-C ${guest_root}/usr/local/etc/pkg.conf \
	-o IGNORE_OSVERSION="yes" \
	bootstrap -f -y || \
		{ echo pkg bootstrap failed ; exit 1 ; }

##########
# UPDATE #
##########

echo ; echo Running pkg update 

echo ; echo pkg -vv SMOKE TEST
pkg -C ${guest_root}/usr/local/etc/pkg.conf -vv

pkg \
	-C ${guest_root}/usr/local/etc/pkg.conf \
	-o IGNORE_OSVERSION="yes" \
	update -f || \
		{ echo pkg update failed ; exit 1 ; }

du -h ${guest_root}

echo ; echo pkg -vv SMOKE TEST
pkg -C ${guest_root}/usr/local/etc/pkg.conf -vv

###########
# INSTALL #
###########

echo ; echo Running pkg rquery and xargs 

echo ; echo SMOKE TEST: Query for one package
pkg \
	-C ${guest_root}/usr/local/etc/pkg.conf \
	-o IGNORE_OSVERSION="yes" \
	rquery --repository="FreeBSD-base" '%n' \
		| grep FreeBSD-rc

echo ; echo SMOKE TEST: Count available packages
pkg \
	-C ${guest_root}/usr/local/etc/pkg.conf \
	-o IGNORE_OSVERSION="yes" \
	rquery --repository="FreeBSD-base" '%n' \
		| wc -l

echo ; echo SMOKE TEST: Count filtered packages
pkg \
	-C ${guest_root}/usr/local/etc/pkg.conf \
	-o IGNORE_OSVERSION="yes" \
	rquery --repository="FreeBSD-base" '%n' \
		| grep -vE 'FreeBSD-.*(.*-(dbg|lib32|dev)|(bsnmp|clang|cxgbe-tools|dtrace|lld|lldb|mlx-tools|rescue|tests))$' \
		| wc -l

echo ; cat ${guest_root}/etc/pkg/FreeBSD.conf
echo

#echo ; echo SMOKE TEST: Install one package
# WORKS
#pkg \
#	-C ${guest_root}/usr/local/etc/pkg.conf \
#	-o IGNORE_OSVERSION="yes" \
#	--rootdir ${guest_root} install --repository=FreeBSD-base \
#	FreeBSD-rc || \
#		{ echo pkg install failed ; exit 1 ; }

echo ; echo Installing a jail-oriented subset of base packages

pkg \
	-C ${guest_root}/usr/local/etc/pkg.conf \
	-o IGNORE_OSVERSION="yes" \
	rquery --repository="FreeBSD-base" '%n' \
		| grep -vE 'FreeBSD-.*(.*-(dbg|lib32|dev)|(bsnmp|clang|cxgbe-tools|dtrace|lld|lldb|mlx-tools|rescue|tests))$' \
		| xargs -o pkg \
			-C ${guest_root}/usr/local/etc/pkg.conf \
			-o IGNORE_OSVERSION="yes" \
			--rootdir ${guest_root} \
			install \
			--

#######################
# ADDITIONAL PACKAGES #
#######################

Installing additional packages if requested
# To see if it will work!
if [ "$additional_packages " ] ; then
pkg \
	-C ${guest_root}/usr/local/etc/pkg.conf \
		-o IGNORE_OSVERSION="yes" \
		--rootdir ${guest_root} \
		install $additional_packages || \
			{ echo Additional packages failed ; exit 1 ; }
fi

echo ; echo Generating persistent ${guest_root}/usr/local/etc/pkg/repos/FreeBSD-base.conf REPO file
cat << HERE > ${guest_root}/usr/local/etc/pkg/repos/FreeBSD-base.conf
FreeBSD-base: {
  enabled: yes
  url: "pkg+https://pkg.FreeBSD.org/\${ABI}/${abi_minor}", 
  mirror_type: "srv",
  signature_type: "fingerprints",
  fingerprints: "/usr/share/keys/pkg"
}
HERE

[ -f ${guest_root}/usr/local/etc/pkg/repos/FreeBSD-base.conf ] || \
	{ echo FreeBSD-base.conf generation failed ; exit 1 ; }

echo Moving the bootstrap FreeBSD.conf to the root directory
# Else pkg will not work upon BE boot
mv ${guest_root}/usr/local/etc/pkg/repos/FreeBSD-base.conf ${guest_root}/root/

echo Moving the bootstrap pkg.conf to the root directory
# Else pkg will not work upon BE boot
mv ${guest_root}/usr/local/etc/pkg.conf ${guest_root}/root/

echo Setting the default repo to "latest" for consistency
sed -i '' -e "s/quarterly/latest/" ${guest_root}/etc/pkg/FreeBSD.conf

echo Do you see "latest"?
cat ${guest_root}/etc/pkg/FreeBSD.conf

####################################
# SIDELOAD PERSONAL CONFIGURATIONS #
####################################

echo Copying configuration files - missing ones will fail for now
[ -f /boot/loader.conf ] && cp /boot/loader.conf ${guest_root}/boot/
#[ -f /etc/fstab ] && cp /etc/fstab ${guest_root}/etc/
touch ${guest_root}/etc/fstab
[ -f /etc/rc.conf ] && cp /etc/rc.conf ${guest_root}/etc/
[ -f /etc/sysctl.conf ] && cp /etc/sysctl.conf ${guest_root}/etc/
[ -f /etc/group ] && cp /etc/group ${guest_root}/etc/
[ -f /etc/pwd.db ] && cp /etc/pwd.db ${guest_root}/etc/
[ -f /etc/spwd.db ] && cp /etc/spwd.db ${guest_root}/etc/
[ -f /etc/master.passwd ] && cp /etc/master.passwd ${guest_root}/etc/
[ -f /etc/passwd ] && cp /etc/passwd ${guest_root}/etc/
[ -f /etc/wpa_supplicant.conf ] && \
	cp /etc/wpa_supplicant.conf ${guest_root}/etc/
# Was failing on host keys                                
cp -rp /etc/ssh/* ${guest_root}/etc/ssh/
cp -rp /root/.ssh ${guest_root}/root/

############
# VM-IMAGE #
############

echo ; echo Generating experimental /tmp/pkgbase-generate-vm-image.sh
cat << HERE > /tmp/pkgbase-generate-vm-image.sh
env TARGET=amd64 TARGET_ARCH=amd64 SWAPSIZE=1g \
	/usr/src/release/scripts/mk-vmimage.sh \
	-C /usr/src/release/tools/vmimage.subr \
	-d $guest_root \
	-F zfs \
	-i /tmp/pkgbase.raw.zfs.img \
	-s 8g -f raw \
	-S /usr/src/release/.. \
	-o /tmp/pkgbase.vm.zfs.img
HERE

# It uses the traditional toolchain...
#--------------------------------------------------------------
#>>> Installing everything started on Sat Aug 24 20:32:10 UTC 2024
#--------------------------------------------------------------
#cd /usr/src; make -f Makefile.inc1 install
# ...

# BUT, it fails to install and continues!

# ...
#Cannot install the base system to /mnt.
#ELF ldconfig path: /lib /usr/lib /usr/lib/compat /usr/local/lib
#32-bit compatibility ldconfig path:
#Creating image...  Please wait.

#Creating `/tmp/efiboot.A84GOG'
#/tmp/efiboot.A84GOG: 65528 sectors in 65528 FAT32 clusters (512 bytes/cluster)
#BytesPerSec=512 SecPerClust=1 ResSectors=32 FATs=2 Media=0xf0 SecPerTrack=63 Heads=255 HiddenSecs=0 HugeSectors=66584 FATsecs=512 RootCluster=2 FSInfo=1 Backup=2
#Populating `/tmp/efiboot.A84GOG'
#Image `/tmp/efiboot.A84GOG' complete
#Building filesystem...  Please wait.
#ZFS support is currently considered experimental. Do not use it for anything critical.
#Building final disk image...  Please wait.
#Disk image /tmp/pkgbase.vm.zfs.img created.

# It boots under bhyve!

echo ; echo To unmount the boot environment, run:
echo umount ${guest_root}/dev
echo umount ${guest_root}

# Note that bectl will not unmount <mountpoint>/dev if devfs is mounted
# bectl umount $guest_root
#cannot unmount '${guest_root}': pool or dataset is busy
#unknown error
#Failed to unmount bootenv pkgbase

exit 0

# PKG NOTES

Here are a few things I really wish I were more clear before diving into this.

This is good porting, packaging, and Poudriere documentation but a few things could be more clear to users.

Case in point: I still cannot find 'pkg prime-list' in a manual page. It just may be the single most useful pkg feature. It lists the packages you installed, not dependencies.

That said...

pkg(8) is a package for frequent updating.

/etc/pkg/FreeBSD.conf is not a pkg(8) configuration file. It is a repository file, meaning, the OS tells pkg what repository it should use. You can get fresher packages by changing "quarterly" to "latest" in the file. Note the sed(1) syntax for this above. 

Being a package itself, the pkg(8) configuration file is under /usr/local/etc:

/usr/local/etc/pkg.conf

As for the confusion of /etc/pkg/ sounding like a place for pkg(8) configuration, this is more clear in /usr/local:

/usr/local/etc/pkg/repos/FreeBSD-base.conf

Your *repos* can go in there and note the comment about disabling the default one in pkg(8).

While /etc/pkg/FreeBSD.conf has:

FreeBSD: {
  url: "pkg+https://pkg.FreeBSD.org/${ABI}/latest",

/usr/local/etc/pkg/repos/FreeBSD-base.conf has things like:

FreeBSD-base: {
  enabled: yes
  url: "pkg+https://pkg.FreeBSD.org/${ABI}/base_release_1}",

${ABI} can expand to 'FreeBSD:14:arm64' and the base_release_1 indicates the .1 in 14.1-RELEASE

CURRENT is slightly different and hopefully there is a way to manage patch levesl such as forcing use of 14.1p2 should you need to downgrade or keep systems identical for ${reasons}.

Related, putting quotation marks around "yes" will break it, also for $reasons

If you are really wanting to exercise PkgBase, consider a Varnish cache for packages to not punish the public servers.

Peace



