#ifndef VANDAL_GUEST_RESULT_H
#define VANDAL_GUEST_RESULT_H

typedef enum guest_result {
    GUEST_RESULT_TEST_OK = 0x10,
    GUEST_RESULT_SERIAL_UNAVAILABLE = 0x11,
    GUEST_RESULT_PANIC_TEST = 0x12,
    GUEST_RESULT_LIMINE_REVISION = 0x13,
    GUEST_RESULT_DATA_CORRUPT = 0x14,
    GUEST_RESULT_BSS_NOT_ZERO = 0x15,
    GUEST_RESULT_UNEXPECTED_PANIC = 0x16,
} guest_result;

/* Report one test result to QEMU, then halt if the device is unavailable. */
__attribute__((noreturn)) void guest_result_report(guest_result result);

#endif
