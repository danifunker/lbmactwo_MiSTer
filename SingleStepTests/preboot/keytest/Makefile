# keytest -- floppy-only ADB keyboard diagnostic.
#
# Produces:
#   payload_keytest_dsk.bin  -- continuous KeyMap poller

include ../common/make/common.mk

BUILD := build

COMMON_RUNTIME := $(COMMON)/runtime
COMMON_DISPLAY := $(COMMON)/display

COMMON_OBJS := $(BUILD)/freestanding.o $(BUILD)/display.o

DSK_C_OBJS  := $(BUILD)/keytest_main.o

ENTRY_OBJ   := $(BUILD)/payload_entry.o
EXC_OBJ     := $(BUILD)/exc_handlers.o
BOOT_OBJ    := $(BUILD)/boot_stub.o
BOOT_BIN    := $(BUILD)/boot_stub.bin

DSK_OBJS    := $(ENTRY_OBJ) $(EXC_OBJ) $(DSK_C_OBJS) $(COMMON_OBJS)

.PHONY: all dsk clean
all: dsk
dsk: $(BUILD)/payload_keytest_dsk.bin $(BOOT_BIN)

$(BUILD):
	mkdir -p $@

$(BOOT_OBJ): $(BOOT_STUB_SRC) | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<
$(BUILD)/boot_stub.elf: $(BOOT_OBJ) $(BOOT_STUB_LD)
	$(LD) $(LDFLAGS) -T $(BOOT_STUB_LD) -o $@ $<
$(BOOT_BIN): $(BUILD)/boot_stub.elf
	$(OBJCOPY) -O binary $< $@

$(ENTRY_OBJ): payload_entry.s | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<
$(EXC_OBJ): exc_handlers.s | $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<

$(BUILD)/keytest_main.o: keytest_main.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/freestanding.o: $(COMMON_RUNTIME)/freestanding.c | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<
$(BUILD)/display.o: $(DISPLAY_SRC) | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/payload_keytest_dsk.elf: $(DSK_OBJS) $(PAYLOAD_LD)
	$(LD) $(LDFLAGS) -T $(PAYLOAD_LD) -o $@ $(DSK_OBJS)
$(BUILD)/payload_keytest_dsk.bin: $(BUILD)/payload_keytest_dsk.elf
	$(OBJCOPY) -O binary $< $@

clean:
	rm -rf $(BUILD)
