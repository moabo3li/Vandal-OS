#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$project_root"

mode="${1:-}"
case "$mode" in
  direct-result)
    build_dir="build/test-guest-result"
    expected_status=33
    build_args=(BUILD_DIR="$build_dir" EXTRA_CFLAGS=-DVANDAL_TEST_GUEST_RESULT)
    serial_backend=none
    ;;
  serial-absent)
    build_dir="build/vandal-os"
    expected_status=35
    build_args=(BUILD_DIR="$build_dir")
    serial_backend=none
    ;;
  expected-panic)
    build_dir="build/test-panic"
    expected_status=37
    build_args=(BUILD_DIR="$build_dir" EXTRA_CFLAGS=-DVANDAL_TEST_PANIC)
    serial_backend=stdio
    ;;
  expected-panic-serial-absent)
    build_dir="build/test-panic"
    expected_status=37
    build_args=(BUILD_DIR="$build_dir" EXTRA_CFLAGS=-DVANDAL_TEST_PANIC)
    serial_backend=none
    ;;
  bad-revision)
    build_dir="build/test-bad-revision"
    expected_status=39
    build_args=(BUILD_DIR="$build_dir" EXTRA_CFLAGS=-DVANDAL_TEST_BAD_LIMINE_REVISION)
    serial_backend=none
    ;;
  bad-data)
    build_dir="build/test-bad-data"
    expected_status=41
    build_args=(BUILD_DIR="$build_dir" EXTRA_CFLAGS=-DVANDAL_TEST_BAD_DATA)
    serial_backend=none
    ;;
  bad-bss)
    build_dir="build/test-bad-bss"
    expected_status=43
    build_args=(BUILD_DIR="$build_dir" EXTRA_CFLAGS=-DVANDAL_TEST_BAD_BSS)
    serial_backend=none
    ;;
  *)
    printf 'usage: %s {direct-result|serial-absent|expected-panic|expected-panic-serial-absent|bad-revision|bad-data|bad-bss}\n' "$0" >&2
    exit 2
    ;;
esac

make "${build_args[@]}" all

qemu_flags=(
  -machine q35
  -m 128M
  -smp 1
  -cdrom "$build_dir/vandal-os.iso"
  -boot d
  -display none
  -serial "$serial_backend"
  -monitor none
  -no-reboot
  -device isa-debug-exit,iobase=0x501,iosize=0x02
)

set +e
timeout --foreground 5s qemu-system-x86_64 "${qemu_flags[@]}"
observed_status=$?
set -e

if [[ "$observed_status" -eq "$expected_status" ]]; then
  printf '%s: observed expected guest result (status %s)\n' "$mode" "$observed_status"
  exit 0
fi

if [[ "$observed_status" -eq 124 ]]; then
  printf '%s: guest produced no accepted result before timeout\n' "$mode" >&2
elif [[ "$observed_status" -ge 128 ]]; then
  printf '%s: QEMU terminated by signal %s\n' "$mode" "$((observed_status - 128))" >&2
else
  printf '%s: expected status %s, observed %s\n' \
    "$mode" "$expected_status" "$observed_status" >&2
fi
exit 1
