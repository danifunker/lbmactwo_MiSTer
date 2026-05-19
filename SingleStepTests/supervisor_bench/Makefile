# Mac II supervisor bench — builds flat boot_stub.bin + payload.bin.
# Skeleton: links empty stubs. Real logic comes in Steps C–F.

RETRO68 ?= $(HOME)/repos/Retro68-build/toolchain
PREFIX  := $(RETRO68)/bin/m68k-apple-macos-
CC      := $(PREFIX)gcc
AS      := $(PREFIX)as
LD      := $(PREFIX)ld
OBJCOPY := $(PREFIX)objcopy
SIZE    := $(PREFIX)size

BUILD := build

# 68020 (Mac II CPU). Freestanding, no libc, no PIC.
CPUFLAGS := -m68020
CFLAGS   := $(CPUFLAGS) -ffreestanding -fno-builtin -fomit-frame-pointer \
            -nostdlib -Os -Wall -Wextra -fno-pic -fno-exceptions \
            -fno-asynchronous-unwind-tables
ASFLAGS  := $(CPUFLAGS)
LDFLAGS  := -nostdlib --no-eh-frame-hdr

.PHONY: all clean minimal scsi cpu_scsi cpu_scsi_m2hires m2hires_probe
all: $(BUILD)/boot_stub.bin $(BUILD)/payload.bin sizes
cpu_scsi_m2hires: $(BUILD)/boot_stub_scsi_m2hires.bin $(BUILD)/payload_cpu_scsi_m2hires.bin

$(BUILD)/boot_stub_scsi_m2hires.o: boot_stub_scsi_m2hires.s | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD)/boot_stub_scsi_m2hires.elf: $(BUILD)/boot_stub_scsi_m2hires.o boot_stub.ld
	$(LD) $(LDFLAGS) -T boot_stub.ld -o $@ $<

$(BUILD)/boot_stub_scsi_m2hires.bin: $(BUILD)/boot_stub_scsi_m2hires.elf
	$(OBJCOPY) -O binary $< $@

CPU_M2HIRES_OBJS := $(BUILD)/payload_entry_cpu_m2hires.o \
                 $(BUILD)/variant_cpu_scsi.o \
                 $(BUILD)/bench_main.o \
                 $(BUILD)/jsonl_writer.o \
                 $(BUILD)/freestanding.o \
                 $(BUILD)/font_ascii_m2hires.o \
                 $(BUILD)/recovery.o

$(BUILD)/payload_entry_cpu_m2hires.o: payload_entry_cpu_m2hires.s | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD)/font_ascii_m2hires.o: font_ascii_m2hires.c bench_types.h | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/payload_cpu_scsi_m2hires.elf: $(CPU_M2HIRES_OBJS) payload.ld
	$(LD) $(LDFLAGS) -T payload.ld -o $@ $(CPU_M2HIRES_OBJS)

$(BUILD)/payload_cpu_scsi_m2hires.bin: $(BUILD)/payload_cpu_scsi_m2hires.elf
	$(OBJCOPY) -O binary $< $@
minimal: $(BUILD)/boot_stub_minimal.bin
m2hires_probe: $(BUILD)/boot_stub_m2hires_probe.bin
m2hires_calibrate: $(BUILD)/boot_stub_m2hires_calibrate.bin
m2hires_v3: $(BUILD)/boot_stub_m2hires_v3.bin

$(BUILD)/boot_stub_m2hires_v3.o: boot_stub_m2hires_v3.s | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD)/boot_stub_m2hires_v3.elf: $(BUILD)/boot_stub_m2hires_v3.o boot_stub.ld
	$(LD) $(LDFLAGS) -T boot_stub.ld -o $@ $<

$(BUILD)/boot_stub_m2hires_v3.bin: $(BUILD)/boot_stub_m2hires_v3.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD)/boot_stub_m2hires_calibrate.o: boot_stub_m2hires_calibrate.s | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD)/boot_stub_m2hires_calibrate.elf: $(BUILD)/boot_stub_m2hires_calibrate.o boot_stub.ld
	$(LD) $(LDFLAGS) -T boot_stub.ld -o $@ $<

$(BUILD)/boot_stub_m2hires_calibrate.bin: $(BUILD)/boot_stub_m2hires_calibrate.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD)/boot_stub_m2hires_probe.o: boot_stub_m2hires_probe.s | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD)/boot_stub_m2hires_probe.elf: $(BUILD)/boot_stub_m2hires_probe.o boot_stub.ld
	$(LD) $(LDFLAGS) -T boot_stub.ld -o $@ $<

$(BUILD)/boot_stub_m2hires_probe.bin: $(BUILD)/boot_stub_m2hires_probe.elf
	$(OBJCOPY) -O binary $< $@
scsi: $(BUILD)/boot_stub_scsi.bin $(BUILD)/payload_scsi.bin
cpu_scsi: $(BUILD)/boot_stub_scsi.bin $(BUILD)/payload_cpu_scsi.bin

$(BUILD)/payload_entry_scsi.o: payload_entry_scsi.s | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD)/payload_scsi.elf: $(BUILD)/payload_entry_scsi.o payload.ld
	$(LD) $(LDFLAGS) -T payload.ld -o $@ $(BUILD)/payload_entry_scsi.o

$(BUILD)/payload_scsi.bin: $(BUILD)/payload_scsi.elf
	$(OBJCOPY) -O binary $< $@

# ---------- CPU bench payload (SCSI) ----------
CPU_SCSI_OBJS := $(BUILD)/payload_entry_cpu.o \
                 $(BUILD)/variant_cpu_scsi.o \
                 $(BUILD)/bench_main.o \
                 $(BUILD)/jsonl_writer.o \
                 $(BUILD)/freestanding.o \
                 $(BUILD)/font_ascii.o \
                 $(BUILD)/recovery.o

$(BUILD)/recovery.o: recovery.s | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD)/font_ascii.o: font_ascii.c bench_types.h | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/freestanding.o: freestanding.c freestanding.h bench_types.h | $(BUILD)
	$(CC) $(CFLAGS) -fno-builtin -c -o $@ $<

$(BUILD)/payload_entry_cpu.o: payload_entry_cpu.s | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD)/variant_cpu_scsi.o: variant_cpu_scsi.s | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD)/bench_main.o: bench_main.c bench_types.h freestanding.h jsonl_writer.h tests_cpu.h | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/jsonl_writer.o: jsonl_writer.c jsonl_writer.h bench_types.h freestanding.h | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/payload_cpu_scsi.elf: $(CPU_SCSI_OBJS) payload.ld
	$(LD) $(LDFLAGS) -T payload.ld -o $@ $(CPU_SCSI_OBJS)

$(BUILD)/payload_cpu_scsi.bin: $(BUILD)/payload_cpu_scsi.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD)/boot_stub_minimal.o: boot_stub_minimal.s | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD)/boot_stub_minimal.elf: $(BUILD)/boot_stub_minimal.o boot_stub.ld
	$(LD) $(LDFLAGS) -T boot_stub.ld -o $@ $<

$(BUILD)/boot_stub_minimal.bin: $(BUILD)/boot_stub_minimal.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD)/boot_stub_scsi.o: boot_stub_scsi.s | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD)/boot_stub_scsi.elf: $(BUILD)/boot_stub_scsi.o boot_stub.ld
	$(LD) $(LDFLAGS) -T boot_stub.ld -o $@ $<

$(BUILD)/boot_stub_scsi.bin: $(BUILD)/boot_stub_scsi.elf
	$(OBJCOPY) -O binary $< $@

# ---------- boot block ----------
$(BUILD)/boot_stub.o: boot_stub.s | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD)/boot_stub.elf: $(BUILD)/boot_stub.o boot_stub.ld
	$(LD) $(LDFLAGS) -T boot_stub.ld -o $@ $<

$(BUILD)/boot_stub.bin: $(BUILD)/boot_stub.elf
	$(OBJCOPY) -O binary $< $@

# ---------- payload ----------
PAYLOAD_SRCS_S := payload_entry.s exception_handlers.s
PAYLOAD_SRCS_C := bench_main.c jsonl_writer.c
PAYLOAD_OBJS   := $(patsubst %.s,$(BUILD)/%.o,$(PAYLOAD_SRCS_S)) \
                  $(patsubst %.c,$(BUILD)/%.o,$(PAYLOAD_SRCS_C))

$(BUILD)/%.o: %.s | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD)/%.o: %.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/payload.elf: $(PAYLOAD_OBJS) payload.ld
	$(LD) $(LDFLAGS) -T payload.ld -o $@ $(PAYLOAD_OBJS)

$(BUILD)/payload.bin: $(BUILD)/payload.elf
	$(OBJCOPY) -O binary $< $@

# ---------- helpers ----------
$(BUILD):
	mkdir -p $@

.PHONY: sizes
sizes: $(BUILD)/boot_stub.bin $(BUILD)/payload.bin
	@echo "--- sizes ---"
	@wc -c $(BUILD)/boot_stub.bin $(BUILD)/payload.bin

clean:
	rm -rf $(BUILD)
