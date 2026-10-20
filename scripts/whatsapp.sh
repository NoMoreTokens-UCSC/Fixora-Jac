#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
channel_python="${FIXORA_WHATSAPP_PYTHON:-$HOME/.cache/fixora-whatsapp/python/bin/python}"
uv_bin="$(command -v uv || true)"
if [[ -z "$uv_bin" && -x "$HOME/.local/bin/uv" ]]; then uv_bin="$HOME/.local/bin/uv"; fi

case "${1:-help}" in
  setup)
    if [[ ! -x "$channel_python" ]]; then
      if [[ -n "$uv_bin" ]]; then
        "$uv_bin" venv "$(dirname "$(dirname "$channel_python")")"
      else
        python3 -m venv "$(dirname "$(dirname "$channel_python")")"
      fi
    fi
    if [[ -n "$uv_bin" ]]; then
      "$uv_bin" pip install --python "$channel_python" -r whatsapp/requirements-dev.txt
    else
      "$channel_python" -m pip install -r whatsapp/requirements-dev.txt
    fi
    ;;
  public|owner|worker|test|verify)
    if [[ ! -x "$channel_python" ]]; then printf 'Run bash scripts/whatsapp.sh setup first.\n' >&2; exit 1; fi
    case "$1" in
      public) exec "$channel_python" -m uvicorn whatsapp.app:public_app --host 127.0.0.1 --port 8010 ;;
      owner) exec "$channel_python" -m uvicorn whatsapp.app:owner_app --host 127.0.0.1 --port 8011 ;;
      worker) exec "$channel_python" -m whatsapp.worker ;;
      verify) exec "$channel_python" scripts/verify-whatsapp.py ;;
      test)
        "$channel_python" -m pytest tests/test_whatsapp.py tests/test_enquiries.py -q
        PYTEST_XDIST_AUTO_NUM_WORKERS=1 bash scripts/jac.sh test tests/platform_tests.jac tests/specialist_tests.jac tests/owner_tests.jac -v
        bash scripts/test-ui.sh
        ;;
    esac
    ;;
  *) printf 'Usage: bash scripts/whatsapp.sh {setup|public|owner|worker|test|verify}\n' ;;
esac
