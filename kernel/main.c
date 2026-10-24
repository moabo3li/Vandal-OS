#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <limine.h>

#include "guest_result.h"
#include "panic.h"
#include "serial.h"

#define LIMINE_BASE_REVISION_SUPPORTED(VAR) ((VAR)[2] == 0)
#define DATA_PROBE_EXPECTED UINT64_C(0x56414e44414c4d30)

#if (defined(VANDAL_TEST_BAD_LIMINE_REVISION) + defined(VANDAL_TEST_BAD_DATA) +                    \
     defined(VANDAL_TEST_BAD_BSS)) > 1
#error "select only one handoff-validation injection"
#endif

_Static_assert(sizeof(size_t) == 8, "x86-64 size_t must be 64 bits");
_Static_assert(sizeof(uintptr_t) == 8, "x86-64 pointers must be 64 bits");

static volatile uint64_t data_probe = DATA_PROBE_EXPECTED;
static volatile uint64_t bss_probe;

/* Limine scans the loaded image between these markers for protocol requests. */
__attribute__((
    used, section(".limine_requests_start"))) static volatile uint64_t limine_requests_start[] =
    LIMINE_REQUESTS_START_MARKER;

__attribute__((used, section(".limine_requests"))) static volatile uint64_t limine_base_revision[] =
    LIMINE_BASE_REVISION(6);

__attribute__((used,
               section(".limine_requests_end"))) static volatile uint64_t limine_requests_end[] =
    LIMINE_REQUESTS_END_MARKER;

static void validate_limine_handoff(void) {
    bool revision_supported = LIMINE_BASE_REVISION_SUPPORTED(limine_base_revision);
    uint64_t observed_data = data_probe;
    uint64_t observed_bss = bss_probe;

#if defined(VANDAL_TEST_BAD_LIMINE_REVISION)
    revision_supported = false;
#elif defined(VANDAL_TEST_BAD_DATA)
    observed_data ^= UINT64_C(1);
#elif defined(VANDAL_TEST_BAD_BSS)
    observed_bss = UINT64_C(1);
#endif

    if (!revision_supported) {
        kernel_panic(KERNEL_PANIC_LIMINE_REVISION);
    }
    if (observed_data != DATA_PROBE_EXPECTED) {
        kernel_panic(KERNEL_PANIC_DATA_CORRUPT);
    }
    if (observed_bss != 0) {
        kernel_panic(KERNEL_PANIC_BSS_NOT_ZERO);
    }
}

/* A named, non-returning destination makes the terminal state easy to inspect. */
__attribute__((noreturn, noinline)) void kernel_idle(void) {
    __asm__ volatile("cli" ::: "memory");
    for (;;) {
        __asm__ volatile(".globl kernel_halt\n"
                         "kernel_halt:\n"
                         "hlt" ::
                             : "memory");
    }
}

/*
 * Limine enters here using the x86-64 System V ABI. It has already supplied
 * the stack, installed paging, zero-filled the ELF BSS, and cleared DF and IF.
 */
__attribute__((noreturn)) void kernel_main(void) {
    /* Keep these entry requirements explicit while no IDT exists. */
    __asm__ volatile("cli\ncld" ::: "memory");

    validate_limine_handoff();

#if defined(VANDAL_TEST_GUEST_RESULT)
    guest_result_report(GUEST_RESULT_TEST_OK);
#endif

    bool serial_ready = serial_init();

#if defined(VANDAL_TEST_PANIC)
    kernel_panic(KERNEL_PANIC_TEST);
#endif

    if (!serial_ready) {
        guest_result_report(GUEST_RESULT_SERIAL_UNAVAILABLE);
    }

    (void)serial_puts("Vandal-OS: serial ready\r\n");

    kernel_idle();
}
