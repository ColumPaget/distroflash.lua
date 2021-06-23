SYNOPSIS
========

distroflash.lua is a linux command-line utility for making multiboot usb disks that contain multiple linux distributions from .iso files. It does this by examining the contents of .iso files, copying them to a directory on the destination media, and setting up a syslinux bootloader to load them. It requires syslinux, lua, libUseful and libUseful-lua to be installed. Currently it does not support UEFI boot, and will install distros in 'installer' form by default, falling back to 'live' for those distros where the installation process doesn't work. It does not yet install both 'installer' and 'live' forms for distros that support that.

distroflash.lua will try to avoid acting on mounted or non-removable media, although non-removable media can be written to using the '-force' option.


AUTHOR
======

distroflash.lua is (C) 2020 Colum Paget. It is released under the Gnu Public License Version 3, so you may do anything with it that the GPL allows. 
Email: colums.projects@gmail.com



INSTALL
=======

The application consists of the lua script `distroflash.lua` and the config file `distroflash.conf`. The config file needs to go into the `/etc` system config directory, unless you use the `-c` or `-config` options to force a different location. The script itself would normally go in `/usr/local/bin` or `/usr/bin` but it can go anywhere.


USAGE
=====

```
distroflash.lua [options] -d <device>  <iso file>
```

OPTIONS
=======

```
	-d <device>         specify device to install onto, which can be a disk or a partition
	-dev <device>       specify device to install onto, which can be a disk or a partition
	-device <device>    specify device to install onto, which can be a disk or a partition
  -c <path>           specify path to config file that describes known distributions 
  -config <path>      specify path to config file that describes known distributions 
	-force              carry out installation even if destination media isn't detected as removable
	-format             format the destination partition
	-syslinuxdir      path to syslinux dir containing mbr.bin, ldlinux.c32, etc. distroflash.lua should find this itself.
	-?                this help
	-h                this help
	-help             this help
	--help            this help

```


DETAILED USAGE
==============

As it does a lot of mounting/partitioning and writing of disks distroflash.lua has to be run as root. The basic usage is to specify a device and a number of iso files like this:

```
	lua distroflash.lua -d /dev/sdc1 bodhi-5.0.0-64.iso linuxmint-19.3-xfce-32bit.iso trisquel-mini_8.0_i686.iso

```

If the destination is a disk, such as `/dev/sdc` then distroflash.lua will repartition it as a single large partition, format the partition, and then install onto it. THIS WILL WIPE ANY DATA ON THE DISK.

If the destination is a partition, such as `/dev/sdc1` then distroflash will install to that partition, but will not format the partition unless the `-format` option is passed. The `-format` option WILL WIPE ANY DATA ON DISK. If the `-format` option is not used, and a syslinux.cfg file already exists on the disk, distroflash will append new entries to it. If the syslinux.cfg file does not exist a new one will be created.

If distroflash.lua objects that the destination device isn't removable (which can happen even with some devices that are, but don't declare themselves as such) you can force installation with the `-force` option.

distroflash.lua creates directories on the destination media for each distribution. For example, if we install the `trisquel-mini_8.0_i686.iso` iso file the directory `trisquel-mini_8.0_i686` will be created on disk. For some linux distributions, like salix linux, you will have to tell the installer where to find it's stage2 installation files. For salix (from the .iso `salix64-xfce-14.2.iso`) these will be in `salix64-xfce-14.2\salix`.

If distroflash.lua doesn't recognize the distribution that's in an iso file it falls back to a 'generic' install mode where it looks for a kernel file with a name like 'vmlinuz' or 'bzImage' in the root of the iso file, or within one of the top level directories (so, for example `/vmlinuz` or `/boot/vmlinuz`). It also seeks an initial ramdisk with a names matching `initrd*`, `initfs*` or `initrfs.*` (so, for example `/initrd.gz` or `/somedir/initrfs.img`). This will allow it to set up unknown distributions at least to the point where they will boot into their initial ramdisk environments (where many then present a shell for installation to be continued manually).



SUPPORTED O.S. DISTRIBUTIONS
=============================

distroflash.lua has been seen to work with the following distributions. If anyone knows any tricks to get other distros working from a usb-stick, feel free to mail me at colums.projects@gmail.com

## Perfect, runs live and/or installs 

  * Android x86 9.0
  * Android Bliss O.S. v11.12
  * Android Prime O.S. 0.4.5 
  * AntiX Linux 19
  * ArchLinux 2020.03.01
  * Bodhi Linux 5.0.0
  * Deepin Community Desktop 1002
  * GRML 2020.06
  * MX Linux 19.1
  * Linux Mint 19.3
  * Ubuntu Desktop 18.04.4
  * LUbuntu Desktop 19.10
  * Manjaro 20.1.2
  * KUbuntu Desktop 19.10
  * KNOPPIX 8.6.1
  * Peppermint 10
  * Porteus 3.2.2
  * PCLinuxOS 2020.02
  * Slackware 14.2
  * Sparky Linux 5.14
  * Trisquel-mini 8.0
  * ZorinOS 15.3
 
## Finiky, can be made to install
 
  * TinyCorePlus              - has to be told path to core.gz to install (see 'Finiky installs' below)
  * Puppy Linux slacko 6.3.2  - complex install process (see 'Finiky installs' below)
  * Puppy Linux tahr 6.0.5    - complex install process (see 'Finiky installs' below)
  * Salix 14.2                - has to be told to install from harddrive, and given both the device name and path to files on disk
  * Calculate Linux           - has been seen to install to a vm. Installer has issues with some graphics cards.
  * CentOS Linux 8.1          - has been seen to install to a vm. Installer crashes on some hardware.

## Runs live. Might also install from usb to hard-drive if you really know how and the wind is in the right direction

  * Slax 9.11.0               - no automated installer, apparently can be installed from live by copying files manually
  * Gentoo                    - no automated installer, apparently can be installed manually from live
  * Damn Small Linux 4.4.10   - difficult to use installer, not had a successful install from it yet, but it may work.
 
## Live environment only
 
  * Kali Linux 2020.1
  * Clonezilla 
  * SystemRescueCD 
  * Fatdog Linux 721
  * Nst Linux 30-11210           - runs live, but installer refuses to install from mounted usb key
  * Puppy Linux xenialpup 7.5    - installs, but installed system doesn't seem to boot
  * Slitaz-rolling               - installer can't find installation files



## Finiky installs

TinyCorePlus
: TinyCorePlus linux has an issue where the installer will ask for the location of the `core.gz` file. Search under '/mnt/' to find this. Available partitions will usually be mounted under '/mnt' (e.g. /mnt/sdb1) and you're looking for a directory named something like 'CorePlus-current' (or whatever your original .iso file was called) that contains a 'boot' directory, which then contains 'core.gz'. Once that has been selected the install should continue successfully.

Puppy Linux
: Puppy linux has a very complex install system. Puppy versions 'slacko' and 'tahr' have been seen to install. The 'xenialpup' version hasn't worked, and seems to have a problem setting up the bootloader for the installed OS. The installer in all versions will ask you to find the install files. First click on the icons for the available disk partitions at the bottom of the desktop to make sure that these partitions are mounted under '/mnt'. You should then be able to browse under /mnt to find a directory with the same name as the .iso file that you pointed distroflash to. Within that directory you should find the files that the installer is asking for. Select one of them and continue.  
