## OccamBSD: An application of Occam's razor to FreeBSD
a.k.a. "super svelte stripped down FreeBSD"

This project incorporates several inter-related scripts with the broad goal of producing purpose-built FreeBSD systems and preparing disk images for OmniOS, Debian, and Windows:

```
mirror-upstream.sh	Creates and maintains a local git.freebsd.org repository with releng, stable, and main branches
bos-lite.sh		Launched by mirror-upstream.sh and performs an inverse "build option survey"
bos-upload.sh		Launched by bos-lite.sh if present for uploating to a web server (not included)
build-option-smoke-test.sh	A build option CI test proposed to the FreeBSD cluster aministration team
occambsd.sh		Builds a "svelte", purpose-build FreeBSD bootable disk image using the FreeBSD build(7) system
profile-amd64-minimum13.txt	A minimum system configuration for use on a virtual machine for FreeBSD 13.x
profile-amd64-minimum.txt	A minimum system configuration for use on a UFS-booted virtual machine
profile-amd64-zfs13.txt		The minimum configuration with ZFS added for 13.x
profile-amd64-zfs14.txt		The minimum configuration with ZFS added for 14.0R
profile-amd64-hardware.txt	A minimum configuration with ZFS and hardware machine support, tested on a ThinkPad
profile-amd64-ipv4.txt	The hardware profile plus minimum IPv4 networking with ssh(1) and host(1)
profile-arm64-minimum.txt	A minimum configuration file for ARM64 (builds but not tested on qemu|hardware)
imagine.sh		Images official and OccamBSD bootable disk images to hardware and virtual machine images, or dist sets or build objects to a boot environment
winagine.sh		Facilitates configurating Windows bootable disk images using autounattend.xml
autounattend_xml	Windows autounattend.xml files for use with winagine.sh
make-rescue-iso.sh	A script to make a bootonly.iso rescue ISO with useful tools
rc.local.sh		An experimental stand-alone or /etc/rc.local script that configures FreeBSD system in an idempotent manner
```

## Preface

The relationships of the components in this repo can be confusing.

TL:DR: They allow the author to (nearly) never use an installer again with FreeBSD, OmniOS, Debian, and Windows, with the added benefit of completely customizing FreeBSD using in-base tools.

There have been countless "Cloud" and "Virtual Machine" boot images or appliances produced for various operating systems over the years. These are often symptoms of the use of "feature-rich" virtual machine boot images formats such as QCOW2, VDI, VHD(X), and others. In OpenZFS environments, any say... "copy on write!" or compression features of a non-raw disk image format are  categorically obsoleted by OpenZFS below the POSIX layer. 

On OpenZFS, a raw boot image can benefit from snapshotting, compression, thin/over-provisioning, and many other features without modification or intervention. A raw boot image can also be imaged to an OpenZFS volume (ZVOL) or shared via iSCSI or Fiber Channel.

Above all, a raw boot image can be imaged to a *hardware* boot device and booted on compatible hardware platforms.

In short, they are all, and always have been fundamentally *boot images*, and not "Cloud" or "Virtual Machine" images. For example, the FreeBSD "raw" "VM-IMAGE" files can be imaged to hardware devices and booted, which is exactly what imagine.sh helps with. Enjoy!

## Motivations

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

## Requirements

```
mirror-upstream.sh:		Internet access, ZFS, git
bos-lite.sh			FreeBSD source and object directories
bos-upload.sh			Depends on your upload strategy
occambsd.sh:			FreeBSD 13.0 or later, and FreeBSD 14.0 for 'makefs -t zfs' support
imagine.sh:			Internet access if using images from download.freebsd.org
				QEMU and Xen packages as needed
build-option-smoke-test.sh	FreeBSD source and object directories, optional git for metadata
rc.local.sh			A FreeBSD userland
```

## Output Layout

```
/b/				"Build" mount point for mirror-upstream.sh
/tmp/occambsd/OCCAMBSD		OccamBSD kernel configuration file
/tmp/occambsd/all_modules.txt	Generated list of all available kernel modules
/tmp/occambsd/all_options.conf	Generated list of all available build options
/tmp/occambsd/logs		World, Kernel, and VM-IMAGE build logs
/tmp/occambsd/src.conf		The generated src.conf excluding components
/tmp/occambsd/*.sh		Jail and VM management scripts
/root/imagine-work		Working directory for some imagine.sh operations
```

## Usage

Most of these scripts are position independent unless they depend on one another.

# occambsd.sh

By default, occambsd.sh will build the requested profile but will only generate Jail and Virtual Machine images with the specified flags.

occambsd.sh requires a profile and can build a root-on-ZFS image with -z:


```
sudo sh occambsd.sh -v -z -p profile-amd64-zfs.txt
```

Note that -z support is only available on FreeBSD 14.0 or later

The full occambsd.sh usage is:

```
-p <profile file> (required)
-s <source directory override>
-o <object directory override>
-O <output directory override>
-w (Reuse the previous world objects)
-W (Reuse the previous world objects without cleaning)
-k (Reuse the previous kernel objects)
-K (Reuse the previous kernel objects without cleaning)
-G (Use the GENERIC/stock world)
-g (Use the GENERIC kernel)
-j (Build for Jail boot)
-v (Generate vm-image)
-z (Generate ZFS vm-image)
-Z <size> (vm-image siZe i.e. 500m - default is 5g)
-S <size> (vm-image Swap size i.e. 500m - default is 1g)
-i (Generate disc1 and bootonly.iso ISOs)
-m (Generate mini-memstick image)
-n (No-op dry-run only generating configuration files)
```

The -W and -K options exist for use with WITH_META_MODE set in /etc/src-env.conf and the filemon.ko kernel module loaded.

Want to aggressively build test FreeBSD on a fast system?

Simply excute a list of occambsd.sh commands with separate output directories:

```
sudo sh occambsd.sh -O /tmp/amd64-minimum -p profile-amd64-minimum.txt
sudo sh occambsd.sh -O /tmp/amd64-hardware -p profile-amd64-hardware.txt
sudo sh occambsd.sh -O /tmp/arm64-minimum -p profile-arm64-minimum.txt
...

```

# imagine.sh

imagine.sh downloads a FreeBSD official release, stable, or current "VM-IMAGE", or a custom-build vm.raw image and assists with configuring it as a virtual machine disk image or images it to a hardware device for hardware boot. Alternatively, it can download the base.txz and kernel.txz distribution sets to a new ZFS boot environment, install OccamBSD /usr/obj build objects to a boot environment using /tmp/occambsd/src.conf and the OCCAMBSD kernel configuration file.

Note that this requires use of the /media mount point, administrative privileges, and it creates /root/imagine-work for use for downloaded artifacts. Note the syntax in the EXAMPLES section of the script.

-r debian support has been restored and -r omnios, which supports zpool expansion and renaming.

```
sudo sh imagine.sh -r 15.0-CURRENT
```

# Example Scenario

Example usage on a FreeBSD 14.0 system with 'makefs -t zfs' support to produce a minimum root-on-ZFS image that is grown to 10GB in size and boots in seconds:

```
sudo sh occambsd.sh -p profile-amd64-zfs.txt -v -z
sudo sh imagine.sh -r obj -g 10 -b -z
```

# winagine.sh

A script to facilitate Windows autounattend.xml installations that follows the imagine file layout and terrible naming

```
sudo sh winagine.sh -i win2025.iso -x autounattend_xml/win2025.iso
```

# mirror-upstream.sh

mirror-upstream.sh is hard-coded to use zpool "zroot" but that can be overridden with by appending a zpool name:

```
sh mirror-upstream.sh tank
```


# rc.local.sh

rc.local.sh will prompt for a root destination directory, or will auto-execute on boot if renamed "/etc/rc.local" (remove .sh)

```
sh rc.local.sh
```


Read EXACTLY what it is doing and configure it to your needs. Modify, comment out, or delete sections as needed.


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
