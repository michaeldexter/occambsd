#!/bin/sh
#-
# SPDX-License-Identifier: BSD-2-Clause-FreeBSD
#
# Copyright 2021 Michael Dexter
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

# VERSION: 1.0

# STYLE GUIDELINES

# This script is formatted with shfmt -l -w <script> and %s/fi  #/fi #/g
# This script violates wrapping sensibilities while still in flux
# if statements are used in place of most case statements
# Every if statements is followed by # End if <variable_name> <condition>
# 	to allow a search for if to show the balancing of if statements
# This script avoids if, colons, apostrophes, and quotation marks in comments
#	and in user messages given their tendency to confuse /bin/sh

# LOCAL VARIABLES

pub_dir="/httpd/download"
upd_dir="/usr/freebsd-update-build"
vm_img_dir="/vm-images/"
src_dir="/usr/src"
top_obj_dir="/usr/obj"
log_dir="/usr/obj"
target="$(uname -m)"
target_arch="$(uname -p)"
jobs="$(sysctl -n hw.ncpu)"
eol_date=1609401600 # Probably should not be hard-coded

# INTERNAL DEFAULTS and UNSETS

src_rev=""
src_rev_string=""
upd_rev_string=""
kernconf_string=""
build_options=""
build_options_to_keep=""
branch_override_string=""
make_flags=""
build_name=""

f_usage() {
	echo By default this utility approximates a FreeBSD Release Engineering
	echo weekly snapshot build using the contents of /usr/src
	echo
	echo "Supported Flags"
	echo
	echo "-s \"<path>\"		Source directory path"
	echo "-o \"<path>\"		Object directory path"
	echo "-l \"<path>\"		Log and progress \".done\" bread crumb directory"
	echo "-r \"<number>\"		SVN or Git revision number or hash"
	echo "-S \"<URL>\"		SVN server base URL"
	echo "-b \"/branch/\"		SVN or Git branch such as \"stable/12\""
	echo "-G \"<URL>\"		Git server URL"
	echo "-g \"<path>\"		Git directory path for local clone --reference"
	echo "-t \"<target>\"		Architecture override such as \"arm64\""
	echo "-T \"<target arch>\"	Architecture arch override such as \"aarch64\""
	echo "-j \"<number>\"		Parallel make jobs number"
	echo "-k \"<name>\"		In-source KERNCONF to use such as GENERIC-NODEBUG"
	echo "-K \"<path>\"		External KERNCONF to replace GENERIC with"
	echo "-d \"<path>\"		Diffs directory - sequence is alphabetical"
	echo "-O \"<list>\"		Build options to keep. ALL others will be excluded"
	echo "				Use a src.conf if that is NOT what you want"
	echo "-u			freebsd-update handling"
	echo "-m \"<string>\"		make flags that are not handled by this monstrosity"
	echo "-n \"-name\"		Name to append to a release name for separation"
	echo "-R \"<user@host>\"	Remote user, host and path above object directory"
	echo "				to rsync tmpfs build to"
	echo
	echo "Be sure to \"quote/long/things\" like URLs"
	exit 1
} # End f_usage

f_sanitize_path() {
	# Remove the trailing slash and multiple slashes
	echo ${1%/} | tr -s /
} # end f_sanitize_path

while getopts s:o:l:r:S:b:G:g:t:T:j:k:K:d:O:um:n:R: opts; do
	case $opts in
	s)
		src_dir="${OPTARG}"
		src_dir=$(f_sanitize_path $src_dir)
		;;
	o)
		top_obj_dir="${OPTARG}"
		top_obj_dir=$(f_sanitize_path $top_obj_dir)
		echo DEBUG sanitized top_obj_dir is $top_obj_dir
		;;
	l)
		log_dir="${OPTARG}"
		;;
	r)
		src_rev="${OPTARG}"
		# DEBUG Verify that it is set... if [ "$src_rev" ]; then...
		# Either ignore this for Git or handle it in-context
		# This is global for re-runs
		upd_rev_string="-${src_rev}"
		;;
	S)
		svn_svr="${OPTARG}"
		;;
	b)
		src_branch="${OPTARG}"
		;;
	G)
		git_svr="${OPTARG}"
		;;
	g)
		git_dir="${OPTARG}"
		[ -d "$git_dir" ] || {
			echo $git_dir not found
			exit 1
		}
		;;
	t)
		target="${OPTARG}"
		# Verify against a list? Later?
		# Is there a way to get a canonical, up to date list from src?
		;;
	T)
		target_arch="${OPTARG}"
		;;
	j)
		jobs="${OPTARG}"
		# Verify that it is a number?
		;;
	k)
		kernconf="${OPTARG}"
		# Validate later because it may depend on a source checkout
		;;
	K)
		custom_kernconf="${OPTARG}"
		;;
	d)
		diff_dir="${OPTARG}"
		[ -d "${diff_dir}" ] || {
			echo $diff_dir is not a directory
			exit 1
		}
		[ -r "${diff_dir}" ] || {
			echo $diff_dir is not readable
			exit 1
		}
		;;
	O)
		build_options=1
		build_options_to_keep="${OPTARG}"
		;;
	u)
		freebsd_update=1
		;;
	m)
		make_flags="${OPTARG}"
		;;
	n)
		build_name="${OPTARG}"
		;;
	R)
		tmpfs_host="${OPTARG}"
		;;
	*)
		f_usage
		;;
	esac
done # End while getopts

# It would be nice to put all of the build strings here for review
# but the update handling ones are based on version information provided
# by newvers.sh which is only obtained after source checkout

# EARLY TESTS OF THE DEFAULTS THAT MAY HAVE BEEN OVERRIDDEN WITH ARGUMENTS

if ! [ -d "${src_dir}" ]; then
	echo
	echo Source directory does not exist
	echo
	echo Making ${src_dir}
	mkdir -p "${src_dir}" || {
		echo Failed to create $src_dir
		exit 1
	}
fi # End if src_dir

if ! [ -d "${log_dir}" ]; then
	echo Log directory does not exist. Creating
	mkdir -p "${log_dir}" || {
		echo Failed to create $log_dir
		exit 1
	}
fi # End if log_dir

echo -----------------------------------------
echo ---------- Validating Sources -----------
echo -----------------------------------------
echo
echo Preparing the source directory ${src_dir}
echo

# If neither SVN nor Git assume local

# DEBUG Note that this approach precludes a default for either as the default would result in decisions
if ! [ "$svn_svr" -o "$git_svr" -o "$git_dir" ]; then

	# This suggested syntax from shellcheck does not work - test again
	#if [ "$svn_svr" ] || [ "$git_svr" ] || [ "$git_dir" ]; then
	echo Using local sources
	if [ $(find $src_dir -maxdepth 0 -empty) ]; then
		echo Requested $src_dir is empty
		exit 1
	elif [ -f "${src_dir}/sys/${target}/conf/newvers.sh" ]; then
		echo ${src_dir} does not appear to contain a FreeBSD source tree
		exit 1
	fi # End if src_dir empty
elif [ "$svn_svr" -a "$git_svr" ]; then
	#elif [ "$svn_svr" ] && [ "$git_svr" ]; then
	echo Specify either -S\(vn\) or -G\(it\) but not both
	exit 1
elif [ "$git_svr" -a "$git_dir" ]; then
	#elif [ "$git_svr" ] && [ "$git_dir" ]; then
	echo Specify either a -G\(it\) server or -g\(ig\) directory but not both
	exit 1
fi # End if svn_svr git_svr git_dir preflight

if [ "$svn_svr" ]; then

	if [ $(which svnlite) ]; then
		svn_app=$(which svnlite)
	elif [ $(which svn) ]; then
		svn_app=$(which svnlite)
	else
		echo Neither svnlite nor svn found
		exit 1
	fi # End if which svn_app

	# SVN strings
	if [ "$src_rev" ]; then
		src_rev_string=" -r $src_rev "
	else
		src_rev_string=""
	fi # End if src_rev

	# Check if src_dir is empty with find $src_dir -maxdepth 0 -empty
	if [ $(find $src_dir -maxdepth 0 -empty) ]; then
		echo
		echo Checking out ${src_rev}/${src_branch} with $svn_app co $src_rev_string ${svn_svr}/${src_branch} ${src_dir}
		echo Logging to ${log_dir}/svnco.log

		if [ "$tmpfs_host" ]; then
			\time -h ssh $tmpfs_host $svn_app co $src_rev_string ${svn_svr}/${src_branch} ${src_dir} >${log_dir}/svnco.log || {
				echo SVN checkout failed
				exit 1
			}
		else
			\time -h $svn_app co $src_rev_string ${svn_svr}/${src_branch} ${src_dir} >${log_dir}/svnco.log || {
				echo SVN checkout failed
				exit 1
			}
		fi # End if tmpfs_host
		touch ${log_dir}/svnco.done
	elif [ -f ${log_dir}/svnco.done ]; then
		echo Sources appear to be checked out
	else
		echo ${src_dir} is not empty
		echo
		echo Type k to keep and continue
		echo Type d to delete and check out
		echo Type r to revert it to the desired revision
		echo Type any other key to exit
		read response
		if [ "$response" = "k" ]; then
			response=""
			true
		elif [ "$response" = "d" ]; then
			response=""
			echo Deleting ${src_dir}
			#chflags -R 0 ${src_dir}
			rm -rf "${src_dir:?}"/*
			rm -rf "${src_dir}"/.svn
			echo
			echo Checking out ${src_rev}/${src_branch} with $svn_app co $src_rev_string ${svn_svr}/${src_branch} ${src_dir}
			echo Logging to ${log_dir}/svnco.log
			if [ "$tmpfs_host" ]; then
				\time -h ssh $tmpfs_host $svn_app co $src_rev_string ${svn_svr}/${src_branch} ${src_dir} >${log_dir}/svnco.log || {
					echo SVN checkout failed
					exit 1
				}
			else
				\time -h $svn_app co $src_rev_string ${svn_svr}/${src_branch} ${src_dir} >${log_dir}/svnco.log || {
					echo SVN checkout failed
					exit 1
				}
			fi # End if tmpfs_host

			touch ${log_dir}/svnco.done
		elif [ "$response" = "r" ]; then
			response=""
			echo
			echo Updating to $src_rev with svn up $src_rev_string ${src_dir}
			echo Logging to ${log_dir}/svnup.log
			$svn_app up $src_rev_string ${src_dir} >${log_dir}/svnup.log || {
				echo SVN up failed
				exit 1
			}

			echo
			echo Reverting ${src_dir} to $src_rev with $svn_app revert -R $src_rev_string ${src_dir}
			echo Logging to ${log_dir}/svnrevert.log
			$svn_app revert -R ${src_dir} >${log_dir}/svnrevert.log || {
				echo SVN revert failed
				exit 1
			}

			echo
			echo Cleaning up unversioned files
			echo Logging to ${log_dir}/svncleanup.log
			$svn_app cleanup --remove-unversioned ${src_dir} >${log_dir}/svncleanup.log || {
				echo SVN cleanup failed
				exit 1
			}
		else
			exit 1
		fi # End if response
	fi # End if src_dir empty
fi # End if svn_svr

if [ "$git_svr" -o "$git_dir" ]; then
	if ! [ $(which git) ]; then
		echo git not found
		exit 1
	fi # End if which git_app

	# Git strings
	src_rev_string="$src_rev"

	if [ $src_branch ]; then
		src_branch_string="-b $src_branch"
	fi # End if branch_string

	if [ $git_svr ]; then
		git_string="git clone $git_svr $src_branch_string ${src_dir}"
	elif [ $git_dir ]; then
		git_string="git clone --reference $git_dir $git_dir $src_branch_string ${src_dir}"
	else
		echo Git confusion achieved!
		exit 1
	fi # End if git_svr or git_dir

	# LOOKS LIKE REDIRECTION CONFUSES ITS NUMBER OF ARGUMENTS
	# Running git clone --reference /cgit /cgit /build/c122cf32f2a/src 2> /build/c122cf32f2a/obj/gitclone.log
	#Logging to /build/c122cf32f2a/obj/gitclone.log
	#fatal: Too many arguments.

	if [ $(find $src_dir -maxdepth 0 -empty) ]; then
		echo
		echo Running $git_string
		#echo Logging to ${log_dir}/gitclone.log
		\time -h $git_string || {
			echo Git clone failed
			exit 1
		}
		touch ${log_dir}/gitclone.done

		if [ $src_rev ]; then
			echo Changing directory to ${src_dir} to checkout revision $src_rev
			cd ${src_dir} || {
				echo Change directory failed
				exit 1
			}
			pwd
			echo Running git checkout $src_rev
			\time -h git checkout $src_rev || {
				echo git checkout failed
				exit 1
			}
			echo Running git status
			git status
		fi # End if src_rev
	elif [ -f ${log_dir}/gitclone.done ]; then
		echo Sources appear to be cloned
	else
		echo
		echo ${src_dir} not empty
		echo
		echo Type k to keep and continue
		echo Type d to delete it and clone
		echo Type any other key to exit
		read response
		if [ "$response" = "k" ]; then
			response=""
			true
		elif [ "$response" = "d" ]; then
			response=""
			echo Deleting ${src_dir}
			chflags -R 0 ${src_dir}
			rm -rf ${src_dir}
			echo
			echo Running $git_string
			echo Logging to ${log_dir}/gitclone.log
			\time -h $git_string || {
				echo Git clone failed
				exit 1
			}
			touch ${log_dir}/gitclone.done

			if [ $src_rev ]; then
				echo Changing directory to ${src_dir}
				cd ${src_dir} || {
					echo Change directory failed
					exit 1
				}
				pwd
				echo Running git checkout $src_rev
				\time -h git checkout $src_rev || {
					echo git checkout failed
					exit 1
				}
				echo Running git status
				git status
			fi
		else
			response=""
			exit 1
		fi # End if response
	fi # End if Git and empty
fi # End if git_svr or git_dir

if [ $kernconf ]; then
	echo
	echo -----------------------------------------
	echo ---------- KERNCONF handling ------------
	echo -----------------------------------------

	echo Requested KERNCONF ${src_dir}/sys/${target}/conf/${kernconf}

	if [ "$kernconf" -a "$custom_kernconf" ]; then
		#	if [ "$kernconf" ] && [ "$custom_kernconf" ]; then
		echo Specify either -k or -K KERNCONF options but not both
		exit 1
	fi # End if kernconf

	[ -f ${src_dir}/sys/${target}/conf/${kernconf} ] || {
		echo ${src_dir}/sys/${target}/conf/${kernconf} not found
		exit 1
	}

	echo Setting KERNCONF=$kernconf
	kernconf_string="KERNCONF=$kernconf"

fi # End if kernconf

if [ $custom_kernconf ]; then
	echo
	echo -----------------------------------------
	echo ------- Custom KERNCONF handling --------
	echo -----------------------------------------

	if [ "$kernconf" -a "$custom_kernconf" ]; then
		#	if [ "$kernconf" ] && [ "$custom_kernconf" ]; then
		echo Specify either -k or -K KERNCONF options but not both
		exit 1
	fi # End if kernconf of custom_kernconf

	[ -f $custom_kernconf ] || {
		echo Custom KERNCONF $custom_kernconf not found
		exit 1
	}

	[ -f ${src_dir}/sys/${target}/conf/GENERIC ] || {
		echo ${src_dir}/sys/${target}/conf/GENERIC not found
		exit 1
	}

	echo Overwriting the GENERIC KERNCONF with $custom_kernconf
	cp $custom_kernconf ${src_dir}/sys/${target}/conf/GENERIC || {
		echo $custom_kernconf copy failed
		exit 1
	}

	kernconf_string="KERNCONF=GENERIC"

fi # End if custom_kerconf

if [ $diff_dir ]; then
	echo
	echo -----------------------------------------
	echo ----- Applying diffs if requested -------
	echo -----------------------------------------

	# This step is "destructive" and would need a source reversion

	if [ $(find $diff_dir -maxdepth 0 -empty) ]; then
		echo No diffs in ${diff_dir} to apply
	elif [ -f ${log_dir}/diff-patching.done ]; then
		echo Sources appear to be patched
	else
		echo Changing directory to ${src_dir}
		cd "${src_dir}"
		# Moving to make -C ${src_dir}/release syntax elsewhere
		# Trickier here
		pwd
		echo The contents of diff_dir are
		echo ${diff_dir}/*
		echo
		echo Applying patches
		for diff in $(echo ${diff_dir}/*); do
			echo Running a dry run diff of $diff
			# Might need svn patch?
			echo patch -C \< $diff
			if [ $(patch -C <$diff) ]; then
				echo Diff $diff passed the dry run
				diff_basename=$(basename $diff)
				echo Applying and Logging to ${log_dir}/diff-${diff_basename}.log with
				echo patch \< $diff >${log_dir}/diff-${diff_basename}.log
				echo Apply diff $diff
				patch <$diff >${log_dir}/diff-${diff_basename}.log
			else
				echo Diff $diff failed to apply
				exit 1
			fi # End diff success
		done
	fi # End if diff_dir empty
	touch ${log_dir}/diff-patching.done
fi # End if diff_dir

# Do not validate on the whole string as it will choke
if [ "$build_options" = 1 ]; then
	echo
	echo -----------------------------------------
	echo -------- Build Option handling ----------
	echo -----------------------------------------

	# Obtain the current list of build options in the source tree
	[ -f ${src_dir}/tools/tools/build_option_survey/listallopts.sh ] || {
		echo ${src_dir}/tools/tools/build_option_survey/listallopts.sh not found
		exit 1
	}
	all_options=$(sh ${src_dir}/tools/tools/build_option_survey/listallopts.sh | sed '/^WITH_/d')
	# How to validate or at least check for an error?
	# Save off all_options to ${log_dir}/all_options.txt
	echo $all_options >${log_dir}/all_options.txt

	without_list=""

	for option in $all_options; do
		do_not_add_to_list=0
		for do_not_exclude in $build_options_to_keep; do
			if [ "$option" = "$do_not_exclude" ]; then
				do_not_add_to_list=1
			else
				true
			fi # End if do_not_exclude
		done

		if [ "$do_not_add_to_list" = 1 ]; then
			true
		else
			without_list="${without_list} ${option}=yes"
		fi # End if do_not_add_to_list
	done
fi # End if build_options_to_keep

if [ "$freebsd_update" = 1 ]; then
	echo
	echo -----------------------------------------
	echo -------- freebsd-update handling --------
	echo -----------------------------------------

	# Read newvers.sh in the sources to determine REVISION and BRANCH

	# In case of re-runs
	if [ -f "${log_dir}/REVISION" ] && [ -f "${log_dir}/BRANCH" ]; then
		if ! [ $REVISION ]; then
			echo Reading "${log_dir}"/REVISION
			REVISION=$(cat "${log_dir}"/REVISION) || {
				echo Could not determine REVISION from ${log_dir}/REVISION
				exit 1
			}
		fi # End if REVISION
		if ! [ $BRANCH ]; then
			echo Reading "${log_dir}"/BRANCH
			BRANCH=$(cat "${log_dir}"/BRANCH) || {
				echo Could not determine BRANCH from ${log_dir}/BRANCH
				exit 1
			}
		fi # End if BRANCH
	else
		# This will generate vers.c and version in the current directory
		# Consider redirecting the output as it technically fails with
		# awk: cant open file ./../sys/param.h
		# source line number 1

		echo Reading "${src_dir}"/sys/conf/newvers.sh
		. "${src_dir}"/sys/conf/newvers.sh || {
			echo Reading newvers.sh failed
			exit 1
		}

		if [ "$BRANCH" = "CURRENT" ]; then
			# BACK TO HEAD FOR GIT disc1 ISO naming
			BRANCH="HEAD"
		fi # End if current

		echo "$REVISION" >${log_dir}/REVISION
		echo "$BRANCH" >${log_dir}/BRANCH
	fi # End if cached REVISION and BRANCH or source from newvers.sh

	if [ "$git_svr" -o "$git_dir" ]; then
		cd ${src_dir} # Does not work with simply the directory trailing
		src_git_count=$(git rev-list --count $src_rev)
		[ "$?" = 0 ] || {
			echo git rev-list --count failed
			exit 1
		}
		upd_rev_string="-$src_git_count"
		echo "$src_rev" >${log_dir}/src_git_rev
		echo "$src_git_count" >${log_dir}/src_git_count
	fi # End if git_svr or git_dir

	if [ $upd_rev_string ]; then
		branch_override_string="env BRANCH_OVERRIDE=${BRANCH}${upd_rev_string}${build_name}"

		update_init_string="${upd_dir}/scripts/init.sh ${target} ${REVISION}-${BRANCH}${upd_rev_string}${build_name}"
		update_approve_string="${upd_dir}/scripts/approve.sh ${target} ${REVISION}-${BRANCH}${upd_rev_string}${build_name}"
		update_upload_string="${upd_dir}/scripts/upload.sh ${target} ${REVISION}-${BRANCH}${upd_rev_string}${build_name}"
	else
		branch_override_string="env BRANCH_OVERRIDE=${BRANCH}${build_name}"

		update_init_string="${upd_dir}/scripts/init.sh ${target} ${REVISION}-${BRANCH}${build_name}"
		update_approve_string="${upd_dir}/scripts/approve.sh ${target} ${REVISION}-${BRANCH}${build_name}"
		update_upload_string="${upd_dir}/scripts/upload.sh ${target} ${REVISION}-${BRANCH}${build_name}"
	fi # End if upd_rev_string

	if ! [ -f "${log_dir}/update-patching.done" ]; then
		echo Copying freebsd-update.sh to freebsd-update.sh.original
		cp ${src_dir}/usr.sbin/freebsd-update/freebsd-update.sh \
			${src_dir}/usr.sbin/freebsd-update/freebsd-update.sh.original

		echo Modifying ${src_dir}/usr.sbin/freebsd-update/freebsd-update.sh

		echo Patching freebsd-update.sh
		patch ${src_dir}/usr.sbin/freebsd-update/freebsd-update.sh \
			${upd_dir}/freebsd-update.sh.diff || {
			echo freebsd-update.sh patch failed
			exit 1
		}

		echo testing freebsd-update.sh with sh -n
		sh -n ${src_dir}/usr.sbin/freebsd-update/freebsd-update.sh || {
			echo freebsd-update.sh failed the sh -n test
			exit 1
		}

		echo Patching freebsd-update.conf
		patch ${src_dir}/usr.sbin/freebsd-update/freebsd-update.conf \
			${upd_dir}/freebsd-update.conf.diff || {
			echo freebsd-update.conf patch failed
			exit 1
		}
		touch ${log_dir}/update-patching.done
	else
		echo Sources appear to be patched for updating
	fi # End if update-patching
fi # End if freebsd-update

echo
echo -----------------------------------------
echo ------- Object Directory Handing --------
echo -----------------------------------------

# Keep in mind the object directory can be world, kernel, and release
# There are many scenarios for a "dirty" object directory
# Strategy: Provide facts and let the user decide

# Assign target-specific obj_dir
# Be very careful with leading slashes - src_dir starts with one
obj_dir="${top_obj_dir}${src_dir}/${target}.${target_arch}"
echo obj_dir is $obj_dir

echo
echo Checking for ${obj_dir}
# If obj_dir not present create it regardless of if using tmpfs
# make buildworld will auto-create the full path but the full path is needed
# in advance for mounting obj_dir tmpfs

# if obj_dir exists
if [ -d "${obj_dir}" ]; then

	if [ "$tmpfs_host" ]; then # if tmpfs is requested
		# Report to the user if tmpfs is mounted
		echo "mount | grep tmpfs | grep -q ${obj_dir}"
		#		if [ $(mount | grep "tmpfs" | grep "${obj_dir}") ]; then # if mounted
		# [: tmpfs: unexpected operator
		# Not sure why this refuses to work
		# Whatever the test, loop over it as you can collet many tmpfs mounts
		mount | grep "tmpfs" | grep "${obj_dir}" && tmpfs_is_mounted=1
		if [ "$tmpfs_is_mounted" = 1 ]; then
			echo JUST DETERMINED THAT TMPFS IS MOUNTED
			echo
			echo Object directory ${obj_dir} is mounted tmpfs
			echo
			[ -f "${log_dir}/buildworld-${target}.done" ] && echo ${target} buildworld reportedly complete
			[ -f "${log_dir}/buildkernel-${target}.done" ] && echo ${target} buildkernel reportedly complete
			[ -f "${log_dir}/release-${target}.done" ] && echo ${target} release reportedly complete
			[ -f "${log_dir}/vmimage-${target}.done" ] && echo ${target} vmimage reportedly complete
			[ -f ${log_dir}/rsync_objdir-${target}.done ] && echo ${target} object directory reportedly synchronized

			echo type k to keep or any other key to cleanse
			read response
			if ! [ "$response" = "k" ]; then
				response=""
				echo Removing world-dependent done files that cannot be valid
				[ -f "${log_dir}/buildworld-${target}.done" ] && rm ${log_dir}/buildworld-${target}.done
				[ -f "${log_dir}/tmpfs-buildworld-${target}.done" ] && rm ${log_dir}/tmpfs-buildworld-${target}.done
				[ -f "${log_dir}/buildkernel-${target}.done" ] && rm ${log_dir}/buildkernel-${target}.done
				[ -f "${log_dir}/tmpfs-buildkernel-${target}.done" ] && rm ${log_dir}/tmpfs-buildkernel-${target}.done
				[ -f "${log_dir}/release-${target}.done" ] && rm ${log_dir}/release-${target}.done
				[ -f "${log_dir}/tmpfs-release-${target}.done" ] && rm ${log_dir}/tmpfs-release-${target}.done
				[ -f "${log_dir}/vmimage-${target}.done" ] && rm ${log_dir}/vmimage-${target}.done
				[ -f "${log_dir}/tmpfs-vmimage-${target}.done" ] && rm ${log_dir}/tmpfs-vmimage-${target}.done
				[ -f "${log_dir}/rsync_objdir-${target}.done" ] && rm ${log_dir}/rsync_objdir-${target}.done
				[ -f "${log_dir}/update-init-${target}.done" ] && rm ${log_dir}/update-init-${target}.done
				[ -f "${log_dir}/update-approve-${target}.done" ] && rm ${log_dir}/update-approve-${target}.done
				[ -f "${log_dir}/update-upload-${target}.done" ] && rm ${log_dir}/update-upload-${target}.done
				[ -f "${log_dir}/update-init-${target}.done" ] && rm ${log_dir}/update-init-${target}.done
				[ -f "${log_dir}/update-upload-${target}.done" ] && rm ${log_dir}/update-upload-${target}.done
				[ -f "${log_dir}/rsync_upd_init-${target}.done" ] && rm ${log_dir}/rsync_upd_init-${target}.done
				[ -f "${log_dir}/rsync_upd_upload-${target}.done" ] && rm ${log_dir}/rsync_upd_upload-${target}.done
				# Work out these tests and move to the non-tmpfs cleanup
				# DEBUG consider sourcing REVISION and BRANCH and cleaning these up - repeat below
				#[ -f "${pub_dir}/FreeBSD-${REVISION}-${BRANCH}${upd_rev_string}${build_name}.${target}-disc1.iso" ] &&
				#rm "${pub_dir}/FreeBSD-${REVISION}-${BRANCH}${upd_rev_string}${build_name}-${target}-disc1.iso"
				#[ -f "${pub_dir}/FreeBSD-${REVISION}-${BRANCH}${upd_rev_string}${build_name}.${target}-disc1.iso.xz" ] &&
				#rm "${pub_dir}/FreeBSD-${REVISION}-${BRANCH}${upd_rev_string}${build_name}-${target}-disc1.iso.xz"
				#[ -f "${vm_img_dir}/FreeBSD-${REVISION}-${BRANCH}${upd_rev_string}${build_name}-${target}-vm.raw" ] &&
				#rm "${vm_img_dir}/FreeBSD-${REVISION}-${BRANCH}${upd_rev_string}${build_name}-${target}-vm.raw"
				#echo "${pub_dir}/${REVISION}-${BRANCH}${upd_rev_string}${build_name}"
				#[ -d "${pub_dir}/${REVISION}-${BRANCH}${upd_rev_string}${build_name}" ] &&
				#rm -rf ${pub_dir}/${REVISION}-${BRANCH}${upd_rev_string}${build_name}

				echo Unmounting ${obj_dir}
				umount "${obj_dir}"
				echo Mounting ${obj_dir} tmpfs
				mount -t tmpfs tmpfs "${obj_dir}" || {
					echo Failed to mount ${obj_dir} tmpfs
					exit 1
				}
			fi # End if user decision
		else
			echo Mounting ${obj_dir} tmpfs
			mount -t tmpfs tmpfs "${obj_dir}" || {
				echo Failed to mount ${obj_dir} tmpfs
				exit 1
			}
		fi # End if tmpfs_host mounted
	else # if not tmpfs_host
		echo
		echo Object directory $obj_dir exists
		echo
		[ $(find ${obj_dir}/sys -maxdepth 0 -empty) ] && echo Object directory is not empty
		[ -f "${log_dir}/buildworld-${target}.done" ] && echo ${target} buildworld reportedly complete
		[ -f "${log_dir}/buildkernel-${target}.done" ] && echo ${target} buildkernel reportedly complete
		[ -f "${log_dir}/release-${target}.done" ] && echo ${target} release reportedly complete
		[ -f "${log_dir}/vmimage-${target}.done" ] && echo ${target} vmimage reportedly complete
		echo type k to keep or any other key to cleanse
		read response
		if ! [ "$response" = "k" ]; then
			response=""
			echo Removing world-dependent done files that cannot be valid
			[ -f "${log_dir}/buildworld-${target}.done" ] && rm ${log_dir}/buildworld-${target}.done
			[ -f "${log_dir}/tmpfs-buildworld-${target}.done" ] && rm ${log_dir}/tmpfs-buildworld-${target}.done
			[ -f "${log_dir}/buildkernel-${target}.done" ] && rm ${log_dir}/buildkernel-${target}.done
			[ -f "${log_dir}/tmpfs-buildkernel-${target}.done" ] && rm ${log_dir}/tmpfs-buildkernel-${target}.done
			[ -f "${log_dir}/release-${target}.done" ] && rm ${log_dir}/release-${target}.done
			[ -f "${log_dir}/tmpfs-release-${target}.done" ] && rm ${log_dir}/tmpfs-release-${target}.done
			[ -f "${log_dir}/vmimage-${target}.done" ] && rm ${log_dir}/vmimage-${target}.done
			[ -f "${log_dir}/tmpfs-vmimage-${target}.done" ] && rm ${log_dir}/tmpfs-vmimage-${target}.done
			[ -f "${log_dir}/rsync_objdir-${target}.done" ] && rm ${log_dir}/rsync_objdir-${target}.done
			[ -f "${log_dir}/update-init-${target}.done" ] && rm ${log_dir}/update-init-${target}.done
			[ -f "${log_dir}/update-approve-${target}.done" ] && rm ${log_dir}/update-approve-${target}.done
			[ -f "${log_dir}/update-upload-${target}.done" ] && rm ${log_dir}/update-upload-${target}.done
			[ -f "${log_dir}/update-init-${target}.done" ] && rm ${log_dir}/update-init-${target}.done
			[ -f "${log_dir}/update-upload-${target}.done" ] && rm ${log_dir}/update-upload-${target}.done
			echo Cleaning up previous buildworld
			chflags -R 0 ${obj_dir}
			rm -rf "${obj_dir:?}"/*
		fi # End user response
	fi # End if tmpfs_host
else # create obj_dir if it does not exist
	mkdir -p "${obj_dir}" || {
		echo Failed to create ${obj_dir}
		exit 1
	}
	if [ "$tmpfs_host" ]; then
		echo Mounting ${obj_dir} tmpfs
		mount -t tmpfs tmpfs "${obj_dir}" || {
			echo Failed to mount ${obj_dir} tmpfs
			exit 1
		}
	fi # End if tmpfs_host
fi # End if object exists

echo
echo -----------------------------------------
echo -------- About to begin building --------
echo -----------------------------------------
echo
echo Assembling make commands

buildworld_string="env MAKEOBJDIRPREFIX=${top_obj_dir} env PKGCONFBRANCH=latest make -j$jobs -C ${src_dir}/ buildworld TARGET=$target TARGET_ARCH=$target_arch $without_list $make_flags"

buildkernel_string="env MAKEOBJDIRPREFIX=${top_obj_dir} $branch_override_string make -j$jobs -C ${src_dir}/ buildkernel TARGET=$target TARGET_ARCH=$target_arch $kernconf_string $make_flags"

makerelease_string="env MAKEOBJDIRPREFIX=${top_obj_dir} $branch_override_string make -C ${src_dir}/release/ release TARGET=$target TARGET_ARCH=$target_arch $kernconf_string $make_flags"

vmimage_string="env MAKEOBJDIRPREFIX=${top_obj_dir} $branch_override_string make -C ${src_dir}/release/ vm-image TARGET=$target TARGET_ARCH=$target_arch $kernconf_string $make_flags WITH_VMIMAGES=yes VMFORMATS=raw"

# Note that the update_strings are generated separately based on the actual sources and cannot be included here

echo
echo About to run
echo
echo buildworld command
echo $buildworld_string
echo $buildworld_string >${log_dir}/buildworld_string
echo
echo buildkernel command
echo $buildkernel_string
echo $buildkernel_string >${log_dir}/buildkernel_string
echo
echo release command
echo $makerelease_string
echo $makerelease_string >${log_dir}/makerelease_string
echo
echo vmimage command
echo $vmimage_string
echo $vmimage_string >${log_dir}/vmimage_string
echo
echo update init command
echo $update_init_string
echo $update_init_string >${log_dir}/update_init_string
echo
echo update approve command
echo $update_approve_string
echo $update_approve_string >${log_dir}/update_approve_string
echo
echo update upload command
echo $update_upload_string
echo $update_upload_string >${log_dir}/update_upload_string

# Consider a read here to pause before execution

echo
echo -----------------------------------------
echo ------------- Building ------------------
echo -----------------------------------------

echo Pushing down the ARC to free up RAM
sysctl vfs.zfs.arc_max=1942278144

must_build_world=1
if [ -f "${log_dir}/buildworld-${target}.done" ] || [ -f "${log_dir}/tmpfs-buildworld-${target}.done" ]; then
	echo
	echo Successful $target buildworld reported in ${log_dir}
	echo
	echo Type k to keep or any other key to delete it
	read response
	if [ "$response" = "k" ]; then
		response=""
		must_build_world=0
	else
		response=""
		[ -f "${log_dir}/buildworld-${target}.done" ] && rm ${log_dir}/buildworld-${target}.done
		[ -f "${log_dir}/tmpfs-buildworld-${target}.done" ] && rm ${log_dir}/tmpfs-buildworld-${target}.done
		echo Cleaning up previous buildworld
		chflags -R 0 ${obj_dir}
		rm -rf "${obj_dir:?}"/*
	fi # End if response
fi # End if must_build_world

if [ "$must_build_world" = 1 ]; then

	echo
	echo Running buildworld string $buildworld_string
	echo Logging to ${log_dir}/buildworld-${target}.log
	date

	\time -h $buildworld_string >${log_dir}/buildworld-${target}.log || {
		echo buildworld failed. See ${log_dir}/buildworld-${target}.log
		exit 1
	}
	if [ "$tmpfs_host" ]; then
		touch ${log_dir}/tmpfs-buildworld-${target}.done
	else
		touch ${log_dir}/buildworld-${target}.done
	fi # End if tmpfs_host
fi # End if must_build_world

must_build_kernel=1

if [ -f "${log_dir}/buildkernel-${target}.done" ] || [ -f "${log_dir}/tmpfs-buildkernel-${target}.done" ]; then

	echo
	echo Successful buildkernel reported in ${log_dir}
	echo
	echo Type k to keep or any other key to build over it
	read response
	if [ "$response" = "k" ]; then
		response=""
		must_build_kernel=0
	else
		response=""
		[ -f "${log_dir}/buildkernel-${target}.done" ] && rm ${log_dir}/buildkernel-${target}.done
		[ -f "${log_dir}/tmpfs-buildkernel-${target}.done" ] && rm ${log_dir}/tmpfs-buildkernel-${target}.done
		echo Cleaning up previous buildkernel
		echo Running chflags -R 0 ${obj_dir}/sys
		chflags -R 0 ${obj_dir}/sys
		echo Running rm -rf ${obj_dir}/sys/*
		rm -rf ${obj_dir}/sys/*
	fi # End if response
fi # End if build kernel done

if [ "$must_build_kernel" = 1 ]; then

	# DEBUG perform same check for world?
	if [ $(find ${obj_dir}/sys -maxdepth 0 -empty) ]; then
		[ -f "${log_dir}/buildkernel-${target}.done" ] && rm ${log_dir}/buildkernel-${target}.done
		[ -f "${log_dir}/tmpfs-buildkernel-${target}.done" ] && rm ${log_dir}/tmpfs-buildkernel-${target}.done
		echo Cleaning up previous buildkernel
		chflags -R 0 ${obj_dir}/sys
		rm -rf ${obj_dir}/sys/*
	fi # End if kernel dir empty

	echo
	echo Running buildkernel string $buildkernel_string
	echo Logging to ${log_dir}/buildkernel-${target}.log
	date
	\time -h $buildkernel_string >${log_dir}/buildkernel-${target}.log || {
		echo buildkernel failed. See ${log_dir}/buildkernel-${target}.log
		exit 1
	}
	if [ "$tmpfs_host" ]; then
		touch ${log_dir}/tmpfs-buildkernel-${target}.done
	else
		touch ${log_dir}/buildkernel-${target}.done
	fi # End if tmpfs_host
fi # End if must_build_kernel

must_build_release=1
if [ -f "${log_dir}/release-${target}.done" ] || [ -f "${log_dir}/tmpfs-release-${target}.done" ]; then
	echo
	echo Successful release reported in ${log_dir}
	echo
	echo Type k to keep or any other key to build over it
	read response
	if [ "$response" = "k" ]; then
		response=""
		must_build_release=0
	else
		response=""
		[ -f "${log_dir}/release-${target}.done" ] && rm ${log_dir}/release-${target}.done
		[ -f "${log_dir}/tmpfs-release-${target}.done" ] && rm ${log_dir}/tmpfs-release-${target}.done
	fi # End if response
fi # End if release done

if [ "$must_build_release" = 1 ]; then

	# base.txz appears to be the first file created
	if [ -f ${obj_dir}/release/base.txz ]; then
		echo Cleaning up previous release
		chflags -R 0 ${obj_dir}/release
		rm -rf ${obj_dir}/release/*
	fi # End if release directory empty

	echo
	echo Entering ${src_dir}/release
	pwd
	# Verify if make -C ${src_dir}/release syntax can be used here
	cd ${src_dir}/release || {
		echo Change directory failed
		exit 1
	}
	pwd

	echo
	echo Making release
	echo Logging to ${log_dir}/release-${target}.log
	date
	\time -h $makerelease_string >${log_dir}/release-${target}.log 2>&1 || {
		echo make release failed. See ${log_dir}/release-${target}.log
		exit 1
	}
	if [ "$tmpfs_host" ]; then
		touch ${log_dir}/tmpfs-release-${target}.done
	else
		touch ${log_dir}/release-${target}.done
	fi # End if tmpfs_host
fi # End if must_build_release

must_build_vmimage=1

if [ -f "${log_dir}/vmimage-${target}.done" ]; then
	echo
	echo VM image appears to be built
	echo
	echo Type k to keep or any other key to build over it
	read response
	if [ "$response" = "k" ]; then
		response=""
		must_build_vmimage=0
	else
		response=""
		true
	fi # End if response
fi # End if VM image done

if [ "$must_build_vmimage" = 1 ]; then
	echo Cleaning up the previous VM image if necessary

	[ -f ${obj_dir}/release/vm.raw ] &&
		rm ${obj_dir}/release/vm.raw
	[ -d ${obj_dir}/release/vm-image ] &&
		rmdir ${obj_dir}/release/vm-image

	echo
	echo Making vmimage
	echo Logging to ${log_dir}/vmimage-${target}.log
	date

	if [ "${target}" = "arm64" ]; then
		#cd ${src_dir}/release
		# Moving to make -C ${src_dir}/release syntax

		echo
		echo Running vmimage string $vmimage_string

		\time -h $vmimage_string >${log_dir}/vmimage-${target}.log || {
			echo make vmimage failed. See ${log_dir}/vmimage-${target}.log
			exit 1
		}
	else
		truncate -s 8G ${obj_dir}/release/vm.raw || {
			echo truncate failed
			exit 1
		}

		vmimg_md=$(mdconfig -af ${obj_dir}/release/vm.raw)

		echo Partitioning and formating $vmimg_md
		gpart create -s gpt $vmimg_md
		gpart add -t freebsd-boot -l bootfs -b 128 -s 128K $vmimg_md
		gpart bootcode -b /boot/pmbr -p /boot/gptboot -i 1 $vmimg_md
		gpart add -t freebsd-swap -l swapfs -s 1G $vmimg_md
		gpart add -t freebsd-ufs -l rootfs $vmimg_md
		echo The vm-image partitioning is:
		gpart show $vmimg_md
		newfs -U /dev/${vmimg_md}p3 || {
			echo newfs failed
			exit 1
		}

		echo Mounting ${vmimg_md}p3
		mount /dev/${vmimg_md}p3 /mnt || {
			echo mount failed
			exit 1
		}

		echo Extracting ${obj_dir}/release/base.txz and kernel.txz
		[ -f ${obj_dir}/release/base.txz ] || {
			echo base.txz not found
			exit 1
		}
		tar xzf ${obj_dir}/release/base.txz -C /mnt || {
			echo base.txz extraction failed
			exit 1
		}
		[ -f ${obj_dir}/release/kernel.txz ] || {
			echo kernel.txz not found
			exit 1
		}
		tar xzf ${obj_dir}/release/kernel.txz -C /mnt || {
			echo kernel.txz extraction failed
			exit 1
		}

		tee -a /mnt/etc/rc.conf <<EOF
hostname="freebsd"
ifconfig_DEFAULT="DHCP inet6 accept_rtadv"
growfs_enable=YES
EOF
		[ "$?" = 0 ] || {
			echo rc.conf generation failed
			exit 1
		}

		echo "/dev/gpt/rootfs	/	ufs	rw,noatime	1	1" >/mnt/etc/fstab
		echo "/dev/gpt/swapfs	none	swap	sw	1	1" >>/mnt/etc/fstab || {
			echo fstab generation failed
			exit 1
		}

		touch /mnt/firstboot

		echo loader.conf
		tee -a /mnt/boot/loader.conf <<EOF
kern.geom.label.disk_ident.enable="0"
kern.geom.label.gptid.enable="0"
autoboot_delay="5"
EOF
		[ "$?" = 0 ] || {
			echo loader.conf generation failed
			exit 1
		}

		tzsetup -s -C /mnt UTC || {
			echo tzsetup generation failed
			exit 1
		}

		echo Unmounting /mnt
		umount /mnt

		echo Destroying $vmimg_md
		mdconfig -du $vmimg_md
		mdconfig -lv
	fi # End if arm64

	if [ "$tmpfs_host" ]; then
		touch ${log_dir}/tmpfs-vmimage-${target}.done
	else
		touch ${log_dir}/vmimage-${target}.done
	fi # End if tmpfs_host
fi # End if must_build_vmimage

if [ "$tmpfs_host" ]; then
	echo
	echo -----------------------------------------
	echo --- obj_dir tmpfs/Remote Host handling --
	echo -----------------------------------------

	# Initial thought
	#scp -rp ${obj_dir} ${tmpfs_host}/

	must_rsync_objdir=1

	if [ -f "${log_dir}/rsync_objdir-${target}.done" ]; then
		echo
		echo Successful object rsync reported in ${log_dir}
		echo
		echo Type k to keep it and continue or any other key to resynchronize it
		read response
		if [ "$response" = "k" ]; then
			response=""
			must_rsync_objdir=0
		else
			response=""
			rm ${log_dir}/must_rsync_objdir-${target}.done
		fi # End if response
	fi # End if rsync done

	if [ "$must_rsync_objdir" = 1 ]; then

		[ $(which rsync) ] || {
			echo rsync is not installed
			exit 1
		}

		# Could break into separate source and destination strings
		rsync_objdir_string="rsync -atv --delete ${obj_dir}/ ${tmpfs_host}:${obj_dir}"

		echo Running $rsync_objdir_string
		\time -h $rsync_objdir_string >${log_dir}/must_rsync_objdir-${target}.log || {
			echo $obj_dir rsync failed
			exit 1
		}

		# Setting these bread crumbs ONLY after successful sync to persistent storage if using tmpfs
		# Remove the tmpfs- ones?
		touch ${log_dir}/buildworld-${target}.done
		touch ${log_dir}/buildkernel-${target}.done
		touch ${log_dir}/release-${target}.done
		touch ${log_dir}/vmimage-${target}.done
		touch ${log_dir}/must_rsync_objdir-${target}.done
	fi # End if must rsync
fi # End if tmpfs_host

if [ "$freebsd_update" = 1 ]; then
	echo
	echo -----------------------------------------
	echo ------- freebsd-update handling ---------
	echo -----------------------------------------

	must_init_update=1
	must_approve_update=1 # Uses work and stage
	must_upload_update=1  # Uses pub
	if [ "$tmpfs_host" ]; then
		must_rsync_upd_init=1 # Uses work
		# Consider this - currently inoperable
		#must_rsync_upd_upload=1
	fi # End if tmpfs_host

	if [ "$git_svr" -o "$git_dir" ]; then
		cd "${src_dir}" # Does not work with simply the directory trailing
		src_git_count=$(git rev-list --count $src_rev)
		[ "$?" = 0 ] || {
			echo git rev-list --count failed
			exit 1
		}
		upd_rev_string="-$src_git_count"
		echo "$src_rev" >${log_dir}/src_git_rev
		echo "$src_git_count" >${log_dir}/src_git_count
	fi # End if git_svr or git_dir

	if [ -f "${log_dir}/update-init-${target}.done" ]; then
		echo
		echo Successful update init reported in ${log_dir}
		echo
		echo Type k to keep it and continue or any other key to re-initialize it
		read response
		if [ "$response" = "k" ]; then
			response=""
			must_init_update=0
		else
			response=""
			rm ${log_dir}/update-init-${target}.done
		fi # End if response
	fi # End if must init update

	if [ "$must_init_update" = 1 ]; then
		echo DEBUG Cleaning up incomplete upgrade

		# Example of what needs to be cleaned up
		#./work/13.0-HEAD-...
		#./patches/13.0-HEAD-...
		#./scripts/13.0-HEAD-...
		#./pub/13.0-HEAD-...

		# Path reference ${upd_dir}/scripts/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}

		[ -f "${pub_dir}/FreeBSD-${REVISION}-${BRANCH}${upd_rev_string}${build_name}-${target}-disc1.iso" ] &&
			rm ${pub_dir}/FreeBSD-${REVISION}-${BRANCH}${upd_rev_string}${build_name}-${target}-disc1.iso

		[ $(mount | grep -q world0/dev) ] &&
			umount -f ${upd_dir}/work/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}/world0/dev

		[ $(mount | grep -q world0) ] &&
			umount -f ${upd_dir}/work/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}/world0

		[ $(mount | grep -q iso) ] &&
			umount -f ${upd_dir}/work/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}/iso

		if [ -d "${upd_dir}/work/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}" ]; then
			echo Running rm -rf ${upd_dir}/work/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}
			rm -rf ${upd_dir}/work/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}
			if [ -f "${upd_dir}/work/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}/world.tgz" ]; then
				rm ${upd_dir}/work/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}/world.tgz
			fi # End if work/world.tgz
		fi # if must cleanse update work dir

		if [ -d "${upd_dir}/patches/${REVISION}-${BRANCH}${upd_rev_string}${build_name}" ]; then
			echo Running rm -rf ${upd_dir}/patches/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}
			rm -rf ${upd_dir}/patches/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}
		fi #End if must cleanse update patches dir

		if [ -d "${upd_dir}/scripts/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}" ]; then
			echo Running rm -rf ${upd_dir}/scripts/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}
			rm -rf ${upd_dir}/scripts/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}
		fi # End if must cleanse update scripts dir

		if [ -d "${upd_dir}/pub/${REVISION}-${BRANCH}${upd_rev_string}${build_name}" ]; then
			echo Running rm -rf ${upd_dir}/pub/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}
			rm -rf ${upd_dir}/pub/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}
		fi #End if must cleanse update pub dir

		# End cleaning up

		# Begin providing downloads
		echo
		echo Preparing for freebsd-update and downloads
		echo Logging to ${log_dir}/update-init-${target}.log when possible
		date

		# Copy disc1.iso and vm.raw if present. Allow inti.sh to fail if looking for them
		echo Looking for ${obj_dir}/release/disc1.iso
		if [ -f "${obj_dir}/release/disc1.iso" ]; then
			echo
			echo Copying the resulting disc1.iso to \
				${pub_dir}/FreeBSD-${BRANCH}${upd_rev_string}${build_name}-${target}-disc1.iso
			#${pub_dir}/FreeBSD-${BRANCH}-${upd_rev_string}${build_name}-${target}-disc1.iso
			cp ${obj_dir}/release/disc1.iso \
				${pub_dir}/FreeBSD-${REVISION}-${BRANCH}${upd_rev_string}${build_name}-${target}-disc1.iso || {
				echo disc1.iso copy failed
				exit 1
			}
		elif [ -f "${obj_dir}/release/memstick.img" ]; then
			echo
			echo Copying the resulting memstick.img to \
				${pub_dir}/FreeBSD-${BRANCH}-${upd_rev_string}${build_name}-${target}-memstick.img
			#${pub_dir}/FreeBSD-${BRANCH}${upd_rev_string}${build_name}-${target}-memstick.img
			cp ${obj_dir}/release/memstick.img \
				${pub_dir}/FreeBSD-${REVISION}-${BRANCH}${upd_rev_string}${build_name}-${target}-memstick.img || {
				echo memstick.img copy failed
				exit 1
			}
		else
			echo Neither disc1.iso nor memstick.img found
			# exit 1
		fi # End if disc1.iso

		echo
		echo Looking for ${obj_dir}/release/vm.raw
		ls -l ${obj_dir}/release/vm.raw

		echo Looking for ${obj_dir}/release/vm.raw
		if [ -f "${obj_dir}/release/vm.raw" ]; then
			echo
			echo Copying the resulting vm.raw to \
				${vm_img_dir}/FreeBSD-${BRANCH}${upd_rev_string}${build_name}-${target}-vm.raw
			cp ${obj_dir}/release/vm.raw \
				${vm_img_dir}/FreeBSD-${REVISION}-${BRANCH}${upd_rev_string}${build_name}-${target}-vm.raw || {
				echo vm.raw copy failed
				exit 1
			}
		fi # End if vm.raw

		echo
		echo Making ${upd_dir}/scripts/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}
		mkdir -p "${upd_dir}/scripts/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}" || {
			echo Failed to create ${upd_dir}/scripts/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}
			exit 1
		}

		# From the Handbook chapter
		echo
		echo Making ${upd_dir}/patches/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}
		mkdir -p "${upd_dir}/patches/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}" || {
			echo Make directory failed
			exit 1
		}

		if [ -f "${obj_dir}/release/disc1.iso" ]; then
			echo Generating SHA512 checksum for FreeBSD-${REVISION}-${BRANCH}${upd_rev_string}${build_name}-${target}-disc1.iso
			iso_sha512="$(sha512 -q ${pub_dir}/FreeBSD-${REVISION}-${BRANCH}${upd_rev_string}${build_name}-${target}-disc1.iso)" || {
				echo ISO Checksum generation failed
				exit 1
			}
		else
			iso_sha512="Using_dististribution_sets"
		fi # End if disc1.iso

		build_conf="${upd_dir}/scripts/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}/build.conf"

		echo
		echo Generating $build_conf

		cat >$build_conf <<EOF
export RELH=$iso_sha512
export DISTDIR="${obj_dir}/release"
export WORLDPARTS="base base-dbg lib32 lib32-dbg tests doc"
export SOURCEPARTS="src"
export KERNELPARTS="kernel kernel-dbg"
export EOL=$eol_date
EOF
		[ "$?" = 0 ] || {
			echo build.conf generation failed
			exit 1
		}

		echo
		echo The resulting ${upd_dir}/scripts/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}/build.conf reads
		echo
		cat ${upd_dir}/scripts/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}/build.conf || {
			echo build.conf generation failed
			exit 1
		}

		# tmpfs handling for upd_dir/work
		if [ "$tmpfs_host" ]; then
			upd_work_dir="${upd_dir}/work/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}"
			if ! [ -f "$upd_work_dir" ]; then
				mkdir -p "$upd_work_dir" || {
					echo Failed to create $upd_work_dir
					exit 1
				}
				echo Mounting $upd_work_dir tmpfs
				mount -t tmpfs tmpfs "$upd_work_dir" || {
					echo Failed to mount $upd_work_dir tmpfs
					exit 1
				}
			elif [ $(mount | grep tmpfs | grep -q "$upd_work_dir") ]; then
				echo $upd_work_dir is already mounted
				echo
				echo type k to keep or any other key to remount
				read response
				if ! [ "$response" = "k" ]; then
					response=""
					umount "$upd_work_dir" || {
						echo Failed to unmount $upd_work_dir
						exit 1
					}
					echo Mounting $upd_work_dir tmpfs
					mount -t tmpfs tmpfs "$upd_work_dir" || {
						echo Failed to mount $upd_work_dir tmpfs
						exit 1
					}
				fi # End if response
			fi # End if upd_work_dir exists
		fi # End if tmpfs_host

		# Reference
		#\time -h sh $upd_svr/scripts/init.sh amd64 13.0-CURRENT-356261

		echo
		echo Initializing the update with $update_init_string
		echo Logging to ${log_dir}/update-init-${target}.log
		echo
		echo Running $update_init_string
		echo
		date

		\time -h sh -x $update_init_string >${log_dir}/update-init-${target}.log || {
			echo update failed. See ${log_dir}/update-init-${target}.log
			exit 1
		}
		if ! [ "$tmpfs_host" ]; then
			touch ${log_dir}/update-init-${target}.done
		fi
	fi # End if must_init_update

	must_rsync_upd_init=1
	if [ -f "${log_dir}/rsync_upd_init-${target}.done" ]; then
		echo
		echo Successful update init rsync reported in ${log_dir}
		echo
		echo Type k to keep and continue or resynchronize it
		read response
		if [ "$response" = "k" ]; then
			response=""
			must_rsync_upd_init=0
		else
			response=""
			rm ${log_dir}/must_rsync_upd_init-${target}.done
		fi # End if response

	fi # End if must_rsync_upd_init

	if [ "$must_rsync_upd_init" = 1 ]; then

		# In case of re-runs
		if ! [ $REVISION ]; then
			echo Reading ${log_dir}/REVISION
			REVISION=$(cat ${log_dir}/REVISION) || {
				echo Could not determine REVISION from ${log_dir}/REVISION
				exit 1
			}
		fi # End if REVISION
		if ! [ $BRANCH ]; then
			echo Reading ${log_dir}/BRANCH
			BRANCH=$(cat ${log_dir}/BRANCH) || {
				echo Could not determine BRANCH from ${log_dir}/BRANCH
				exit 1
			}
		fi # End if BRANCH

		rsync_upd_init_string="rsync -atv --delete ${upd_dir}/work/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}/ ${tmpfs_host}:${upd_dir}/work/${REVISION}-${BRANCH}${upd_rev_string}${build_name}/${target}"
		echo rsync upd_init directory string is $rsync_upd_init_string

		\time -h $rsync_upd_init_string >${log_dir}/must_rsync_upd_init-${target}.log || {
			echo $rsync_upd_init_string rsync failed
			exit 1
		}
		touch ${log_dir}/update-init-${target}.done
	fi # End if must_rsync_upd_init

	if [ -f "${log_dir}/update-approve-${target}.done" ]; then

		if [ "$src_rev" ]; then
			upd_rev_string="-${src_rev}"
		fi # End if src_rev

		echo
		echo Successful update approve reported in ${log_dir}
		echo
		echo Type k to keep and continue or any other re-upload it
		read response
		if [ "$response" = "k" ]; then
			response=""
			must_approve_update=0
		else
			response=""
			rm ${log_dir}/update-approve-${target}.done
		fi # End if response
	fi # End if must_approve_update done

	if [ "$must_approve_update" = 1 ]; then
		echo
		echo Checking if the approval key is mounted
		if ! [ $(mount | grep -q keys) ]; then
			echo Mounting apporoval key
			sh ${upd_dir}/scripts/mountkey.sh
			# || \
			#{ echo Approval key mount failed ; exit 1 ; }
			# Private key directory is already mounted
			# Approval key mount failed
		fi # End if must_approve_update

		echo
		echo Approving the update with $update_approve_string
		echo Logging to ${log_dir}/update-approve-${target}.log
		echo
		echo Running $update_approve_string
		echo
		date

		\time -h sh $update_approve_string >${log_dir}/update-approve-${target}.log || {
			echo update failed. See ${log_dir}/update-approve-${target}.log
			exit 1
		}

		touch ${log_dir}/update-approve-${target}.done
	fi # End if must_approve_update

	if [ -f "${log_dir}/update-upload-${target}.done" ]; then

		if [ "$src_rev" ]; then
			upd_rev_string="-${src_rev}"
		fi # End if src_rev

		# In case of re-runs
		if ! [ $REVISION ]; then
			echo Reading ${log_dir}/REVISION
			REVISION=$(cat ${log_dir}/REVISION) || {
				echo Could not determine REVISION from ${log_dir}/REVISION
				exit 1
			}
		fi # End if REVISION
		if ! [ $BRANCH ]; then
			echo Reading ${log_dir}/BRANCH
			BRANCH=$(cat ${log_dir}/BRANCH) || {
				echo Could not determine BRANCH from ${log_dir}/BRANCH
				exit 1
			}
		fi # End if BRANCH

		echo
		echo Successful update upload reported in ${log_dir}
		echo
		echo Type k to keep and continue or any other re-upload it
		read response
		if [ "$response" = "k" ]; then
			response=""
			must_upload_update=0
		else
			response=""
			rm ${log_dir}/update-upload-${target}.done
		fi # End if response
	fi # End if must_upload_update done

	if [ "$must_upload_update" = 1 ]; then
		echo
		echo Uploading the update with $update_upload_string
		echo Logging to ${log_dir}/update-upload-${target}.log
		echo
		echo Running $update_upload_string
		echo
		date

		\time -h sh $update_upload_string >${log_dir}/update-upload-${target}.log || {
			echo update failed. See ${log_dir}/update-upload-${target}.log
			exit 1
		}
		#		if ! [ "$tmpfs_host" ]; then
		touch ${log_dir}/update-upload-${target}.done
		#		fi
	fi # End if must_upload_update

	echo
	echo Compressing installation media and VM image

	# DEBUG Consider separating this from the approval process but init may require the uncompressed ISO
	disc1_img="${pub_dir}/FreeBSD-${REVISION}-${BRANCH}${upd_rev_string}${build_name}-${target}-disc1.iso"
	if [ -f "$disc1_img" ]; then
		echo Found disc1.iso $disc1_img

		if [ -f "${disc1_img}.xz" ]; then
			echo Removing compressed ${disc1_img}.xz image
			rm ${disc1_img}.xz
		fi # End if compressed disc1

		echo
		echo Compressing iso image
		xz -T $jobs $disc1_img || echo Warning disc1.iso compression failed
	fi # End if disc1.iso

	vm_img="${pub_dir}/FreeBSD-${REVISION}-${BRANCH}${upd_rev_string}${build_name}-${target}-vm.raw"

	if [ -f "$vm_img" ]; then
		echo Found vm.raw $vm_img

		if [ -f "${vm_img}.xz" ]; then
			echo Removing compressed ${vm_img}.xz image
			rm ${vm_img}.xz
		fi # End if rm VM image

		# DEBUG consider moving higher in the process before the copy from tmpfs
		echo
		echo Compressing vm.raw image
		xz -T $jobs $vm_img || echo Warning vm.raw compression failed
	fi # End if vm_img

	echo End of compression steps
fi # End if freebsd-update=1

echo Consider running build-upgrade-patches.sh such as
#echo /usr/freebsd-update-build/scripts/build-upgrade-patches.sh amd64 13.0-CURRENT-359556 <previous>

echo
ls -larth /httpd | tail
ls -larth /httpd/download | tail
if [ "$tmpfs_host" ]; then
	echo
	mount | grep tmpfs
	echo
	echo Unmounting "${obj_dir}"
	umount "${obj_dir}"
	echo Unmounting "$upd_work_dir"
	umount "$upd_work_dir"
	#umount "$upd_pub_dir"
	echo Running mount again
	mount | grep tmpfs
#	fi # End if user input
fi # End if tmpfs_host
echo
echo In case it has not been said, thank you for your contributions to the Open Source community.
echo
exit 0
