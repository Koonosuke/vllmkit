#!/usr/bin/env bash
# vLLM Server を起動する (docker compose up -d)。
#
#   ./start.sh            起動して /health が OK になるまで待つ
#   ./start.sh --no-wait  起動のみ
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

WAIT=1
[[ "${1:-}" == "--no-wait" ]] && WAIT=0

load_env
check_container_ownership

for d in "$HF_CACHE_DIR" "$VLLM_CACHE_DIR"; do
  [[ -d "$(abs_path "$d")" ]] || die "Cache dir がありません: $d  (先に ./setup.sh を実行)"
done

info "起動: ${VLLM_MODEL} (image: ${VLLM_IMAGE})"
compose up -d
compose ps

if [[ "$WAIT" -eq 1 ]]; then
  info "/health を待機中 (最大 ${START_TIMEOUT}s。初回は Model download のため時間がかかります)"
  info "中断しても Server は起動を続けます。進捗: ./logs.sh"
  start=$SECONDS
  until api_get /health >/dev/null 2>&1; do
    state="$(docker container inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo missing)"
    if [[ "$state" != "running" && "$state" != "restarting" ]]; then
      err "Container が停止しました (state=${state})。直近のログ:"
      compose logs --tail 40 vllm >&2 || true
      exit 1
    fi
    if (( SECONDS - start > START_TIMEOUT )); then
      warn "${START_TIMEOUT}s 以内に ready になりませんでした。./logs.sh で確認してください。"
      break
    fi
    printf '.'
    sleep 5
  done
  echo
  api_get /health >/dev/null 2>&1 && ok "vLLM Server is ready ($(( SECONDS - start ))s)"
fi

AUTH="$(auth_hint)"
cat <<EOF

------------------------------------------------------------
 API URL     : ${API_BASE}/v1   (このHostの localhost のみ)
 Model       : ${SERVED_MODEL_NAME:-$VLLM_MODEL}
 状態確認    : ./status.sh
 ログ        : ./logs.sh
 停止        : ./stop.sh

 curl ${API_BASE}/health
 curl${AUTH} ${API_BASE}/v1/models
 curl${AUTH} ${API_BASE}/v1/chat/completions \\
   -H "Content-Type: application/json" \\
   -d '{"model":"${SERVED_MODEL_NAME:-$VLLM_MODEL}","messages":[{"role":"user","content":"Hello"}],"max_tokens":64}'
------------------------------------------------------------
EOF
