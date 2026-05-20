# Vintage Apple — Gamba — Video: NuBus card / Monitor Matrix

*A mirror of the famed information pages of Gamba from `home.earthlink.net/~gamba2/`*

Source: <https://vintageapple.org/gamba2/vid-mon-matrix.html>
Originally published 10/17/99, revised 08/23/03.
[Back to Home Page](https://vintageapple.org/gamba2/index.html)

**Quick links**

- [Apple Tech Info links](#apple-tech-info-links)
- [Apple Monitor / NuBus card matrix](#apple-monitor--nubus-card-matrix) (SuperMac, Radius, E‑Machines, RasterOps)
- [Third‑party video card downloads](#video-drivers) (SuperMac, Radius, E‑Machines, RasterOps, Truevision, Micron XCEED)
- [E Machines Futura card switch settings](#e-machines-futura-card-switch-settings)
- MonitorWorld's [Monitor Database](http://monitorworld.com/Monitors/)
- Griffin Technology's [Monitor Database](http://www.griffintechnology.com/monitor.html)

---

## Apple Monitor / NuBus card matrix

The columns are Apple NuBus video cards. The rows are Apple monitors. Each cell shows the maximum colors/grays supported at that monitor's native resolution with that card.

**Card column key** (part numbers shown beneath card name):

| # | Card | Part No. | Depth |
|---|---|---|---|
| 1 | Macintosh II Video Card | 630-0153 | 4 / 8 bit |
| 1 | High‑Resolution Video Display Card | 630-4222 / 630-4230 | 4 / 8 bit |
| 2 | Mac Display Card 4•8 | 630-0400 | 8 bit |
| — | Macintosh Display Card 8•24 | 820-0600-A | 24 bit |
| — | Macintosh Display Card 8•24GC | 670-0310 | 24 bit |
| — | Display Card 24AC | — | 24 bit |
| — | Mac II Mono | 630-4385 | 1 bit |
| 6 | Workstation/Portrait | 630-???? | 2 bit |
| 6 | 2‑Page Mono | 6??-???? | 2 bit |

```
                                                                                                       Workstation/
                                                                                                       Portrait(6)
                                                                         High-Resolution               Display      Macintosh    Display          630-????
                                                         Macintosh II    Video Display     Mac Dsply   Card 670     Display      Card     Mac II     |     2-Page
                            Apple NuBus Video Cards--->  Video Card(1)  .....Card(1).....   4•8 (2)    8•24         8•24GC       24AC     Mono       |     Mono(6)
                                                          630-0153      630-4222 630-4230   630-0400   820-0600-A   670-0310              630-4385   |     6??-????
         Model #   Apple Monitors            resolution  4 bit   8 bit    4 bit  8 bit      8 bit      24 bit       24 bit       24 bit   1 bit    2 bit   2 bit
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ---
12"  M1296 Macintosh 12-in RGB Display      512x384    -       -         -      -       256        16.7M        16.7M*         -       -         -      -
12"  M0400 High Res Monochrome Monitor      640x480    16     256*      16     256*     256*       16.7M*       16.7M*       16.7M     2*        -      -
12"  M1050 Macintosh 12-in Monochrome Dsply 640x480    16     256       16     256      256        16.7M*       16.7M*       16.7M     2         -      -
13"T M0401 AppleColor High-Res RGB     (A)  640x480    16     256*      16     256      256*       16.7M*       16.7M*       16.7M     2*        -      -
 "   M1297   "          "       "      (B)   "
14"T M1212 Macintosh Color Display          640x480    16     256       16     256      256        16.7M        16.7M        16.7M               -      -
14"T M2001 Audio-Vision 14 Display          640x480    16     256       16     256      256        16.7M        16.7M        16.7M               -      -
14"  M1595LL/A Basic Color Monitor (vga)    640x480    -       -        16              256          -            -            -                 -      -
14"  M1787 Apple Color Plus 14-in Dsply (A) 640x480    -       -        16     256      256        16.7M        16.7M        16.7M               -      -
 "   M2346   "     "    "     "     "   (B)  "
14"  M9101 Apple Performa Display           640x480                     16     256      256        16.7M        16.7M        16.7M
14"  M9102 Apple Performa Plus Display      640x480                     16     256      256        16.7M        16.7M        16.7M
15"  M0404 Macintosh Portrait Display   (A) 640x870    -       -         -      -        16         256          256?        ?????               4      -
 "   M1030   "         "        "       (B)  "
16"T M1298 Macintosh 16-in Color Display    832x624    -       -         -      -        16? (4)    256* (5)    65.5K* (5)   16.7M               -      -
21"  M0402 Two-Page Monochrome Monitor  (A)1152x870    -       -*        -      -*       16*        256*         256*         256                -      4
 "   M1025    "         "       "       (B)  "
21"  M3502 Macintosh 21-in Color Display   1152x870    -       -         -      -        16*        256*         256*        16.7M
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - ---
14"  M4222 Multiple Scan 14 Display         640x480    -       -        16     256      256        16.7M        16.7M        16.7M
                                            800x600    -       -         -      -        -           -            -            -
                                            832x624    -       -         -      -        16? (3,4)  256 (3,5)   65.5K (3,5)  16.7M

15"  M2943 Multiple Scan 15 Display         640x480    -       -        16     256      256        16.7M        16.7M        16.7M
                                            800x600    -       -         -      -        -           -            -            -
                                            832x624    -       -         -      -        16? (3,4)  256 (3,5)   65.5K (3,5)  16.7M
                                           1024x768    -       -         -      -        -           -            -            -

17"T M2494 Multiple Scan 17 Display         640x480    -       -        16     256      256        16.7M        16.7M        16.7M
17"  M4436 Multiple Scan 1705 Display       800x600    -       -         -      -        -           -            -            -
                                            832x624    -       -         -      -        16? (3,4)  256 (3,5)   65.5K (3,5)  16.7M
                                           1024x768    -       -         -      -        -           -            -          16.7M

17"T M2935 AppleVision 1710 Display         640x480    -       -        16     256      256        16.7M        16.7M        16.7M
17"T M2942 AppleVision 1710 AV Display      800x600    -       -         -      -        -           -            -            -
                                            832x624    -       -         -      -        16? (3,4)  256 (3,5)   65.5K (3,5)  16.7M
                                           1024x768    -       -         -      -        -           -            -          16.7M
                                           1152x870    -       -         -      -       16?         256?         256?          -
                                          1280x1024    -       -         -      -         -           -           -            -

20"T M1823 Multiple Scan 20 Display         640x480    -       -        16     256      256        16.7M        16.7M        16.7M
                                            800x600    -       -         -      -        -           -            -            -
                                            832x624    -       -         -      -        16? (3,4)  256 (3,5)   65.5K (3,5)  16.7M
                                           1024x768    -       -         -      -        -           -            -          16.7M
                                           1152x870    -       -         -      -        16 (3)     256?         256?        16.7M
                                          1280x1024    -       -         -      -         -           -            -            -
```

**Footnotes**

1. Can be upgraded with eight Mac II Video Expansion RAM chips for 256 grays/colors.
2. The 4•8 can be upgraded to a 8•24 by adding two 256k VRAM SIMMs.
3. Requires Display adaptor to use Multiple Scan Displays at this resolution.
4. Available with rev. B ROM.
5. Available with rev. B card.
6. Can be upgraded with eight Mac II Video Expansion RAM chips for 16 grays.
- (`*`) verified by test

---

## Apple Tech Info links

- Macintosh: Monitor and Video Chart [(1 of 4)](http://docs.info.apple.com/article.html?artnum=11131) [(2 of 4)](http://docs.info.apple.com/article.html?artnum=15878) [(3 of 4)](http://docs.info.apple.com/article.html?artnum=15879) [(4 of 4)](http://docs.info.apple.com/article.html?artnum=15881)
- [Apple Displays: Model Numbers](http://docs.info.apple.com/article.html?artnum=15087)
- [Apple Displays: Frequently Asked Questions](http://docs.info.apple.com/article.html?artnum=18216)
- [Macintosh 12‑Inch RGB Display: Compatible Systems](http://docs.info.apple.com/article.html?artnum=8107)
- [Apple High‑Resolution Monochrome Monitor: Specs](http://docs.info.apple.com/article.html?artnum=2163) — Created 3/6/87, modified 9/13/93 (DA‑15 style connector)
- [Macintosh 12‑Inch Monochrome Display: Description](http://docs.info.apple.com/article.html?artnum=10264) — Created 5/27/92, modified 6/7/94 (attached video cable)
- [Macintosh II: Monochrome Video Card](http://docs.info.apple.com/article.html?artnum=3515)
- [Macintosh II High‑Resolution Video Card: New Features](http://docs.info.apple.com/article.html?artnum=4059)
- [Macintosh II: Old and New Video Card Part Numbers, Etc.](http://docs.info.apple.com/article.html?artnum=4809)
- [Macintosh IIci: Internal Video Circuitry Versus Video Card](http://docs.info.apple.com/article.html?artnum=5180)
- [Macintosh IIci Video: Supported Resolutions and Scan Rates](http://docs.info.apple.com/article.html?artnum=5336)
- [AV Series, Apple NuBus Video Cards: Compatibility](http://docs.info.apple.com/article.html?artnum=14695)
- Macintosh Display Cards Overview [(1 of 3)](http://docs.info.apple.com/article.html?artnum=5210) [(2 of 3)](http://docs.info.apple.com/article.html?artnum=5205) [(3 of 3)](http://docs.info.apple.com/article.html?artnum=5818)
- [Monitor Cables: Pinout Information](http://docs.info.apple.com/article.html?artnum=6382)
- [Sense Lines](http://developer.apple.com/technotes/hw/hw_30.html)
- [Color Monitor Connections](http://developer.apple.com/technotes/hw/hw_08.html) — Macintosh II Video Card, Macintosh LC & IIci built‑in video to third‑party monitors
- [Scan Rates for Monitors](http://docs.info.apple.com/article.html?artnum=4815)
- [Macintosh VRAM Chart](http://docs.info.apple.com/article.html?artnum=11762)

### Portrait & Two Page

- [Macintosh II Portrait Display Card: Specs](http://docs.info.apple.com/article.html?artnum=6961)
- [Macintosh IIci: Two‑Page Monitors Need NuBus Video Card](http://docs.info.apple.com/article.html?artnum=5039)

### 4•8

- [Macintosh Display Card 4•8: Color Problems](http://docs.info.apple.com/article.html?artnum=8221)
- [Display Card 4•8 and 8•24 Specifications](http://docs.info.apple.com/article.html?artnum=5422)

### 8•24GC

**Software**

- [Control Panel v1.1 & v7.0.1](http://download.info.apple.com/Apple_Support_Area/Apple_Software_Updates/English-North_American/Macintosh/Display-Peripheral/Older_Displays/)
- [Cache Control 030](http://www.umich.edu/~archive/mac/system.extensions/init/cachecontrol030.cpt.hqx)

**Docs**

- [Display Card 8•24 GC: Specifications](http://docs.info.apple.com/article.html?artnum=5423)
- [Macintosh Display Cards 8•24 & 8•24 GC: Rev A/B Differences](http://docs.info.apple.com/article.html?artnum=9858)
- [Display Card 8•24 & 8•24 GC: Identifying Rev & Upgrade ROM](http://docs.info.apple.com/article.html?artnum=9913)
- [System 7.5: 8•24GC Card Compatibility](http://docs.info.apple.com/article.html?artnum=16469)
- [Display Card 8•24 GC: Using With Different Monitors](http://docs.info.apple.com/article.html?artnum=5798)
- [Worth‑of‑8‑24‑gc‑card I](http://hyperarchive.lcs.mit.edu/HyperArchive/Archive/info/hdwr/worth-of-8-24-gc-card.txt)
- [Worth‑of‑8‑24‑gc‑card II](http://hyperarchive.lcs.mit.edu/HyperArchive/Archive/info/hdwr/worth-of-8-24-gc-card-son.txt)
- [Macintosh Display Card 8•24GC: The Naked Truth](http://www.mactech.com/articles/develop/issue_03/824GC_V007.html)

### 24AC

| Date | Article # | Subject |
|---|---|---|
| 07/27/94 | 15049 | [Macintosh Display Card 24AC: Compatibility With Power Macintosh](http://docs.info.apple.com/article.html?artnum=15049) |
| 12/21/94 | 14837 | [Macintosh Display Card 24AC: Technical Specifications](http://docs.info.apple.com/article.html?artnum=14837) |
| 02/22/95 | 17245 | [Display Card 24AC: Power Macintosh Can Use Acceleration](http://docs.info.apple.com/article.html?artnum=17245) |
| 06/28/95 | 13987 | [Display Card 24AC: Description](http://docs.info.apple.com/article.html?artnum=13987) |
| 07/23/98 | 20599 | [Mac Display Card 24AC: ROM V1.0 Not Compatible w/7.5.3](http://docs.info.apple.com/article.html?artnum=20599) |

- [24AC video card datasheet (html)](http://www.apple.com.au/Pub/Datasheets/24AC.html)
- [24AC video card datasheet (pdf)](http://www.apple.com.au/Pub/Datasheets/24AC.pdf.hqx)

---

## Video Drivers

[More drivers](https://vintageapple.org/gamba2/mac_software.html#drvrs) · Link to [**Micron XCEED**](https://vintageapple.org/gamba2/microngray.html#dl) software.

### SuperMac

- SuperMac [SuperVideo 2.7.5](http://homepage.mac.com/vintagecom/.cv/vintagecom/Public/VideoCard/SuperVideo275.sit-link.sit) control panel.
- SuperMac [SuperVideo 3.1](http://www.VintageBox.de/download/archive/supermac/SuperVideo3.1.sit)
- SuperMac VideoSpigot [SpigotVDIG 1.0](ftp://ftp.adelaide.edu.au/pub/av/CU-SeeMe/Spigot/SpigotVDIG.bin) extension.
- SuperMac VideoSpigot [SpigotVDIG 1.5B18](ftp://ftp.adelaide.edu.au/pub/av/CU-SeeMe/Spigot/SpigotVDIG_1.5_18.SEA.bin) extension.
- SuperMac VideoSpigot [DigitalFilm 1.5](http://www.VintageBox.de/download/DigitalFilm1.5.sit) application.
- SuperMac VideoSpigot [ScreenPlay 1.2.2](http://www.VintageBox.de/download/archive/supermac/ScreenPlay1.2.2.sit) application.

### Radius

- [RadiusWare for old Macs](http://www.VintageBox.de/download/archive/radius/RadiusWare/backrev/Radius.sea.bin) (Displays and accelerators)
- [RadiusWare Pivot v3.2.1 Software](ftp://ftp.unizh.ch/rzu/macintosh/utilities/radius/SoftPivot3.2.1.sea.hqx) — Dynamic Desktop 3.3, Soft Pivot 3.2.1, Soft Pivot Driver 3.2.1
- [RadiusWare NuBus GS Installer](http://www.shauny.de/computer/apple/drivers/radiusware-3.4.img) — Dynamic Desktop 3.1.1, PowerSaver 1.1
- [RadiusWare NuBus v3.2.5](http://www.macdrivermuseum.com/video/knighttech/DiskImages/Radius/RadiusWare3.2.5.smi.hqx) — Dynamic Desktop 3.2.5, QuickColor 3.2.5, Soft PrecisionColor 3.1.1, PowerSaver 1.2.1
- [RadiusWare 3.3](http://www.kan.org/download/drivers.sit.hqx) — Dynamic Desktop 3.3, QuickColor 3.3, •RADIUS DSP 2.2, RadiusWare 2.3.2, MrFlash 1.2.3
- [Thunder IV Software](http://www.artmix.com/ARTMIXFTP/Thunder_IV_Software.sea.hqx) — Dynamic Desktop 3.3, QuickColor 3.3, •RADIUS DSP 2.2, Radius PhotoEngine Plug‑in 1.2
- [Thunder IV 1.2.3 Update](http://www.artmix.com/ARTMIXFTP/ThunderIV1.2.3Update.sea.hqx) — MrFlash 1.2.3
- [Thunder 24 Manual](http://www.artmix.com/ARTMIXFTP/thunder_manual.sit.hqx)
- [RadiusTV installer](http://www.VintageBox.de/download/RadiusTV.sit)
- [Radius PhotoBooster](http://www.VintageBox.de/download/PhotoBooster1.1.sit)
- [Radius Studio Player 2.6.2](http://www.VintageBox.de/download/StudioPlayer2.6.2.sit)

### E‑Machines

- E‑Machines [Control Panel 3.5.6](http://www.VintageBox.de/download/archive/supermac/E-Machines%203.5.6.sit) — for Futura II LX/DSP, Futura II SX/DSP, Futura II LX, and Futura II SX video cards.

### RasterOps

- [RasterOps Graphics Install](http://homepage.mac.com/vintagecom/.cv/vintagecom/Public/VideoCard/RasterOpsGraphicsInstall.sit-link.sit)
- [Drivers (macdrivermuseum)](http://www.macdrivermuseum.com/video/knighttech/DiskImages/RasterOps/)
- [Drivers (jmug)](http://www.members.jmug.org/~thepickl/archive/Other_Drivers/RasterOps/)
- Video Display Card [Compatibility Matrix](images/rasterops_card_chart.gif)

### Truevision NuVista+

- [FTP site](ftp://ftp.truevision.com/pub/Macintosh/)
- [Software](ftp://ftp.truevision.com/pub/Macintosh/historic.products/NuVista_NuVista+/NuVista_NuVista+_3.7.hqx)
- [Manual](ftp://ftp.truevision.com/pub/Macintosh/historic.products/NuVista_NuVista+/NuVista+Manual.pdf)

---

## NuBus & PDS Video Cards — Resolution Matrix

**Column key**

| Col | Resolution |
|---|---|
| A | 512×384 |
| B | 640×480 |
| D | 640×870 |
| E | 800×600 |
| F | 832×624 |
| G | 1024×768 @ 60 Hz |
| H | 1024×768 @ 65 Hz |
| I | 1024×768 @ 75 Hz |
| J | 1152×870 |
| K | 1152×882 |
| L | 1152×910 |
| M | 1280×1024 |
| N | 1360×1024 |
| O | 1600×1200 |

Cell values are bit depth (8, 16, 24) at that resolution.

```
                                                640x480     800x600                                        1280x1024   1600x1200
                                                   |           |                                               |           |
                                          512x384  |  640x870  |  832x624  ___1024x768___   _____1152x____     | 1360x1024 |
                                     Part                                  60Hz 65Hz 75Hz   870   882   910
NUBUS & PDS VIDEO CARDS               No.    A     B     D     E     F     G     H     I     J     K     L     M     N     O
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Radius
Radius Full Page Display         630-0009
Radius Full Page Display (SE)        0034
Radius Two Page Display TPDII        0039 630-0041-D
Radius Two Page Display (SE30)       0187 . . . . . . . . . . . . . . . . . . . . . . . . . . . .  1
Radius GS/C GS/C-M . . . . . . . .  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 24
Radius DirectColor 8/16/24 . . . .  . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .  Y
Radius DirectColor GX . . . . . . .  . . . . . . . . .  24
Radius Color Pivot               630-0070
Radius Color Pivot For LC            0407          8     8
Radius Pivot Card For IIsi           0409          8     8
Radius Pivot Card SE30               0410          8     8           8
Radius PrecisionColor 8-Xj           0369    8     8           8     8     8     8     8     8     8
Radius PrecisionColor 8-24X (24 b)                24          24    24    24          24    24
Radius PrecisionColor 24X            0354
Radius PrecisionColor 24XK           0391         24          24    24    24          24
Radius PrecisionColor 24XP           0380                                          -->24
Radius PrecisionColor Pro 24X        0429                                 24
Radius PrecisionColor Pro 24XK       0430   24    24                24    24                24
Radius PrecisionColor Pro 24XP       0431                           24
Radius PrecisionColor Pro 24ac                    24          24    24                24    24
Radius Thunder 24 Gt                 0491         24                24                24    24     8                 8     8
Radius Photo Engine Upgrade (0491)   0482
Radius Thunder Iv Gx 1152            0485         24                24                24    24?   24                 8     8
Radius Thunder Iv Gx 1360            0446         24                24                24    24    24                24     8
Radius Thunder Iv Gx 1600            0513         24                24                24    24    24                24    24

SuperMac
SuperMac ColorCard. . . . . . . .  . . . . . . . . 8
SuperMac ColorCard SE/30
SuperMac ColorCard/24               G0630
SuperMac Spectrum . . . . . . . .  . . . . . . . . .  . . . . . . . . . .  8
Supermac Spectrum/8 LC              G1350
Supermac Spectrum/8 si              G1340
Supermac Spectrum/8 Series II SE/30
Supermac Spectrum/8 PDQ             G0430
SuperMac Spectrum/8 Series II     STD9412
Supermac Spectrum/8 Series III      G0231          8                 8                 8
Supermac Spectrum/8 Series IV
Supermac Spectrum/8•24              G1830
Supermac Spectrum/8•24 PDQ si
Supermac Spectrum/8•24 PDQ v1.0     G0930   24    24     24         16     8           8     8     8
                           v1.7.2   G0930   24    24     24         16     8           8     8     8     8
Supermac Spectrum/24 Series III     G0330
Supermac Spectrum/24 Series IV      G2230   24    24     24         24    24          24
Supermac Spectrum/24 Series V       G3930   24    24                24                24
Supermac Spectrum/24 PDQ
SuperMac Spectrum/24 PDQ Plus v1.60 G1430   24    24     24         24    24          24    24    24    24
Supermac Thunder Light              G2130
Supermac Thunder/24                 G1130         24                24                24    24
Supermac Thunder II Gx 1152         G3730         24                24                24    24
Supermac Spectrum Power 1152        G3430   24    24                24                24    24    24
Supermac Thunder II 1360            G2330
Supermac Thunder II Gx 1360 v3.0.0  G3130   24    24     24         24    24?         24    24    24    24          24
Supermac Thunder II Gx 1600         G3230         24                24                24    24                      24    24
Supermac Thunder II GX Upgrade      G3830
Supermac Video Spigot              DV1030
Supermac Video Spigot & Sound      DV1131
Supermac Spigot Power AV           DV1630
Supermac Superview                 PB0161

E-Machines
Spec/24 IV
DoubleColorSX                                      8                 8                 4
Colorlink SX/t                                    24                 8                 8
Futura SX                                         24                24                 8
Futura MX                         1424-XL         24                24                24
Futura II LX                      EMG023L
Futura II SX                      EMG013S
Power Link Presenter              5008PLP
Ultra LX Long Card                EMG043L
Simply TV                         EMG0550
Apple Mac Video               029-00154-00
   Card- The Big Picture II

RasterOps
Movie Pak                            2543
Movie Pak II                         2676
Video Time                           2562
Specs for other RasterOps: images/rasterops_card_chart.gif

Micro Conversions
                             2124NB-II            24    24          24                24    24

Micron Xceed — see https://vintageapple.org/gamba2/microngray.html#specs
```

---

## E Machines Futura card switch settings

*Courtesy of M & M Enterprises' Vancouver field office.*

| Switch | Resolution | Refresh | Monitors |
|---|---|---|---|
| 1 | 832 × 624 | 67 Hz | T16 |
| 2 | 1024 × 808 | 71 Hz | T19/TX |
| 3 | 648 × 480 | 60 Hz | VGA |
| 4 | 1024 × 768 | 60 Hz | GDM‑1952, 1602 |
| 5 | 832 × 624 | 75 Hz | T16a‑E16 |
| 6 | 1024 × 768 | 75 Hz | E16, Supermac 19 |
| 7 | 640 × 480 | 67 Hz | E16 |
| 8 | 1024 × 768 | 75 Hz | RasterOps 19 |
| C | 13"/16" | Dual Resolution | E16 |
| D | 16"/19" | Dual Resolution | T16II/E16 |
| E | 19"/21" | Dual Resolution | T19II |
| F | 16"/21" | Dual Resolution | T16II |

**Futura VRAM**

| Card | VRAM |
|---|---|
| Futura SX | 1.5 MB |
| Futura MX | 3 MB |
| Futura LX | 3 MB |

---

*This page copyright © 1999–2003 by Gamba. All rights reserved.*
