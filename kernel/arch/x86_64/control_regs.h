#ifndef VANDAL_ARCH_X86_64_CONTROL_REGS_H
#define VANDAL_ARCH_X86_64_CONTROL_REGS_H

#include <stdint.h>

/*
 * Read CR2, which the processor loads with the faulting linear address when it
 * delivers #PF (vector 14). CR2 describes only the most recent page fault, so a
 * handler must capture it before any later fault can overwrite it. Reading a
 * control register requires CPL 0.
 *
 * The dispatcher currently captures this once at C entry, which is sound only
 * while delivery is terminal and single-fault. TODO(M2/M3): once a handler can
 * fault or return, capture CR2 in the entry stub before any C code runs so the
 * recorded value still belongs to the fault being diagnosed.
 */
static inline uint64_t read_cr2(void) {
    uint64_t value;

    __asm__ volatile("mov %%cr2, %0" : "=r"(value));
    return value;
}

#endif
