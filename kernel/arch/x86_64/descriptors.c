#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "../../panic.h"
#include "descriptors.h"

#define GDT_KERNEL_CODE UINT64_C(0x00af9a000000ffff)
#define GDT_KERNEL_DATA UINT64_C(0x00cf92000000ffff)

_Static_assert(sizeof(uintptr_t) == 8, "x86-64 descriptor bases must be 64 bits");

enum gdt_index {
    GDT_NULL_INDEX = 0,
    GDT_KERNEL_CODE_INDEX = 1,
    GDT_KERNEL_DATA_INDEX = 2,
    GDT_TSS_LOW_INDEX = 3,
    GDT_TSS_HIGH_INDEX = 4,
    GDT_ENTRY_COUNT = 5,
};

enum gdt_selector {
    GDT_KERNEL_CODE_SELECTOR = GDT_KERNEL_CODE_INDEX * 8,
    GDT_KERNEL_DATA_SELECTOR = GDT_KERNEL_DATA_INDEX * 8,
    GDT_TSS_SELECTOR = GDT_TSS_LOW_INDEX * 8,
};

_Static_assert(GDT_KERNEL_CODE_SELECTOR == 0x08, "kernel code selector");
_Static_assert(GDT_KERNEL_DATA_SELECTOR == 0x10, "kernel data selector");
_Static_assert(GDT_TSS_SELECTOR == 0x18, "TSS selector");

/*
 * LGDT reads this architectural 10-byte memory operand: a 16-bit last-byte
 * offset followed immediately by the 64-bit linear base of the table.
 */
struct __attribute__((packed)) table_pointer {
    uint16_t limit;
    uintptr_t base;
};

_Static_assert(sizeof(struct table_pointer) == 10, "GDTR operand must be 10 bytes");
_Static_assert(offsetof(struct table_pointer, base) == 2, "GDTR base offset must be 2");

/*
 * Assembly boundary for installing the prepared descriptor state. The helper
 * reads the operand but does not retain its address. descriptors_init verifies
 * the owned memory first; CPL 0, IF clear, and a valid current stack remain
 * caller preconditions.
 */
extern void load_descriptor_state(const struct table_pointer *operand);

/* Copy the current ten-byte GDTR value into result without changing GDTR. */
extern void read_gdtr(struct table_pointer *result);

/* Return the visible task-register selector without changing TR. */
extern uint16_t read_tr(void);

/*
 * A 64-bit TSS system descriptor occupies two consecutive GDT slots. The
 * split fields reconstruct one 64-bit TSS base and a 20-bit segment limit;
 * the upper slot also contains 32 reserved bits that must remain zero.
 */
struct __attribute__((packed)) tss_descriptor {
    uint16_t limit_low;
    uint16_t base_low;
    uint8_t base_mid;
    uint8_t access;
    uint8_t limit_high_flags;
    uint8_t base_high;
    uint32_t base_upper;
    uint32_t reserved;
};

_Static_assert(sizeof(struct tss_descriptor) == 16, "64-bit TSS descriptor size");

/*
 * The GDT has a fixed heterogeneous layout: three ordinary 8-byte descriptors
 * followed by one 16-byte system descriptor. The offset assertions below tie
 * the C members to the selector indices consumed by the CPU.
 */
struct global_descriptor_table {
    uint64_t null_descriptor;
    uint64_t kernel_code_descriptor;
    uint64_t kernel_data_descriptor;
    struct tss_descriptor tss_descriptor;
};

_Static_assert(offsetof(struct global_descriptor_table, null_descriptor) == GDT_NULL_INDEX * 8U,
               "null descriptor offset");
_Static_assert(offsetof(struct global_descriptor_table, kernel_code_descriptor) ==
                   GDT_KERNEL_CODE_INDEX * 8U,
               "kernel code descriptor offset");
_Static_assert(offsetof(struct global_descriptor_table, kernel_data_descriptor) ==
                   GDT_KERNEL_DATA_INDEX * 8U,
               "kernel data descriptor offset");
_Static_assert(offsetof(struct global_descriptor_table, tss_descriptor) == GDT_TSS_LOW_INDEX * 8U,
               "TSS descriptor offset");
_Static_assert(sizeof(struct global_descriptor_table) == GDT_ENTRY_COUNT * 8U,
               "unexpected GDT size");

/*
 * Hardware-defined 64-bit TSS byte layout. RSP0 will name the future
 * privilege-entry stack, while ist[0] is architectural IST1 because IDT IST
 * indices are one-based. All reserved fields must remain zero.
 */
struct __attribute__((packed)) tss {
    uint32_t reserved0;
    uint64_t rsp0;
    uint64_t rsp1;
    uint64_t rsp2;
    uint64_t reserved1;
    uint64_t ist[7];
    uint64_t reserved2;
    uint16_t reserved3;
    uint16_t io_map_base;
};

_Static_assert(sizeof(struct tss) == 104, "64-bit TSS size");
_Static_assert(offsetof(struct tss, rsp0) == 4, "RSP0 offset");
_Static_assert(offsetof(struct tss, ist[0]) == 36, "IST1 offset");
_Static_assert(offsetof(struct tss, io_map_base) == 102, "I/O-map offset field");

enum {
    RSP0_STACK_SIZE = 16 * 1024,
    DOUBLE_FAULT_STACK_SIZE = 16 * 1024,
};

/*
 * These statically owned intervals exist for the kernel's entire lifetime.
 * They grow downward from their one-past-the-array addresses. The RSP0 stack
 * is future privilege-entry state; it is not the Limine stack currently
 * executing kernel_main. The second interval is reserved exclusively for
 * architectural IST1 and eventual double-fault delivery.
 */
__attribute__((used, aligned(16))) static uint8_t rsp0_stack[RSP0_STACK_SIZE];

__attribute__((used, aligned(16))) static uint8_t double_fault_stack[DOUBLE_FAULT_STACK_SIZE];

/*
 * The CPU starts each downward-growing stack at its top, so both stored values
 * are one-past their arrays. ist[0] supplies architectural IST1. Setting the
 * I/O-map base one byte beyond the TSS limit declares that no permission
 * bitmap is present; all unspecified and reserved fields remain zero.
 */
__attribute__((used, aligned(16))) static struct tss kernel_tss = {
    .rsp0 = (uintptr_t)&rsp0_stack[RSP0_STACK_SIZE],
    .ist[0] = (uintptr_t)&double_fault_stack[DOUBLE_FAULT_STACK_SIZE],
    .io_map_base = sizeof(struct tss),
};

/*
 * This table begins dormant. Merely emitting these bytes does not change the
 * CPU's cached descriptor state. Its TSS member remains zero until prepare_gdt
 * is called, and descriptors_init activates it only after memory preflight.
 */
__attribute__((used, aligned(16))) static struct global_descriptor_table gdt = {
    .null_descriptor = 0,
    .kernel_code_descriptor = GDT_KERNEL_CODE,
    .kernel_data_descriptor = GDT_KERNEL_DATA,
    .tss_descriptor = {0},
};

_Static_assert(sizeof(gdt) <= (size_t)UINT16_MAX + 1U, "GDT size must fit the architectural limit");

/*
 * This is the 10-byte memory operand that lgdt will read later. Its limit is
 * the last valid byte offset in gdt; the CPU copies both fields into GDTR and
 * does not retain a reference to this operand.
 */
__attribute__((used)) static const struct table_pointer gdt_operand = {
    .limit = (uint16_t)(sizeof(gdt) - 1U),
    .base = (uintptr_t)&gdt,
};

/*
 * Construct the available 64-bit TSS descriptor in ordinary memory. This
 * helper only splits the TSS base and limit into their architectural fields;
 * it neither writes the result into gdt nor changes any CPU register. Starting
 * from zero also keeps every reserved bit clear.
 */
static struct tss_descriptor make_kernel_tss_descriptor(void) {
    struct tss_descriptor descriptor = {0};
    uintptr_t base = (uintptr_t)&kernel_tss;
    uint32_t limit = (uint32_t)sizeof(kernel_tss) - 1U;

    descriptor.limit_low = (uint16_t)(limit & UINT32_C(0xffff));
    descriptor.base_low = (uint16_t)(base & (uintptr_t)UINT32_C(0xffff));
    descriptor.base_mid = (uint8_t)((base >> 16) & (uintptr_t)UINT32_C(0xff));
    descriptor.access = UINT8_C(0x89); /* present, DPL 0, available 64-bit TSS */
    descriptor.limit_high_flags = (uint8_t)((limit >> 16) & UINT32_C(0x0f));
    descriptor.base_high = (uint8_t)((base >> 24) & (uintptr_t)UINT32_C(0xff));
    descriptor.base_upper = (uint32_t)(base >> 32);

    return descriptor;
}

/*
 * Populate only the GDT's 16-byte TSS member. This writes ordinary memory but
 * still does not change GDTR or TR; activation remains a later explicit step.
 */
static void prepare_gdt(void) {
    gdt.tss_descriptor = make_kernel_tss_descriptor();
}

/* Track the one-way initialization transition and reject a second LTR. */
enum descriptor_state {
    DESCRIPTORS_UNINITIALIZED,
    DESCRIPTORS_INSTALLING,
    DESCRIPTORS_READY,
};

static enum descriptor_state descriptor_state = DESCRIPTORS_UNINITIALIZED;

/* Decode the split 64-bit base independently from the descriptor encoder. */
static uintptr_t tss_descriptor_base(const struct tss_descriptor *descriptor) {
    return (uintptr_t)descriptor->base_low | ((uintptr_t)descriptor->base_mid << 16) |
           ((uintptr_t)descriptor->base_high << 24) | ((uintptr_t)descriptor->base_upper << 32);
}

/* Decode the split 20-bit byte limit independently from the encoder. */
static uint32_t tss_descriptor_limit(const struct tss_descriptor *descriptor) {
    return (uint32_t)descriptor->limit_low |
           ((uint32_t)(descriptor->limit_high_flags & UINT8_C(0x0f)) << 16);
}

/* Verify the prepared TSS object, including its absent-I/O-map policy. */
static bool kernel_tss_is_valid(void) {
    if (kernel_tss.reserved0 != 0 || kernel_tss.rsp1 != 0 || kernel_tss.rsp2 != 0 ||
        kernel_tss.reserved1 != 0 || kernel_tss.reserved2 != 0 || kernel_tss.reserved3 != 0) {
        return false;
    }

    for (size_t index = 1; index < 7; index++) {
        if (kernel_tss.ist[index] != 0) {
            return false;
        }
    }

    return kernel_tss.rsp0 == (uintptr_t)&rsp0_stack[RSP0_STACK_SIZE] &&
           kernel_tss.ist[0] == (uintptr_t)&double_fault_stack[DOUBLE_FAULT_STACK_SIZE] &&
           kernel_tss.io_map_base == sizeof(kernel_tss);
}

/*
 * Check ordinary memory before the first privileged state change. This does
 * not inspect live CPU state or prove that the processor will accept it.
 */
static bool prepared_state_is_valid(void) {
    const struct tss_descriptor *descriptor = &gdt.tss_descriptor;

    if (gdt.null_descriptor != 0 || gdt.kernel_code_descriptor != GDT_KERNEL_CODE ||
        gdt.kernel_data_descriptor != GDT_KERNEL_DATA || gdt_operand.base != (uintptr_t)&gdt ||
        gdt_operand.limit != sizeof(gdt) - 1U) {
        return false;
    }

    if (tss_descriptor_base(descriptor) != (uintptr_t)&kernel_tss ||
        tss_descriptor_limit(descriptor) != sizeof(kernel_tss) - 1U ||
        descriptor->access != UINT8_C(0x89) ||
        (descriptor->limit_high_flags & UINT8_C(0xf0)) != 0 || descriptor->reserved != 0) {
        return false;
    }

    return kernel_tss_is_valid();
}

/*
 * Read visible GDTR and TR state after activation and confirm LTR's in-memory
 * busy transition. Hidden descriptor-cache fields require later behavioral
 * evidence and are not exposed by these readbacks.
 */
static bool live_descriptor_state_is_valid(void) {
    struct table_pointer observed_gdtr = {0};
    uint16_t observed_tr;

    read_gdtr(&observed_gdtr);
    observed_tr = read_tr();

    return observed_gdtr.base == gdt_operand.base && observed_gdtr.limit == gdt_operand.limit &&
           observed_tr == GDT_TSS_SELECTOR && gdt.tss_descriptor.access == UINT8_C(0x8b);
}

/*
 * Perform the one-way dormant-to-live transition. Reject reuse before touching
 * the GDT and publish READY only after the visible CPU state matches.
 */
void descriptors_init(void) {
    if (descriptor_state != DESCRIPTORS_UNINITIALIZED) {
        kernel_panic(KERNEL_PANIC_DESCRIPTORS_REINITIALIZED);
    }

    prepare_gdt();

    if (!prepared_state_is_valid()) {
        kernel_panic(KERNEL_PANIC_DESCRIPTORS_PREFLIGHT);
    }

    descriptor_state = DESCRIPTORS_INSTALLING;
    load_descriptor_state(&gdt_operand);

    if (!live_descriptor_state_is_valid()) {
        kernel_panic(KERNEL_PANIC_DESCRIPTORS_READBACK);
    }

    descriptor_state = DESCRIPTORS_READY;
}
