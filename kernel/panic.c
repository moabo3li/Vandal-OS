#include "panic.h"
#include "drivers/serial.h"
#include "guest_result.h"

typedef struct panic_desc {
    const char *message;
    enum guest_result result;
} panic_desc;

static panic_desc panic_describe(kernel_panic_reason reason) {
    switch (reason) {
    case KERNEL_PANIC_TEST:
        return (panic_desc){
            "Vandal-OS panic: injected test\r\n",
            GUEST_RESULT_PANIC_TEST,
        };
    case KERNEL_PANIC_LIMINE_REVISION:
        return (panic_desc){
            "Vandal-OS panic: unsupported Limine base revision\r\n",
            GUEST_RESULT_LIMINE_REVISION,
        };
    case KERNEL_PANIC_DATA_CORRUPT:
        return (panic_desc){
            "Vandal-OS panic: initialized data is corrupt\r\n",
            GUEST_RESULT_DATA_CORRUPT,
        };
    case KERNEL_PANIC_BSS_NOT_ZERO:
        return (panic_desc){
            "Vandal-OS panic: BSS is not zero\r\n",
            GUEST_RESULT_BSS_NOT_ZERO,
        };
    case KERNEL_PANIC_DESCRIPTORS_REINITIALIZED:
        return (panic_desc){
            "Vandal-OS panic: descriptor state initialized more than once\r\n",
            GUEST_RESULT_DESCRIPTORS_REINITIALIZED,
        };
    case KERNEL_PANIC_DESCRIPTORS_PREFLIGHT:
        return (panic_desc){
            "Vandal-OS panic: descriptor state failed preflight\r\n",
            GUEST_RESULT_DESCRIPTORS_PREFLIGHT,
        };
    case KERNEL_PANIC_DESCRIPTORS_READBACK:
        return (panic_desc){
            "Vandal-OS panic: descriptor state readback mismatch\r\n",
            GUEST_RESULT_DESCRIPTORS_READBACK,
        };
    }

    return (panic_desc){
        "Vandal-OS panic: unclassified reason\r\n",
        GUEST_RESULT_UNEXPECTED_PANIC,
    };
}

__attribute__((noreturn)) void kernel_panic(kernel_panic_reason reason) {
    panic_desc desc = panic_describe(reason);
    __asm__ volatile("cli" ::: "memory");
    (void)serial_puts(desc.message);
    guest_result_report(desc.result);
}
