#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

QEMU=qemu-system-riscv32

CC=clang
CFLAGS=(
  -std=c11
  -O2
  -g3
  -Wall
  -Wextra
  --target=riscv32-unknown-elf
  -fuse-ld=lld
  -fno-stack-protector
  -ffreestanding
  -nostdlib
)

# Build again when an input is newer or an output is missing.
needs_build=false
if [[ ! -f kernel.elf || ! -f kernel.map ]]; then
  needs_build=true
else
  for input in kernel.c kernel.ld "${BASH_SOURCE[0]}"; do
    if [[ "$input" -nt kernel.elf ]]; then
      needs_build=true
      break
    fi
  done
fi

if [[ "$needs_build" == true ]]; then
  printf '   Compiling Vandal-OS\n'
  "$CC" "${CFLAGS[@]}" -Wl,-Tkernel.ld -Wl,-Map=kernel.map \
    -o kernel.elf kernel.c
  printf '    Finished kernel.elf\n'
else
  printf '    Finished kernel.elf (up to date)\n'
fi

printf '     Running kernel.elf\n'
exec "$QEMU" -machine virt -bios default -nographic -serial mon:stdio \
  --no-reboot -kernel kernel.elf "$@"
