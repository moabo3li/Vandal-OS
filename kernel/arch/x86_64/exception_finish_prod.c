#include "../../guest_result.h"
#include "exception_policy.h"

/*
 * Production terminal policy.
 *
 * The shared dispatcher has already printed the bounded record. No handler in
 * this milestone can recover from a delivered exception, so the image ends with
 * the unexpected-exception result instead of continuing on a frame it cannot
 * restore.
 */
__attribute__((noreturn)) void exception_finish(const struct exception_frame *frame, uint64_t cr2) {
    (void)frame;
    (void)cr2;

    guest_result_report(GUEST_RESULT_EXCEPTION_UNEXPECTED);
}
