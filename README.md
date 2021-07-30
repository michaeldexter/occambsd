## occambsd: An application of Occam's razor to FreeBSD
a.k.a. "super svelte stripped down FreeBSD"

This script leverages FreeBSD build options and a kernel configuration file
to build the minimum kernel and userland to boot under the bhyve hypervisor.

By default it builds from /usr/src to a tmpfs mount /usr/obj and a tmpfs work
directory mounted at /tmp/occambsd for speed and unobtrusiveness.

## Requirements

FreeBSD 13.0-RELEASE source code or later in /usr/src

## Layout

```
/tmp/occambsd
/tmp/occambsd/src.conf                      OccamBSD src.conf
/tmp/occambsd/OCCAMBSD                      OccamBSD kernel configuration file

/tmp/occambsd/bhyve-kernel                  bhyve kernel directory
/tmp/occambsd/bhyve-mnt                     bhyve disk image mount point
/tmp/occambsd/bhyve.raw                     bhyve disk image with kernel
/usr/obj/usr/src/amd64.amd64/release/       disc1.iso and memstick.img location
/tmp/occambsd/load-bhyve-vmm-module.sh      Script to load vmm.ko
/tmp/occambsd/load-bhyve-disk-image.sh      Script to load bhyve kernel from disk image
/tmp/occambsd/load-bhyve-directory.sh       Script to load bhyve kernel from directory
/tmp/occambsd/load-bhyve-disc1.iso.sh       Script to load bhyve from a 'make release' ISO image
/tmp/occambsd/load-bhyve-memstick.img.sh    Script to load bhyve from a 'make release' installer image

/tmp/occambsd/boot-bhyve.raw.sh             Script to boot bhyve from disk image or directory
/tmp/occambsd/boot-bhyve-disc1.iso.sh       Script to boot bhyve from a 'make release' ISO image
/tmp/occambsd/boot-bhyve-memstick.img.sh    Script to boot bhyve from a 'make release' installer image
/tmp/occambsd/destroy-occambsd-bhyve.sh     Script to clean up the bhyve virtual machine

/tmp/occambsd/xen-kernel                    Xen kernel directory
/tmp/occambsd/xen-mnt                       Xen disk image mount point
/tmp/occambsd/xen.raw                       Xen disk image with kernel
/tmp/occambsd/xen-occambsd.cfg              Xen disk image boot configuration file
/tmp/occambsd/xen-occambsd-kernel.cfg       Xen directory boot configuration file
/tmp/occambsd/boot-occambsd-xen.sh          Script to boot Xen krenel from disk image
/tmp/occambsd/boot-occambsd-xen-kernel.sh   Script to boot Xen kernel from directory
/tmp/occambsd/destroy-occambsd-xen.sh       Script to clean up the Xen virtual machine

/tmp/occambsd/jail                          Jail root directory
/tmp/occambsd/jail.conf                     Jail configuration file
/tmp/occambsd/boot-occambsd-jail.sh         Script to boot the jail(8)
```

## Usage

The occambsd.sh script is position independent and can be executed anywhere on the file system:
```
\time -h sh occambsd.sh
```
All writes will be to a tmpfs mount on /usr/obj and /tmp/occambsd

The script will ask for enter at each key step, allowing you to inspect the progress, along with asking a few questions.

To boot the results under bhyve, run:
```
sh load-bhyve-vmm-module.sh
sh load-bhyve-disk-image.sh
sh boot-occambsd-bhyve.sh
< explore the VM and shut down >
sh destroy-occambsd-bhyve.sh
```

## Build times on an EPYC 7402p

buildworld:	1m13.41s, 1m12.14s warm ARC

buildkernel:	12.86s, 9.79s warm ARC

installworld: 18.46s, 15.05s warm ARC

installkernel:	0.35s, 0.32s warm ARC

Boot time:	Approximately two seconds

Total build and installation time for bhyve, Xen, and Jail: 3 minutes

This is not a desired endorsement of GitHub
