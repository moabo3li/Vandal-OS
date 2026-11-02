#include <stdbool.h>
#include <stdint.h>

#include "../kernel/arch/x86_64/exception_policy.h"
#include "../kernel/drivers/serial.h"
#include "../kernel/guest_result.h"
#include "exception_stimulus.h"

/*
 * Acceptance policy for exception tests.
 *
 * This object is the only place a test decides what a delivered exception
 * means. The IDT, entry stubs, frame layout, dispatcher and diagnostics it
 * observes are the unmodified production objects linked beside it.
 *
 * These predicates accept a diagnosis; they do not prove recovery. TODO(M3):
 * add cases that resolve a page fault and resume the faulting instruction once
 * an owned address space makes that meaningful.
 */

/* The owned GDT's flat kernel-code selector, as descriptors_init() installs it. */
#define EXPECTED_KERNEL_CS UINT16_C(0x08)

/* The unmapped canonical address read by trigger_page_fault(). */
#define CONTROLLED_PAGE_FAULT_ADDRESS UINT64_C(0x0000400000000000)

/* #UD on the ud2 instruction: vector 6, synthetic error zero, kernel CS, ud_site. */
static bool is_controlled_ud(const struct exception_frame *frame) {
    return frame->vector == 6 && frame->error_code == 0 && frame->cs == EXPECTED_KERNEL_CS &&
           frame->rip == (uintptr_t)&ud_site;
}

/* #PF on the controlled read: not-present supervisor read at the predicted address. */
static bool is_controlled_page_fault(const struct exception_frame *frame, uint64_t cr2) {
    return frame->vector == PAGE_FAULT_VECTOR && frame->error_code == 0 &&
           frame->cs == EXPECTED_KERNEL_CS && frame->rip == (uintptr_t)&pf_site &&
           cr2 == CONTROLLED_PAGE_FAULT_ADDRESS;
}

__attribute__((noreturn)) void exception_finish(const struct exception_frame *frame, uint64_t cr2) {
    if (is_controlled_ud(frame)) {
        (void)serial_puts("UD_PASS\n");
        guest_result_report(GUEST_RESULT_UD_PASS);
    }

    if (is_controlled_page_fault(frame, cr2)) {
        (void)serial_puts("PF_PASS\n");
        guest_result_report(GUEST_RESULT_PF_PASS);
    }

    /* Any other delivery, including the deliberate #BP, fails the test. */
    guest_result_report(GUEST_RESULT_EXCEPTION_UNEXPECTED);
}
