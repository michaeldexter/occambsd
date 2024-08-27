#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause-FreeBSD
#
# Copyright 2023, 2024 Michael Dexter
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

# Version v0.3

# USER VARIABLES

hostname="nassense"
root_password="freebsd"
user_username="dexter"
user_password="freebsd"
#timezone="UTC"
timezone="America/Los_Angeles"
# Would be nice to validate that input

#package_list="gdb tmux rsync git-lite
package_list="gdb tmux rsync cmdwatch smartmontools e2fsprogs fusefs-ntfs minio minio-client git-lite fio iozone iperf3 dmidecode samba419 samba-nsupdate ldb22 bind-tools"
# rclone rclone-browser ddrescue clonehdd
# TrueNAS: net-snmp netatalk3 pciutils sg3_utils sedutil openseachest smp_utils trafshow fusefs-ntfs fusefs-s3fs


[ "$( id -u )" -ne 0 ] && \
        { echo "Must be excuted with root privileges" ; exit 1 ; }

# Work automaticaly in /etc/rc.local, with a provided path, or interactively
if [ "$1" ] ; then
	[ -d "${1}/etc" ] || { echo "$1 must be a root path" ; exit 1 ; }
	DESTDIR="$1"
elif [ "$0" = "rc.local" ] ; then
	DESTDIR="/"
	echo "Beginning rc.local idempotent system configuration"
	logger "Beginning rc.local idempotent system configuration"
else
	echo ; echo "Enter directory path to configure: \( / for host system \)"
	read DESTDIR
	[ -d "$DESTDIR" ] || { echo "Directory $DESTDIR not found" ; exit 1 ; }
	echo ; echo "ABOUT TO CONFIGURE $DESTDIR" ; echo
	echo ; echo "ARE YOU SURE YOU WANT TO CONTINUE?"
	echo -n "\(y/n\): " ; read continue
	[ "$continue" = "y" -o "$continue" = "n" ] || { echo Invalid input ; exit 1 ; }
	[ "$continue" = "n" ] && { echo "Exiting" ; exit 0 ; }
fi

sh -n $( pwd )/$0

if [ "$?" -ne "0" ] ; then
	echo "Configuration script $0 failed to validate"
	logger "Configuration script $0 failed to validate"
	exit 1
fi


# HOSTNAME
# Validate the name first? You probably do not want an apostrophe in it...

if [ "$( sysrc -c -R $DESTDIR hostname=$hostname )" ] ; then
	echo "Hostname $hostname is correct"
	logger "Hostname $hostname is correct"
else
	echo ; echo "Changing hostname to $hostname"
	logger "Changing Hostname to $hostname"
	sysrc -R $DESTDIR hostname="$hostname"
	# Not helpful for an specified directory
	service hostname restart
fi


# TIME ZONE

current_timezone=$( cat $DESTDIR/var/db/zoneinfo )

if [ ! "$current_timezone" = "$timezone" ] ; then
	tzsetup -C $DESTDIR $timezone
fi

# MOUSE DAEMON

if [ "$( sysrc -c -R $DESTDIR moused_enable=YES )" ] ; then
	echo "Mouse daemon is enabled"
	logger "Mouse daemon is enabled"
else
	echo ; echo "Enabling mouse daemon"
	logger "Enabling mouse daemon"
	sysrc -R $DESTDIR moused_enable=YES
	service moused restart
fi


# NETWORK TIME DAEMONS

if [ "$( sysrc -c -R $DESTDIR ntpdate_enable=YES )" ] ; then
	echo "NTP Date daemon is enabled"
	logger "NTP Date daemon is enabled"
else
	echo ; echo "Enabling NTP Date daemon"
	logger "Enabling NTP Date daemon"
	sysrc -R $DESTDIR ntpdate_enable=YES
	service ntpdate restart
fi

if [ "$( sysrc -c -R $DESTDIR ntpd_enable=YES )" ] ; then
	echo "NTP daemon is enabled"
	logger "NTP daemon is enabled"
else
	echo ; echo "Enabling NTP daemon"
	logger "Enabling NTP daemon"
	sysrc -R $DESTDIR ntpd_enable=YES
	service ntpd restart
fi


# SECURE SHELL DAEMON

if [ "$( sysrc -c -R $DESTDIR sshd_enable=YES )" ] ; then
	echo ; echo "Verifying if secure shell daemon is enabled"
	logger "Verifying if secure shell daemon is enabled"
else
	echo ; echo "Enabling secure shell daemon"
	logger "Enabling secure shell daemon"
	sysrc -R $DESTDIR sshd_enable=YES
	# restart will NOT work on first use
	service sshd stop ; service sshd start
fi


# CRASH DUMP DEVICE

if [ "$( sysrc -c -R $DESTDIR dumpdev=AUTO )" ] ; then
	echo "Dump device is configured"
	logger "Dump device is configured"
else
	echo ; echo "Configuring dump device"
	logger "Configuring dump device"
	sysrc -R $DESTDIR dumpdev=AUTO
	service dumpon restart
fi


# Verbose my foot. Show what is really happening!

# Add 'set -x' to rc.conf for KRAKKEN MODE


# loader.conf: sysrc will not create loader.conf if asked to modify it

[ -f "${DESTDIR}/boot/loader.conf" ] || touch ${DESTDIR}/boot/loader.conf

if ! [ -f "${DESTDIR}/boot/loader.conf" ] ; then
	echo "touch ${DESTDIR}/boot/loader.conf failed"
	logger "touch ${DESTDIR}/boot/loader.conf failed"
	exit 1
fi


# AUTOBOOT DELAY

if [ "$( sysrc -c -f ${DESTDIR}/boot/loader.conf autoboot_delay=5 )" ] ; then
	echo ; echo "Verifying autoboot of $autoboot_delay"
	logger "Verifying autoboot of $autoboot_delay"
else
	echo ; echo "Configuring autoboot delay"
	logger "Configuring autoboot delay"
	sysrc -f ${DESTDIR}/boot/loader.conf autoboot_delay=5
fi


# VERBOSE LOADING

if [ "$( sysrc -c -f ${DESTDIR}/boot/loader.conf verbose_loading=YES )" ] ; then
	echo ; echo "Verifying verbose loading"
	logger "Verifying verbose loading"
else
	echo ; echo "Enabling verbose loading"
	logger "Enabling verbose loading"
	sysrc -f ${DESTDIR}/boot/loader.conf verbose_loading=YES
fi


# VERBOSE BOOTING

#if [ "$( sysrc -c -f ${DESTDIR}/boot/loader.conf boot_verbose=YES )" ] ; then
#	echo ; echo "Verbose boot is configured"
#	logger "Verbose boot is configured"
#else
#	echo ; echo "Enabling verbose boot"
#	sysrc -f ${DESTDIR}/boot/loader.conf boot_verbose=YES
#fi


# END IDEMPOTENCE

echo LEAVING THE IDEMPOTENCE OPTIONS


# ROOT PASSWORD

# REALLY WANT A HASH-BASED STRATEGY
# STRATEGY TO IDEMPOTENTLY test a password before setting?
# How would one backup all all related files?

echo "Setting root password with pw"
logger "Setting root password with pw"
echo "$root_password" | pw -R "$DESTDIR" usermod -n root -h 0

# Some observations
#echo "$root_password" | pw usermod -n root -h 0
#root:$6$Llmi2FQ2wo.2IgPb$NeMYls203jVV9H5Q.qc7bBotET6AzpBlxGItDBKauHOkVySgXih.fGv6qtKOtSoMLh5/8zqIfJUbVNAr3mlJ91:0:0::0:0:Charlie &:/root:/bin/sh
# https://forums.freebsd.org/threads/how-to-generate-the-hashes-in-etc-master-passwd.78940/


# ADD USER

# -n(ame) -s(hell) -m(ake home directory)
pw useradd -R $DESTDIR -n $user_username -g wheel -s /bin/sh -m
echo "$user_password" | pw -R "$DESTDIR" usermod -n "$user_usernane" -h 0


# Consider firstboot

#echo ; echo Touching /firstboot
#touch /media/firstboot


# PERMIT ROOT SSH LOGIN

# Ideally distinguish bewteen the line being enabled vs. custom configuration
# "The argument must be yes, prohibit-password, forced-commands-only, or no."

# Test appears to failing idempotence
if [ "$( grep -q "PermitRootLogin yes" ${DESTDIR}/etc/ssh/sshd_config )" ] ; then
	echo ; echo "Verifying PermitRootLogin"
	logger "Verifying PermitRootLogin"
else
	echo ; echo "Setting PermitRootLogin yes"
	sed -i '' -e "s/#PermitRootLogin no/PermitRootLogin yes/" \
	${DESTDIR}/etc/ssh/sshd_config
fi


# SET PACKAGE REPO TO LATEST

# Test appears to failing idempotence
if [ "$( grep -q "latest" ${DESTDIR}/etc/pkg/FreeBSD.conf )" ] ; then
	echo ; echo "Verifying Package Branch"
	logger "Verifying Package Branch"
else
	echo ; echo "Setting Package Branch to latest"
	sed -i '' -e "s/quarterly/latest/" \
	${DESTDIR}/etc/pkg/FreeBSD.conf
fi


# PACKAGES - NETWORKING REQUIRED

# PERFORM A PACKAGE UPGRADE?
# REMOVE UNDESIRED PACKAGES?
# NOTE THAT PKG WILL SNIFF FOR A DIFFERENT OS VERSION AND ARCHITECTURE

echo Installing Packages
logger Installing Packages
pkg -r $DESTDIR install -y $package_list

exit 0
