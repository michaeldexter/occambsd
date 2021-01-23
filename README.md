## occambsd: An application of Occam's razor to FreeBSD
a.k.a. "super svelte stripped down FreeBSD"

This script leverages FreeBSD build options and a kernel configuration file
to build the minimum kernel and userland to boot under the bhyve hypervisor.

By default it builds from /usr/src to a tmpfs mount /usr/obj and a tmpfs work
directory mounted at /tmp/occambsd for speed and unobtrusiveness.

## Requirements

FreeBSD 13.0-ALPHA1 source code or later

## Layout

```
/tmp/occambsd
/tmp/occambsd/jail		                   A world/distribution for use with jail(8)
/tmp/occambsd/root		                  The optional virtual machine kernel directory
/tmp/occambsd/occambsd.raw	            The virtual machine disk image
/tmp/occambsd/mnt		                    A mount point used during VM image creation
/tmp/occambsd/load-vmm-module.sh        A script to load the vmm.ko kernel module
/tmp/occambsd/load-from-directory.sh    A script to load the VM kernel from the directory
/tmp/occambsd/load-from-disk-image.sh   A script to load thd VM from disk image (pick one)
/tmp/occambsd/boot-occam-vm.sh          A script to boot the occam VM
/tmp/occambsd/destroy-occam-vm.sh       A script to destroy/clean-up the occam VM
```

bhyve load, boot, and destroy commands will be printed after build completion.

## Build times on an EPYC 7402p

buildworld:	1m15.82s
buildkernel:	9.35s
installworld:	14.63ss
installkernel:	0.32s

Total:		Approximately three minutes

Boot time:	Approximately two seconds

This is not a desired endorsement of GitHub
