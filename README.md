## OccamBSD: An application of Occam's razor to FreeBSD
a.k.a. "super svelte stripped down FreeBSD"

Note that the December, 2024 update is sweeping and due for much testing.

## Imagine: Virtual and Hardware Machine Boot Image Imaging 
a.k.a. "An unnecessarily-complex solution to what should be a simple problem"

This evolving project incorporates several inter-related scripts with the broad goal of producing and/or deploying bootable FreeBSD, OmniOS, Debian, RouterOS, and Windows systems from source or downloaded boot images. Official OpenBSD boot images would be greatly appreciated.

```
occambsd.sh		Builds a "svelte", purpose-build FreeBSD bootable disk image using the FreeBSD build(7) system
profile-amd64-minimum*.txt	A minimum system configuration for use on a virtual machine for FreeBSD
profile-amd64-zfs*.txt		The minimum configuration with ZFS support
profile-amd64-hardware.txt	A minimum configuration with ZFS and hardware machine support, tested on a ThinkPad
propagate.sh		Builds PkgBase jails, boot environments, and VM-IMAGEs
imagine.sh		Images official and OccamBSD bootable disk images to hardware and virtual machine images, or dist sets or build objects to a boot environment
autounattend_xml	A directory of Windows autounattend.xml files
```

## Preface

The relationships of the components in this repo is complex.

TL:DR: The author prefers to never use a "next, next, next, finish" installer again yet wants a selection of operating systems available with one or two commands.

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

# occambsd.sh

By default, occambsd.sh will only perform a build using the specified profile and requires additional flags to generate Jail and Virtual Machine images.

To build a root-on-ZFS Virtual Machine image using FreeBSD 14.0 or later:

```
sudo sh occambsd.sh -v -z -p profile-amd64-zfs14.txt
```

The full occambsd.sh usage is:

```
-p <profile file> (required)
-s <source directory> (Default: /usr/src)
-o <object directory> (Default: /usr/obj)
-O <output directory> (Default: /tmp/occambsd)
-w (Reuse the previous world objects)
-W (Reuse the previous world objects without cleaning)
-k (Reuse the previous kernel objects)
-K (Reuse the previous kernel objects without cleaning)
-a <additional build option to exclude>
-b (Package base)
-G (Use the GENERIC/stock world)
-g (Use the GENERIC kernel)
-j (Build for Jail boot)
-9 (Build for 9pfs boot)
-v (Generate VM image)
-z (Generate ZFS VM image)
-Z <size> (VM image siZe i.e. 500m - default is 5g)
-S <size> (VM image Swap size i.e. 500m - default is 1g)
-i (Generate disc1 and bootonly.iso ISOs)
-m (Generate mini-memstick image)
-n (No-op dry-run only generating configuration files)

```

-p packaged base is experimental until further notice.

The -W and -K options exist for use with WITH_META_MODE set in /etc/src-env.conf and the filemon.ko kernel module loaded.

Want to aggressively build test FreeBSD?

Simply execute a list of occambsd.sh commands with separate output directories, adjusting the exact names as appropriate:

```
sudo sh occambsd.sh -O /tmp/amd64-minimum -p profile-amd64-minimum.txt
sudo sh occambsd.sh -O /tmp/amd64-hardware -p profile-amd64-hardware.txt
sudo sh occambsd.sh -O /tmp/arm64-minimum -p profile-arm64-minimum.txt
...

```

# propagate.sh

See the USAGE section of the file for usage, notes, and caveats


# imagine.sh

imagine.sh downloads a FreeBSD official release, stable, or current "VM-IMAGE", or a custom-build 'make release' or OccamBSD vm.raw image. It can also retrieve and copy or image OmniOS, Debian, and RouterOS images, plus prepare Windows boot devices using autounattend.xml files. The resulting images can be booted in bhyve, QEMU, or Xen.

Note that this requires use of the /media mount point, administrative privileges, and it creates /root/imagine-work for use for downloaded artifacts. Note the syntax in the EXAMPLES section of the script.

## imagine.sh Output Layout

```
/root/imagine-work		Working directory for imagine.sh operations
/root/imagine-work/15.0-CURRENT	Directory of upstream, uncompressed images/src.txz
/root/imagine-work/freebsd-amd64-15.0-CURRENT-zfs.raw	Example VM image
/root/imagine-work/bhyve-15.0-CURRENT-amd64-zfs.sh	Related boot script
```

To download a FreeBSD 15.0-CURRENT "Latest" VM-IMAGE and generate boot scripts:

```
sudo sh imagine.sh -r 15.0-CURRENT -v
```

To download an OmniOS image (version embedded in the script for want of "Latest" aliases on the mirrors) and image it to a hardware device /dev/da0 :

```
sudo sh imagine -r omnios -t /dev/da0
```

The full occambsd.sh usage is:

```
-O <output directory> (Default: /root/imagine-work)
-a <architecture> [ amd64 | arm64 | i386 | riscv ] (Default: Host)
-r [ obj | /path/to/image | <version> | omnios | debian ]
obj i.e. /usr/obj/usr/src/<target>.<target_arch>/release/vm.ufs.raw
/path/to/image.raw for an existing image
<version> i.e. 14.0-RELEASE | 15.0-CURRENT | 15.0-ALPHAn|BETAn|RCn
-o (Offline mode to re-use fetched releases and src.txz)
-t <target> [ img | /dev/device | /path/myimg ] (Default: img)
-T <mirror target> [ img | /dev/device ]
-f (FORCE imaging to a device without asking)
-g <gigabytes> (grow image to gigabytes i.e. 10)
-s (Include src.txz or /usr/src as appropriate)
-m (Mount image and keep mounted for further configuration)
-V (Generate VMDK image wrapper)
-v (Generate VM boot scripts)
-z (Use a 14.0-RELEASE or newer root on ZFS image)
-Z <new zpool name>
-A (Set the ZFS ARC to only cache metadata)
-x <autounattend.xml file for Windows> (Requires -i and -g)
-i <Installation ISO file for Windows> (Requires -x and -g)
```

# Example Scenario of using occambsd.sh with imagine.sh

Example usage on a FreeBSD 14.0 system with 'makefs -t zfs' support to produce a minimum root-on-ZFS image that is grown to 10GB in size and boots in seconds:

```
sudo sh occambsd.sh -p profile-amd64-zfs.txt -v -z
sudo sh imagine.sh -r obj -g 10 -v -z
```

# Example Window Usage

```
sudo sh imagine.sh -x autounattend_xml/win2025.iso -i win2025.iso -g 30
```

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
