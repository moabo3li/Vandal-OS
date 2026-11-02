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

/*
 * Deliberate #PF (vector 14).
 *
 * Read from a canonical but intentionally unmapped virtual address.
 * Expected: CR2 = 0x0000400000000000, error code = 0x0
 * (supervisor read of a non-present page).
 *
 * The faulting RIP points to the movq instruction.
 * The terminal exception dispatcher never returns.
 */
.globl trigger_page_fault
.type trigger_page_fault, @function
.globl pf_site

trigger_page_fault:
    movabsq $0x0000400000000000, %rax
pf_site:
    movq (%rax), %rax

4:
    cli
    hlt
    jmp 4b

.size trigger_page_fault, .-trigger_page_fault
