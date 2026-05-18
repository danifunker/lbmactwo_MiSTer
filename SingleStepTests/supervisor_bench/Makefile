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

.PHONY: all clean minimal
all: $(BUILD)/boot_stub.bin $(BUILD)/payload.bin sizes
minimal: $(BUILD)/boot_stub_minimal.bin

$(BUILD)/boot_stub_minimal.o: boot_stub_minimal.s | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD)/boot_stub_minimal.elf: $(BUILD)/boot_stub_minimal.o boot_stub.ld
	$(LD) $(LDFLAGS) -T boot_stub.ld -o $@ $<

$(BUILD)/boot_stub_minimal.bin: $(BUILD)/boot_stub_minimal.elf
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
