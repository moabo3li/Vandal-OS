#include "serial.h"
#include "arch/x86_64/io.h"
#include <stddef.h>
#include <stdint.h>

/* ISA I/O-port base for the first 16550-compatible serial device. */
#define COM1_BASE_PORT UINT16_C(0x03f8)

/* QEMU's PC-compatible serial device uses a 115200-baud base clock. */
#define SERIAL_BAUD_BASE UINT32_C(115200)
#define SERIAL_BAUD_RATE UINT32_C(115200)
#define SERIAL_BAUD_DIVISOR (SERIAL_BAUD_BASE / SERIAL_BAUD_RATE)
#define SERIAL_DIVISOR_LOW_BYTE ((uint8_t)(SERIAL_BAUD_DIVISOR & UINT16_C(0x00ff)))
#define SERIAL_DIVISOR_HIGH_BYTE ((uint8_t)(SERIAL_BAUD_DIVISOR >> 8))

/* Iteration budget only; this is not a measured time duration. */
#define SERIAL_POLL_ATTEMPTS UINT32_C(100000)

/*
 * Register offsets relative to COM1_BASE_PORT.
 * Read/write direction and DLAB can change the meaning of an offset.
 */
enum serial_register_offset {
    SERIAL_REG_RBR = 0, /* Read, DLAB clear: receiver buffer. */
    SERIAL_REG_THR = 0, /* Write, DLAB clear: transmitter holding register. */
    SERIAL_REG_DLL = 0, /* Read/write, DLAB set: divisor low byte. */

    SERIAL_REG_IER = 1, /* Read/write, DLAB clear: interrupt enable. */
    SERIAL_REG_DLM = 1, /* Read/write, DLAB set: divisor high byte. */

    SERIAL_REG_IIR = 2, /* Read: interrupt identification. */
    SERIAL_REG_FCR = 2, /* Write: FIFO control. */

    SERIAL_REG_LCR = 3, /* Line format and DLAB selection. */
    SERIAL_REG_MCR = 4, /* Modem signals and loopback control. */
    SERIAL_REG_LSR = 5, /* Receive, transmit, and line-error status. */
    SERIAL_REG_MSR = 6, /* Modem input status. */
    SERIAL_REG_SCR = 7, /* General-purpose device-local storage. */
};

/* Line Control Register bit: expose the divisor latch at offsets 0 and 1. */
#define SERIAL_LCR_DLAB (1u << 7)

/* Complete Line Control Register value: 8 data bits, no parity, one stop bit. */
#define SERIAL_LCR_8N1 UINT8_C(0x03)

/* This polling driver does not use UART interrupts or hardware FIFOs yet. */
#define SERIAL_IER_DISABLED UINT8_C(0x00)
#define SERIAL_FCR_DISABLED UINT8_C(0x00)

/* Line Status Register bit: the transmit holding register is empty. */
#define SERIAL_LSR_THRE (1u << 5)

/* An unimplemented ISA I/O port conventionally reads back as all ones. */
#define SERIAL_LSR_NO_DEVICE UINT8_C(0xff)

_Static_assert(SERIAL_BAUD_BASE % SERIAL_BAUD_RATE == 0,
               "the selected baud rate requires an integer divisor");
_Static_assert(SERIAL_BAUD_DIVISOR >= 1 && SERIAL_BAUD_DIVISOR <= UINT16_MAX,
               "the serial divisor must fit the two 8-bit divisor latches");
_Static_assert((SERIAL_LCR_8N1 & SERIAL_LCR_DLAB) == 0,
               "the normal line configuration must leave DLAB clear");

/* Output remains unavailable until serial_init confirms that COM1 responds. */
/* TODO: Use an enum if absent and failed devices need different handling. */
static bool serial_initialized;

/* Keep COM1 address calculation and byte-wide port writes in one place. */
static void serial_write(enum serial_register_offset reg, uint8_t value) {
    uint16_t port = (uint16_t)(COM1_BASE_PORT + (uint16_t)reg);
    outb(port, value);
}

/* Keep COM1 address calculation and byte-wide port reads in one place. */
static uint8_t serial_read(enum serial_register_offset reg) {
    uint16_t port = (uint16_t)(COM1_BASE_PORT + (uint16_t)reg);
    return inb(port);
}

/* Poll for THRE with a bounded attempt budget, then write one byte. */
static bool serial_write_byte(uint8_t byte) {
    uint32_t attempts = 0;

    /* THRE means that writing the THR now will not overwrite pending data. */
    while (attempts < SERIAL_POLL_ATTEMPTS) {
        if ((serial_read(SERIAL_REG_LSR) & SERIAL_LSR_THRE) != 0) {
            serial_write(SERIAL_REG_THR, byte);
            return true;
        }
        attempts++;
    }
    return false;
}

bool serial_init(void) {
    serial_initialized = false;

    /* Clear DLAB first so offset 1 selects the Interrupt Enable Register. */
    serial_write(SERIAL_REG_LCR, SERIAL_LCR_8N1);
    serial_write(SERIAL_REG_IER, SERIAL_IER_DISABLED);

    /* DLAB exposes the two bytes of the baud-rate divisor. */
    serial_write(SERIAL_REG_LCR, SERIAL_LCR_DLAB);
    serial_write(SERIAL_REG_DLL, SERIAL_DIVISOR_LOW_BYTE);
    serial_write(SERIAL_REG_DLM, SERIAL_DIVISOR_HIGH_BYTE);

    /* Select 8N1 and clear DLAB to restore normal register access. */
    serial_write(SERIAL_REG_LCR, SERIAL_LCR_8N1);
    serial_write(SERIAL_REG_FCR, SERIAL_FCR_DISABLED);

    /* Reject the all-ones value returned when the COM1 port is absent. */
    if (serial_read(SERIAL_REG_LSR) == SERIAL_LSR_NO_DEVICE) {
        return false;
    }

    serial_initialized = true;
    return true;
}

bool serial_puts(const char *text) {
    if (!serial_initialized || text == NULL) {
        return false;
    }
    /* Write each character until the terminating NUL or a transmission failure. */
    while (*text != '\0') {
        if (!serial_write_byte(*text)) {
            return false;
        }
        text++;
    }
    return true;
}
