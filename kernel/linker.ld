OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(kernel_main)

PHDRS {
    requests PT_LOAD FLAGS(0x06); /* Read, write. */
    text     PT_LOAD FLAGS(0x05); /* Read, execute. */
    rodata   PT_LOAD FLAGS(0x04); /* Read only. */
    data     PT_LOAD FLAGS(0x06); /* Read, write. */
}

SECTIONS {
    /* Limine maps non-relocatable executables in the topmost 2 GiB. */
    . = 0xffffffff80000000;

    .limine_requests : ALIGN(8) {
        KEEP(*(.limine_requests_start))
        KEEP(*(.limine_requests))
        KEEP(*(.limine_requests_end))
    } :requests

    . = ALIGN(CONSTANT(MAXPAGESIZE));
    .text : {
        *(.text .text.*)
    } :text

    . = ALIGN(CONSTANT(MAXPAGESIZE));
    .rodata : {
        *(.rodata .rodata.*)
    } :rodata

    . = ALIGN(CONSTANT(MAXPAGESIZE));
    .data : {
        *(.data .data.*)
    } :data

    .bss : {
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    } :data

    /DISCARD/ : {
        *(.eh_frame*)
        *(.note .note.*)
        *(.got .got.*)
    }
}

ASSERT((kernel_main >= 0xffffffff80000000),
       "kernel entry must be in Limine's higher-half executable range")
