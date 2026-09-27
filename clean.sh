#!/usr/bin/env bash
# このリポジトリの Container / Network を削除する。
#
# 削除しないもの:
#   - Hugging Face cache / vLLM cache / Model (HF_CACHE_DIR, VLLM_CACHE_DIR)
#   - Docker Image (他ユーザーと共有している可能性があるため)
#   - 他の Compose project の Container / Image / Volume
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

load_env
check_container_ownership

info "削除: project=${COMPOSE_PROJECT_NAME} の Container / Network (cache は残します)"
# -v / --rmi は付けない
compose down --remove-orphans --timeout 30
ok "完了。再構築: ./start.sh"
