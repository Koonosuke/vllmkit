#!/usr/bin/env bash
# 完全削除: Container / Network に加えて、このキットの cache (Model を含む) を削除する。
# 誤操作防止のため、確認入力が必要。setup.sh が作った目印ファイルのある dir 以外は削除しない。
#
#   ./clean-all.sh              cache を削除 (Image は残す)
#   ./clean-all.sh --rmi        さらに VLLM_IMAGE も削除 (他の Container が使用中なら削除されない)
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

RMI=0
[[ "${1:-}" == "--rmi" ]] && RMI=1

load_env
check_container_ownership

targets=()
for d in "$HF_CACHE_DIR" "$VLLM_CACHE_DIR"; do
  p="$(abs_path "$d")"
  [[ -d "$p" ]] || continue
  p="$(cd "$p" && pwd -P)"
  case "$p" in
    /|/home|/root|/tmp|/var|/etc|/usr|/opt|"$HOME"|"$HOME/.cache"|"$HOME/.cache/huggingface")
      die "危険なパスのため削除を拒否しました: $p" ;;
  esac
  if [[ ! -f "${p}/${CACHE_MARKER}" ]]; then
    warn "目印 (${CACHE_MARKER}) がないため対象外: $p"
    warn "  (他のツールと共有している cache の可能性があります。必要なら手動で削除してください)"
    continue
  fi
  targets+=("$p")
done

echo "以下を削除します:"
echo "  - Compose project '${COMPOSE_PROJECT_NAME}' の Container / Network"
for t in "${targets[@]}"; do echo "  - ${t}  ($(du -sh "$t" 2>/dev/null | cut -f1))"; done
[[ "$RMI" -eq 1 ]] && echo "  - Image ${VLLM_IMAGE}"
echo
read -r -p "本当に削除する場合は DELETE と入力してください: " ans
[[ "$ans" == "DELETE" ]] || { info "中止しました。"; exit 0; }

compose down --remove-orphans --timeout 30

for t in "${targets[@]}"; do
  info "削除: $t"
  # Container が root で書いたファイルがあるため、Container 内で削除する (対象 dir のみ mount)
  docker run --rm --entrypoint /bin/sh -v "${t}:/target" "$VLLM_IMAGE" \
    -c 'find /target -mindepth 1 -delete' \
    || die "削除に失敗しました: $t"
  rmdir "$t" 2>/dev/null || true
done

if [[ "$RMI" -eq 1 ]]; then
  docker image rm "$VLLM_IMAGE" || warn "Image を削除できませんでした (他の Container が使用中の可能性)。"
fi

ok "完全削除が完了しました。再構築: ./setup.sh && ./start.sh"
