# preboot/common/make/common.mk — shared Make plumbing for every preboot
# bench. Bench Makefiles `include` this file relative to themselves and
# get a consistent toolchain, flags, and paths to the common library.
#
# Tested with Retro68 toolchain (m68k-apple-macos-*). Override RETRO68
# from the environment if your Retro68 install is elsewhere.

RETRO68 ?= $(HOME)/repos/Retro68-build/toolchain
PREFIX  := $(RETRO68)/bin/m68k-apple-macos-
CC      := $(PREFIX)gcc
AS      := $(PREFIX)as
LD      := $(PREFIX)ld
OBJCOPY := $(PREFIX)objcopy

# Path to the preboot/common/ tree from a bench's own directory:
#   preboot/<bench>/Makefile  -> ../common
COMMON ?= ../common

CPUFLAGS := -m68020
CFLAGS   := $(CPUFLAGS) -ffreestanding -fno-builtin -fomit-frame-pointer \
            -nostdlib -Os -Wall -Wextra -fno-pic -fno-exceptions \
            -fno-asynchronous-unwind-tables \
            -I. -I$(COMMON)/runtime -I$(COMMON)/display
ASFLAGS  := $(CPUFLAGS)
LDFLAGS  := -nostdlib --no-eh-frame-hdr

# Linker scripts live in common/runtime.
PAYLOAD_LD   := $(COMMON)/runtime/payload.ld
BOOT_STUB_LD := $(COMMON)/runtime/boot_stub.ld

# The canonical boot block (SCSI-bootable, PAYLDOFF-patchable). Older
# variants live under common/boot/old/ but aren't selected by default.
BOOT_STUB_SRC := $(COMMON)/boot/boot_stub_scsi.s

# Active display kernel — 1bpp paint, works on the Mac II built-in
# framebuffer and on any NuBus video card in its power-on 1bpp default
# (Toby, m2hires, mdc824). 8bpp paint lives under common/display/old/
# until depth-switch init code exists.
DISPLAY_SRC := $(COMMON)/display/display_1bpp.c
