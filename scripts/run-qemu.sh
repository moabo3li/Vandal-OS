#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$project_root"

debug=false
if [[ "${1:-}" == "--debug" ]]; then
  debug=true
  shift
fi

make all

if ! command -v qemu-system-x86_64 >/dev/null; then
  printf 'error: qemu-system-x86_64 is required to run Vandal-OS\n' >&2
  exit 1
fi

qemu_flags=(
  -machine q35
  -m 128M
  -smp 1
  -cdrom build/vandal-os.iso
  -boot d
  -display none
  -serial stdio
  -monitor none
  -no-reboot
  -no-shutdown
)

if [[ "$debug" == true ]]; then
  qemu_flags+=( -S -gdb tcp::1234 )
  printf 'QEMU paused; attach GDB to localhost:1234\n'
fi

exec qemu-system-x86_64 "${qemu_flags[@]}" "$@"
