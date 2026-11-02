#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "../../panic.h"
#include "exceptions.h"

/*
 * Own the IDT policy for the pinned single-CPU target. This module encodes
 * present DPL-0 interrupt gates for every CPU-defined vector 0-31 and publishes
 * them with LIDT. Exception entry, normalization, and diagnostics belong to the
 * assembly boundary and later increments.
 */

/* The owned GDT's flat kernel-code selector. */
#define GDT_KERNEL_CODE_SELECTOR UINT16_C(0x08)

/* P=1, DPL=0, S=0, type=0xe: 64-bit interrupt gate that clears IF on entry. */
#define IDT_INTERRUPT_GATE_ATTRIBUTES UINT8_C(0x8e)

/* The IST field is three bits; IST1 names the double-fault emergency stack. */
#define IDT_IST_MASK UINT8_C(0x07)
#define IDT_IST_NONE UINT8_C(0)
#define IDT_IST_DOUBLE_FAULT UINT8_C(1)

enum {
    IDT_VECTOR_COUNT = 32,
    IDT_ENTRY_SIZE = 16,
    DOUBLE_FAULT_VECTOR = 8,
};

/*
 * A 64-bit interrupt/trap gate descriptor. The handler offset is split across
 * three fields, and the upper 32 bits are reserved and must remain zero.
 */
struct __attribute__((packed)) idt_descriptor {
    uint16_t offset_low;
    uint16_t selector;
    uint8_t ist;
    uint8_t type_attributes;
    uint16_t offset_mid;
    uint32_t offset_high;
    uint32_t reserved;
};

_Static_assert(sizeof(struct idt_descriptor) == IDT_ENTRY_SIZE, "64-bit IDT descriptor size");
_Static_assert(offsetof(struct idt_descriptor, type_attributes) == 5,
               "descriptor attribute offset");

/*
 * LIDT reads this architectural 10-byte operand: a 16-bit last-byte offset
 * followed by the 64-bit linear base of the table.
 */
struct __attribute__((packed)) idt_pointer {
    uint16_t limit;
    uintptr_t base;
};

_Static_assert(sizeof(struct idt_pointer) == 10, "IDTR operand must be 10 bytes");
_Static_assert(offsetof(struct idt_pointer, base) == 2, "IDTR base offset must be 2");

/*
 * The assembly module owns one entry point per vector so each can supply the
 * vector number the processor does not push. This table maps every index
 * 0-31 to its stub, and the adjacent count object lets the IDT builder reject
 * a table that no longer matches IDT_VECTOR_COUNT.
 */
extern void (*const exception_vector_entries[IDT_VECTOR_COUNT])(void);
extern const uint64_t exception_vector_entry_count;

/* Load IDTR from the packed operand in RDI; copy the current IDTR into RDI. */
extern void load_idtr(const struct idt_pointer *operand);
extern void read_idtr(struct idt_pointer *result);

__attribute__((used, aligned(16))) static struct idt_descriptor kernel_idt[IDT_VECTOR_COUNT];

__attribute__((used)) static const struct idt_pointer kernel_idt_operand = {
    .limit = (uint16_t)(sizeof(kernel_idt) - 1U),
    .base = (uintptr_t)&kernel_idt,
};

static struct idt_descriptor make_interrupt_descriptor(uintptr_t target, uint16_t selector,
                                                       uint8_t ist, uint8_t type_attributes) {
    struct idt_descriptor desc = {0};

    desc.offset_low = (uint16_t)(target & UINT64_C(0xffff));
    desc.selector = selector;
    desc.ist = (uint8_t)(ist & UINT8_C(0x07));
    desc.type_attributes = type_attributes;
    desc.offset_mid = (uint16_t)((target >> 16) & UINT64_C(0xffff));
    desc.offset_high = (uint32_t)(target >> 32);

    return desc;
}

static uint8_t vector_ist(size_t vector) {
    return vector == DOUBLE_FAULT_VECTOR ? IDT_IST_DOUBLE_FAULT : IDT_IST_NONE;
}

static void populate_idt(void) {
    uint16_t selector = GDT_KERNEL_CODE_SELECTOR;
    uint8_t type_attributes = IDT_INTERRUPT_GATE_ATTRIBUTES;

    for (size_t vector = 0; vector < IDT_VECTOR_COUNT; vector++) {
        kernel_idt[vector] =
            make_interrupt_descriptor((uintptr_t)exception_vector_entries[vector], selector,
                                      vector_ist(vector), type_attributes);
    }
}

/* Reconstruct a descriptor's 64-bit handler offset independently of the encoder. */
static uintptr_t idt_descriptor_offset(const struct idt_descriptor *descriptor) {
    return (uintptr_t)descriptor->offset_low | ((uintptr_t)descriptor->offset_mid << 16) |
           ((uintptr_t)descriptor->offset_high << 32);
}

static bool idt_is_well_formed(void) {
    if (exception_vector_entry_count != (uint64_t)IDT_VECTOR_COUNT) {
        return false;
    }

    if (kernel_idt_operand.base != (uintptr_t)&kernel_idt ||
        kernel_idt_operand.limit != sizeof(kernel_idt) - 1U) {
        return false;
    }

    for (size_t vector = 0; vector < IDT_VECTOR_COUNT; vector++) {
        const struct idt_descriptor *descriptor = &kernel_idt[vector];

        if (descriptor->selector != GDT_KERNEL_CODE_SELECTOR ||
            descriptor->type_attributes != IDT_INTERRUPT_GATE_ATTRIBUTES ||
            (descriptor->ist & (uint8_t)~IDT_IST_MASK) != 0 ||
            descriptor->ist != vector_ist(vector) || descriptor->reserved != 0 ||
            idt_descriptor_offset(descriptor) != (uintptr_t)exception_vector_entries[vector]) {
            return false;
        }
    }

    return true;
}

static bool live_idtr_is_valid(void) {
    struct idt_pointer observed = {0};

    read_idtr(&observed);

    return observed.base == kernel_idt_operand.base && observed.limit == kernel_idt_operand.limit;
}

enum exceptions_state {
    EXCEPTIONS_UNINITIALIZED,
    EXCEPTIONS_INSTALLING,
    EXCEPTIONS_READY,
};

static enum exceptions_state exceptions_state = EXCEPTIONS_UNINITIALIZED;

void exceptions_init(void) {
    if (exceptions_state != EXCEPTIONS_UNINITIALIZED) {
        kernel_panic(KERNEL_PANIC_EXCEPTIONS_REINITIALIZED);
    }

    populate_idt();

    if (!idt_is_well_formed()) {
        kernel_panic(KERNEL_PANIC_EXCEPTIONS_PREFLIGHT);
    }

    exceptions_state = EXCEPTIONS_INSTALLING;
    load_idtr(&kernel_idt_operand);

    if (!live_idtr_is_valid()) {
        kernel_panic(KERNEL_PANIC_EXCEPTIONS_READBACK);
    }

    exceptions_state = EXCEPTIONS_READY;
}
