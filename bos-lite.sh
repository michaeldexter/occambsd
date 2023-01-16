#!/bin/sh

# (REVISED) USAGE

# BY DEFAULT USE /usr/src and /usr/ojb or take in a branch $1

branch="/usr"
#	src/
#	obj/

[ -n "$1" ] && branch="$1"

#echo DEBUG The branch is $branch - look good?
#read good

# i.e. $branch = /b/stable/13
#	src/
#	obj/
#	githash
#	gitdate

# ADDING WITHOUT_MACHDEP_OPTIMIZATIONS because of the regresion
required_options="WITHOUT_AUTO_OBJ WITHOUT_UNIFIED_OBJDIR WITHOUT_INSTALLLIB"

buildjobs="$(sysctl -n hw.ncpu)"

#[ -d "/b/HTML" ] || mkdir -p /b/HTML

#[ -f lib_occambsd.sh ] || \
#	{ echo lib_occambsd.sh not found ; exit 1 ; }

#echo Sourcing lib_occambsd.sh
#. lib_occambsd.sh || \
#	{ echo lib_occambsd.sh failed to source ; exit 1 ; }


echo Generating all_options.txt
#f_occam_options $branch/src "$required_options" \
#	> $branch/src.conf || \
#	{ echo $branch/src.conf generation failed ; exit 1 ; }

allopts=$( make -C $branch/src showconfig __MAKE_CONF=/dev/null SRCCONF=/dev/null \
		| sort \
		| sed '
			s/^MK_//
			s/=//
		' | awk '
		$2 == "yes"	{ printf "WITHOUT_%s=YES\n", $1 }
		$2 == "no"	{ printf "WITH_%s=YES\n", $1 }
		'
	)

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

	\time -h env MAKEOBJDIRPREFIX=$branch/obj \
		make -C $branch/src -j$buildjobs \
		SRCCONF=$branch/without_src.conf buildworld \
			> $branch/${git_date}-WITHOUT.log || status="failed"
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
