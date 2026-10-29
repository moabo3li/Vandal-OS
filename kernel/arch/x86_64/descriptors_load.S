.section .text
.globl load_descriptor_state
.type load_descriptor_state, @function

/*
 * Install the descriptor state described by the packed ten-byte GDTR operand
 * whose address arrives in RDI.
 *
 * Preconditions: CPL 0, IF clear, valid code/data descriptors at selectors
 * 0x08/0x10, and an available 64-bit TSS descriptor at selector 0x18.
 *
 * On return, GDTR, CS, DS, ES, SS, the visible FS/GS selectors, and TR contain
 * the supplied state; the TSS descriptor is busy. RAX and arithmetic flags are
 * clobbered, while IF and DF are unchanged. The temporary far-return frame has
 * no net effect on RSP. This helper does not load IDTR or switch stacks.
 */
load_descriptor_state:
    lgdt (%rdi)

    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    xorw %ax, %ax
    movw %ax, %fs
    movw %ax, %gs

    pushq $0x08
    leaq .Lcs_ready(%rip), %rax
    pushq %rax
    lretq

.Lcs_ready:
    movw $0x18, %ax
    ltr %ax
    ret

.size load_descriptor_state, .-load_descriptor_state

/*
 * Copy the current ten-byte GDTR value into the writable object whose address
 * arrives in RDI. SGDT observes descriptor state without changing it.
 */
.globl read_gdtr
.type read_gdtr, @function
read_gdtr:
    sgdt (%rdi)
    ret
.size read_gdtr, .-read_gdtr

/*
 * Return the visible 16-bit task-register selector in AX. Clearing EAX first
 * makes the full return register deterministic; STR itself does not change TR.
 */
.globl read_tr
.type read_tr, @function
read_tr:
    xorl %eax, %eax
    str %ax
    ret
.size read_tr, .-read_tr

.section .note.GNU-stack,"",@progbits
