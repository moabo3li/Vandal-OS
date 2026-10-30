#ifndef VANDAL_DESCRIPTORS_H
#define VANDAL_DESCRIPTORS_H

/*
 * Activate and verify the kernel-owned GDT and TSS exactly once.
 *
 * The caller must run at CPL 0 with IF clear and a valid current stack. On
 * success, GDTR names the owned GDT; CS uses its kernel-code descriptor;
 * DS/ES/SS use its kernel-data descriptor; FS/GS are null; and TR names the
 * owned, busy TSS. RSP and IDTR are unchanged. A repeated call or validation
 * mismatch panics instead of returning.
 */
void descriptors_init(void);

#endif
