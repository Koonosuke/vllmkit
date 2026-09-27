#!/usr/bin/env bash
# vLLM 環境の状態を表示する (読み取りのみ)。
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
set +e

load_env

echo "=== Compose (${COMPOSE_PROJECT_NAME}) ==="
compose ps -a

echo
echo "=== docker ps (${CONTAINER_NAME}) ==="
docker ps -a --filter "name=^/${CONTAINER_NAME}$" \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}'
health="$(docker container inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "$CONTAINER_NAME" 2>/dev/null)"
echo "healthcheck: ${health:-container not found}"

echo
echo "=== nvidia-smi ==="
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi
else
  warn "nvidia-smi not found"
fi

echo
echo "=== Host memory (Unified Memory) ==="
free -h 2>/dev/null

echo
echo "=== vLLM API (${API_BASE}) ==="
if api_get /health >/dev/null 2>&1; then
  ok "/health: OK"
else
  err "/health: 応答なし (起動中 / 停止中の可能性。./logs.sh で確認)"
fi
if models="$(api_get /v1/models 2>&1)"; then
  ok "/v1/models:"
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$models" | python3 -c 'import json,sys; [print("       -", m["id"], "(max_model_len=%s)" % m.get("max_model_len")) for m in json.load(sys.stdin)["data"]]' 2>/dev/null \
      || printf '       %s\n' "$models"
  else
    printf '       %s\n' "$models"
  fi
else
  err "/v1/models: 取得失敗 (${models})"
fi
