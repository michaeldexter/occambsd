#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause-FreeBSD
#
# Copyright 2023 Michael Dexter
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

# Version v0.1

[ "$( id -u ) -ne 0 ] && \
        { echo "Must be excuted with root privileges" ; exit 1 ; }

if [ "$0" = "rc.local" ] ; then
	DESTDIR="/"
	echo "Beginning rc.local idempotent system configuration"
	logger "Beginning rc.local idempotent system configuration"
else
	echo ; echo "Enter directory path to configure: ( / for host system )"
	read DESTDIR
	[ -d "$DESTDIR" ] || { echo "Directory $DESTDIR not found" ; exit 1 ; }
	echo ; echo "ABOUT TO CONFIGURE $DESTDIR" ; echo
	echo ; echo "ARE YOU SURE YOU WANT TO CONTINUE?"
	echo -n "(y/n): " ; read continue
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
# Validate the name first? You probably cannot have an apostrophe in it...

hostname="current"
if [ "$( sysrc -c -R $DESTDIR hostname=$hostname )" ] ; then
	echo "Hostname is correct"
	logger "Hostname is correct"
else
	echo ; echo Changing hostname to $hostname
	sysrc -R $DESTDIR hostname="$hostname"
	service hostname restart
fi


# MOUSE DAEMON

if [ "$( sysrc -c -R $DESTDIR moused_enable=YES )" ] ; then
	echo "Mouse daemon is already enabled"
	logger "Mouse daemon is already enabled"
else
	echo ; echo "Enabling mouse daemon"
	sysrc -R $DESTDIR moused_enable=YES
	service moused restart
fi


# NETWORK TIME DAEMONS

if [ "$( sysrc -c -R $DESTDIR ntpdate_enable=YES )" ] ; then
	echo "NTP Date daemon is already enabled"
	logger "NTP Date daemon is already enabled"
else
	echo ; echo "Enabling NTP Date daemon"
	sysrc -R $DESTDIR ntpdate_enable=YES
	service ntpdate restart
fi

if [ "$( sysrc -c -R $DESTDIR ntpd_enable=YES )" ] ; then
	echo "NTP daemon is already enabled"
	logger "NTP daemon is already enabled"
else
	echo ; echo "Enabling NTP daemon"
	sysrc -R $DESTDIR ntpd_enable=YES
	service ntpd restart
fi


# CRASH DUMP DEVICE

if [ "$( sysrc -c -R $DESTDIR dumpdev=AUTO )" ] ; then
	echo "Dump device is already configured"
	logger "Dump device is already configured"
else
	echo ; echo "Configuring dump device"
	sysrc -R $DESTDIR dumpdev=AUTO
	service dumpon restart
fi


# Verbose my foot. Show what is really happening!

# consider set -x for KRAKKEN MODE


# loader.conf
# loader.conf: Note that sysrc will not create loader.conf if asked to modify it

[ -f "${DESTDIR}/boot/loader.conf" ] || touch ${DESTDIR}/boot/loader.conf

if ! [ -f "${DESTDIR}/boot/loader.conf" ] ; then
	echo "touch ${DESTDIR}/boot/loader.conf failed"
	logger "touch ${DESTDIR}/boot/loader.conf failed"
	exit 1
fi


# AUTOBOOT DELAY

if [ "$( sysrc -c -f ${DESTDIR}/boot/loader.conf autoboot_delay=5 )" ] ; then
	echo "Autoboot delay is already configured"
	logger "Autoboot delay is already configured"
else
	echo ; echo "Configuring autoboot delay"
	sysrc -f ${DESTDIR}/boot/loader.conf autoboot_delay=5
fi


# VERBOSE LOADING

if [ "$( sysrc -c -f ${DESTDIR}/boot/loader.conf verbose_loading=YES )" ] ; then
	echo "Verbose loading is already configured"
	logger "Verbose loading is already configured"
else
	echo ; echo "Configuring verbose loading"
	sysrc -f ${DESTDIR}/boot/loader.conf verbose_loading=YES
fi


# VERBOSE BOOTING

#if [ "$( sysrc -c -f ${DESTDIR}/boot/loader.conf boot_verbose=YES )" ] ; then
#	echo "Verbose boot is already configured"
#	logger "Verbose boot is already configured"
#else
#	echo ; echo "Configuring verbose boot"
#	sysrc -f ${DESTDIR}/boot/loader.conf boot_verbose=YES
#fi


# END IDEMPOTENCE

echo LEAVING THE IDEMPOTENCE ZONE


# ROOT PASSWORD

# REALLY WANT A HASH-BASED STRATEGY
# STRATEGY TO IDEMPOTENTLY test a password before setting?
# How would one backup all all related files?

root_password="freebsd"
echo "Setting root password with pw"
logger "Setting root password with pw"
echo "$root_password" | pw -R $DESTDIR usermod -n root -h 0

# Some observations
#echo "$root_password" | pw usermod -n root -h 0
#root:$6$Llmi2FQ2wo.2IgPb$NeMYls203jVV9H5Q.qc7bBotET6AzpBlxGItDBKauHOkVySgXih.fGv6qtKOtSoMLh5/8zqIfJUbVNAr3mlJ91:0:0::0:0:Charlie &:/root:/bin/sh
# https://forums.freebsd.org/threads/how-to-generate-the-hashes-in-etc-master-passwd.78940/


# Consider firstboot

#echo ; echo Touching /firstboot
#touch /media/firstboot


# PERMIT ROOT SSH LOGIN

# Ideally distinguish bewteen the line being enabled, and the specific configuration
# "yes" is not the only option IIRC
if [ "$( grep -q "PermitRootLogin yes" ${DESTDIR}/etc/ssh/sshd_config )" ] ; then
	echo "PermitRootLogin is already set to yes"
	logger "PermitRootLogin is already set to yes"
else
	echo ; echo "Setting PermitRootLogin yes"
	sed -i '' -e "s/#PermitRootLogin no/PermitRootLogin yes/" \
	${DESTDIR}/etc/ssh/sshd_config
fi


# Secure Shell Daemon (Already idempotent)

if [ "$( sysrc -c -R $DESTDIR sshd_enable=YES )" ] ; then
	echo "Secure shell daemon is already enabled"
	logger "Secure shell daemon is already enabled"
else
	echo ; echo "Enabling secure shell daemon"
	sysrc -R $DESTDIR sshd_enable=YES
	# restart will NOT work on first use
	service sshd stop ; service sshd start
fi


# PACKAGES - NETWORKING REQUIRED

# PERFORM A PACKAGE UPGRADE?
# REMOVE UNDESIRED PACKAGES?
# NOTE THAT PKG WILL SNIFF FOR A DIFFERENT OS VERSION

package_list="tmux rsync smartmontools fio git-lite iperf3"

echo Installing Packages
logger Installing Packages
pkg -r $DESTDIR install -y $package_list

exit 0
