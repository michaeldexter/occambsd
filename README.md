## OccamBSD: An application of Occam's razor to FreeBSD
a.k.a. "super svelte stripped down FreeBSD"

This script leverages FreeBSD build options and a minimum kernel configuration file to build the minimum kernel and userland to boot FreeBSD under jail(8) and the bhyve and Xen hypervisors.

By default it builds from /usr/src to a tmpfs mount /usr/obj and a tmpfs work
directory mounted at /tmp/occambsd for speed and unobtrusiveness.

## Motivations

FreeBSD Jail has long provided a lightweight container for services and applications. Internet-facing services are by definition at risk of remote abuse of the service and/or the operating system hosting them. A "minimum" Jail or virtual machine can theoretically contain only the dependencies to deliver the desired service, and nothing more. In practice, FreeBSD offers a flexible build system with which build options (man src.conf) and kernel configuration options can significantly reduce the kernel and userland of a specially-build system, rather than using the standard "buildworld". Unfortunately, the supported build option shave been inconsistent in their reliability, up until the 13.0 release of FreeBSD. While the FreeBSD "build option survey" exists to test the build options in mass, it is highly inconvenient to use. The related "bos-ng" project improves upon it, but the frequent exercise of many options at once is proving more effective in their validation along active source branches. OccamBSD can generate reduced-size userlands using either buildworld with build options/exclusions, or "from scratch", using the -u options which builds and installs the individual components needed to boot and log in.

The OccamBSD approach can provide:

* Validation of the FreeBSD build system
* The foundation for purpose-build Jails/containers and virtual machines
* The foundation for embedded projects and products
* An academic tour of the essential components of FreeBSD that are used by virtually all users at all times
* An inventory of the essential components of FreeBSD that must be prioritized for security auditing, quality assurance, and documentation
* An opportunity to review what's left after a "userland" build for consideration of removal from base
* Hopefully the foundation for an update mechanism to replace freebsd-update based on lessons from the up.bsd.lv proof of concept
* To be determined: The relationship of this to "packaged base"; the Makefile hygiene related to this should prove useful

In short, to help deliver on the unwavering FreeBSD promise to provide a flexible, permissively-licensed operating system for use for nearly any purpose.

## Requirements

FreeBSD 13.0-RELEASE or later source code in /usr/src or modify the $src_dir variable in the script as required. A Git-compatible client if cloning from GitHub.

## Layout
```
/tmp/occambsd/OCCAMBSD		OccamBSD kernel configuration file
/tmp/occambsd/src.conf		OccamBSD src.conf used for the build
/tmp/occambsd/kernel		OccamBSD kernel directory for bhyve and Xen
/tmp/occambsd/occambsd.raw	OccamBSD raw disk image with world and kernel for bhyve and Xen
/tmp/occambsd/image-mnt		OccamBSD raw disk image mount point
/tmp/occambsd/jail-mnt		OccamBSD jail image mount point
/tmp/occambsd/jail.conf		OccamBSD jail configuration file
/tmp/occambsd/*load.sh		OccamBSD generated load scripts
/tmp/occambsd/*boot.sh		OccamBSD generated boot scripts
/tmp/occambsd/logs/*		OccamBSD log files
```

## Usage

The occambsd.sh script is position independent with one dependency, lib_occambsd.sh

It defaults to a build a bhyve-compatible, root-on-UFS virtual machine and different behavior is controlled by the following flags:

```
-z	Use root-on-ZFS rather than UFS
-x	Target Xen rather than bhyve
-j	Target Jail rather than bhyve
-u	Build and install a minimum userland without build|installworld
-r	Build a release with bootable disc1 and memstick images
	(Only supported with a standard userland)
-q	Quiet mode - do not ask to continue at every major step
```

For example, to create a root-on-ZFS virtual machine and note the time it takes to build:
```
\time -h sh occambsd.sh -z
```
All written output is to tmpfs mounts on /usr/obj and /tmp/occambsd

To boot the results under bhyve, run:
```
sh load-bhyve-vmm-module.sh
sh load-bhyve-disk-image.sh
sh boot-bhyve-disk-image.sh
< explore the VM and shut down >
sh destroy-bhyve.sh
```

## Results from an EPYC 7402p
```
UFS/bhyve/buildworld:		1m14.31s real, 7.2M kernel, 174M total
ZFS/bhyve/buildworld:		1m28.78s real, 7.2M kernel, 120M total
UFS/bhyve/userland:		2m6.56s real, 105M
UFS/ZFS buildkernel:		19.52 real
Total UFS/bhyve/buildworld:	2m10.51s real
Total ZFS/bhyve/buildworld:	2m7.28s real ~ 2m27.17s real
ZFS/bhyve/buildworld release:	3m35.70s real

bhyve boot time: 		two ~ three seconds
```
Note that ARC "warmth" on the host will speed build times

## Known Issues/To Do

* v3-beta - bhyve target is tested, Xen is not
* Lots of 14-CURRENT fallout for both "buildworld" and "userland" approaches
* Investigate Juniper's static_libpam towards the goal of an optional fully statically-built userland
* Could have bhyve and Xen-specific kernel configuration files
* Could add release support to the minimum userland
* Could add automatic du(1) and tree(1) (if installed) analysis
* Would be nice to target a Raspberry Pi image

## Related Tools

NanoBSD (nanobsd(8) and /usr/src/tools/tools/nanobsd/) is a "utility used to create a FreeBSD system image suitable for embedded applications" that produces a flashable disk image that can have one or more additional boot partitions for upgrading and fallback. A FreeBSD 13.0R build of NanoBSD consumes 2.7G of disk space per boot partition, representing a full installation of FreeBSD. Using NanoBSD with FreeBSD 13.0R requires a larger default image size and note that it defaults to 'make -j 3'. A NanoBSD installation can be reduced using KERNCONF and src.conf entries. Consider these changes to ~/nanobsd/defaults.sh:
```
NANO_PMAKE="make -j $(sysctl -n hw.ncpu)"
NANO_MEDIASIZE=16000000
```

picobsd (formerly referred to as PicoBSD) was located in /usr/src/release/picobsd and appears to have been removed from FreeBSD 13.0R. It can be found in the 12.X and earlier sources, and is unique in that it includes custom utilities.

TinyBSD (/usr/src/tools/tools/tinybsd) is focused on minimization of a FreeBSD installation but is not compatible with recent FreeBSD. TinyBSD uses seven template files, bridge, firewall, vpn, wrap, default, minimal, and wireless, which each have a dedicated kernel configuration file named TINYBSD, plus a list of all binaries to be copied in to the target image named tinybsd.basefiles. TinyBSD supports a list of desired ports, and support files like /etc/fstab and /etc/rc.conf. By contrast, OccamBSD uses either 'make installworld' or selective 'make install' for the installation of binaries.

[Crochet](https://github.com/freebsd/crochet) is a a relatively-recent image builder designed to "Build FreeBSD images for RaspberryPi, BeagleBone, PandaBoard, and others." Its functionality may be partly replaced by the official ~/src/release tools.

[Poudriere image.sh](https://github.com/freebsd/poudriere/blob/master/src/share/poudriere/image.sh) is an actively-developed framework for image generation that is well documented as part of the [BSD Router Project](https://bsdrp.net/documentation/technical_docs/poudriere?s[]=build) A Poudriere image installation can be reduced using KERNCONF and src.conf entries.

[mkjail](https://github.com/mkjail/mkjail) can be used on FreeBSD to create new jails, keep them updated, and upgrade to a new release.

Was μbsd a thing?

## Observations

There are (and have been) many FreeBSD build tools but few, with the notable exception of TinyBSD, have made any effort to "minimize" the FreeBSD kernel and/or base system with any effort beyond a kernel configuration file and a src.conf file. This is understandable, given that the FreeBSD build options have been under-maintained for decades. FreeBSD 13.0-RELEASE marks an important milestone with the quality of its build options. Unfortunately, FreeBSD 14-MAIN already suffers from build option fallout. (Sad face)

This project is not an endorsement of GitHub
