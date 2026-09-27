#!/usr/bin/env bash
# vLLM Server のログを表示する (Ctrl+C で終了。Server は止まらない)。
#
#   ./logs.sh            直近200行 + 追従
#   ./logs.sh --tail 50  docker compose logs の引数をそのまま渡せる
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

load_env

if [[ $# -eq 0 ]]; then
  set -- --tail 200
fi
compose logs -f "$@" vllm
