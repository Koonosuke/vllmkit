#!/usr/bin/env bash
# vLLM Server を停止する。Container / Model cache / vLLM cache は残す。
# 再開は ./start.sh (Model の再 download は不要)。
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

load_env
check_container_ownership

info "停止: project=${COMPOSE_PROJECT_NAME}"
compose stop --timeout 30
compose ps
ok "停止しました (cache は保持されています)。Container ごと削除する場合: ./clean.sh"
