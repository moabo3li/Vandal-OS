#include <stdint.h>

#include "../../arch/x86_64/io.h"
#include "../../guest_result.h"

#define GUEST_RESULT_PORT UINT16_C(0x0501)

_Static_assert(GUEST_RESULT_DESCRIPTORS_READBACK <= UINT16_MAX,
               "guest result must fit the selected port-write width");

__attribute__((noreturn)) void guest_result_report(guest_result result) {
    outw(GUEST_RESULT_PORT, (uint16_t)result);

    __asm__ volatile("cli" ::: "memory");
    for (;;) {
        __asm__ volatile(".globl guest_result_halt\n"
                         "guest_result_halt:\n"
                         "hlt" ::
                             : "memory");
    }
}
