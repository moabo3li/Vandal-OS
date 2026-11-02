/*
 * x86-64 CPU exception entry stubs (vectors 0–31).
 *
 * Each vector has a dedicated entry point referenced by the IDT.
 * The stubs normalize hardware error-code differences and transfer
 * control to a common entry that saves registers and calls C.
 *
 * This is a terminal-only exception path: handlers do not return
 * to interrupted execution.
 */

.section .text

/*
 * Normalize exception frames for the common handler.
 *
 * The CPU saves the interrupted execution state but does not push
 * the exception vector number.
 *
 * NO_ERROR: push a synthetic zero error code and the vector number.
 * WITH_ERROR: the CPU already pushed an error code; push only
 *             the vector number.
 *
 * Both paths produce:
 *   vector, error_code, RIP, CS, RFLAGS, old RSP, old SS
 *
 * Jump rather than call to avoid adding a return address.
 */
.macro EXCEPTION_NO_ERROR number
.globl exception_vector_\number
.type exception_vector_\number, @function
exception_vector_\number:
    pushq $0
    pushq $\number
    jmp exception_common
.size exception_vector_\number, .-exception_vector_\number
.endm

.macro EXCEPTION_WITH_ERROR number
.globl exception_vector_\number
.type exception_vector_\number, @function
exception_vector_\number:
    pushq $\number
    jmp exception_common
.size exception_vector_\number, .-exception_vector_\number
.endm

/*
 * Generate entry points for architectural exception vectors 0–31.
 *
 * Some exceptions depend on optional CPU features. These stubs
 * assume genuine hardware exception delivery, not software INT.
 */
EXCEPTION_NO_ERROR   0
EXCEPTION_NO_ERROR   1
EXCEPTION_NO_ERROR   2
EXCEPTION_NO_ERROR   3
EXCEPTION_NO_ERROR   4
EXCEPTION_NO_ERROR   5
EXCEPTION_NO_ERROR   6
EXCEPTION_NO_ERROR   7
EXCEPTION_WITH_ERROR 8
EXCEPTION_NO_ERROR   9
EXCEPTION_WITH_ERROR 10
EXCEPTION_WITH_ERROR 11
EXCEPTION_WITH_ERROR 12
EXCEPTION_WITH_ERROR 13
EXCEPTION_WITH_ERROR 14
EXCEPTION_NO_ERROR   15
EXCEPTION_NO_ERROR   16
EXCEPTION_WITH_ERROR 17
EXCEPTION_NO_ERROR   18
EXCEPTION_NO_ERROR   19
EXCEPTION_NO_ERROR   20
EXCEPTION_WITH_ERROR 21
EXCEPTION_NO_ERROR   22
EXCEPTION_NO_ERROR   23
EXCEPTION_NO_ERROR   24
EXCEPTION_NO_ERROR   25
EXCEPTION_NO_ERROR   26
EXCEPTION_NO_ERROR   27
EXCEPTION_NO_ERROR   28
EXCEPTION_WITH_ERROR 29
EXCEPTION_WITH_ERROR 30
EXCEPTION_NO_ERROR   31

/*
 * Common exception entry.
 *
 * Clear DF for the C ABI, then save the general-purpose registers.
 * The resulting stack layout must match struct exception_frame.
 *
 * Pass the frame address in RDI.
 * Align RSP to 16 bytes before calling the C dispatcher.
 *
 * The dispatcher is expected not to return. Halt defensively if
 * it does; no register restoration or IRETQ is implemented yet.
 */
.type exception_common, @function
exception_common:
    cld

    pushq %rax
    pushq %rbx
    pushq %rcx
    pushq %rdx
    pushq %rsi
    pushq %rdi
    pushq %rbp
    pushq %r8
    pushq %r9
    pushq %r10
    pushq %r11
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15

    movq %rsp, %rdi
    andq $-16, %rsp
    call exception_dispatch

halt_forever:
    cli
    hlt
    jmp halt_forever

.size exception_common, .-exception_common

/*
 * Vector-to-entry address table consumed by populate_idt().
 *
 * Each element is an 8-byte function address. The C IDT builder
 * uses these addresses to populate the 64-bit gate offsets.
 *
 * This table is software-owned; the CPU reads the IDT itself,
 * not exception_vector_entries.
 *
 * Keep the order consistent with exception vector numbers 0–31.
 */
.section .rodata,"a",@progbits
.p2align 3

.globl exception_vector_entries
.type exception_vector_entries, @object

exception_vector_entries:
    .quad exception_vector_0
    .quad exception_vector_1
    .quad exception_vector_2
    .quad exception_vector_3
    .quad exception_vector_4
    .quad exception_vector_5
    .quad exception_vector_6
    .quad exception_vector_7
    .quad exception_vector_8
    .quad exception_vector_9
    .quad exception_vector_10
    .quad exception_vector_11
    .quad exception_vector_12
    .quad exception_vector_13
    .quad exception_vector_14
    .quad exception_vector_15
    .quad exception_vector_16
    .quad exception_vector_17
    .quad exception_vector_18
    .quad exception_vector_19
    .quad exception_vector_20
    .quad exception_vector_21
    .quad exception_vector_22
    .quad exception_vector_23
    .quad exception_vector_24
    .quad exception_vector_25
    .quad exception_vector_26
    .quad exception_vector_27
    .quad exception_vector_28
    .quad exception_vector_29
    .quad exception_vector_30
    .quad exception_vector_31

.size exception_vector_entries, .-exception_vector_entries

/*
 * The IDT builder reads this count to reject a table whose length no longer
 * matches its C-side IDT_VECTOR_COUNT.
 */
.globl exception_vector_entry_count
.type exception_vector_entry_count, @object
exception_vector_entry_count:
    .quad 32
.size exception_vector_entry_count, 8

.section .text

/*
 * IDTR access boundary. LIDT copies the packed ten-byte operand into IDTR;
 * SIDT observes the live value without changing descriptor state.
 */
.globl load_idtr
.type load_idtr, @function
load_idtr:
    lidt (%rdi)
    ret
.size load_idtr, .-load_idtr

.globl read_idtr
.type read_idtr, @function
read_idtr:
    sidt (%rdi)
    ret
.size read_idtr, .-read_idtr

.section .note.GNU-stack,"",@progbits
