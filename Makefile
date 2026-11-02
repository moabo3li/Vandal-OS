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

# Sources that every image shares. The exception mechanism is production code.
KERNEL_CORE_C_SOURCES := \
	kernel/main.c \
	kernel/drivers/serial.c \
	kernel/platform/qemu/guest_result.c \
	kernel/arch/x86_64/descriptors.c \
	kernel/arch/x86_64/exceptions.c \
	kernel/arch/x86_64/exception_dispatch.c \
	kernel/panic.c
KERNEL_CORE_ASM_SOURCES := \
	kernel/arch/x86_64/descriptor_state.S \
	kernel/arch/x86_64/exception_vector.S

# Exactly one terminal exception policy is linked. An exception-test image also
# links the controlled fault stimuli it needs; both policy implementations and
# both stimuli live outside kernel/ so a production image contains no test code.
EXCEPTION_POLICY ?= production
ifeq ($(EXCEPTION_POLICY),production)
EXCEPTION_C_SOURCES := kernel/arch/x86_64/exception_finish_prod.c
EXCEPTION_ASM_SOURCES :=
else ifeq ($(EXCEPTION_POLICY),test)
EXCEPTION_C_SOURCES := tests/exception_finish_test.c
EXCEPTION_ASM_SOURCES := tests/exception_stimulus.S
else
$(error EXCEPTION_POLICY must be production or test)
endif

KERNEL_C_SOURCES := $(KERNEL_CORE_C_SOURCES) $(EXCEPTION_C_SOURCES)
KERNEL_ASM_SOURCES := $(KERNEL_CORE_ASM_SOURCES) $(EXCEPTION_ASM_SOURCES)
KERNEL_HEADERS := \
	kernel/guest_result.h \
	kernel/panic.h \
	kernel/drivers/serial.h \
	kernel/arch/x86_64/descriptors.h \
	kernel/arch/x86_64/exceptions.h \
	kernel/arch/x86_64/exception_frame.h \
	kernel/arch/x86_64/exception_policy.h \
	kernel/arch/x86_64/io.h
KERNEL_OBJECTS := $(addprefix $(BUILD_DIR)/,$(KERNEL_C_SOURCES:.c=.o) $(KERNEL_ASM_SOURCES:.S=.o))
# The test policy and its stimuli stay outside kernel/. Assembly is excluded
# from formatting because clang-format does not parse it.
EXCEPTION_TEST_C_FILES := tests/exception_finish_test.c tests/exception_stimulus.h
EXCEPTION_TEST_ASM_FILES := tests/exception_stimulus.S
EXCEPTION_TEST_FILES := $(EXCEPTION_TEST_C_FILES) $(EXCEPTION_TEST_ASM_FILES)
FORMAT_FILES := $(KERNEL_CORE_C_SOURCES) kernel/arch/x86_64/exception_finish_prod.c \
	$(KERNEL_HEADERS) $(EXCEPTION_TEST_C_FILES) tests/serial_test.c
SCRIPT_FILES := run.sh scripts/debug-kernel.sh scripts/run-qemu.sh scripts/test-guest-result.sh \
	scripts/verify-artifact.sh
SERIAL_TEST_BINARY := $(HOST_TEST_DIR)/serial-test
SERIAL_TEST_SOURCES := tests/serial_test.c kernel/drivers/serial.c

.PHONY: all run debug gdb \
	test test-host test-serial test-qemu test-guest-result test-panic test-limine-handoff \
	test-descriptors test-exceptions \
	test-qemu-direct test-qemu-serial-absent test-qemu-panic \
	test-qemu-panic-serial-absent test-qemu-bad-revision test-qemu-bad-data \
	test-qemu-bad-bss test-qemu-descriptors-reinitialized test-qemu-ud \
	test-qemu-unexpected-exception test-qemu-exceptions-reinitialized test-artifact \
	test-qemu-page-fault \
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
	$(MAKE) test-qemu-exceptions-reinitialized
	$(MAKE) test-qemu-ud
	$(MAKE) test-qemu-unexpected-exception
	$(MAKE) test-qemu-page-fault

# Compatibility groups retained for the documented workflows.
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

test-exceptions:
	$(MAKE) test-qemu-exceptions-reinitialized
	$(MAKE) test-qemu-ud
	$(MAKE) test-qemu-unexpected-exception
	$(MAKE) test-qemu-page-fault

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

test-qemu-exceptions-reinitialized: | check-qemu-tools
	$(MAKE) BUILD_DIR=$(QEMU_TEST_DIR)/exceptions-reinitialized \
		EXTRA_CPPFLAGS=-DVANDAL_TEST_EXCEPTIONS_REINITIALIZED all
	VANDAL_QEMU_MACHINE=$(QEMU_MACHINE) VANDAL_QEMU_ACCEL=$(QEMU_ACCEL) \
		./scripts/test-guest-result.sh exceptions-reinitialized \
		$(QEMU_TEST_DIR)/exceptions-reinitialized/vandal-os.iso 53 stdio \
		$(TEST_RESULTS_DIR)/exceptions-reinitialized.log

test-qemu-ud: | check-qemu-tools
	$(MAKE) BUILD_DIR=$(QEMU_TEST_DIR)/ud EXTRA_CPPFLAGS=-DVANDAL_TEST_UD \
		EXCEPTION_POLICY=test all
	VANDAL_QEMU_MACHINE=$(QEMU_MACHINE) VANDAL_QEMU_ACCEL=$(QEMU_ACCEL) \
		./scripts/test-guest-result.sh ud \
		$(QEMU_TEST_DIR)/ud/vandal-os.iso 59 stdio \
		$(TEST_RESULTS_DIR)/ud.log

test-qemu-unexpected-exception: | check-qemu-tools
	$(MAKE) BUILD_DIR=$(QEMU_TEST_DIR)/unexpected-exception \
		EXTRA_CPPFLAGS=-DVANDAL_TEST_UNEXPECTED_EXCEPTION EXCEPTION_POLICY=test all
	VANDAL_QEMU_MACHINE=$(QEMU_MACHINE) VANDAL_QEMU_ACCEL=$(QEMU_ACCEL) \
		./scripts/test-guest-result.sh unexpected-exception \
		$(QEMU_TEST_DIR)/unexpected-exception/vandal-os.iso 61 stdio \
		$(TEST_RESULTS_DIR)/unexpected-exception.log

test-qemu-page-fault: | check-qemu-tools
	$(MAKE) BUILD_DIR=$(QEMU_TEST_DIR)/page-fault EXTRA_CPPFLAGS=-DVANDAL_TEST_PF \
		EXCEPTION_POLICY=test all
	VANDAL_QEMU_MACHINE=$(QEMU_MACHINE) VANDAL_QEMU_ACCEL=$(QEMU_ACCEL) \
		./scripts/test-guest-result.sh page-fault \
		$(QEMU_TEST_DIR)/page-fault/vandal-os.iso 63 stdio \
		$(TEST_RESULTS_DIR)/page-fault.log

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

$(BUILD_DIR)/%.o: %.c Makefile $(LIMINE_HEADER) | check-compiler-tools
	@mkdir -p $(@D)
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MMD -MP -c $< -o $@

$(BUILD_DIR)/%.o: %.S Makefile | check-compiler-tools
	@mkdir -p $(@D)
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MMD -MP -c $< -o $@

$(SERIAL_TEST_BINARY): $(SERIAL_TEST_SOURCES) kernel/drivers/serial.h Makefile | check-compiler-tools
	@mkdir -p $(@D)
	$(HOST_CC) $(HOST_TEST_CPPFLAGS) $(HOST_TEST_CFLAGS) $(SERIAL_TEST_SOURCES) -o $@

$(LSP_DATABASE): $(KERNEL_C_SOURCES) $(KERNEL_ASM_SOURCES) $(EXCEPTION_TEST_FILES) \
	tests/serial_test.c Makefile $(LIMINE_HEADER) | check-compiler-tools
	@mkdir -p $(@D)
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MJ $@.main.tmp -fsyntax-only kernel/main.c
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MJ $@.serial.tmp -fsyntax-only kernel/drivers/serial.c
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MJ $@.panic.tmp -fsyntax-only kernel/panic.c
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MJ $@.guest-result.tmp -fsyntax-only kernel/platform/qemu/guest_result.c
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MJ $@.descriptors.tmp -fsyntax-only kernel/arch/x86_64/descriptors.c
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MJ $@.exceptions.tmp -fsyntax-only kernel/arch/x86_64/exceptions.c
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MJ $@.exception-dispatch.tmp -fsyntax-only kernel/arch/x86_64/exception_dispatch.c
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MJ $@.exception-finish.tmp \
		-fsyntax-only kernel/arch/x86_64/exception_finish_prod.c
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MJ $@.exception-finish-test.tmp \
		-fsyntax-only tests/exception_finish_test.c
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MJ $@.descriptor-state.tmp \
		-c kernel/arch/x86_64/descriptor_state.S -o /dev/null
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MJ $@.exception-vector.tmp \
		-c kernel/arch/x86_64/exception_vector.S -o /dev/null
	$(TARGET_CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MJ $@.exception-stimulus.tmp \
		-c tests/exception_stimulus.S -o /dev/null
	$(HOST_CC) $(HOST_TEST_CPPFLAGS) $(HOST_TEST_CFLAGS) -MJ $@.serial-test.tmp -fsyntax-only tests/serial_test.c
	@{ printf '[\n'; sed -n 'p' $@.main.tmp; sed -n 'p' $@.serial.tmp; \
		sed -n 'p' $@.panic.tmp; sed -n 'p' $@.guest-result.tmp; \
		sed -n 'p' $@.descriptors.tmp; sed -n 'p' $@.exceptions.tmp; \
		sed -n 'p' $@.exception-dispatch.tmp; \
		sed -n 'p' $@.exception-finish.tmp; sed -n 'p' $@.exception-finish-test.tmp; \
		sed -n 'p' $@.descriptor-state.tmp; sed -n 'p' $@.exception-vector.tmp; \
		sed -n 'p' $@.exception-stimulus.tmp; \
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
