# shellcheck shell=bash
# vllmkit 共通関数。各 script から source して使う。
# Host の設定を変更する処理はここに書かないこと。

set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${KIT_DIR}/.env"
CACHE_MARKER=".vllmkit-cache"

if [[ -t 1 ]]; then
  C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YEL=$'\e[33m'; C_BLU=$'\e[34m'; C_RST=$'\e[0m'
else
  C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_RST=""
fi

info() { printf '%s[INFO]%s %s\n' "$C_BLU" "$C_RST" "$*"; }
ok()   { printf '%s[ OK ]%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_YEL" "$C_RST" "$*" >&2; }
err()  { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RST" "$*" >&2; }
die()  { err "$*"; exit 1; }

# .env を読み込み、未設定の項目に既定値を入れる
load_env() {
  [[ -f "$ENV_FILE" ]] || die ".env がありません。先に: cp .env.example .env"
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a

  COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-vllmkit}"
  CONTAINER_NAME="${CONTAINER_NAME:-vllmkit-vllm}"
  HOST_PORT="${HOST_PORT:-8000}"
  HF_CACHE_DIR="${HF_CACHE_DIR:-./cache/huggingface}"
  VLLM_CACHE_DIR="${VLLM_CACHE_DIR:-./cache/vllm}"
  VLLM_API_KEY="${VLLM_API_KEY:-}"
  START_TIMEOUT="${START_TIMEOUT:-900}"
  API_BASE="http://127.0.0.1:${HOST_PORT}"
}

# 相対パスをリポジトリ基準の絶対パスへ
abs_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *)  printf '%s\n' "${KIT_DIR}/${1#./}" ;;
  esac
}

# 常にこのリポジトリの compose project だけを操作する
compose() {
  docker compose --project-directory "$KIT_DIR" -f "${KIT_DIR}/docker-compose.yml" \
    --env-file "$ENV_FILE" -p "$COMPOSE_PROJECT_NAME" "$@"
}

# 同名 Container が「別の project / 別のディレクトリ」のものなら中止する
# (他ユーザーの Container を誤って操作・置換しないため)
check_container_ownership() {
  local proj wdir
  if ! docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    return 0
  fi
  proj="$(docker container inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$CONTAINER_NAME")"
  wdir="$(docker container inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$CONTAINER_NAME")"
  if [[ "$proj" != "$COMPOSE_PROJECT_NAME" || "$wdir" != "$KIT_DIR" ]]; then
    err "Container名 '${CONTAINER_NAME}' は別の環境が使用中です。"
    err "  project=${proj:-<none>}  working_dir=${wdir:-<none>}"
    die ".env の CONTAINER_NAME / COMPOSE_PROJECT_NAME / HOST_PORT を自分固有の値に変更してください。"
  fi
}

# API 呼び出し (VLLM_API_KEY があれば付与)
api_get() {
  local path="$1"
  local -a hdr=()
  [[ -n "$VLLM_API_KEY" ]] && hdr=(-H "Authorization: Bearer ${VLLM_API_KEY}")
  curl -fsS --max-time 5 "${hdr[@]}" "${API_BASE}${path}"
}

auth_hint() {
  if [[ -n "$VLLM_API_KEY" ]]; then
    printf '%s' ' -H "Authorization: Bearer $VLLM_API_KEY"'
  fi
}
