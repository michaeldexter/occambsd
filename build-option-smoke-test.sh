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

f_usage() {
        echo "USAGE:"
	echo "-s <source directory override>"
	echo "-o <object directory override>"
	echo "-a(dd) \"WITH_OPTION1 WITH_OPTION2\""
	echo "-r(emove) \"WITHOUT_OPTION1 WITHOUT_OPTION2\""
        exit 1
}


# EXAMPLE USAGE

# \time -h sh build-option-smoke-test.sh -s "/b/releng/13.1/src"


# DEFAULT VARIABLES

SRC_DIR="/usr/src"			# Can be overridden with -s <dir>
OBJ_DIR="/usr/obj"			# Can be overridden with -o <dir>
BUILD_JOBS="$(sysctl -n hw.ncpu)"
EPOCH_DATE=$( date "+%s" )
SRC_CONF="/tmp/${EPOCH_DATE}-SRC_CONF.txt"
BUILD_LOG="/tmp/${EPOCH_DATE}-BUILD_LOG.txt"
REQUIRED_OPTIONS="WITHOUT_AUTO_OBJ WITHOUT_UNIFIED_OBJDIR WITHOUT_INSTALLLIB"

# INTRODUCTION

# FreeBSD includes 200+ build options that determine what base/world components are built
# during 'make buildworld', plus optional, often experimental components.

# Adding WITHOUT_VI=YES to /etc/src.conf builds world without the vi text editor.

# Adding WITH_BEARSSL=YES to /src/src.conf will include the optional BearSSL in buildworld.

# WHAT THIS DOES

# By default this produces a src.conf that includes every viable WITHOUT_ build option,
# which will build a minimum world/userland. Three options are required for the build
# to succeed, and they are added back to the build by removing them from the list.

# This "default minimum" can have "WITH_" options added manually with -a, or have
# "WITHOUT_" options removed with -r, causing them to be built.

# 1. Build a list of all available WITHOUT_ and WITH_ build options
# 2. Remove all WITH_* options from the list of all options leaving only "WITHOUT_" options
# 3. Remove the options from that list that are required to build the OS
# 4. Optionally add WITH_* options, using -a "WITH_OPTION ..."
# 5. Optionally remove automatically-excluded WITHOUT_* options to include them in the build

while getopts s:o:a:r: opts ; do
	case $opts in
	s)
		# Override source directory
		SRC_DIR="${OPTARG}"
		[ -d "$SRC_DIR" ] || { echo "Source directory $SRC_DIR not found" ; exit 1 ; }
		;;
	o)
		# Override source directory
		OBJ_DIR="${OPTARG}"
		[ -d "$OBJ_DIR" ] || { echo "Object directory $OBJ_DIR not found" ; exit 1 ; }
		;;
	a)
		# Additional WITH_ options
		ADD_OPTIONS="${OPTARG}"
		;;
	r)
		# Removed WITHOUT_ options
		REMOVED_OPTIONS="${OPTARG}"
		;;
	*)
		f_usage
		exit 1
		;;
	esac
done


# PREFLIGHT

[ -f $SRC_DIR/sys/amd64/conf/GENERIC ] || \
	{ echo "FreeBSD sources not found in $SRC_DIR" ; exit 1 ; }


# TASTE FOR GIT

IS_GIT="no"
git -C $SRC_DIR rev-parse HEAD > /dev/null 2>&1 && IS_GIT="yes"

if [ "$IS_GIT" = "yes" ] ; then
	#GIT_HASH="$( git -C $SRC_DIR log --format="%H" | head -1 )"
	GIT_HASH="$( git -C $SRC_DIR rev-parse HEAD )"
	# Similar better way?
	GIT_DATE="$( git -C $SRC_DIR log --format="%ad" \
		--date=raw | head -1 | cut -d " " -f1)"
	# Override the date
	EPOCH_DATE="$GIT_DATE"
fi


# SRC.CONF

# Comment out for fully machine-readable output that will only provide a return value
echo ; echo "Generating $SRC_CONF"

# ALL_OPTIONS is space delimited and each option is appended with "=YES"
ALL_OPTIONS=$( make -C $SRC_DIR showconfig \
	__MAKE_CONF=/dev/null SRCCONF=/dev/null \
	| sort \
	| sed '
		s/^MK_//
		s/=//
	' | awk '
	$2 == "yes"	{ printf "WITHOUT_%s=YES\n", $1 }
	$2 == "no"	{ printf "WITH_%s=YES\n", $1 }
	'
)

# This step converts to newline delimited for grep to work
# Prune WITH_ options leaving only WITHOUT_ build options
IFS=" "
WITHOUT_OPTIONS="$( echo $ALL_OPTIONS | grep -v WITH_ )"


# REQUIRED_OPTIONS and REMOVED_OPTIONS are space delimited
if [ -n "$REMOVED_OPTIONS" ] ; then
	# Add the "removed" options to the required options to include them in the build
	REQUIRED_OPTIONS="$REQUIRED_OPTIONS $REMOVED_OPTIONS"
fi


# Remove the required options with grep -v
IFS=" "
for OPTION in $REQUIRED_OPTIONS ; do
	WITHOUT_OPTIONS="$( echo $WITHOUT_OPTIONS | grep -v $OPTION )"
done


# Generate src.conf
echo $WITHOUT_OPTIONS > $SRC_CONF


# Add requested WITH_ options to src.conf
if [ -n "$ADD_OPTIONS" ] ; then
	IFS=" "
	for OPTION in $ADD_OPTIONS ; do
		echo "${OPTION}=YES" >> $SRC_CONF
	done
fi

# Comment out for fully machine-readable output that will only provide a return value
echo ; echo "The generated $SRC_CONF reads:" ; echo
cat $SRC_CONF


# Comment out for fully machine-readable output that will only provide a return value
echo ; echo "Building world - logging to $BUILD_LOG"

STATUS="success"

env MAKEOBJDIRPREFIX=$OBJ_DIR make -C $SRC_DIR \
	-j$BUILD_JOBS SRCCONF=$SRC_CONF buildworld \
	> $BUILD_LOG || STATUS="failed"

# TAB-DELIMITED MACHINE-READABLE OUTPUT


# OPTIONAL HUMAN-FRIENDLY DATE

#EPOCH_DATE="$( date -r $EPOCH_DATE '+%Y-%m-%d:%H:%M:%S' )"
EPOCH_DATE="$( date -r $EPOCH_DATE '+%Y-%m-%d' )"


if [ "$IS_GIT" = "yes" ] ; then
	echo "$EPOCH_DATE	$GIT_HASH	$BUILD_LOG	$STATUS"
else
	echo "$EPOCH_DATE	$BUILD_LOG	$STATUS"
fi

if [ "$STATUS" = "success" ] ; then
	# return 0
	exit 0
else
	# return 1
	exit 1
fi

# Consider adding 'git -C $SRC_DIR branch' to show the git branch but remove "* "
