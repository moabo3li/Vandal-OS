#include <stddef.h>
#include <stdint.h>

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
 * A 64-bit TSS system descriptor occupies two consecutive GDT slots. Its
 * fields will be populated when the kernel-owned TSS is added.
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
 * This table is deliberately dormant. Merely emitting these bytes does not
 * change the CPU's cached descriptor state. The two TSS slots remain zero
 * until a later step encodes the 16-byte system descriptor, and no code in
 * this translation unit changes GDTR or TR.
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
