#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$project_root"

debug=false
if [[ "${1:-}" == "--debug" ]]; then
  debug=true
  shift
fi

image_path="${1:-}"
if [[ -z "$image_path" ]]; then
  printf 'usage: %s [--debug] ISO_PATH [QEMU_ARGUMENT ...]\n' "$0" >&2
  exit 2
fi
shift

qemu="${QEMU:-qemu-system-x86_64}"
machine="${VANDAL_QEMU_MACHINE:-pc-q35-10.1}"
accelerator="${VANDAL_QEMU_ACCEL:-tcg}"
serial="${VANDAL_QEMU_SERIAL:-stdio}"

if [[ ! -r "$image_path" ]]; then
  printf 'error: ISO image is not readable: %s\n' "$image_path" >&2
  exit 1
fi

if ! command -v "$qemu" >/dev/null; then
  printf 'error: %s is required to run Vandal-OS\n' "$qemu" >&2
  exit 1
fi

qemu_flags=(
  -machine "$machine",accel="$accelerator"
  -m 128M
  -smp 1
  -cdrom "$image_path"
  -boot d
  -display none
  -serial "$serial"
  -monitor none
  -no-reboot
  -no-shutdown
)

if [[ "$debug" == true ]]; then
  qemu_flags+=( -S -gdb tcp::1234 )
  printf 'QEMU paused; attach GDB to localhost:1234\n'
fi

exec "$qemu" "${qemu_flags[@]}" "$@"
