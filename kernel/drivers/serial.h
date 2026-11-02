#ifndef VANDAL_DRIVERS_SERIAL_H
#define VANDAL_DRIVERS_SERIAL_H

#include <stdbool.h>
#include <stdint.h>

/*
 * Configure COM1 for 115200-baud, 8N1 polling output.
 * Call this during early kernel initialization before serial_puts. It may be
 * called again to reinitialize COM1. Return false if COM1 appears absent.
 */
bool serial_init(void);

/*
 * Write one byte using polling. Return false if initialization has not
 * succeeded or transmission reaches its poll limit.
 */
bool serial_putc(uint8_t byte);

/*
 * Write a null-terminated string using polling. Return false if text is NULL,
 * initialization has not succeeded, or transmission reaches its poll limit.
 */
bool serial_puts(const char *text);

/*
 * Write a fixed-width "0x" plus sixteen hexadecimal digits using polling.
 * Return false under the same conditions as serial_putc.
 */
bool serial_puthex(uint64_t value);

#endif
