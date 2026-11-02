/*
 * Controlled architectural fault stimuli for exception-acceptance images.
 *
 * These entry points exist only to raise a real exception through the
 * production IDT, entry stubs and dispatcher. Only a test image links this
 * object; the production image neither references nor contains it.
 */

.section .text

/*
 * Deliberate #UD (vector 6).
 *
 * UD2 raises an invalid-opcode fault, so the processor saves the address of ud2
 * itself as RIP and pushes no error code. ud_site is exported so the acceptance
 * policy can compare the saved RIP with the instruction that faulted.
 *
 * Nothing resumes after the fault: the terminal policy ends the image.
 */
.globl trigger_ud
.type trigger_ud, @function
.globl ud_site

trigger_ud:
ud_site:
    ud2

2:
    cli
    hlt
    jmp 2b

.size trigger_ud, .-trigger_ud

/*
 * Deliberate #BP (vector 3).
 *
 * INT3 raises a trap, so a resuming path would continue after the instruction.
 * This terminal-only build never returns and the acceptance policy rejects
 * vector 3, so the halt loop only makes that explicit.
 */
.globl trigger_breakpoint
.type trigger_breakpoint, @function

trigger_breakpoint:
    int3

3:
    cli
    hlt
    jmp 3b

.size trigger_breakpoint, .-trigger_breakpoint
