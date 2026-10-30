#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$project_root"

kernel_elf="${1:-}"
image_path="${2:-}"
gdb_command_file="${3:-}"

if [[ -z "$kernel_elf" || -z "$image_path" || -z "$gdb_command_file" ]]; then
  printf 'usage: %s KERNEL_ELF ISO_PATH GDB_COMMAND_FILE\n' "$0" >&2
  exit 2
fi

gdb="${GDB:-gdb}"
build_dir="$(dirname -- "$kernel_elf")"
pid_file="$build_dir/qemu-gdb.pid"
serial_log="$build_dir/qemu-gdb-serial.log"

cleanup() {
  if [[ -r "$pid_file" ]]; then
    qemu_pid="$(<"$pid_file")"
    if [[ "$qemu_pid" =~ ^[0-9]+$ ]]; then
      kill "$qemu_pid" 2>/dev/null || true
    fi
    rm -f -- "$pid_file"
  fi
}

trap cleanup EXIT HUP INT TERM
rm -f -- "$pid_file"

VANDAL_QEMU_SERIAL="file:$serial_log" \
  ./scripts/run-qemu.sh --debug "$image_path" -daemonize -pidfile "$pid_file"

if [[ ! -r "$pid_file" ]]; then
  printf 'error: QEMU did not create its debug-session PID file\n' >&2
  exit 1
fi

"$gdb" -q "$kernel_elf" -ex "target remote localhost:1234" -x "$gdb_command_file"
