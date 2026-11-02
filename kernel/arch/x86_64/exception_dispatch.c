#include "../../drivers/serial.h"
#include "exception_policy.h"

/*
 * Shared terminal C view of one delivered CPU exception.
 *
 * The record is produced by the assembly entry boundary, so this file is
 * production code in every image: it prints one bounded diagnostic record and
 * hands the terminal decision to the linked policy. Keep test acceptance rules
 * out of this path.
 */
__attribute__((noreturn)) void exception_dispatch(const struct exception_frame *frame) {
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
    (void)serial_puts("\n");

    exception_finish(frame);
}
