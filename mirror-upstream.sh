#!/bin/sh

# Set the zpool you will be operating from
# Make this a command line argument and prompt if not entered
_zp="zroot"

[ -n "$1" ] && _zp="$1"

# Layout

# /b/MAIN/src.git	Local Git repo mirror
# /b/main		main/CURRENT/HEAD checkout
# /b/releng		Releases, i.e. /b/releng/13.0
# /b/stable		MFM branches, i.e. /b/stable/13


#git_upstream="https://git.freebsd.org/src.git"
# git -C /b/MAIN clone --mirror https://git.freebsd.org/src.git
# Paths not fully deduplicated
git_server="file:///b/MAIN/src.git"
H="/b/HTML/index.html"

branches="main
stable/12
stable/13
releng/13.1
releng/13.2"

# No easy way to do architectures. Thank you arm64.aarch64.

[ $( which git ) ] || { echo git not found ; exit 1 ; }

zpool get name $_zp > /dev/null 2>&1 || \
	{ echo "zpool $_zp not found, specify the active pool" ; exit 1 ; }

echo Checking for $_zp/b/MAIN/src.git
main_missing=1
# Trusting a return value of 0
zfs get name $_zp/b/MAIN/src.git > /dev/null 2>&1
main_missing=$?
if [ "$main_missing" = "1" ] ; then
	echo $_zp/b/MAIN/src.git does not exist. Creating
	zfs create -o mountpoint=/b $_zp/b || \
		{ echo $_zp/b failed to create ; exit 1 ; }
	zfs create -p $_zp/b/MAIN/src.git || \
		{ echo $_zp/b/MAIN/src.git failed to create ; exit 1 ; }
#	zfs list|grep MAIN ; echo ; echo Look good? ; read good

	echo Checking out git.freebsd.org/src.git
\time -h git -C /b/MAIN clone --mirror https://git.freebsd.org/src.git || \
	{ echo Initial clone checkout failed ; exit 1 ; }
fi

# Deduplicate path...
echo ; echo Updating MAIN mirror
git -C /b/MAIN/src.git remote update || { echo MAIN update failed; exit 1 ; }

echo ; echo Stepping through the Branches
for _br in $branches ; do

	echo Processing $_br

############################################################
### Would be wise to reset the branch-specific variables ###
# Note that some are set in context, which may be wise for all of them
############################################################

	echo DEBUG testing for /b/$_br/src
# Might want to silence the output for when the test fails
	branch_validation=1
	if [ -d "/b/$_br/src" ] ; then
#		validation="$( git -C /b/$_br/src branch | cut -c 3- )"
validation="$( git -C /b/$_br/src branch --format='%(refname:short)' )"

		echo DEBUG comparing $_br to $validation

		if [ "$_br" = "$validation" ] ; then
			echo $_br validation passed
			branch_validation=0
		fi
	fi

	echo DEBUG testing if "$branch_validation" = "1"
	if [ "$branch_validation" = "1" ] ; then
		echo $_br validation failed, scortching earth

		zfs get -H name "$_zp/b/$_br" > /dev/null && \
			zfs destroy -rf "$_zp/b/$_br"
#			[ $? =  0 ] || { echo zfs destroy failed ; exit 1 ; }

		echo Creating "$_zp/b/$_br"
		zfs create -p "$_zp/b/$_br/src" || \
			{ echo zfs create src failed ; exit 1 ; }

		zfs create -p "$_zp/b/$_br/obj" || \
			{ echo zfs create obj failed ; exit 1 ; }

		echo Cloning /b/MAIN/src.git to /b/$_br/src with git -C /b/$_br/ clone -b $_br $git_server
		git -C /b/$_br/ clone -b $_br $git_server || \
			{ echo git clone failed ; exit 1 ; }

		echo Snapshotting /b/$_br/src@cloned dataset
		zfs snap $_zp/b/$_br/src@cloned || \
			{ echo zfs snapshot src@cloned failed ; exit 1 ; }

		echo Snapshotting /b/$_br/obj@empty dataset
		zfs snap $_zp/b/$_br/obj@empty || \
			{ echo zfs snapshot obj@empty failed ; exit 1 ; }
	fi # End if branch does not exist

	# Roll back the object directory
	echo Rolling back $_zp/b/$_br/obj
	zfs rollback -r $_zp/b/$_br/obj@empty || \
		{ echo zfs rollback failed ; exit 1 ; }

#	echo DEBUG listing /b/$_br/obj - is it empty?
#	ls /b/$_br/obj ; read ok

	echo Updating $_br sources with git -C /b/$_br/src pull
	git -C /b/$_br/src pull || \
		{ echo git pull failed ; exit 1 ; }

	echo Checking branch $_br
	git -C /b/$_br/src checkout $_br || \
		{ echo git checkout failed ; exit 1 ; }

	echo Running git -C /b/$_br/src status | tail
	git -C /b/$_br/src status | tail

	echo Listing /b/$_br/src
	ls /b/$_br/src

#echo DEBUG look good? ; read good

	echo Obtaining Git date and hash
#	git_date="$( git -C /b/$_br/src log --format="%at" | head -1 )"
# Is there a correct way to get around the added timezone info? i.e. 1635972800 -0700
	git_date="$( git -C /b/$_br/src log --format="%ad" --date=raw | head -1 | cut -d " " -f1)"

	echo "$git_date" > /b/$_br/gitdate

	git_hash="$( git -C /b/$_br/src log --format="%H" | head -1 )"

	echo Obtaining last hash
	if [ -f "/b/$_br/lasthash" ] ; then
		last_hash="$( cat /b/$_br/lasthash )"
	else
		last_hash=""
	fi

	echo DEBUG git_date is $git_date
	echo DEBUG git_hash is $git_hash
	echo DEBUG lasthash is $last_hash

	if [ "$git_hash" = "$last_hash" ] ; then
		echo ----------------------
		echo Branch has not changed
		echo ----------------------
		echo
		continue
	else
		echo Setting /b/$_br/lasthash which reads:
		echo $git_hash > /b/$_br/lasthash
		cat /b/$_br/lasthash

		if [ -f "bos-lite.sh" ] ; then
			echo "KICKING OFF A bos-lite.sh build for /b/$_br"

			sh bos-lite.sh "/b/$_br" || \
				{ echo ; echo WARNING! $_br build failed ! ; }

			echo ; echo Updating /b/bos-lite.log

			cat /b/$_br/bos-lite-latest.log >> \
				/b/bos-lite.log || \
				{ echo ; echo Log update failed! ; }
		fi
	fi
done # End branches loop

	if [ -f "bos-upload.sh" ] ; then
		echo "KICKING OFF bos-upload.sh uploading"
		sh bos-upload.sh || \
			{ echo ; echo WARNING! Upload failed! ; }
	fi

exit 0
