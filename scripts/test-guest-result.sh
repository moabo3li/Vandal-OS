#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$project_root"

mode="${1:-}"
image_path="${2:-}"
expected_status="${3:-}"
serial_backend="${4:-}"
log_path="${5:-}"

if [[ -z "$mode" || -z "$image_path" || -z "$expected_status" || -z "$serial_backend" ||
      -z "$log_path" ]]; then
  printf 'usage: %s NAME ISO_PATH EXPECTED_STATUS SERIAL_BACKEND LOG_PATH\n' "$0" >&2
  exit 2
fi

if [[ ! "$expected_status" =~ ^(0|[1-9][0-9]{0,2})$ ]]; then
  printf 'error: expected status must be an integer from 0 through 255\n' >&2
  exit 2
fi
expected_status_value=$((10#$expected_status))
if ((expected_status_value > 255)); then
  printf 'error: expected status must be an integer from 0 through 255\n' >&2
  exit 2
fi

if [[ ! -r "$image_path" ]]; then
  printf '%s: kernel image is not readable: %s\n' "$mode" "$image_path" >&2
  exit 1
fi

qemu="${QEMU:-qemu-system-x86_64}"
machine="${VANDAL_QEMU_MACHINE:-pc-q35-10.1}"
accelerator="${VANDAL_QEMU_ACCEL:-tcg}"

if ! command -v "$qemu" >/dev/null; then
  printf 'error: %s is required to run %s\n' "$qemu" "$mode" >&2
  exit 1
fi
if ! command -v timeout >/dev/null; then
  printf 'error: GNU timeout is required to run %s\n' "$mode" >&2
  exit 1
fi

mkdir -p -- "$(dirname -- "$log_path")"

qemu_flags=(
  -machine "$machine",accel="$accelerator"
  -m 128M
  -smp 1
  -cdrom "$image_path"
  -boot d
  -display none
  -serial "$serial_backend"
  -monitor none
  -no-reboot
  -device isa-debug-exit,iobase=0x501,iosize=0x02
)

set +e
timeout --foreground 5s "$qemu" "${qemu_flags[@]}" >"$log_path" 2>&1
observed_status=$?
set -e

if [[ "$observed_status" -eq "$expected_status_value" ]]; then
  if [[ -s "$log_path" ]]; then
    sed -n '1,120p' "$log_path"
  fi
  printf '%s: PASS (status %s, log %s)\n' "$mode" "$observed_status" "$log_path"
  exit 0
fi

if [[ -s "$log_path" ]]; then
  sed -n '1,120p' "$log_path" >&2
fi
if [[ "$observed_status" -eq 124 ]]; then
  printf '%s: FAIL: guest produced no accepted result before timeout (log %s)\n' \
    "$mode" "$log_path" >&2
elif [[ "$observed_status" -ge 128 ]]; then
  printf '%s: FAIL: QEMU terminated by signal %s (log %s)\n' \
    "$mode" "$((observed_status - 128))" "$log_path" >&2
else
  printf '%s: FAIL: expected status %s, observed %s (log %s)\n' \
    "$mode" "$expected_status" "$observed_status" "$log_path" >&2
fi
exit 1
