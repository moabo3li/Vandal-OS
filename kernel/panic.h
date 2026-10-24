#ifndef VANDAL_PANIC_H
#define VANDAL_PANIC_H

typedef enum kernel_panic_reason {
    KERNEL_PANIC_TEST,
    KERNEL_PANIC_LIMINE_REVISION,
    KERNEL_PANIC_DATA_CORRUPT,
    KERNEL_PANIC_BSS_NOT_ZERO,
} kernel_panic_reason;

/* Publish one terminal kernel failure; this function never returns. */
__attribute__((noreturn)) void kernel_panic(kernel_panic_reason reason);

#endif
