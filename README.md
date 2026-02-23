## OccamBSD: An application of Occam's razor to FreeBSD
a.k.a. "super svelte stripped down FreeBSD"

## Imagine: Virtual and Hardware Machine Boot Image Imaging at the block level
a.k.a. "No one clicks 'next, next, next, finish' to install cloud systems, right?"

## Propagate: "Packaged Base" Jails and Boot Environments at the file level
a.k.a. "bsdinstall(8) and bsdconfig(8) should do all this, right?"

This evolving project incorporates several inter-related scripts with the broad goal of producing and/or deploying bootable FreeBSD, OmniOS, Debian, RouterOS, and Windows systems from source or downloaded boot images. Official OpenBSD boot images would be greatly appreciated.

```
occambsd.sh		Builds a "svelte", purpose-build FreeBSD bootable disk image using the FreeBSD build(7) system
profile-*.txt		Build profiles for occambsd.sh
imagine.sh		Images upstream bootable disk images to hardware and virtual machine images
propagate.sh		Builds packaged base jails and boot environments
autounattend_xml	A directory of Windows autounattend.xml files used by imagine.sh
```

## Brief History

1991: "Unix makes perfect sense as 'behind the scenes of the computer', like working behind the camera"
1998: "Red Hat Linux 5.2 is a halfway-decent Unix clone in which RPM "packaged base" accounts for most OS files but unleashes RPM Hell for third party software"
1999: "Red Hat Linux 6.0 is a stunningly-bad Windows clone with that early GNOME release"
1999: "Red Hat Linux 6.1 up2date finally allows online updating, better late than never"
2002: "FreeBSD Jail in 4.7 mitigates RPM Hell and small Jails can be built with SKIPDIR and build options"
2003: "FreeBSD 5.0 jls(8) and jexec(8) are awesome but wow is that sucker unstable"
2003: FreeBSD 5.1 introduces AMD64 support
2006: BSD.lv SysJail OpenBSD Jails, until systrace was removed
2009: BSD.lv mult *went there*
2012: FreeNAS 8.2 delivers OpenZFS v28
2012: FreeBSD 9.0 delivers Clang/LLVM
2014: FreeBSD 10.0 introduces the BHyVe come bhyve hypervisor
2021: FreeBSD 13.0 introduces OpenZFS and working build options after years of bug reporting
2023: FreeBSD 14.0 preserves working build options and introduces root-on-ZFS VM-IMAGES
2025: FreeBSD 15.0 institutionalizes packaged base and adds bhyve/ARM64 but "Who broke the damn build options?"

Finally, Jail, OpenZFS, bhyve and packaged base on AMD64 and ARM64 are here!

"That only took 34 <expletive deleted> years"

## Motivations

* OpenZFS everywhere
* Small Jail Containers and Virtual Machines
* Never using a "next, next, next, finish" installer again
* Easy deployment of FreeBSD, OmniOS, Debian, RouterOS, and Windows using or or two commands

## Context

There have been countless "Cloud" and "Virtual Machine" boot images or "appliances" produced for various operating systems over the years. These are often symptoms of the use of "feature-rich" virtual machine boot images formats such as QCOW2, VDI, VHD(X), and others. In OpenZFS environments, any such... "copy on write!", "snapshot", or compression features of a non-raw disk image format are  categorically obsoleted by OpenZFS below the POSIX layer. 

On OpenZFS, a raw boot image can benefit from snapshotting, compression, thin/over-provisioning, and many other features without modification or intervention. A raw boot image can also be imaged to an OpenZFS volume (ZVOL) or shared via iSCSI or Fiber Channel.

Above all, a raw boot image can be imaged to a *hardware* boot device and booted on compatible hardware platforms, leaving "cloud" to only referring to configuration, not operation.

In short, they are all, and always have been fundamentally *boot images*, and not "Cloud" or "Virtual Machine" images. For example, the FreeBSD "raw" "VM-IMAGE" files can be imaged to hardware devices and booted, which is exactly what imagine.sh helps with. Enjoy!

## OccamBSD Motivations

FreeBSD Jail has long provided a lightweight container for services and applications. Internet-facing services are by definition at risk of remote abuse of the service and/or the operating system hosting them. A "minimum" Jail or virtual machine can theoretically contain only the dependencies to deliver the desired service, and nothing more, reducing the attack surface. In practice, FreeBSD offers a flexible build system with which build options (man src.conf) and kernel configuration options can significantly reduce the kernel and userland of a tailor-built system, rather than using the standard "buildworld". Furthermore, recent progress with "reproducible builds" can guarantee that stock components remain stock. Unfortunately, the supported build option have been inconsistent in their reliability up until the 13.0 release of FreeBSD.

The OccamBSD approach can provide:

* Validation of the FreeBSD build system and its build options using build-option-smoke-test.sh
* The foundation for embedded projects and products
* An academic tour of the essential components of FreeBSD that are used by all users at all times
* An academic tour of the FreeBSD build system
* An inventory of the essential components of FreeBSD that must be prioritized for security auditing, quality assurance, and documentation
* An opportunity to review what's left after a "userland" build for consideration of additional build options or removal from base
* Hopefully the foundation for an update mechanism to replace freebsd-update based on lessons from the up.bsd.lv proof of concept
* To be determined: The relationship of this to "packaged base"; the Makefile hygiene related to this should prove useful

In short, to help deliver on the FreeBSD promise to provide a flexible, permissively-licensed operating system for use for nearly any purpose.

## OccamBSD Output Layout

```
/tmp/occambsd/OCCAMBSD		OccamBSD kernel configuration file
/tmp/occambsd/all_modules.txt	Generated list of all available kernel modules
/tmp/occambsd/all_options.conf	Generated list of all available build options
/tmp/occambsd/all_withouts.txt	Generated list of all "WITHOUT" build options
/tmp/occambsd/logs		Directory of build output logs from each stage 
/tmp/occambsd/src.conf		The generated src.conf excluding components
/tmp/occambsd/profile-*.txt	The profile used for the build
/tmp/occambsd/vm.raw		A generated Virtual Machine image
/tmp/occambsd/jail		A generated Jail root directory
/tmp/occambsd/9pfs		A generated 9pfs root directory
/tmp/occambsd/*.sh		Jail and VM management scripts
```

## Usage

```
-p <profile file> (Required)
-s <source directory> (Default: /usr/src)
-o <object directory> (Default: /usr/obj)
-O <output directory> (Default: /tmp/occambsd)
-w (Reuse the previous world objects)
-k (Reuse the previous kernel objects)
-a <additional build option to exclude>
-b (Package base)
-G (Use the GENERIC/stock world - increase image size as needed)
-g (Use the GENERIC kernel)
-P <patch directory> (NB! This will modify your sources!)
-j (Build for Jail boot)
-9 (Build for p9fs boot - 15.0-CURRENT only)
-v (Generate VM image and boot scripts)
-z (Generate ZFS VM image and boot scripts)
-Z <size> (VM image siZe i.e. 500m - default is 2.9G)
-S <size> (VM image Swap size i.e. 500m - default is 100M)
-i (Generate disc1 and bootonly.iso ISOs)
-m (Generate mini-memstick image)
-n (No-op dry-run only generating configuration files)
```

By default, occambsd.sh will only perform a build using the specified profile and requires additional flags to generate Jail and Virtual Machine images.

To build a root-on-ZFS Virtual Machine image using FreeBSD 14.0 or later:

```
doas sh occambsd.sh -v -z -p profile-amd64-zfs14.txt
```

Status: OccamBSD needs testing and refactoring for FreeBSD 15.0

# imagine.sh

## Usage

```
-O <output directory> (Default: ~/imagine-work)
-a <architecture> [ amd64 | arm64 | i386 | riscv ] (Default: Host)
-r [ obj | /path/to/image | <version> | omnios | debian ]
   obj i.e. /usr/obj/usr/src/<target>.<target_arch>/release/vm.ufs.raw
   /path/to/image.raw for an existing image
   <version> i.e. 15.0-RELEASE | 16.0-CURRENT | 15.0-ALPHAn|BETAn|RCn
   (Default: Host)
-o (Offline mode to re-use fetched releases)
-t <target> [ img | /dev/<device> | /path/myimg ] (Default: img)
-T <mirror target> [ img | /dev/<device> ]
-f (FORCE imaging to a device without prompting for confirmation)
-g <gigabytes> (grow image to gigabytes i.e. 10)
-p "<packages>" (Quoted space-separated list)
-c (Copy cached packages from the host to the target)
-C (Clean package cache after installation)
-u (Add root/root and freebsd/freebsd users and enable sshd)
-d (Enable crash dumping)
-m (Mount image and keep mounted for further configuration)
-M <Mount point> (Default: /media)
-V (Generate VMDK image wrapper)
-v (Generate VM boot scripts)
-n (Include tap0 e1000 network device in VM boot scripts)
-U (Use a UFS image rather than ZFS image)
-Z <new zpool name if conflicting i.e. with zroot>
-A (Enable ZFS ARC cache to default rather than metadata)
-x <autounattend.xml file for Windows> (Requires -i)
-i <Full path to installation ISO file for Windows> (Requires -x)
```
imagine.sh downloads a FreeBSD official release, stable, or current "VM-IMAGE", or a custom-build 'make release' or OccamBSD vm.raw image. It can also retrieve image OmniOS, Debian, and RouterOS images, plus prepare Windows boot devices using autounattend.xml files. The resulting images can be booted in bhyve, QEMU, or Xen.

Note that this requires use of the /media mount point, administrative privileges, and it creates /root/imagine-work for use for downloaded artifacts.

## imagine.sh Output Layout Essentials

```
~/imagine-work			Working directory for imagine.sh operations
~/imagine-work/15.0-RELEASE	Directory of upstream, uncompressed images/src.txz
~/imagine-work/FreeBSD-amd64-15.0-RELEASE-zfs.raw	Example VM image
~/imagine-work/bhyve-15.0-RELEASE-amd64-zfs.sh		Example bhyve boot script
```

To download a VM-IMAGE matching the host's version and generate boot scripts:

```
doas sh imagine.sh -v
```

To download an OmniOS image (version embedded in the script for want of "Latest" aliases on the mirrors) and image it to a hardware device /dev/da0 :

```
doas sh imagine -r omnios -t /dev/da0
```

Note: OmniOS is slow to boot while performing cloud init operations that can be disabled with:
```
svcadm disable svc:/system/cloud-init:initlocal
svcadm disable svc:/system/cloud-init:init
svcadm disable svc:/system/cloud-init:modules
svcadm disable svc:/system/cloud-init:final
```

# Example Scenario of using occambsd.sh with imagine.sh

Example usage on a FreeBSD 14.0 system with 'makefs -t zfs' support to produce a minimum root-on-ZFS image that is grown to 10GB in size and boots in seconds:

```
doas sh occambsd.sh -p profile-amd64-zfs.txt -v -z
doas sh imagine.sh -r obj -g 10 -v -z
```

# Example Window Usage

```
doas sh imagine.sh -x autounattend_xml/win2025.iso -i win2025.iso -g 30
```
## Imagine and Propagate

Elaborate example of using imagine.sh in conjunction with propagate.sh:
```
doas sh imagine.sh -r 16.0-CURRENT -t /dev/da0 -p "doas tmux got" -d -g 10 -u -Z mypool -v -n -m
doas sh propagate.sh -r 15.0-STABLE -t mypool/ROOT/15.0-STABLE -n -p "doas tmux got"
doas sh propagate.sh -r 16.0-CURRENT -t mypool/ROOT/16.0-CURRENT -n -b -p "doas tmux got"
```
Which breaks down, by flag:
```
-r Image the 15.0-RELEASE release of FreeBSD to a USB device attached at /dev/da0
-p "doas tmux got" Install the doas, tmux and got packages
-d Enable crash dumping
-g Grow the image to 10GB
-u Add the root and freebsd users, and enable sshd following the FreeBSD RPi/RockPro64/etc. "ISO" images
-Z Rename the default zpool of "zroot" to "mypool"
-v Create bhyve, QEMU, and Xen boot scripts (will only work with the device attached at /dev/da0)
-n Add a e1000 network interface to the bhyve boot script
-m Keep the image mounted for the next steps...

-r 15.0-STABLE Install a 15.0-STABLE weekly snapshot
-t Install to a new boot environment "mypool/ROOT/15.0-STABLE"
-n Fully nest all datasets rather than use a single one
-p "doas tmux got" Install the doas, tmux and got packages

-r 16.0-CURRENT Install a 16.0-CURRENT weekly snapshot
-t Install to a new boot environment "mypool/ROOT/16.0-CURRENT"
-n Fully nest all datasets rather than use a single one
-b Update the EFI boot code in case it is needed by 16.0-CURRENT
-p "doas tmux got" Install the doas, tmux and got packages

```

Note the -c flag that copies packages from the host's package cache, saving on repeated retrievals. BE SURE TO GROW IMAGES ADEQUATELY TO RECEIVE THE PACKAGE CACHE.

# propagate.sh

## Usage

```
-r <release> (i.e. 15.0-RELEASE | 16.0-CURRENT Default: Host)
-a <architecture> [ amd64 | arm64 ] (Default: Host)
-t <target root> (Boot environment or Jail path - Required)
   i.e. zroot/ROOT/pkgbase15, zroot/jails/pkgbase15 datasets or
   /jails/myjail directory Default: /tmp/propagate/root)
-n Create fully-nested datasets
-q (quarterly package branch rather than latest)
-m (Keep boot environment mounted for further configuration)
-p "<additional packages>" (Quoted space-separated list)
-s (Perform best-effort sideload of the current configuration)
-c (Copy cached packages from the host to the target)
-C (Clean package cache after installation)
-G (Write a graph of base package selections and dependencies)
-b (Install boot code)
-d (Enable crash dumping)
-u (Add root/root and freebsd/freebsd users and enable sshd)
-o <output directory/work> (Default: /tmp/propagate)
```

## MISCELLANEOUS

## OccamBSD build results from an EPYC 7402p

```
UFS/bhyve/buildworld:		1m14.31s real, 7.2M kernel, 174M total
ZFS/bhyve/buildworld:		1m28.78s real, 7.2M kernel, 120M total
UFS/ZFS buildkernel:		19.52 real
Total UFS/bhyve/buildworld:	2m10.51s real
Total ZFS/bhyve/buildworld:	2m7.28s real ~ 2m27.17s real

bhyve boot time: 		two ~ three seconds
```

## OccamBSD profile-minimum.txt build time results on a Xeon E-2144G CPU @ 3.60GHz

```
UFS/buildworld		3m39.37s real
UFS/buildkernel		32.31s real
UFS/vm-image		1m31.32s real
```

Note that ARC "warmth" on the host will speed build times

## build(7) Notes

FreeBSD is traditionally built as a "world" userland and a kernel with "make buildworld" and "make buildkernel" respectively. These are installed to a destination directory "DESTDIR" that can be the build host itself, a jail root directory, a mounted machine boot image, or release directories for packing as "distribution sets" for use by bsdinstall(8), the default FreeBSD installer. The "make vm-image" build target produces .qcow2, .raw, .vhd, and .vmdk boot images directly from /usr/obj/ artifacts and does not require intermediary distribution sets. See:

```
[download.freebsd.org/snapshots/VM-IMAGES](https://download.freebsd.org/snapshots/VM-IMAGES)
```

## Related Tools and Prior Art

NanoBSD (nanobsd(8) and /usr/src/tools/tools/nanobsd/) is a "utility used to create a FreeBSD system image suitable for embedded applications" that produces a flashable disk image that can have one or more additional boot partitions for upgrading and fallback. A FreeBSD 13.0R build of NanoBSD consumes 2.7G of disk space per boot partition, representing a full installation of FreeBSD. Using NanoBSD with FreeBSD 13.0R requires a larger default image size and note that it defaults to 'make -j 3'. A NanoBSD installation can be reduced using KERNCONF and src.conf entries. Consider these changes to ~/nanobsd/defaults.sh:
```
NANO_PMAKE="make -j $(sysctl -n hw.ncpu)"
NANO_MEDIASIZE=16000000
```

picobsd (formerly referred to as PicoBSD) was located in /usr/src/release/picobsd and appears to have been removed from FreeBSD 13.0R. It can be found in the 12.X and earlier sources, and is unique in that it includes custom utilities.

TinyBSD (/usr/src/tools/tools/tinybsd) is focused on minimization of a FreeBSD installation but is not compatible with recent FreeBSD. TinyBSD uses seven template files, bridge, firewall, vpn, wrap, default, minimal, and wireless, which each have a dedicated kernel configuration file named TINYBSD, plus a list of all binaries to be copied in to the target image named tinybsd.basefiles. TinyBSD supports a list of desired ports, and support files like /etc/fstab and /etc/rc.conf. By contrast, OccamBSD uses either 'make installworld' or selective 'make install' for the installation of binaries.

[Crochet](https://github.com/freebsd/crochet) is a a relatively-recent image builder designed to "Build FreeBSD images for Raspberry Pi, BeagleBone, PandaBoard, and others." Its functionality may be partly replaced by the official ~/src/release tools.

[Poudriere image.sh](https://github.com/freebsd/poudriere/blob/master/src/share/poudriere/image.sh) is an actively-developed framework for image generation that is well documented as part of the [BSD Router Project](https://bsdrp.net/documentation/technical_docs/poudriere?s[]=build) A Poudriere image installation can be reduced using KERNCONF and src.conf entries.

[mkjail](https://github.com/mkjail/mkjail) can be used on FreeBSD to create new jails, keep them updated, and upgrade to a new release.

Was μbsd a thing?

## Observations

There are (and have been) many FreeBSD build tools but few, with the notable exception of TinyBSD, have made any effort to "minimize" the FreeBSD kernel and/or base system with any effort beyond a kernel configuration file and a src.conf file. This is understandable, given that the FreeBSD build options have been under-maintained for decades. FreeBSD 13.0-RELEASE marks an important milestone with the quality of its build options.

This project is not an endorsement of GitHub
