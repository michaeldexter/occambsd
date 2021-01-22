headbanger.sh - a script to build FreeBSD 12.0 onward with many options

DISCLAIMER

The "head" in "headbanger" is misleading. FreeBSD "HEAD" is
more accurately called CURRENT or now "main", and this script also
bangs out STABLE branches as far back as FreeBSD 12.0, at which point the
architectures were separated into separate directories.


By default, this script should execute the following traditional commands and
direct the build output to /usr.obj/

'cd /usr/src ; make buildworld ; make buildkernel ; cd release ; make release'

The additional 1700+ lines help:

* Check out sources from SVN or Git
* Select a stock or custom KERNCONF
* Patch sources with a directory of patches
* Include a list of build options (see the src.conf manual page)
* Patch the sources for use with custom freebsd-update
* Build the release for use with custom freebsd-update
* Append a release with a custom name to avoid name collisions
	Useful for building releases with reviews applied
* Build to tmpfs and rsync the results to another host
* Resume all steps based on .done breadcrumb files

In practice, this script allows up.bsd.lv to maintain a centralized
source/binary object server and have multiple higher-performance
hosts perform builds for multiple revisions and architectures.


USAGE EXAMPLES

Build AMD64 SVN revision 366954 from local SVN mirror /pub/FreeBSD/svn/base
	The architecture defaults to the host architecture

sh headbanger.sh -s "/build/366954/src" -o "/build/366954/obj" -l \
	"/build/366954/log" -r 366954 -S "file:///pub/FreeBSD/svn/base" \
	-b "stable/12" -t amd64 -T amd64


Build ARM64 Git revision/hash 7ae27c2d6c4 from local Git mirror
	/pub/FreeBSD/git/src with the GENERIC-NODEBUG kernel configuration file
	while performing freebsd-update preparations (-u) and
	rsync'ing the results to host 10.40 because FreeBSD cannot be
	built on NFS for want of chflags(1) or 'cp -p' support:

sh headbanger.sh -s "/build/7ae27c2d6c4/src" -o "/build/7ae27c2d6c4/obj" \
	-l "/build/7ae27c2d6c4/log" -r 7ae27c2d6c4 -g "/pub/FreeBSD/git/src" \
	-t arm64 -T aarch64 -R "10.0.0.40" -k "GENERIC-NODEBUG" -u


Build SVN revision 364182 with kernel GENERIC-NODEBUG in the default /usr/src
	and /usr/obj with bhyve NE2000 patches in /build/diffs/ and an appended
	name "-ne2k" to distinguish it:

sh headbanger.sh -o "ne2k-build-logs" -r 364182 -b "head" -k "GENERIC-NODEBUG" \
	-d "/pub/scripts/diffs" -n "-ne2k"


Build the source in /usr/src with ONLY the listed build options and an
	out-of-src kernel configuration file named "OCCAM". All other build
	options are excluded, resulting in a reduced-size userland.

sh headbanger.sh -O "WITHOUT_AUTO_OBJ WITHOUT_UNIFIED_OBJDIR WITHOUT_INSTALLLIB WITHOUT_LIBPTHREAD WITHOUT_LIBTHR WITHOUT_LIBCPLUSPLUS WITHOUT_CRYPT WITHOUT_DYNAMICROOT WITHOUT_BOOT WITHOUT_LOADER_LUA WITHOUT_LOCALES WITHOUT_ZONEINFO WITHOUT_VI" -K /tmp/OCCAM"


KNOWN ISSUES

* Search for DEBUG to find in-line known issues

* ARM64 disc1.iso images will fail to build with makefs on most 12.* versions

* Fix: https://svnweb.freebsd.org/base/head/usr.sbin/makefs/cd9660/cd9660_eltorito.c?revision=365847&view=co

* hs-ShellCheck would prefer more quoting

* Complex tests like "$svn_svr" -o "$git_svr" -o "$git_dir" should be verified

* eol_date should be a command line argument but hopefully freebsd-update-build will use MANIFEST files

* git(1) appears to no like output redirection - re-test this

* RPi and similar image generation would be great but the current tool is
	completely independent of the standard build

* You will find additional issues


ACKNOWLEDGMENTS

Thank you Conor Beh for your extensive help with the up.bsd.lv effort.
Thank you dteske@ for your years of /bin/sh mentorship.
