#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
bash scripts/jac.sh build --client web
bun_bin="$(find "$HOME/.cache/jac/rt" -path '*/runtimelib/client/_bun/bun' -type f -executable -print -quit)"
if [[ -z "$bun_bin" ]]; then printf 'Bundled Bun runtime not found. Run Jac once first.\n' >&2; exit 1; fi
cp tests/gateway.test.mjs .jac/client/gateway.test.mjs
cd .jac/client
"$bun_bin" test gateway.test.mjs
