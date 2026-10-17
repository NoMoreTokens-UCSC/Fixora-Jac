#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
compiler="${FIXORA_JAC_BINARY:-}"
if [[ -z "$compiler" ]] && command -v jac >/dev/null 2>&1; then
  compiler="$(command -v jac)"
fi
if [[ -z "$compiler" ]]; then
  compiler="$project_dir/../../Jac-Technology-Knowledge/.tools/jac/0.34.13/jac"
fi
if [[ ! -x "$compiler" ]]; then
  printf 'Jac 0.34.13 was not found. Install it in WSL or set FIXORA_JAC_BINARY to its Linux path.\n' >&2
  exit 1
fi
exec "$compiler" "$@"
