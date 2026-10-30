SHELL := /bin/sh
.DELETE_ON_ERROR:

TARGET_CC ?= clang
HOST_CC ?= clang
GDB ?= gdb
XORRISO ?= xorriso
QEMU ?= qemu-system-x86_64
QEMU_MACHINE ?= pc-q35-10.1
QEMU_ACCEL ?= tcg

BUILD_DIR ?= build
SHARED_BUILD_DIR ?= build
ISO_ROOT := $(BUILD_DIR)/iso-root
DEPS_DIR := $(SHARED_BUILD_DIR)/deps
DOWNLOAD_DIR := $(SHARED_BUILD_DIR)/downloads
LSP_DATABASE := $(SHARED_BUILD_DIR)/compile_commands.json
HOST_TEST_DIR := $(SHARED_BUILD_DIR)/tests/host
QEMU_TEST_DIR := $(SHARED_BUILD_DIR)/tests/qemu
TEST_RESULTS_DIR := $(SHARED_BUILD_DIR)/test-results
GDB_COMMAND_FILE := scripts/kernel.gdb

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

KERNEL_CPPFLAGS := -I$(DEPS_DIR)/include $(EXTRA_CPPFLAGS)
KERNEL_LINKER_SCRIPT := kernel/arch/x86_64/linker.ld
KERNEL_CFLAGS := \
	--target=x86_64-unknown-none-elf \
	-std=c11 -O2 -g3 -Wall -Wextra -Wpedantic -Werror \
	-ffreestanding -fno-stack-protector -fno-pic -fno-pie \
	-fno-asynchronous-unwind-tables -ffunction-sections -fdata-sections \
	-m64 -march=x86-64 -mno-red-zone -mno-mmx -mno-sse -mno-sse2 \
	-mgeneral-regs-only -mcmodel=kernel \
	$(EXTRA_CFLAGS)
KERNEL_LDFLAGS := \
	--target=x86_64-unknown-none-elf -fuse-ld=lld \
	-nostdlib -static -Wl,-no-pie \
	-Wl,-T,$(KERNEL_LINKER_SCRIPT) -Wl,-Map,$(BUILD_DIR)/kernel.map \
	-Wl,--gc-sections -Wl,-z,max-page-size=0x1000 \
	-Wl,-z,noexecstack -Wl,--build-id=none -Wl,--fatal-warnings

HOST_TEST_CPPFLAGS := -DVANDAL_SERIAL_TEST -Ikernel
HOST_TEST_CFLAGS := -std=c11 -O2 -g3 -Wall -Wextra -Wpedantic -Werror

KERNEL_C_SOURCES := \
	kernel/main.c \
	kernel/drivers/serial.c \
	kernel/platform/qemu/guest_result.c \
	kernel/arch/x86_64/descriptors.c \
	kernel/panic.c
KERNEL_ASM_SOURCES := \
	kernel/arch/x86_64/descriptor_state.S
KERNEL_HEADERS := \
	kernel/guest_result.h \
	kernel/panic.h \
	kernel/drivers/serial.h \
	kernel/arch/x86_64/descriptors.h \
	kernel/arch/x86_64/io.h
KERNEL_ASM_OBJECTS := $(KERNEL_ASM_SOURCES:kernel/%.S=$(BUILD_DIR)/kernel/%.o)
KERNEL_OBJECTS := \
	$(KERNEL_C_SOURCES:kernel/%.c=$(BUILD_DIR)/kernel/%.o) \
	$(KERNEL_ASM_OBJECTS)
FORMAT_FILES := $(KERNEL_C_SOURCES) $(KERNEL_HEADERS) tests/serial_test.c
SCRIPT_FILES := run.sh scripts/debug-kernel.sh scripts/run-qemu.sh scripts/test-guest-result.sh \
	scripts/verify-artifact.sh
SERIAL_TEST_BINARY := $(HOST_TEST_DIR)/serial-test
SERIAL_TEST_SOURCES := tests/serial_test.c kernel/drivers/serial.c

.PHONY: all run debug gdb \
	test test-host test-serial test-qemu test-guest-result test-panic test-limine-handoff \
	test-descriptors \
	test-qemu-direct test-qemu-serial-absent test-qemu-panic \
	test-qemu-panic-serial-absent test-qemu-bad-revision test-qemu-bad-data \
	test-qemu-bad-bss test-qemu-descriptors-reinitialized test-artifact \
	lsp format check-format check-scripts check check-tools check-compiler-tools \
	check-download-tools check-image-tools check-qemu-tools check-gdb-tools check-format-tools \
	check-artifact-tools clean

all: $(BUILD_DIR)/vandal-os.iso

run: all | check-qemu-tools
	VANDAL_QEMU_MACHINE=$(QEMU_MACHINE) VANDAL_QEMU_ACCEL=$(QEMU_ACCEL) \
		./scripts/run-qemu.sh $(BUILD_DIR)/vandal-os.iso

debug: all | check-qemu-tools
	VANDAL_QEMU_MACHINE=$(QEMU_MACHINE) VANDAL_QEMU_ACCEL=$(QEMU_ACCEL) \
		./scripts/run-qemu.sh --debug $(BUILD_DIR)/vandal-os.iso

gdb: all $(GDB_COMMAND_FILE) scripts/debug-kernel.sh | check-qemu-tools check-gdb-tools
	GDB=$(GDB) QEMU=$(QEMU) VANDAL_QEMU_MACHINE=$(QEMU_MACHINE) \
		VANDAL_QEMU_ACCEL=$(QEMU_ACCEL) ./scripts/debug-kernel.sh \
		$(BUILD_DIR)/kernel.elf $(BUILD_DIR)/vandal-os.iso $(GDB_COMMAND_FILE)

test:
	$(MAKE) test-host
	$(MAKE) test-artifact
	$(MAKE) test-qemu

test-host: test-serial

test-serial: $(SERIAL_TEST_BINARY)
	./$(SERIAL_TEST_BINARY)

test-qemu:
	$(MAKE) test-qemu-direct
	$(MAKE) test-qemu-serial-absent
	$(MAKE) test-qemu-panic
	$(MAKE) test-qemu-panic-serial-absent
	$(MAKE) test-qemu-bad-revision
	$(MAKE) test-qemu-bad-data
	$(MAKE) test-qemu-bad-bss
	$(MAKE) test-qemu-descriptors-reinitialized

# Compatibility groups retained for the documented M0 workflows.
test-guest-result:
	$(MAKE) test-qemu-direct
	$(MAKE) test-qemu-serial-absent

test-panic:
	$(MAKE) test-qemu-panic
	$(MAKE) test-qemu-panic-serial-absent

test-limine-handoff:
	$(MAKE) test-qemu-bad-revision
	$(MAKE) test-qemu-bad-data
	$(MAKE) test-qemu-bad-bss

test-descriptors:
	$(MAKE) test-qemu-descriptors-reinitialized

test-qemu-direct: | check-qemu-tools
	$(MAKE) BUILD_DIR=$(QEMU_TEST_DIR)/direct EXTRA_CPPFLAGS=-DVANDAL_TEST_GUEST_RESULT all
	VANDAL_QEMU_MACHINE=$(QEMU_MACHINE) VANDAL_QEMU_ACCEL=$(QEMU_ACCEL) \
		./scripts/test-guest-result.sh direct-result \
		$(QEMU_TEST_DIR)/direct/vandal-os.iso 33 none \
		$(TEST_RESULTS_DIR)/direct-result.log

test-qemu-serial-absent: | check-qemu-tools
	$(MAKE) BUILD_DIR=$(QEMU_TEST_DIR)/serial-absent all
	VANDAL_QEMU_MACHINE=$(QEMU_MACHINE) VANDAL_QEMU_ACCEL=$(QEMU_ACCEL) \
		./scripts/test-guest-result.sh serial-absent \
		$(QEMU_TEST_DIR)/serial-absent/vandal-os.iso 35 none \
		$(TEST_RESULTS_DIR)/serial-absent.log

test-qemu-panic: | check-qemu-tools
	$(MAKE) BUILD_DIR=$(QEMU_TEST_DIR)/panic EXTRA_CPPFLAGS=-DVANDAL_TEST_PANIC all
	VANDAL_QEMU_MACHINE=$(QEMU_MACHINE) VANDAL_QEMU_ACCEL=$(QEMU_ACCEL) \
		./scripts/test-guest-result.sh expected-panic \
		$(QEMU_TEST_DIR)/panic/vandal-os.iso 37 stdio \
		$(TEST_RESULTS_DIR)/expected-panic.log

test-qemu-panic-serial-absent: | check-qemu-tools
	$(MAKE) BUILD_DIR=$(QEMU_TEST_DIR)/panic EXTRA_CPPFLAGS=-DVANDAL_TEST_PANIC all
	VANDAL_QEMU_MACHINE=$(QEMU_MACHINE) VANDAL_QEMU_ACCEL=$(QEMU_ACCEL) \
		./scripts/test-guest-result.sh expected-panic-serial-absent \
		$(QEMU_TEST_DIR)/panic/vandal-os.iso 37 none \
		$(TEST_RESULTS_DIR)/expected-panic-serial-absent.log

test-qemu-bad-revision: | check-qemu-tools
	$(MAKE) BUILD_DIR=$(QEMU_TEST_DIR)/bad-revision \
		EXTRA_CPPFLAGS=-DVANDAL_TEST_BAD_LIMINE_REVISION all
	VANDAL_QEMU_MACHINE=$(QEMU_MACHINE) VANDAL_QEMU_ACCEL=$(QEMU_ACCEL) \
		./scripts/test-guest-result.sh bad-revision \
		$(QEMU_TEST_DIR)/bad-revision/vandal-os.iso 39 none \
		$(TEST_RESULTS_DIR)/bad-revision.log

test-qemu-bad-data: | check-qemu-tools
	$(MAKE) BUILD_DIR=$(QEMU_TEST_DIR)/bad-data EXTRA_CPPFLAGS=-DVANDAL_TEST_BAD_DATA all
	VANDAL_QEMU_MACHINE=$(QEMU_MACHINE) VANDAL_QEMU_ACCEL=$(QEMU_ACCEL) \
		./scripts/test-guest-result.sh bad-data \
		$(QEMU_TEST_DIR)/bad-data/vandal-os.iso 41 none \
		$(TEST_RESULTS_DIR)/bad-data.log

test-qemu-bad-bss: | check-qemu-tools
	$(MAKE) BUILD_DIR=$(QEMU_TEST_DIR)/bad-bss EXTRA_CPPFLAGS=-DVANDAL_TEST_BAD_BSS all
	VANDAL_QEMU_MACHINE=$(QEMU_MACHINE) VANDAL_QEMU_ACCEL=$(QEMU_ACCEL) \
		./scripts/test-guest-result.sh bad-bss \
		$(QEMU_TEST_DIR)/bad-bss/vandal-os.iso 43 none \
		$(TEST_RESULTS_DIR)/bad-bss.log

test-qemu-descriptors-reinitialized: | check-qemu-tools
	$(MAKE) BUILD_DIR=$(QEMU_TEST_DIR)/descriptors-reinitialized \
		EXTRA_CPPFLAGS=-DVANDAL_TEST_DESCRIPTORS_REINITIALIZED all
	VANDAL_QEMU_MACHINE=$(QEMU_MACHINE) VANDAL_QEMU_ACCEL=$(QEMU_ACCEL) \
		./scripts/test-guest-result.sh descriptors-reinitialized \
		$(QEMU_TEST_DIR)/descriptors-reinitialized/vandal-os.iso 47 stdio \
		$(TEST_RESULTS_DIR)/descriptors-reinitialized.log

test-artifact: all | check-artifact-tools
	./scripts/verify-artifact.sh $(BUILD_DIR)/kernel.elf $(BUILD_DIR)/vandal-os.iso

lsp: $(LSP_DATABASE)

format: | check-format-tools
	clang-format -i $(FORMAT_FILES)

check-format: | check-format-tools
	clang-format --dry-run --Werror $(FORMAT_FILES)

check-scripts:
	bash -n $(SCRIPT_FILES)

check:
	$(MAKE) check-format
	$(MAKE) check-scripts
	$(MAKE) lsp
	$(MAKE) test

check-tools: check-compiler-tools check-download-tools check-image-tools check-qemu-tools \
	check-format-tools check-artifact-tools

check-compiler-tools:
	@command -v $(TARGET_CC) >/dev/null || { echo "error: $(TARGET_CC) is required" >&2; exit 1; }
	@command -v $(HOST_CC) >/dev/null || { echo "error: $(HOST_CC) is required" >&2; exit 1; }
	@command -v ld.lld >/dev/null || { echo "error: ld.lld is required" >&2; exit 1; }

check-download-tools:
	@command -v curl >/dev/null || { echo "error: curl is required to fetch pinned Limine files" >&2; exit 1; }
	@command -v sha256sum >/dev/null || { echo "error: sha256sum is required" >&2; exit 1; }
	@command -v tar >/dev/null || { echo "error: tar is required" >&2; exit 1; }

check-image-tools:
	@command -v $(XORRISO) >/dev/null || { echo "error: $(XORRISO) is required" >&2; exit 1; }
	@command -v cc >/dev/null || { echo "error: a host C compiler is required for the Limine tool" >&2; exit 1; }

check-qemu-tools:
	@command -v $(QEMU) >/dev/null || { echo "error: $(QEMU) is required" >&2; exit 1; }
	@command -v timeout >/dev/null || { echo "error: GNU timeout is required" >&2; exit 1; }

check-gdb-tools:
	@command -v $(GDB) >/dev/null || { echo "error: $(GDB) is required" >&2; exit 1; }

check-format-tools:
	@command -v clang-format >/dev/null || { echo "error: clang-format is required" >&2; exit 1; }

check-artifact-tools:
	@command -v llvm-readelf >/dev/null || { echo "error: llvm-readelf is required" >&2; exit 1; }
	@command -v llvm-nm >/dev/null || { echo "error: llvm-nm is required" >&2; exit 1; }
	@command -v llvm-objdump >/dev/null || { echo "error: llvm-objdump is required" >&2; exit 1; }
	@command -v $(XORRISO) >/dev/null || { echo "error: $(XORRISO) is required" >&2; exit 1; }

$(BUILD_DIR)/kernel/%.o: kernel/%.c Makefile $(LIMINE_HEADER) | check-compiler-tools
	@mkdir -p $(@D)
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MMD -MP -c $< -o $@

$(BUILD_DIR)/kernel/%.o: kernel/%.S Makefile | check-compiler-tools
	@mkdir -p $(@D)
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MMD -MP -c $< -o $@

$(SERIAL_TEST_BINARY): $(SERIAL_TEST_SOURCES) kernel/drivers/serial.h Makefile | check-compiler-tools
	@mkdir -p $(@D)
	$(HOST_CC) $(HOST_TEST_CPPFLAGS) $(HOST_TEST_CFLAGS) $(SERIAL_TEST_SOURCES) -o $@

$(LSP_DATABASE): $(KERNEL_C_SOURCES) $(KERNEL_ASM_SOURCES) tests/serial_test.c Makefile \
	$(LIMINE_HEADER) | check-compiler-tools
	@mkdir -p $(@D)
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MJ $@.main.tmp -fsyntax-only kernel/main.c
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MJ $@.serial.tmp -fsyntax-only kernel/drivers/serial.c
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MJ $@.panic.tmp -fsyntax-only kernel/panic.c
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MJ $@.guest-result.tmp -fsyntax-only kernel/platform/qemu/guest_result.c
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MJ $@.descriptors.tmp -fsyntax-only kernel/arch/x86_64/descriptors.c
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MJ $@.descriptor-state.tmp \
		-c kernel/arch/x86_64/descriptor_state.S -o /dev/null
	$(HOST_CC) $(HOST_TEST_CPPFLAGS) $(HOST_TEST_CFLAGS) -MJ $@.serial-test.tmp -fsyntax-only tests/serial_test.c
	@{ printf '[\n'; sed -n 'p' $@.main.tmp; sed -n 'p' $@.serial.tmp; \
		sed -n 'p' $@.panic.tmp; sed -n 'p' $@.guest-result.tmp; \
		sed -n 'p' $@.descriptors.tmp; sed -n 'p' $@.descriptor-state.tmp; \
		sed '$$s/,$$//' $@.serial-test.tmp; printf ']\n'; } >$@
	@rm -f $@.*.tmp

$(BUILD_DIR)/kernel.elf: $(KERNEL_OBJECTS) $(KERNEL_LINKER_SCRIPT) Makefile
	$(TARGET_CC) $(KERNEL_CFLAGS) $(KERNEL_LDFLAGS) $(KERNEL_OBJECTS) -o $@

$(BUILD_DIR)/vandal-os.iso: $(BUILD_DIR)/kernel.elf boot/limine.conf $(LIMINE_TOOL) | check-image-tools
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

$(LIMINE_ARCHIVE): | check-download-tools
	@mkdir -p $(@D)
	curl -fL $(LIMINE_URL) -o $@.tmp
	@printf '%s  %s\n' '$(LIMINE_SHA256)' '$@.tmp' | sha256sum -c -
	mv $@.tmp $@

$(LIMINE_TOOL): $(LIMINE_ARCHIVE) | check-image-tools
	@mkdir -p $(DEPS_DIR)
	tar -xJf $< -C $(DEPS_DIR)
	$(MAKE) -C $(LIMINE_DIR)

$(LIMINE_HEADER): | check-download-tools
	@mkdir -p $(@D)
	curl -fL $(LIMINE_HEADER_URL) -o $@.tmp
	@printf '%s  %s\n' '$(LIMINE_HEADER_SHA256)' '$@.tmp' | sha256sum -c -
	mv $@.tmp $@

clean:
	rm -rf build

-include $(KERNEL_OBJECTS:.o=.d)
