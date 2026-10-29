#ifndef VANDAL_DESCRIPTORS_H
#define VANDAL_DESCRIPTORS_H

/* Activate and verify the kernel-owned GDT/TSS; panic on failure or reuse. */
void descriptors_init(void);

#endif
