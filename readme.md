# Macintosh II for the [MiSTer Board](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

This core was forked from a [MacPlus](https://github.com/MiSTer-devel/MacPlus_MiSTer). Then used code from the Macintosh Classic emulator [snow](https://github.com/twvd/snow)

This is an initial build, I doubt any of it works yet!

## Usage

* Copy the *.rbf onto the root of the SD card (build from source with Quartus)
* Copy ROM files to the `lbmactwo` folder on the SD card:
  * `boot0.rom` — Mac II system ROM (256K). Use `1987-12 - 9779D2C4 - MacII (800k v2).ROM` (md5 `66223be1497460f1e60885eeb35e03cc`).
    * Optionally, the memory-test-skip variant produced by `scripts/patch_rom_nomemtest.sh` (see [Skipping the power-on memory test](#skipping-the-power-on-memory-test)) is also a valid `boot0.rom` (md5 `3ac98d2aab2ebd399bce2d52c9a80753`).


The core emulates the **Apple Macintosh II High Resolution Video Card** (TFB 2.2 ASIC + Bt453 RAMDAC, 640×480) as a NuBus card. Its declaration ROM (`341-0660.bin`, md5 `9ae47fa338406441a5a6a39321c990fa`) is **baked into the FPGA bitstream**, just like a real card carries its own ROM, so you do **not** need to copy it to the SD card. (It is only supplied at runtime as `boot1.rom`, index 1, by the Verilator simulator.)
* Copy disk images in dsk format (e.g. Disk605.dsk) to lbmactwo folder

After a few seconds, the floppy disk icon should appear. Open the on-screen display using the F12 key and select the a disk image. The upload of the disk image will take a few seconds. If a bootable system is found on disk, a smiling Mac icon will appear. lbmactwo will then begin booting into the desktop.

## Floppy disk support

One (internal) floppy disk drive is supported — "Mount Floppy" in the OSD. (The second/external bay was removed 2026-08-08 to free fit headroom for BlueSCSI Toolbox / CD-ROM.)

The OSD "Aspect ratio: Original" setting requests true **4:3**, matching both monitor modes (640×480 13" and 512×384 12" — both are 4:3 CRTs). Older builds requested 256:171 (a Mac Plus 512×342 leftover), which squished the picture ~12% and made the integer-scaling modes request a wider-than-panel image on 5:4/4:3 panels (e.g. 1280×1024 → blank screen). `scripts/aspect_check.py` is the offline regression gate for this path.

Floppy disk images need to be in raw disk format (a.k.a. DiskDup format) with a .dsk extension. Single-sided 400k disk images must be exactly 409,600 bytes in size. Double-sided 800k disk images must be exactly 819,200 bytes in size.  Disk Copy 4.2 files are not currently supported. They are largely the same as raw disk format, but include an additional 84-byte header. A tool to convert DC42 format to dsk is available [here](https://www.bigmessowires.com/2013/12/16/macintosh-diskcopy-4-2-floppy-image-converter/).

Currently, floppy disk images are not writable within the core.

Floppy disk images cannot be loaded while the Mac accesses a floppy disk. Thus, it's recommended to wait for the desktop to appear until a second floppy can be inserted. Before loading a different disk image, it's recommended to eject the previously inserted disk image from within the OS. 

Note that the floppy disk drive will not be read when the CPU speed is set to 16 MHz.

Official system disk images are available from an archived Apple support page [here](https://web.archive.org/web/20141025043714/http://www.info.apple.com/support/oldersoftwarelist.html). Under Linux these can be converted into the desired dsk format using [Linux StuffIt](http://web.archive.org/web/20060205025441/http://www.stuffit.com/downloads/files/stuffit520.611linux-i386.tar.gz), unar, and [dc2dsk](http://www.bigmessowires.com/dc2dsk.c), in that order. A shell script has been provided for convenience at [releases/bin2dsk.sh](releases/bin2dsk.sh). 

## Hard disk support

The lbmactwo core supports SCSI hard drive images up to 2GB (HFS) in size, with a .vhd extension. The core currently implements only a subset of the SCSI commands. This is sufficient to read and write the disk, to boot from it, and to format it using the setup tools that come with System 6.0.8.

The harddisk image to be used can be selected from the "Mount *.vhd" entry in the on-screen-display. Copy the boot.vhd to lbmactwo folder and it will be automatically mounted at start. The format of the disk image is the same as the one used by the SCSI2SD project, documented [here](http://www.codesrc.com/mediawiki/index.php?title=HFSFromScratch).

Unlike the floppy, the SCSI disk is writable and data can be written to the disk from within the core.

It has been tested that System 6.0.8 can format the SCSI disk, as well as doing a full installation from floppy disk to the harddisk. However, keep in mind the core is an early work in progress and expect data loss when working with HDD images.

A matching harddisk image file can be found [here](https://github.com/MiSTer-devel/MacPlus_MiSTer/tree/master/releases). This is a 20MB harddisk image with correct partitioning information and a basic SCSI driver installed. The data partition itself is empty and unformatted. After booting the Mac will thus ask whether the disk is to be initialized. Saying yes and giving the disk a name will result in a usable file system. You don't need to use the Setup tool to format this disk as it is already formatted, but you can format it if you want to. This has only been tested with System 6.0.8.

A tool to create harddisk images (with working SCSI driver and partition table) is available [here](https://diskjockey.onegeekarmy.eu/).

## CPU Speed

The CPU speed can be adjusted to 8 MHz (original speed) or 16 MHz. This port implements a workaround to allow booting from SCSI when using the 16 MHz configuration.

## Memory

1MB, 4MB, and 8MB memory configurations are available and can be selected from the on-screen display. Cold boot with a larger RAM size selected takes some time before it starts to boot from FDD/SCSI, so be patient. Warm boot won't take as long.

### Skipping the power-on memory test

The long cold-boot delay is the Mac II ROM's destructive RAM test. The ROM normally skips this test when it detects a warm start (a "WLSC" flag in low memory); the [snow](https://github.com/twvd/snow) emulator boots quickly by faking that flag. You can get the same fast cold boot by patching `boot0.rom` so the test is always skipped:

```sh
scripts/patch_rom_nomemtest.sh boot0.rom
```

This flips the two warm-start branches in the ROM and fixes up the ROM checksum, writing the result back in place (a pristine copy is kept at `boot0.rom.bak`). It is pure POSIX `sh`, so it can be run directly on the MiSTer. Pass a second argument to write to a separate file instead of patching in place. The script only supports the original Mac II system ROM (checksum `9779D2C4`).

## Keyboard

The Alt key is mapped to the Mac's Command (⌘) key, and the Windows key is mapped to the Mac's Option (⌥) key. Core emulates keyboard with numeric keypad.
