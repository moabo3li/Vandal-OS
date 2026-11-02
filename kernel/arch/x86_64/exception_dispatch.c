#include "../../drivers/serial.h"
#include "control_regs.h"
#include "exception_policy.h"

/*
 * Shared terminal C view of one delivered CPU exception.
 *
 * The record is produced by the assembly entry boundary, so this file is
 * production code in every image: it prints one bounded diagnostic record and
 * hands the terminal decision to the linked policy. Keep test acceptance rules
 * out of this path.
 *
 * This is a diagnostic boundary, not fault handling: nothing here restores the
 * saved frame, returns to the interrupted instruction or resolves a page fault.
 * TODO(M2): restore the recorded state and return with IRETQ instead of
 * halting. TODO(M3): resolve #PF against owned page tables before the terminal
 * policy runs.
 */
__attribute__((noreturn)) void exception_dispatch(const struct exception_frame *frame) {
    /*
     * CR2 is one register overwritten by each page fault, so capture it before
     * the first call that could fault again. It is architecturally meaningful
     * only for #PF, and the record prints it for that vector alone.
     */
    const uint64_t cr2 = read_cr2();

    (void)serial_puts("EXCEPTION vector=");
    (void)serial_puthex(frame->vector);
    (void)serial_puts(" error=");
    (void)serial_puthex(frame->error_code);
    (void)serial_puts(" rip=");
    (void)serial_puthex(frame->rip);
    (void)serial_puts(" cs=");
    (void)serial_puthex(frame->cs);
    (void)serial_puts(" rflags=");
    (void)serial_puthex(frame->rflags);
    if (frame->vector == PAGE_FAULT_VECTOR) {
        (void)serial_puts(" cr2=");
        (void)serial_puthex(cr2);
    }
    (void)serial_puts("\n");

    exception_finish(frame, cr2);
}
