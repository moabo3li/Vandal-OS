#ifndef VANDAL_EXCEPTION_FRAME_H
#define VANDAL_EXCEPTION_FRAME_H

#include <stddef.h>
#include <stdint.h>

/*
 * C-visible record built by the assembly entry boundary.
 *
 * Exceptions are delivered at CPL 0. Vectors without an IST index push three
 * hardware words (RIP, CS, RFLAGS); the stub adds the vector and error-code
 * words. Vector 8 uses IST1, which pushes SS and RSP as well; those two extra
 * words lie above RFLAGS and are deliberately outside this record.
 *
 * The assembly push order is the source of truth; the assertions below check
 * that this C view still matches it.
 */
struct exception_frame {
    uint64_t r15;
    uint64_t r14;
    uint64_t r13;
    uint64_t r12;
    uint64_t r11;
    uint64_t r10;
    uint64_t r9;
    uint64_t r8;
    uint64_t rbp;
    uint64_t rdi;
    uint64_t rsi;
    uint64_t rdx;
    uint64_t rcx;
    uint64_t rbx;
    uint64_t rax;
    uint64_t vector;
    uint64_t error_code;
    uint64_t rip;
    uint64_t cs;
    uint64_t rflags;
};

_Static_assert(sizeof(struct exception_frame) == 160, "exception frame size");
_Static_assert(offsetof(struct exception_frame, vector) == 120, "vector offset");
_Static_assert(offsetof(struct exception_frame, error_code) == 128, "error code offset");
_Static_assert(offsetof(struct exception_frame, rip) == 136, "saved RIP offset");
_Static_assert(offsetof(struct exception_frame, cs) == 144, "saved CS offset");
_Static_assert(offsetof(struct exception_frame, rflags) == 152, "saved RFLAGS offset");

/* Classify one delivered exception; the implemented paths do not return. */
__attribute__((noreturn)) void exception_dispatch(const struct exception_frame *frame);

#endif
