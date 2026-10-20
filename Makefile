SHELL := /bin/sh
.DELETE_ON_ERROR:

CC := clang
XORRISO := xorriso

BUILD_DIR ?= build
ISO_ROOT := $(BUILD_DIR)/iso-root
DEPS_DIR := $(BUILD_DIR)/deps
DOWNLOAD_DIR := $(BUILD_DIR)/downloads

LIMINE_VERSION := 12.9.3
LIMINE_ARCHIVE := $(DOWNLOAD_DIR)/limine-binary-$(LIMINE_VERSION).tar.xz
LIMINE_URL := https://github.com/limine-bootloader/limine/releases/download/v$(LIMINE_VERSION)/limine-binary.tar.xz
LIMINE_SHA256 := e02a473c6dc6df25159697f94930272397f21fd86e5d4eeee61bba72c95ec8d2
LIMINE_DIR := $(DEPS_DIR)/limine-binary
LIMINE_TOOL := $(LIMINE_DIR)/limine

PROTOCOL_COMMIT := 3a0526b700e356f0eac1b71a77697b3fd1c707a3
LIMINE_HEADER := $(DEPS_DIR)/include/limine.h
LIMINE_HEADER_URL := https://raw.githubusercontent.com/limine-bootloader/limine-protocol/$(PROTOCOL_COMMIT)/include/limine.h
LIMINE_HEADER_SHA256 := 0aadf2633c85d8cb145344c968add158aeb1deb68af567d55ba8431c492b6d4c

CPPFLAGS := -I$(DEPS_DIR)/include
CFLAGS := \
	--target=x86_64-unknown-none-elf \
	-std=c11 -O2 -g3 -Wall -Wextra -Wpedantic -Werror \
	-ffreestanding -fno-stack-protector -fno-pic -fno-pie \
	-fno-asynchronous-unwind-tables -ffunction-sections -fdata-sections \
	-m64 -march=x86-64 -mno-red-zone -mno-mmx -mno-sse -mno-sse2 \
	-mgeneral-regs-only -mcmodel=kernel \
	$(EXTRA_CFLAGS)
LDFLAGS := \
	--target=x86_64-unknown-none-elf -fuse-ld=lld \
	-nostdlib -static -Wl,-no-pie \
	-Wl,-T,kernel/linker.ld -Wl,-Map,$(BUILD_DIR)/kernel.map \
	-Wl,--gc-sections -Wl,-z,max-page-size=0x1000 \
	-Wl,-z,noexecstack -Wl,--build-id=none -Wl,--fatal-warnings

KERNEL_SOURCES := kernel/main.c kernel/serial.c
KERNEL_OBJECTS := $(KERNEL_SOURCES:kernel/%.c=$(BUILD_DIR)/kernel/%.o)
FORMAT_FILES := $(KERNEL_SOURCES) kernel/serial.h kernel/arch/x86_64/io.h

.PHONY: all run debug lsp format check-format clean check-tools
all: $(BUILD_DIR)/vandal-os.iso

run: all
	./scripts/run-qemu.sh

debug: all
	./scripts/run-qemu.sh --debug

lsp: $(BUILD_DIR)/compile_commands.json

format:
	clang-format -i $(FORMAT_FILES)

check-format:
	clang-format --dry-run --Werror $(FORMAT_FILES)

check-tools:
	@command -v $(CC) >/dev/null || { echo "error: clang is required" >&2; exit 1; }
	@command -v $(XORRISO) >/dev/null || { echo "error: xorriso is required" >&2; exit 1; }
	@command -v curl >/dev/null || { echo "error: curl is required to fetch pinned Limine files" >&2; exit 1; }
	@command -v sha256sum >/dev/null || { echo "error: sha256sum is required" >&2; exit 1; }
	@command -v tar >/dev/null || { echo "error: tar is required" >&2; exit 1; }

$(BUILD_DIR)/kernel/%.o: kernel/%.c Makefile $(LIMINE_HEADER) | check-tools
	@mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -MMD -MP -c $< -o $@

$(BUILD_DIR)/compile_commands.json: $(KERNEL_SOURCES) Makefile $(LIMINE_HEADER) | check-tools
	@mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -MJ $@.main.tmp -fsyntax-only kernel/main.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -MJ $@.serial.tmp -fsyntax-only kernel/serial.c
	@{ printf '[\n'; sed -n 'p' $@.main.tmp; sed '$$s/,$$//' $@.serial.tmp; printf ']\n'; } >$@
	@rm -f $@.main.tmp $@.serial.tmp

$(BUILD_DIR)/kernel.elf: $(KERNEL_OBJECTS) kernel/linker.ld Makefile
	$(CC) $(CFLAGS) $(LDFLAGS) $(KERNEL_OBJECTS) -o $@

$(BUILD_DIR)/vandal-os.iso: $(BUILD_DIR)/kernel.elf boot/limine.conf $(LIMINE_TOOL) | check-tools
	@rm -rf $(ISO_ROOT)
	@mkdir -p $(ISO_ROOT)/boot/limine $(ISO_ROOT)/EFI/BOOT
	cp $(BUILD_DIR)/kernel.elf $(ISO_ROOT)/boot/kernel.elf
	cp boot/limine.conf $(ISO_ROOT)/boot/limine/limine.conf
	cp $(LIMINE_DIR)/limine-bios.sys $(ISO_ROOT)/boot/limine/
	cp $(LIMINE_DIR)/limine-bios-cd.bin $(LIMINE_DIR)/limine-uefi-cd.bin $(ISO_ROOT)/boot/limine/
	cp $(LIMINE_DIR)/BOOTX64.EFI $(ISO_ROOT)/EFI/BOOT/
	$(XORRISO) -as mkisofs -R -r -J \
		-b boot/limine/limine-bios-cd.bin -no-emul-boot \
		-boot-load-size 4 -boot-info-table \
		-hfsplus -apm-block-size 2048 \
		--efi-boot boot/limine/limine-uefi-cd.bin \
		-efi-boot-part --efi-boot-image --protective-msdos-label \
		$(ISO_ROOT) -o $@
	$(LIMINE_TOOL) bios-install $@
	@rm -rf $(ISO_ROOT)

$(LIMINE_ARCHIVE): | check-tools
	@mkdir -p $(@D)
	curl -fL $(LIMINE_URL) -o $@.tmp
	@printf '%s  %s\n' '$(LIMINE_SHA256)' '$@.tmp' | sha256sum -c -
	mv $@.tmp $@

$(LIMINE_TOOL): $(LIMINE_ARCHIVE)
	@mkdir -p $(DEPS_DIR)
	tar -xJf $< -C $(DEPS_DIR)
	$(MAKE) -C $(LIMINE_DIR)

$(LIMINE_HEADER): | check-tools
	@mkdir -p $(@D)
	curl -fL $(LIMINE_HEADER_URL) -o $@.tmp
	@printf '%s  %s\n' '$(LIMINE_HEADER_SHA256)' '$@.tmp' | sha256sum -c -
	mv $@.tmp $@

clean:
	rm -rf build

-include $(KERNEL_OBJECTS:.o=.d)
