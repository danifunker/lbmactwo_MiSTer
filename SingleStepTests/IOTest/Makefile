# IOTest — disk I/O timing bench. Two payload binaries:
#   payload_iotest_hda.bin  — SCSI variant, 12 sizes (1B .. 4MB)
#   payload_iotest_dsk.bin  — Floppy variant,  8 sizes (1B .. 256KB)
#
# Boot stub is the same boot_stub_scsi.s from supervisor_bench — it's
# medium-agnostic (uses Device Manager via DrvQHdr lookup), so the
# floppy artifact reuses the SCSI boot stub. Image build scripts patch
# the per-size byte offsets after laying out the HFS partition.

RETRO68 ?= $(HOME)/repos/Retro68-build/toolchain
PREFIX  := $(RETRO68)/bin/m68k-apple-macos-
CC      := $(PREFIX)gcc
AS      := $(PREFIX)as
LD      := $(PREFIX)ld
OBJCOPY := $(PREFIX)objcopy

BUILD := build
SB    := ../supervisor_bench

CPUFLAGS := -m68020
CFLAGS   := $(CPUFLAGS) -ffreestanding -fno-builtin -fomit-frame-pointer \
            -nostdlib -Os -Wall -Wextra -fno-pic -fno-exceptions \
            -fno-asynchronous-unwind-tables -I. -I$(SB)
ASFLAGS  := $(CPUFLAGS)
LDFLAGS  := -nostdlib --no-eh-frame-hdr

# Source files shared with supervisor_bench (compiled fresh here so we
# can pick up any IOTest-specific cflags without touching that dir).
SB_OBJS := $(BUILD)/jsonl_writer.o \
           $(BUILD)/freestanding.o \
           $(BUILD)/font_ascii.o

# IOTest C objects — one per variant (different IOTEST_VARIANT_* define).
HDA_C_OBJS := $(BUILD)/diskio_main.hda.o $(BUILD)/sizes.hda.o $(BUILD)/timing.hda.o
DSK_C_OBJS := $(BUILD)/diskio_main.dsk.o $(BUILD)/sizes.dsk.o $(BUILD)/timing.dsk.o

ENTRY_OBJ := $(BUILD)/payload_entry.o

HDA_OBJS  := $(ENTRY_OBJ) $(HDA_C_OBJS) $(SB_OBJS)
DSK_OBJS  := $(ENTRY_OBJ) $(DSK_C_OBJS) $(SB_OBJS)

BOOT_OBJ  := $(BUILD)/boot_stub.o
BOOT_BIN  := $(BUILD)/boot_stub.bin

.PHONY: all hda dsk clean
all: hda dsk

hda: $(BUILD)/payload_iotest_hda.bin $(BOOT_BIN)
dsk: $(BUILD)/payload_iotest_dsk.bin $(BOOT_BIN)

$(BUILD):
	mkdir -p $@

# ---- Boot stub (shared) ----
$(BOOT_OBJ): boot_stub.s | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<
$(BUILD)/boot_stub.elf: $(BOOT_OBJ) $(SB)/boot_stub.ld
	$(LD) $(LDFLAGS) -T $(SB)/boot_stub.ld -o $@ $<
$(BOOT_BIN): $(BUILD)/boot_stub.elf
	$(OBJCOPY) -O binary $< $@

# ---- Payload entry (shared between variants) ----
$(ENTRY_OBJ): payload_entry.s | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<

# ---- IOTest C sources (per variant) ----
$(BUILD)/diskio_main.hda.o: diskio_main.c sizes.h timing.h | $(BUILD)
	$(CC) $(CFLAGS) -DIOTEST_VARIANT_HDA -c -o $@ $<
$(BUILD)/sizes.hda.o: sizes.c sizes.h | $(BUILD)
	$(CC) $(CFLAGS) -DIOTEST_VARIANT_HDA -c -o $@ $<
$(BUILD)/timing.hda.o: timing.c timing.h | $(BUILD)
	$(CC) $(CFLAGS) -DIOTEST_VARIANT_HDA -c -o $@ $<

$(BUILD)/diskio_main.dsk.o: diskio_main.c sizes.h timing.h | $(BUILD)
	$(CC) $(CFLAGS) -DIOTEST_VARIANT_DSK -c -o $@ $<
$(BUILD)/sizes.dsk.o: sizes.c sizes.h | $(BUILD)
	$(CC) $(CFLAGS) -DIOTEST_VARIANT_DSK -c -o $@ $<
$(BUILD)/timing.dsk.o: timing.c timing.h | $(BUILD)
	$(CC) $(CFLAGS) -DIOTEST_VARIANT_DSK -c -o $@ $<

# ---- Shared supervisor_bench objects ----
$(BUILD)/jsonl_writer.o: $(SB)/jsonl_writer.c $(SB)/jsonl_writer.h | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<
$(BUILD)/freestanding.o: $(SB)/freestanding.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<
$(BUILD)/font_ascii.o: $(SB)/font_ascii.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

# ---- Link both payload variants ----
$(BUILD)/payload_iotest_hda.elf: $(HDA_OBJS) $(SB)/payload.ld
	$(LD) $(LDFLAGS) -T $(SB)/payload.ld -o $@ $(HDA_OBJS)
$(BUILD)/payload_iotest_hda.bin: $(BUILD)/payload_iotest_hda.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD)/payload_iotest_dsk.elf: $(DSK_OBJS) $(SB)/payload.ld
	$(LD) $(LDFLAGS) -T $(SB)/payload.ld -o $@ $(DSK_OBJS)
$(BUILD)/payload_iotest_dsk.bin: $(BUILD)/payload_iotest_dsk.elf
	$(OBJCOPY) -O binary $< $@

clean:
	rm -rf $(BUILD)
