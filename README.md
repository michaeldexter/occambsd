## OccamBSD: An application of Occam's razor to FreeBSD
a.k.a. "super svelte stripped down FreeBSD"

This script leverages FreeBSD build options and a minimum kernel configuration file to build the minimum kernel and userland to boot FreeBSD under jail(8) and the bhyve and Xen hypervisors.

By default it builds from /usr/src to a tmpfs mount /usr/obj and a tmpfs work
directory mounted at /tmp/occambsd for speed and unobtrusiveness.

## Requirements

FreeBSD 13.0-RELEASE or later source code in /usr/src or modify the $src_dir variable in the script as required. A Git client if cloning from GitHub.

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

* v3-beta - bhyve target is tested, Xen is not. Not tested on CURRENT

* Investigate Juniper's static_libpam towards the goal of an optional fully statically-built userland

* Could have bhyve and Xen-specific kernel configuration files

* Could add release support to the minimum userland

* Would be nice to target a Raspberry Pi image


This is not an endorsement of GitHub
