# vllmkit — 共有 GX10 用 vLLM 再構築キット

## 1. このリポジトリの目的

研究室で共有している **ASUS GX10 (NVIDIA GB10)** で、vLLM の OpenAI 互換 API Server を
**`git clone` 後、少ない操作で安全に再構築**するためのキットです。

```bash
git clone <repository> && cd <repository>
cp .env.example .env
./setup.sh
./start.sh
```

- Host の NVIDIA Driver / OS / Docker 設定は**一切変更しません**（確認のみ）。
- vLLM は Docker Compose で管理し、長い `docker run` を手で打つ必要はありません。
- Model cache は Host に残るため、Container を作り直しても再 download は不要です。

## 2. 構成図

```text
 ┌──────────────────────── ASUS GX10 (Host) ────────────────────────┐
 │                                                                  │
 │  client (curl / Python / 将来: Nginx :443)                       │
 │        │                                                         │
 │        ▼                                                         │
 │  127.0.0.1:${HOST_PORT}   ← localhost のみ。LAN からは見えない      │
 │        │                                                         │
 │  ┌─────┼──── Container: vllmkit-vllm (docker compose) ───────┐    │
 │  │     ▼                                                   │    │
 │  │  0.0.0.0:8000  vLLM OpenAI-compatible Server            │    │
 │  │  CUDA Runtime / PyTorch / vLLM                          │    │
 │  │  /root/.cache/huggingface ─────┐                        │    │
 │  │  /root/.cache/vllm ────────┐   │                        │    │
 │  └────────────────────────────┼───┼────────────────────────┘    │
 │                               ▼   ▼   (bind mount)              │
 │  ${VLLM_CACHE_DIR}  ${HF_CACHE_DIR}   ← Model / cache を永続化     │
 │                                                                  │
 │  Ubuntu 24.04 (aarch64) / NVIDIA Driver 580 / Docker /           │
 │  NVIDIA Container Toolkit          ← 管理者の責務。キットは触らない  │
 │  GPU: GB10 + 128GB級 Unified Memory (CPU と GPU で共有)           │
 └──────────────────────────────────────────────────────────────────┘
```

ファイル構成:

```text
vllmkit/
├ README.md            この説明書
├ docker-compose.yml   vLLM Service の定義
├ .env.example         設定のひな形 (cp して .env を作る)
├ .gitignore           .env / cache を commit しない
├ setup.sh             Host の確認、GPU Container テスト、cache dir 作成、image pull
├ start.sh             起動 + /health 待機 + 使い方表示
├ stop.sh              停止 (Container と cache は残す)
├ status.sh            状態確認 (compose / docker ps / nvidia-smi / API)
├ logs.sh              ログ追従
├ clean.sh             Container / Network 削除 (cache・image は残す)
├ clean-all.sh         確認のうえ cache まで完全削除
└ lib/common.sh        共通関数 (.env 読込、compose wrapper、衝突検知)
```

## 3. Host と Container の責務

| 層 | 担当するもの | 管理者 |
|---|---|---|
| Host | Ubuntu, Kernel, **NVIDIA Driver**, Docker Engine, Docker Compose, NVIDIA Container Toolkit | サーバー管理者 |
| Container | CUDA Runtime, PyTorch, vLLM, Model Runtime | このキット (Image tag で固定) |
| Host 上のデータ | Hugging Face cache, vLLM cache | このキット (`.env` で場所を指定) |

CUDA **Runtime** は Container の中、CUDA **Driver** は Host にあります。
Container は NVIDIA Container Toolkit 経由で Host の Driver を借りて GPU を使います。

## 4. 前提環境

| 項目 | 想定値 | 確認コマンド |
|---|---|---|
| Architecture | aarch64 | `uname -m` |
| OS | Ubuntu 24.04 (ARM64) | `cat /etc/os-release` |
| GPU | NVIDIA GB10 | `nvidia-smi` |
| Driver | 580.159.03 (CUDA 13.0) | `nvidia-smi` |
| Docker | Engine + Compose v2 | `docker --version`, `docker compose version` |
| NVIDIA Container Toolkit | 導入済み | `nvidia-ctk --version` |
| 権限 | `docker` group に所属 | `id -nG` |
| Disk | Image 十数GB + Model 分 | `df -h .` |

不足している場合は `setup.sh` が対応方法を表示して終了します。**自分で Driver 等を入れず、管理者に依頼してください。**

## 5. 初回セットアップ

```bash
cp .env.example .env
vi .env          # 複数人で使うなら COMPOSE_PROJECT_NAME / CONTAINER_NAME / HOST_PORT を自分用に
./setup.sh
```

`setup.sh` が行うこと:

1. `uname -m` で Architecture 確認
2. `nvidia-smi` で GPU / Driver / CUDA Version 確認
3. `docker` / `docker compose` の有無と daemon への接続確認
4. NVIDIA Container Toolkit (`nvidia-ctk`, docker runtime) の確認
5. `docker run --rm --gpus all ${CUDA_TEST_IMAGE} nvidia-smi -L` で **Container から GPU が見えるか**確認
6. `HF_CACHE_DIR` / `VLLM_CACHE_DIR` を作成（目印ファイル `.vllmkit-cache` を置く）
7. Host memory を表示
8. `docker compose config` で設定を検証し、vLLM Image を pull（`--no-pull` で省略可）

`setup.sh` が**行わないこと**: `apt install`、Driver / Kernel の変更、`/etc/docker/daemon.json` の編集、`sudo` の実行。

### Image について（重要）

- **vLLM Image**: 既定値は NVIDIA NGC の `nvcr.io/nvidia/vllm:25.11-py3` です。
  GB10 (Blackwell, sm_121) + ARM64 + CUDA 13 に対応したビルドが必要で、DGX Spark / GX10 では
  NGC の vLLM Container が NVIDIA 公式に案内されています。
  この tag は作成時点のものです。**[NGC カタログ](https://catalog.ngc.nvidia.com/orgs/nvidia/containers/vllm)で
  新しい tag と対応 Driver を確認し、研究室で 1 つに揃えてください。**
  `vllm/vllm-openai:<version>` (Docker Hub) も arm64 版がありますが、GB10 で動くかは version ごとに確認が必要です。
- **CUDA テスト Image**: `nvcr.io/nvidia/cuda:13.0.0-base-ubuntu24.04`。
  Container 内 CUDA は Host Driver の CUDA Version (13.0) **以下**である必要があります。
  pull できない場合は `.env` の `CUDA_TEST_IMAGE` を `nvidia/cuda:13.0.0-base-ubuntu24.04` などに変更してください。

## 6. 起動方法

```bash
./start.sh            # 起動し /health が OK になるまで待つ (初回は Model download で数分)
./start.sh --no-wait  # 起動だけ
```

起動後に API URL、ログや状態を確認するコマンド、`curl` の例が表示されます。

```bash
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8000/v1/models
curl http://127.0.0.1:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen/Qwen2.5-1.5B-Instruct","messages":[{"role":"user","content":"こんにちは"}]}'
```

`VLLM_API_KEY` を設定した場合は `-H "Authorization: Bearer <key>"` を付けます。

Python (openai SDK):

```python
from openai import OpenAI
client = OpenAI(base_url="http://127.0.0.1:8000/v1", api_key="<VLLM_API_KEY または任意の文字列>")
r = client.chat.completions.create(model="Qwen/Qwen2.5-1.5B-Instruct",
                                   messages=[{"role": "user", "content": "Hello"}])
print(r.choices[0].message.content)
```

手元の PC から使う場合は SSH port forward を使います（LAN には公開しません）:

```bash
ssh -L 8000:127.0.0.1:8000 <user>@<gx10-host>
```

## 7. 停止方法

```bash
./stop.sh
```

Container を停止するだけで、Container と cache は残ります。GPU メモリは解放されます。
**使わないときは停止して、他の学生にメモリを空けてください。**

## 8. 状態確認

```bash
./status.sh
```

Compose の状態、`docker ps`、healthcheck、`nvidia-smi`、`free -h`、`/health`、`/v1/models` を表示します（読み取りだけで、何も変更しません）。

## 9. ログ確認

```bash
./logs.sh              # 直近200行 + 追従 (Ctrl+C で抜ける。Server は止まらない)
./logs.sh --tail 50
```

## 10. `.env` 各項目の説明

| 変数 | 既定値 | 説明 |
|---|---|---|
| `COMPOSE_PROJECT_NAME` | `vllmkit` | Compose project 名。スクリプトはこの project だけを操作する。**複数人で使うときは固有名にする** |
| `CONTAINER_NAME` | `vllmkit-vllm` | Container 名。同名 Container が別ディレクトリのものなら、スクリプトは中止する |
| `VLLM_IMAGE` | `nvcr.io/nvidia/vllm:25.11-py3` | vLLM Image。**tag 固定を推奨** |
| `CUDA_TEST_IMAGE` | `nvcr.io/nvidia/cuda:13.0.0-base-ubuntu24.04` | setup で GPU を確認するための Image |
| `VLLM_MODEL` | `Qwen/Qwen2.5-1.5B-Instruct` | Hugging Face Model ID (`vllm serve <model>` の位置引数。`--model` に相当) |
| `SERVED_MODEL_NAME` | 同上 | API で使う model 名 |
| `GPU_MEMORY_UTILIZATION` | `0.30` | vLLM が確保するメモリの割合（→ 16） |
| `MAX_MODEL_LEN` | `8192` | 最大 context 長（→ 17） |
| `SHM_SIZE` | `8g` | Container の `/dev/shm`（→ 15） |
| `HOST_PORT` | `8000` | Host 側の Port（bind 先は `127.0.0.1` で固定） |
| `HF_CACHE_DIR` | `./cache/huggingface` | Model 等の保存先（Host） |
| `VLLM_CACHE_DIR` | `./cache/vllm` | torch.compile / CUDA graph 等の cache（Host） |
| `HF_TOKEN` | 空 | gated model 用。**commit 禁止** |
| `VLLM_API_KEY` | 空 | 設定すると API に Bearer 認証を要求する。共有サーバーでは設定を推奨 |
| `RESTART_POLICY` | `unless-stopped` | 障害時・再起動時の動作。crash loop が心配なら `on-failure:3` |
| `VLLM_EXTRA_ARGS` | 空 | 追加の vLLM 引数（例 `"--dtype bfloat16 --max-num-seqs 16"`） |
| `START_TIMEOUT` | `900` | `start.sh` が ready を待つ秒数 |

> `docker compose config` の出力には `.env` の Token が展開されて表示されます。出力を貼り付けて共有しないでください。

## 11. Port 8000 を localhost に限定している理由

`docker-compose.yml` では `127.0.0.1:${HOST_PORT}:8000` と書き、Host の **loopback にだけ** bind しています。

- vLLM 単体には TLS、ユーザー管理、Rate Limit がありません。LAN に直接出すと、誰でも GPU を使い放題になり、通信内容も平文になります。
- Docker が公開する Port は ufw などの Host firewall を**迂回する**ことがあります。`0.0.0.0` への bind は想定より広く公開される危険があります。
- 将来は `Nginx / Gateway :443 → 127.0.0.1:8000 → vLLM` の構成にし、TLS・認証・Rate Limit を Gateway 側で行います。

注意: localhost 限定でも、**同じサーバーにログインしている他ユーザーからはアクセスできます**。`VLLM_API_KEY` の設定を推奨します。

## 12. Model / Cache を永続化している理由

- Model は数GB〜数百GBあります。Container を作り直すたびに download すると、時間も回線も無駄になります。
- vLLM cache（torch.compile や CUDA graph の成果物）が残っていると、2 回目以降の起動が速くなります。
- Container は「いつ捨てても良いもの」、データは Host に置く、という分離です。`clean.sh` は cache を消しません。

## 13. NVIDIA Driver を Container に入れない理由

- Driver は Kernel module と一体で、**Host に 1 つだけ**存在できます。Container から入れ替えることはできず、試みると Host を壊す原因になります。
- Container には CUDA Runtime / ライブラリだけを入れ、NVIDIA Container Toolkit が Host の Driver を Container に注入します。
- 共有サーバーで Driver を変更すると、全員の環境に影響します。Driver の更新は管理者の作業です。
- 条件: Container の CUDA Runtime の version は、Host Driver が対応する CUDA Version（`nvidia-smi` の表示、ここでは 13.0）以下であること。

## 14. `--gpus all` の意味

`docker run --gpus all` は「Host のすべての GPU を Container から使えるようにする」という指定です（NVIDIA Container Toolkit が必要）。
Compose では次のように書きます。

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all
          capabilities: [gpu]
```

GX10 の GPU は 1 基なので `all` = GB10 です。**GPU を占有するわけではありません**。他の学生の Process も同じ GPU で動けるので、メモリの取り合いになる点に注意してください。

## 15. `--ipc=host` / shared memory 設定の意味

PyTorch / vLLM は Process 間のデータ受け渡しに `/dev/shm`（共有メモリ）を使います。Docker の既定値は 64MB と小さく、そのままだとエラーや性能低下が起きます。

- `--ipc=host`: Host の IPC namespace を共有します。手軽ですが、Host 上の他 Process と IPC が見える状態になり、隔離性が下がります。
- `--shm-size`（本キットでは Compose の `shm_size: ${SHM_SIZE}`）: Container 専用の `/dev/shm` のサイズを指定します。**共有サーバーではこちらを採用しています**。

`/dev/shm` は使った分だけ RAM（GX10 では Unified Memory）を消費します。Tensor Parallel 等で足りなくなったら `SHM_SIZE` を増やしてください。

## 16. `--gpu-memory-utilization`

vLLM が起動時に確保する GPU メモリの**割合**です。この中に Model の重みと KV cache が入ります。

- vLLM は起動時に `全メモリ × 値` を確保しようとし、**空きが足りなければ起動に失敗します**。
- **GX10 は Unified Memory** です。GPU 専用の VRAM はなく、CPU（OS・他ユーザーの Process）と同じ 128GB 級のメモリを共有します。
  - `0.80` を指定すると、約 100GB を 1 人で確保することになり、OS や他の学生を圧迫します（最悪 OOM killer が動きます）。
  - `nvidia-smi` のメモリ欄は GB10 では正確に表示されないことがあります。空き容量は `free -h` で確認してください。
- 既定値は **0.30** です（小型 Qwen には十分）。上げる前に `free -h` と他の利用者の状況を確認してください。
- 値が小さすぎると KV cache が足りず、`MAX_MODEL_LEN` を満たせないというエラーで起動に失敗します。その場合は `MAX_MODEL_LEN` を下げるか、少しずつ値を上げてください。

## 17. `--max-model-len`

1 リクエストで扱える最大 token 数（入力 + 出力）です。

- 大きくするほど 1 リクエストあたりの KV cache が増え、同時に処理できるリクエスト数が減ります。
- Model 自体の上限（Qwen2.5-1.5B は 32K）を超える値は指定できません。
- 既定値の `8192` は安全側の値です。長文を扱う場合は、`GPU_MEMORY_UTILIZATION` とのバランスを見て増やしてください。

## 18. Troubleshooting

| 症状 | 原因 / 対応 |
|---|---|
| `.env がありません` | `cp .env.example .env` |
| `permission denied ... docker.sock` | `docker` group に未所属です。管理者に依頼してください（自分で sudo しない） |
| setup の GPU Container テストが失敗する | NVIDIA Container Toolkit が未設定か、`CUDA_TEST_IMAGE` が arm64 非対応です。Image を変えても駄目なら管理者に相談 |
| `exec format error` | Image が arm64 に対応していません。arm64 対応の tag を使ってください |
| `no kernel image is available` / sm_121 未対応 | Image が GB10 (Blackwell) 未対応です。NGC の新しい vLLM Image を使ってください |
| `Free memory on device ... is less than desired` | 空きが `GPU_MEMORY_UTILIZATION` に足りません。値を下げるか、他の利用状況を `free -h` / `nvidia-smi` で確認してください |
| `max_model_len ... larger than ... KV cache` | `MAX_MODEL_LEN` を下げるか、`GPU_MEMORY_UTILIZATION` を上げてください |
| `port is already allocated` | `HOST_PORT` を他の人が使っています。`.env` で 8001 などに変更してください |
| `Container名 ... は別の環境が使用中` | 他の人と名前が衝突しています。`COMPOSE_PROJECT_NAME` / `CONTAINER_NAME` を固有名にしてください |
| `401 Unauthorized` / 403 (Hugging Face) | gated model です。`HF_TOKEN` を設定し、Hugging Face 上で利用規約に同意してください |
| `401` (vLLM API) | `VLLM_API_KEY` を設定しています。`Authorization: Bearer` header を付けてください |
| 起動が遅い | 初回は Model download と torch.compile に時間がかかります。`./logs.sh` で進捗を確認してください |
| 再起動を繰り返す | `./logs.sh` で原因を確認してください。`RESTART_POLICY=on-failure:3` にすると、メモリの取り合いによる crash loop を防げます |
| cache が root 所有で消せない | Container は root で書き込みます。`./clean-all.sh` は Container 経由で削除します |

## 19. 完全削除方法

```bash
./clean.sh             # Container / Network を削除 (cache・Image は残る)
./clean-all.sh         # DELETE と入力 → cache (Model を含む) も削除
./clean-all.sh --rmi   # さらに VLLM_IMAGE も削除 (使用中なら削除されない)
cd .. && rm -rf <repository>
```

安全のための仕様:
- 操作対象は自分の Compose project（`COMPOSE_PROJECT_NAME`）だけです。
- `clean-all.sh` は、`setup.sh` が置いた目印 `.vllmkit-cache` のある dir しか削除しません。`/` や `$HOME` は拒否します。
- `docker system prune`、`docker volume prune`、Image や Container の一括削除、GPU Process の kill は**一切行いません**。自分でも実行しないでください（他の学生の環境が消えます）。

## 20. 将来的な拡張（ロードマップ）

```text
Phase 1  Docker + vLLM + Qwen                        ← 本キット
Phase 2  OpenAI-compatible API                       ← 本キット (/v1/*)
Phase 3  Open WebUI
Phase 4  Nginx / Gateway, TLS, Authentication, Rate Limit
Phase 5  Prometheus / Grafana
Phase 6  Multi-GPU: Tensor Parallel / Data Parallel / Expert Parallel
Phase 7  DeepSeek 等の大規模 MoE モデル
```

拡張する際の方針:

- **Phase 3**: `docker-compose.yml` に `open-webui` service を追加し、`OPENAI_API_BASE_URL=http://vllm:8000/v1`（Compose 内 network）で接続します。WebUI の Port も `127.0.0.1` に bind します。
- **Phase 4**: Nginx などの Gateway だけを `:443` で公開し、`127.0.0.1:8000` へ reverse proxy します。TLS 証明書、認証（API key / OIDC）、`limit_req` による Rate Limit を Gateway で行います。
- **Phase 5**: vLLM は `/metrics` で Prometheus 形式の metrics を出力します。Prometheus と Grafana を同じ project に追加し、これらも localhost bind にします。GPU metrics は DCGM exporter で取得します（管理者と相談）。
- **Phase 6**: `VLLM_EXTRA_ARGS` に `--tensor-parallel-size N` / `--data-parallel-size N` / `--enable-expert-parallel` を指定します。GPU の指定は `count` / `device_ids` で行います。複数ノードでは Ray などが必要です。
- **Phase 7**: 巨大な Model は Unified Memory 128GB に収まるかを最初に見積もります（量子化 FP8/FP4 や複数ノード構成を検討）。長時間占有することになるため、研究室で利用時間を調整してください。
