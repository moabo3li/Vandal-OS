#include <stddef.h>
#include <stdint.h>

#include <limine.h>

_Static_assert(sizeof(size_t) == 8, "x86-64 size_t must be 64 bits");
_Static_assert(sizeof(uintptr_t) == 8, "x86-64 pointers must be 64 bits");

/* Limine scans the loaded image between these markers for protocol requests. */
__attribute__((
    used, section(".limine_requests_start"))) static volatile uint64_t limine_requests_start[] =
    LIMINE_REQUESTS_START_MARKER;

__attribute__((used, section(".limine_requests"))) static volatile uint64_t limine_base_revision[] =
    LIMINE_BASE_REVISION(6);

__attribute__((used,
               section(".limine_requests_end"))) static volatile uint64_t limine_requests_end[] =
    LIMINE_REQUESTS_END_MARKER;

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

    kernel_idle();
}
