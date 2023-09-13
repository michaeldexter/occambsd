#!/bin/sh

# BUGS
#--- read.o ---
#/b/main/src/contrib/mandoc/read.c:40:10: fatal error: 'zlib.h' file not found
#include <zlib.h>


# (REVISED) USAGE

# BY DEFAULT USE /usr/src and /usr/ojb or take in a branch $1

branch="/usr"

#	src/
#	obj/

[ -n "$1" ] && branch="$1"

[ -f "${branch}/src/Makefile" ] || \
	{ echo "branch ${branch}/src not found" ; exit 1 ; }

# i.e. $branch = /b/stable/13
#	src/
#	obj/
#	githash
#	gitdate

# ADDING WITHOUT_MACHDEP_OPTIMIZATIONS because of the regresion
required_options="WITHOUT_AUTO_OBJ WITHOUT_UNIFIED_OBJDIR WITHOUT_INSTALLLIB"


#[ -d "/b/HTML" ] || mkdir -p /b/HTML

#[ -f lib_occambsd.sh ] || \
#	{ echo lib_occambsd.sh not found ; exit 1 ; }

#echo Sourcing lib_occambsd.sh
#. lib_occambsd.sh || \
#	{ echo lib_occambsd.sh failed to source ; exit 1 ; }

case $( uname -s ) in
	FreeBSD)
		buildjobs="$(sysctl -n hw.ncpu)"
		allopts=$( make -C $branch/src showconfig __MAKE_CONF=/dev/null SRCCONF=/dev/null )
	;;
	Linux)
		buildjobs="$(nproc)"

# which cc, clang, and llvm give nothing
# which cpp does
# NOTE THE 11 or 13!
#sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/clang++ 100
#update-alternatives --install /usr/bin/cc cc /usr/bin/clang-11 100
#update-alternatives --install /usr/bin/c++ c++ /usr/bin/clang++-11 100
#update-alternatives --install /usr/bin/cpp cpp /usr/bin/clang++-11 100

# make XCC=/usr/local/bin/clang XCXX=/usr/local/bin/clang++ XCPP=/usr/local/bin/clang-cpp buildworld

# MOST I HAVE SEEN
# https://maskray.me/blog/2021-08-22-freebsd-src-browsing-on-linux-and-my-rtld-contribution

# HOLY CRAP WORKS
#env MAKEOBJDIRPREFIX=/b/main/obj env XCC=/usr/bin/clang-11 env XCXX=/usr/bin/clang++-11 env XCPP=/usr/bin/clang-cpp-11 XLD=/usr/bin/lldb-11 /b/main/src/tools/build/make.py buildworld TARGET=amd64 TARGET_ARCH=amd64 MACHINE_ARCH=amd64

# MORE
#env MAKEOBJDIRPREFIX=/b/main/obj env XCC=/usr/bin/clang-11 env XCXX=/usr/bin/clang++-11 env XCPP=/usr/bin/clang-cpp-11 env XLD=/usr/bin/lldb-11 /b/main/src/tools/build/make.py -j 16 buildworld TARGET=amd64 TARGET_ARCH=amd64 MACHINE_ARCH=amd64 SRCCONF=/b/main/without

# AGAIN YEP, need to env them or... --cross-bindir= (no workie)
#env MAKEOBJDIRPREFIX=/b/main/obj /b/main/src/tools/build/make.py -j 16 buildworld SRCCONF=/b/main/without TARGET=amd64 TARGET_ARCH=amd64 MACHINE_ARCH=amdenv 64 XCC=/usr/bin/clang-11 XCXX=/usr/bin/clang++-11 XCPP=/usr/bin/clang-cpp-11 XLD=/usr/bin/lldb-11

#env MAKEOBJDIRPREFIX=/b/main/obj env XCC=/usr/bin/clang-11 env XCXX=/usr/bin/clang++-11 env XCPP=/usr/bin/clang-cpp-11 env XLD=/usr/bin/lldb-11 /b/main/src/tools/build/make.py -j 16 buildworld SRCCONF=/b/main/without TARGET=amd64 TARGET_ARCH=amd64 MACHINE_ARCH=amd64

# FAILS ON bmake[4]: "/b/main/src/lib/libc/Makefile" line 195: amd64 libc requires linker ifunc support
#env MAKEOBJDIRPREFIX=/b/main/obj env XCC=/usr/bin/clang-13 env XCXX=/usr/bin/clang++-13 env XCPP=/usr/bin/clang-cpp-13 env XLD=/usr/bin/lldb-13 /b/main/src/tools/build/make.py -j 16 buildworld SRCCONF=/b/main/without TARGET=amd64 TARGET_ARCH=amd64 MACHINE_ARCH=amd64

# Verify without_src.conf generation




# LOOKS LIKE SRCCONF WAS NOT RESPECTED BUT /ETC/SRC.CONF MIGHT WORK, MAYBE ENV
# Not sure we need machine arch
#USING --bootstrap-toolchain
# NOT SURE HOW MANY ALTERNATIVES ARE NEEDED FOR THIS
env MAKEOBJDIRPREFIX=/b/main/obj /b/main/src/tools/build/make.py --bootstrap-toolchain /b/main/src/tools/build/make.py -j 16 buildworld SRCCONF=/b/main/without_src.conf TARGET=amd64 TARGET_ARCH=amd64 MACHINE_ARCH=amd64 -j 16 buildworld SRCCONF=/b/main/without TARGET=amd64 TARGET_ARCH=amd64 MACHINE_ARCH=amd64 > /b/main/cross-build-log.txt

# WTF

#time env MAKEOBJDIRPREFIX=/b/main/obj env SRCCONF=/b/main/without_src.conf /b/main/src/tools/build/make.py --bootstrap-toolchain /b/main/src/tools/build/make.py -j 16 buildworld SRCCONF=/b/main/without_src.conf TARGET=amd64 TARGET_ARCH=amd64 MACHINE_ARCH=amd64 -j 16 buildworld SRCCONF=/b/main/without_src.conf TARGET=amd64 TARGET_ARCH=amd64 COMPILER_TYPE=clang > /b/main/cross-build-log2.txt



#Trying 13.2

#root@pve:/b/releng/13.2# time env MAKEOBJDIRPREFIX=/b/releng/13.2/obj env SRCCONF=/b/releng/13.2/without_src.conf /b/releng/13.2/src/tools/build/make.py --bootstrap-toolchain /b/main/src/tools/build/make.py -j 16 buildworld SRCCONF=/b/releng/13.2/without_src.conf TARGET=amd64 TARGET_ARCH=amd64 MACHINE_ARCH=amd64 -j 16 buildworld SRCCONF=/b/releng/13.2/without_src.conf TARGET=amd64 TARGET_ARCH=amd64 COMPILER_TYPE=clang > /b/releng/13.2/cross-build-log2.txt


#Failed tests: opt-debug-x-trace
#*** Error code 1
#Stop.
#bmake[1]: stopped in /b/releng/13.2/src/contrib/bmake/unit-tests
#*** Error code 1







# apt install clang-11 llvm-11 lldb-11 libarchive-dev libbz2-dev bmake
	which bmake || { echo "bmake not found" ; exit 1 ; }
	which cc || { echo "cc not found" ; exit 1 ; }

		allopts=$( bmake -C $branch/src showconfig __MAKE_CONF=/dev/null SRCCONF=/dev/null COMPILER_TYPE=foo TARGET=amd64 MACHINE_ARCH=amd64 )
	;;
esac

echo DEBUG branch is $branch





echo Generating all_options.txt
#f_occam_options $branch/src "$required_options" \
#	> $branch/src.conf || \
#	{ echo $branch/src.conf generation failed ; exit 1 ; }

allopts=$( $allopts | sort | sed '
			s/^MK_//
			s/=//
		' | awk '
		$2 == "yes"	{ printf "WITHOUT_%s=YES\n", $1 }
		$2 == "no"	{ printf "WITH_%s=YES\n", $1 }
		' )

echo DEBUG did the alltops processing work?

echo $allopts | tail

read allops

# STEP ONE COLLECT ALL OPTIONS LIKE BOS listallopts.sh does

# Set the IFS to space or you will not get carriage returns
	IFS=" "
	echo $allopts > $branch/all_options.txt
	tail -10 $branch/all_options.txt

	IFS=" "
	for exclusion in $required_options ; do
		allopts=$( echo $allopts | grep -v $exclusion )
	done

	echo $allopts > $branch/valid_options.txt


# STEP TWO grep -v out the WITH_ options for the WITHOUT_ build

	echo $allopts | grep -v "WITH_" > $branch/without_src.conf
	echo $allopts | grep -v "WITHOUT_" > $branch/with_src.conf

	echo DEBUG tailing $branch/without_src.conf
	tail $branch/without_src.conf

	status="success"
	start_time=$( date +%s )

# MOVED THE LOGGING FROM /b/HTML/

git_date=$( cat $branch/gitdate )
git_hash=$( cat $branch/lasthash )

echo Building WITHOUT_ world - logging to $branch/${git_date}-WITHOUT.log


# MOVED THE LOG DIRECTORY

case $( uname -s ) in
	FreeBSD)
		\time -h env MAKEOBJDIRPREFIX=$branch/obj \
			make -C $branch/src -j$buildjobs \
			SRCCONF=$branch/without_src.conf buildworld \
			> $branch/${git_date}-WITHOUT.log || status="failed"
	;;
	Linux)
#env MAKEOBJDIRPREFIX=/b/main/obj /b/main/src/tools/build/make.py  buildworld TARGET=amd64 TARGET_ARCH=amd64 MACHINE_ARCH=amd64
#Could not infer value for $CC: /usr/bin/cc does not exist

		# --bootstrap-toolchain to bootstrap the native toolchain
# NOPE
export PATH=$PATH:/usr/bin/clang-11:/usr/bin/clang++-11
#		export CMAKE_C_COMPILER=clang-11
#		export CMAKE_CXX_COMPILER=clang++-11
		\time env MAKEOBJDIRPREFIX=$branch/obj \
		$branch/src/tools/build/make.py \
		TARGET=amd64 TARGET_ARCH=amd64 MACHINE_ARCH=amd64 \
			> $branch/${git_date}-WITHOUT.log || status="failed"
	;;
esac



	end_time=$( date +%s )

	build_time=$(( $end_time - $start_time ))

	echo build_time is $build_time

# Remove the directory prefix /b/ from the branch
# The user may have nested it, which will fail

printbranch=$( echo ${branch#/*/} )

	echo Build results:
	echo "$git_date	$printbranch	$git_hash	$build_time	WITHOUT	$status"

	echo "$git_date	$printbranch	$git_hash	$build_time	WITHOUT	$status" \
		> $branch/bos-lite-latest.log
#		>> /b/bos-lite.log

exit 0
