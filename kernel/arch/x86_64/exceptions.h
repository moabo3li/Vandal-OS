#ifndef VANDAL_EXCEPTIONS_H
#define VANDAL_EXCEPTIONS_H

/*
 * Populate and install the owned 32-entry IDT for CPU exception vectors 0-31.
 *
 * The caller must run at CPL 0 with IF clear and owned GDTR/TSS state active.
 * On success, IDTR names the owned table with limit 0x1ff. A repeated call or a
 * validation mismatch panics instead of returning.
 */
void exceptions_init(void);

#endif
