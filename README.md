## OccamBSD: An application of Occam's razor to FreeBSD
a.k.a. "super svelte stripped down FreeBSD"

This script leverages FreeBSD build options and a kernel configuration file to build the minimum kernel and userland to boot FreeBSD under jail(8) and the bhyve and Xen hypervisors.

By default it builds from /usr/src to a tmpfs mount /usr/obj and a tmpfs work
directory mounted at /tmp/occambsd for speed and unobtrusiveness.

## Requirements

FreeBSD 13.0-RELEASE source code or later in /usr/src or modify the $src_dir variable as required

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
/tmp/occambsd/*log		OccamBSD log files
```

## Usage

The occambsd.sh script is position independent with one dependency, lib_occambsd.sh

It defaults to a bhyve-compatible build but can build for Jail with -j and Xen with -x

Root on ZFS support is enabled with the -z flag:
```
\time -h sh occambsd.sh -z
```
All writes will be to a tmpfs mount on /usr/obj and /tmp/occambsd

The script will ask for enter at each key step, allowing you to inspect the progress, along with asking a few questions.

To boot the results under bhyve, run:
```
sh load-bhyve-vmm-module.sh
sh load-bhyve-disk-image.sh
sh boot-bhyve-disk-image.sh
< explore the VM and shut down >
sh destroy-bhyve.sh
```

## Build times on an EPYC 7402p with SSD

buildworld:	1m11.35s real

buildkernel:	7.22s real

installworld:	15.49s real

installkernel:	0.35s real

Boot time:	Approximately two seconds

Total build and installation time for bhyve, Xen, and Jail: 3 minutes

## Know Issues

v2-beta - Only bhyve is working!

Jail is showing the root file system, for some reason
Xen requires re-testing

This is not an endorsement of GitHub
