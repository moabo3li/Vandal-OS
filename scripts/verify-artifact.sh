#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$project_root"

elf_path="${1:-}"
iso_path="${2:-}"
if [[ -z "$elf_path" || -z "$iso_path" ]]; then
  printf 'usage: %s ELF_PATH ISO_PATH\n' "$0" >&2
  exit 2
fi
if [[ ! -r "$elf_path" || ! -r "$iso_path" ]]; then
  printf 'error: ELF and ISO artifacts must both be readable\n' >&2
  exit 1
fi

for tool in llvm-readelf llvm-nm llvm-objdump xorriso; do
  if ! command -v "$tool" >/dev/null; then
    printf 'error: %s is required for artifact verification\n' "$tool" >&2
    exit 1
  fi
done

elf_header="$(llvm-readelf -h "$elf_path")"
program_headers="$(llvm-readelf -l "$elf_path")"
section_headers="$(llvm-readelf -S "$elf_path")"
relocations="$(llvm-readelf -r "$elf_path")"

entry="$(awk '/Entry point address:/ { print tolower($4) }' <<<"$elf_header")"
kernel_main="$(llvm-nm -n "$elf_path" | awk '$3 == "kernel_main" { print "0x" tolower($1) }')"
if [[ -z "$kernel_main" || "$entry" != "$kernel_main" ]]; then
  printf 'artifact: FAIL: ELF entry %s does not equal kernel_main %s\n' \
    "${entry:-missing}" "${kernel_main:-missing}" >&2
  exit 1
fi

if ! awk '
  $1 == "LOAD" {
    count++
    flags = ""
    for (i = 7; i < NF; i++) flags = flags $i
    if (flags ~ /W/ && flags ~ /E/) writable_executable = 1
  }
  END { exit !(count == 4 && !writable_executable) }
' <<<"$program_headers"; then
  printf 'artifact: FAIL: expected four LOAD segments and no writable/executable segment\n' >&2
  exit 1
fi

if ! grep -Eq '[[:space:]]\.bss[[:space:]]+NOBITS' <<<"$section_headers"; then
  printf 'artifact: FAIL: .bss is not a NOBITS section\n' >&2
  exit 1
fi
if ! grep -q 'There are no relocations in this file.' <<<"$relocations"; then
  printf 'artifact: FAIL: unexpected relocations remain in the kernel\n' >&2
  exit 1
fi
if [[ -n "$(llvm-nm -u "$elf_path")" ]]; then
  printf 'artifact: FAIL: undefined symbols remain in the kernel\n' >&2
  llvm-nm -u "$elf_path" >&2
  exit 1
fi
if ! llvm-nm "$elf_path" | awk '$3 == "limine_requests_start" { start = 1 }
  $3 == "limine_base_revision" { revision = 1 }
  $3 == "limine_requests_end" { end = 1 }
  END { exit !(start && revision && end) }'; then
  printf 'artifact: FAIL: required Limine request markers are missing\n' >&2
  exit 1
fi
if llvm-objdump -d "$elf_path" |
  grep -Eiq '\b(xmm|ymm|zmm|mm[0-7]|st\([0-7]\)|fld|fst|fadd|fsub|fmul|fdiv)\b'; then
  printf 'artifact: FAIL: FP, MMX, or SIMD instructions appear in executable code\n' >&2
  exit 1
fi

extract_dir="$(mktemp -d /tmp/vandal-artifact-check.XXXXXX)"
trap 'rm -rf -- "$extract_dir"' EXIT
xorriso -osirrox on -indev "$iso_path" -extract /boot/kernel.elf \
  "$extract_dir/kernel.elf" >/dev/null 2>&1
if ! cmp -s "$elf_path" "$extract_dir/kernel.elf"; then
  printf 'artifact: FAIL: the ISO does not contain the inspected kernel ELF\n' >&2
  exit 1
fi

printf 'artifact: PASS (entry %s, four W^X LOAD segments, exact ISO payload)\n' "$entry"
