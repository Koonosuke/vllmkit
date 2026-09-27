#!/usr/bin/env bash
# Host 環境の確認と、vLLM 実行の準備を行う。
# Host の Driver / Docker daemon / /etc 配下は一切変更しない (確認のみ)。
#
#   ./setup.sh             すべて確認し、Image を pull
#   ./setup.sh --no-pull   Image の pull を省略
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

DO_PULL=1
[[ "${1:-}" == "--no-pull" ]] && DO_PULL=0

load_env
FAILED=0
fail() { err "$1"; shift; for l in "$@"; do printf '       %s\n' "$l" >&2; done; FAILED=1; }

echo "=== vllmkit setup (${KIT_DIR}) ==="

# 1. Architecture
arch="$(uname -m)"
if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
  ok "Architecture: ${arch}"
else
  warn "Architecture: ${arch} (GX10 は aarch64 の想定。Image の対応 arch を確認してください)"
fi

# 2. NVIDIA Driver / GPU
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  drv="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1)"
  gpu="$(nvidia-smi --query-gpu=name --format=csv,noheader | paste -sd ',' -)"
  cuda="$(nvidia-smi | grep -oE 'CUDA Version: *[0-9.]+' | head -n1 | awk '{print $3}')"
  ok "GPU: ${gpu} / Driver: ${drv} / CUDA (driver): ${cuda:-unknown}"
else
  fail "nvidia-smi が実行できません。" \
    "対応: サーバー管理者に NVIDIA Driver の状態確認を依頼してください。" \
    "      (共有サーバーのため、このキットは Driver をインストール/変更しません)"
fi

# 3. Docker
if command -v docker >/dev/null 2>&1; then
  ok "Docker: $(docker --version)"
  if ! docker info >/dev/null 2>&1; then
    fail "Docker daemon に接続できません (権限不足または停止中)。" \
      "対応: 'docker' group への追加を管理者に依頼してください。" \
      "      確認: id -nG | grep -w docker"
  fi
else
  fail "docker コマンドがありません。" "対応: 管理者に Docker Engine の導入を依頼してください。"
fi

# 4. Docker Compose v2
if docker compose version >/dev/null 2>&1; then
  ok "Docker Compose: $(docker compose version --short 2>/dev/null || docker compose version)"
else
  fail "docker compose (v2 plugin) がありません。" \
    "対応: 管理者に docker-compose-plugin の導入を依頼してください。"
fi

# 5. NVIDIA Container Toolkit
if command -v nvidia-ctk >/dev/null 2>&1; then
  ok "NVIDIA Container Toolkit: $(nvidia-ctk --version 2>/dev/null | head -n1)"
else
  warn "nvidia-ctk が PATH にありません (下の GPU Container テストで最終判定します)。"
fi
if docker info >/dev/null 2>&1; then
  if docker info --format '{{json .Runtimes}}' 2>/dev/null | grep nvidia >/dev/null; then
    ok "Docker runtime に nvidia が登録されています。"
  else
    info "Docker runtime 一覧に nvidia はありません (CDI 構成の場合は問題ありません)。"
  fi
fi

[[ "$FAILED" -eq 0 ]] || die "前提条件が不足しています。上記の対応後に再実行してください。"

# 6. Docker Container から GPU が見えるか
info "GPU Container テスト: docker run --rm --gpus all ${CUDA_TEST_IMAGE} nvidia-smi"
if docker run --rm --gpus all "${CUDA_TEST_IMAGE}" nvidia-smi -L; then
  ok "Docker Container から GPU を利用できます。"
else
  err "Container から GPU を利用できませんでした。"
  cat >&2 <<EOF
       考えられる原因:
         - NVIDIA Container Toolkit が未導入 / Docker に未設定  → 管理者に依頼
         - CUDA_TEST_IMAGE (${CUDA_TEST_IMAGE}) が arm64 に非対応、または pull 不可
             → .env の CUDA_TEST_IMAGE を変更して再実行
               例: nvidia/cuda:13.0.0-base-ubuntu24.04
       ※ このキットは /etc/docker/daemon.json 等を変更しません。
EOF
  exit 1
fi

# 7. Cache directory
for d in "$HF_CACHE_DIR" "$VLLM_CACHE_DIR"; do
  p="$(abs_path "$d")"
  mkdir -p "$p"
  # clean-all.sh が「このキットが作った dir」だけを削除できるよう目印を置く
  [[ -f "${p}/${CACHE_MARKER}" ]] || echo "created by vllmkit (${KIT_DIR})" > "${p}/${CACHE_MARKER}"
  ok "Cache dir: ${p}"
done

# 8. Memory (Unified Memory のため空き容量を表示)
if command -v free >/dev/null 2>&1; then
  info "Host memory (GX10 は GPU と共有):"
  free -h | sed 's/^/       /'
fi

# 9. vLLM Image
compose config -q || die "docker-compose.yml / .env の設定にエラーがあります。"
if [[ "$DO_PULL" -eq 1 ]]; then
  info "vLLM Image を pull します: ${VLLM_IMAGE} (初回は数GB〜十数GB)"
  compose pull
  ok "Image pull 完了"
else
  info "Image pull をスキップしました (--no-pull)"
fi

if [[ "$VLLM_IMAGE" == *":latest" || "$VLLM_IMAGE" != *":"* ]]; then
  warn "VLLM_IMAGE が latest です。共通環境では tag を固定してください。"
fi
if [[ -z "$VLLM_API_KEY" ]]; then
  warn "VLLM_API_KEY が未設定です。同じサーバーの他ユーザーも API を呼べます。"
fi

echo
ok "setup 完了。次: ./start.sh"
