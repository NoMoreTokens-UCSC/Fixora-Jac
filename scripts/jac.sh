#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
expected_version="$(tr -d '\r\n' < "$project_dir/.jac-version")"
compiler="${FIXORA_JAC_BINARY:-}"
if [[ -z "$compiler" ]] && command -v jac >/dev/null 2>&1; then
  compiler="$(command -v jac)"
fi
if [[ -z "$compiler" && -x "$HOME/.local/bin/jac" ]]; then
  compiler="$HOME/.local/bin/jac"
fi
if [[ -z "$compiler" || ! -x "$compiler" ]]; then
  printf 'Jac %s was not found. Install it in Linux/WSL or set FIXORA_JAC_BINARY to its Linux path.\n' "$expected_version" >&2
  exit 1
fi
actual_version="$("$compiler" --version)"
if [[ "$actual_version" != "jac $expected_version "* && "$actual_version" != "jac $expected_version" ]]; then
  printf 'Expected Jac %s from .jac-version, got: %s\n' "$expected_version" "$actual_version" >&2
  exit 1
fi
exec "$compiler" "$@"
