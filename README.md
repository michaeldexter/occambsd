## occambsd: An application of Occam's razor to FreeBSD
a.k.a. "super svelte stripped down FreeBSD"

This script leverages FreeBSD build options and a kernel configuration file to build the minimum kernel and userland to boot FreeBSD under jail(8) and the bhyve and Xen hypervisors.

By default it builds from /usr/src to a tmpfs mount /usr/obj and a tmpfs work
directory mounted at /tmp/occambsd for speed and unobtrusiveness.

## Requirements

FreeBSD 13.0-RELEASE source code or later in /usr/src

## Layout

```
/tmp/occambsd/OCCAMBSD                      OccamBSD kernel configuration file
/tmp/occambsd/all_options.txt               A list of all available "WITHOUT" build options
/tmp/occambsd/bhyve-kernel                  OccamBSD bhyve kernel directory
/tmp/occambsd/bhyve-mnt                     OccamBSD bhyve mount point
/tmp/occambsd/bhyve.raw                     OccamBSD bhyve raw disk image with world and kernel
/tmp/occambsd/boot-bhyve-disc1.iso.sh       Script to boot bhyve from a 'make release' ISO installer image
/tmp/occambsd/boot-bhyve-memstick.img.sh    Script to boot bhyve from a 'make release' memstick installer image
/tmp/occambsd/boot-bhyve-disk-image.sh      Script to boot the loaded OccamBSD bhyve VM from disk image or directory
/tmp/occambsd/boot-jail.sh                  Script to boot the OccamBSD jail(8)
/tmp/occambsd/boot-xen-directory.sh         Script to boot the OccamBSD Xen virtual machine from directory
/tmp/occambsd/boot-xen-disk-image.sh        Script to boot the OccamBSD Xen virtual machine from disk image
/tmp/occambsd/destroy-bhyve.sh              Script to clean up the OccamBSD bhyve virtual machine
/tmp/occambsd/destroy-xen.sh                Script to clean up the OccamBSD Xen virtual machine
/tmp/occambsd/jail                          OccamBSD jail root directory
/tmp/occambsd/jail.conf                     OccamBSD jail configuration file
/tmp/occambsd/load-bhyve-directory.sh       Script to bhyve load OccamBSD kernel from directory
/tmp/occambsd/load-bhyve-disc1.iso.sh       Script to bhyve load OccamBSD kernel from 'make release' ISO installer image
/tmp/occambsd/load-bhyve-disk-image.sh      Script to bhyve load OccamBSD kernel from disk image
/tmp/occambsd/load-bhyve-memstick.img.sh    Script to bhyve load OccamBSD kernel from 'make release' memstick installer image
/tmp/occambsd/load-bhyve-vmm-module.sh      Script to load the bhyve kernel module vmm.ko
/tmp/occambsd/src.conf                      OccamBSD world configuration file
/tmp/occambsd/xen-kernel                    OccamBSD Xen kernel directory
/tmp/occambsd/xen-kernel.cfg                OccamBSD Xen directory boot configuration file
/tmp/occambsd/xen-mnt                       OccamBSD Xen mount point
/tmp/occambsd/xen.cfg                       OccamBSD Xen raw disk image boot configuration file
/tmp/occambsd/xen.raw                       OccamBSD Xen raw disk image with world and kernel
/tmp/occambsd/*.log                         OccamBSD log files for larger steps
/usr/obj/usr/src/amd64.amd64/release/       disc1.iso and memstick.img location
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

This is not a desired endorsement of GitHub
