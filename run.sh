#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd -- "$project_root"

case "$#" in
  0)
    exec make run
    ;;
  1)
    if [[ "$1" == "--debug" ]]; then
      exec make debug
    fi
    ;;
esac

printf 'usage: %s [--debug]\n' "$0" >&2
exit 2
