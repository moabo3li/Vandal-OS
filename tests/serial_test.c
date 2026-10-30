#include "drivers/serial.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#define COM1_BASE_PORT UINT16_C(0x03f8)
#define SERIAL_REG_THR UINT16_C(0)
#define SERIAL_REG_DLL UINT16_C(0)
#define SERIAL_REG_IER UINT16_C(1)
#define SERIAL_REG_DLM UINT16_C(1)
#define SERIAL_REG_FCR UINT16_C(2)
#define SERIAL_REG_LCR UINT16_C(3)
#define SERIAL_REG_LSR UINT16_C(5)
#define SERIAL_LCR_DLAB (1u << 7)
#define SERIAL_LCR_8N1 UINT8_C(0x03)
#define SERIAL_LSR_THRE (1u << 5)
#define SERIAL_LSR_NO_DEVICE UINT8_C(0xff)
#define SERIAL_POLL_ATTEMPTS UINT32_C(100000)
#define SERIAL_BAUD_DIVISOR_LOW UINT8_C(1)
#define SERIAL_BAUD_DIVISOR_HIGH UINT8_C(0)
#define SERIAL_DISABLED UINT8_C(0)

struct port_write {
    uint16_t port;
    uint8_t value;
};

static uint8_t mock_lcr;
static uint8_t mock_lsr;
static uint32_t lsr_reads;
static uint32_t thr_writes;
static uint8_t transmitted[2];
static struct port_write port_writes[8];
static size_t port_write_count;

void serial_test_outb(uint16_t port, uint8_t value) {
    if (port_write_count < sizeof(port_writes) / sizeof(port_writes[0])) {
        port_writes[port_write_count] = (struct port_write){
            .port = port,
            .value = value,
        };
    }
    port_write_count++;

    if (port == COM1_BASE_PORT + SERIAL_REG_LCR) {
        mock_lcr = value;
        return;
    }

    if (port == COM1_BASE_PORT + SERIAL_REG_THR && (mock_lcr & SERIAL_LCR_DLAB) == 0) {
        if (thr_writes < sizeof(transmitted)) {
            transmitted[thr_writes] = value;
        }
        thr_writes++;
    }
}

uint8_t serial_test_inb(uint16_t port) {
    if (port == COM1_BASE_PORT + SERIAL_REG_LSR) {
        lsr_reads++;
        return mock_lsr;
    }
    return 0;
}

#define CHECK(condition)                                                                           \
    do {                                                                                           \
        if (!(condition)) {                                                                        \
            fprintf(stderr, "FAIL: %s:%d: %s\n", __FILE__, __LINE__, #condition);                  \
            return 1;                                                                              \
        }                                                                                          \
    } while (0)

static int check_initialization_writes(void) {
    static const struct port_write expected[] = {
        {COM1_BASE_PORT + SERIAL_REG_LCR, SERIAL_LCR_8N1},
        {COM1_BASE_PORT + SERIAL_REG_IER, SERIAL_DISABLED},
        {COM1_BASE_PORT + SERIAL_REG_LCR, SERIAL_LCR_DLAB},
        {COM1_BASE_PORT + SERIAL_REG_DLL, SERIAL_BAUD_DIVISOR_LOW},
        {COM1_BASE_PORT + SERIAL_REG_DLM, SERIAL_BAUD_DIVISOR_HIGH},
        {COM1_BASE_PORT + SERIAL_REG_LCR, SERIAL_LCR_8N1},
        {COM1_BASE_PORT + SERIAL_REG_FCR, SERIAL_DISABLED},
    };

    CHECK(port_write_count == sizeof(expected) / sizeof(expected[0]));
    for (size_t index = 0; index < sizeof(expected) / sizeof(expected[0]); index++) {
        CHECK(port_writes[index].port == expected[index].port);
        CHECK(port_writes[index].value == expected[index].value);
    }
    return 0;
}

int main(void) {
    CHECK(!serial_puts("before init"));

    mock_lsr = SERIAL_LSR_NO_DEVICE;
    port_write_count = 0;
    CHECK(!serial_init());
    CHECK(check_initialization_writes() == 0);
    CHECK(!serial_puts("absent"));

    mock_lsr = SERIAL_LSR_THRE;
    port_write_count = 0;
    CHECK(serial_init());
    CHECK(check_initialization_writes() == 0);
    CHECK(!serial_puts(NULL));

    mock_lsr = 0;
    lsr_reads = 0;
    thr_writes = 0;
    CHECK(!serial_puts("X"));
    CHECK(lsr_reads == SERIAL_POLL_ATTEMPTS);
    CHECK(thr_writes == 0);

    mock_lsr = SERIAL_LSR_THRE;
    CHECK(serial_init());
    thr_writes = 0;
    CHECK(serial_puts("OK"));
    CHECK(thr_writes == 2);
    CHECK(transmitted[0] == 'O');
    CHECK(transmitted[1] == 'K');

    puts("serial tests: PASS");
    return 0;
}
