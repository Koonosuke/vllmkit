あなたはLinux / Docker / NVIDIA GPU / vLLMの運用に詳しいインフラエンジニアです。

共有GPUサーバーで利用する、vLLMの再構築キットを作成してください。

# 背景

利用するサーバーは ASUS GX10 です。

現在確認できている環境：

- OS: Ubuntu 24.04 ARM64系
- CPU Architecture: ARM64 / aarch64
- GPU: NVIDIA GB10
- NVIDIA Driver: 580.159.03
- `nvidia-smi` 上の CUDA Version: 13.0
- GPUは他の学生とも共有
- vLLMはDocker Containerとして動かしたい
- ModelはまずQwen系の小型モデルで動作確認する
- 将来的にはDeepSeekなどの大規模モデル、Multi-GPU、Open WebUI、Nginx、Prometheus/Grafana等へ拡張予定

このサーバーは共有環境なので、NVIDIA DriverやOS設定を勝手に変更する処理は入れないでください。

# 目的

GitHub Repositoryを `git clone` したあと、できるだけ少ない操作でvLLM Serverを再構築できるようにしてください。

理想的には以下で起動できるようにします。

```bash
git clone <repository>
cd <repository>

cp .env.example .env

./setup.sh
./start.sh
```

# 作成してほしい構成

以下を基本構成としてください。

```text
vllm-kit/
├ README.md
├ docker-compose.yml
├ .env.example
├ .gitignore
├ setup.sh
├ start.sh
├ stop.sh
├ status.sh
├ logs.sh
└ clean.sh
```

必要性が高い場合のみ、追加ファイルを作成して構いません。

# 重要な設計方針

## 1. HostとContainerの責務を分離する

Host側：

```text
Ubuntu
NVIDIA Driver
Docker
NVIDIA Container Toolkit
```

Container側：

```text
CUDA Runtime
PyTorch
vLLM
Model Runtime
```

この責務分離を崩さないでください。

## 2. NVIDIA Driverを自動インストールしない

`setup.sh` から、

```bash
apt install nvidia-driver
```

などを実行してはいけません。

共有サーバーなので、HostのDriverやKernelなどを勝手に変更しないでください。

`setup.sh` では、

- `uname -m`
- `nvidia-smi`
- `docker --version`
- `docker compose version`
- NVIDIA Container Toolkit / GPU Container実行可否

などを確認してください。

不足している場合は、自動変更ではなくエラーメッセージと必要な対応を表示してください。

## 3. GPU Containerの動作確認

setup時に、NVIDIA GPUがDocker Containerから見えることを確認してください。

例：

```bash
docker run --rm --gpus all <NVIDIA CUDA IMAGE> nvidia-smi
```

ただし、GX10 / ARM64 / CUDA 13系で利用可能な適切なImageを選んでください。

固定値に自信がない場合はREADMEに注意事項を記載してください。

## 4. vLLMはDocker Composeで管理する

ユーザーが長い `docker run` コマンドを毎回入力する設計にはしないでください。

`docker-compose.yml` に以下をまとめてください。

- vLLM Docker Image
- GPU割り当て
- Port mapping
- Volume
- IPC / shared memory
- restart policy
- vLLM Server起動オプション

## 5. vLLM ImageのVersionを固定可能にする

`.env` で、

```text
VLLM_IMAGE=
```

を変更できるようにしてください。

`latest` を利用する場合でも、READMEで本番・研究室共通環境ではVersion固定を推奨すると説明してください。

## 6. vLLM Server

まずはOpenAI-compatible Serverとして動作させます。

必要な基本設定：

```text
--model
--host
--port
--gpu-memory-utilization
--max-model-len
```

初期値は安全側にしてください。

例：

```text
GPU_MEMORY_UTILIZATION=0.80
MAX_MODEL_LEN=8192
```

ただしGX10がUnified Memoryであることを考慮し、設定値の意味と注意事項をREADMEに記載してください。

## 7. Port公開

vLLMの8000番Portを、最初からLAN全体へ直接公開しないでください。

Host側は原則、

```text
127.0.0.1:8000
```

へbindしてください。

イメージ：

```text
Host
127.0.0.1:8000
        ↓
Container
0.0.0.0:8000
        ↓
vLLM
```

将来的に、

```text
Nginx / Gateway :443
        ↓
127.0.0.1:8000
        ↓
vLLM
```

へ拡張することを前提にしてください。

## 8. Model / CacheはContainerから分離する

Containerを削除しても、Modelを毎回再downloadしなくて済むようにしてください。

最低限、

```text
Hugging Face cache
vLLM cache
```

をHost側へ永続化してください。

可能ならHost側の保存先を `.env` から指定できるようにします。

例：

```text
HF_CACHE_DIR=
VLLM_CACHE_DIR=
```

## 9. SecretをGitへcommitしない

HF TokenなどをRepositoryへcommitしない設計にしてください。

`.gitignore` に、

```text
.env
```

を含めてください。

`.env.example` には実際のTokenを書かないでください。

## 10. Scriptの役割

### setup.sh

以下を確認する。

- Architecture
- NVIDIA Driver / GPU
- Docker
- Docker Compose
- NVIDIA Container Toolkit
- DockerからGPUが利用可能か
- Cache directory作成
- vLLM Imageのpull

HostのDriver等は変更しない。

### start.sh

```text
docker compose up -d
```

を基本としてvLLMを起動する。

起動後、

- Container状態
- API URL
- logsコマンド
- `/health`
- `/v1/models`

の確認方法を表示する。

### stop.sh

vLLM環境を安全に停止する。

Model cacheやvLLM cacheは削除しない。

### status.sh

以下を簡単に確認できるようにする。

- Containerの状態
- `docker ps`
- `nvidia-smi`
- vLLM `/health`
- `/v1/models`

### logs.sh

```text
docker compose logs -f
```

相当でvLLM Serverのログを確認できるようにする。

### clean.sh

Container等を削除する。

ただし、

```text
Model cache
Hugging Face cache
vLLM cache
```

は削除しない。

キャッシュまで削除する操作は誤操作リスクが高いため、`clean.sh` には含めないでください。

必要なら別途 `clean-all.sh` を作成してもよいですが、実行前に確認を要求してください。

# READMEに書いてほしい内容

READMEは他の学生でも理解できる内容にしてください。

最低限、

1. このRepositoryの目的
2. 構成図
3. HostとContainerの責務
4. 前提環境
5. 初回セットアップ
6. 起動方法
7. 停止方法
8. 状態確認
9. ログ確認
10. `.env` 各項目の説明
11. Port 8000をlocalhostに限定している理由
12. Model / Cacheを永続化している理由
13. NVIDIA DriverをContainerに入れない理由
14. `--gpus all` の意味
15. `--ipc=host` またはshared memory設定の意味
16. `--gpu-memory-utilization`
17. `--max-model-len`
18. Troubleshooting
19. 完全削除方法
20. 将来的な拡張

を書いてください。

# 将来的な拡張

現時点では実装不要ですがREADMEに以下のロードマップを書いてください。

```text
Phase 1
Docker + vLLM + Qwen

Phase 2
OpenAI-compatible API

Phase 3
Open WebUI

Phase 4
Nginx / Gateway
TLS
Authentication
Rate Limit

Phase 5
Prometheus / Grafana

Phase 6
Multi-GPU
Tensor Parallel
Data Parallel
Expert Parallel

Phase 7
DeepSeek等の大規模MoEモデル
```

# 安全性

共有GPU Serverなので特に重要です。

以下は禁止してください。

- NVIDIA Driverの自動変更
- Docker daemon設定の無断変更
- `/etc` 配下への無断書き込み
- 他ユーザーのContainer削除
- `docker system prune -a`
- 他ユーザーのImageやVolumeの一括削除
- Host全体のcache削除
- 全GPU Processのkill

自分が作成したContainer / Resourceだけを操作するようにしてください。

Container名やCompose project名も、このRepository固有のものにしてください。

# 作業手順

まず実装前に、以下を提示してください。

1. 作成予定のファイル一覧
2. 各ファイルの役割
3. 全体アーキテクチャ
4. Host / Docker / vLLMの責務分離
5. 共有GX10で危険になり得る操作

この設計を提示した後、その設計に沿ってファイルを作成してください。

作成後は、

```bash
bash -n setup.sh
bash -n start.sh
bash -n stop.sh
bash -n status.sh
bash -n logs.sh
bash -n clean.sh
```

などでShell ScriptのSyntax Checkを行ってください。

Docker Composeについても、

```bash
docker compose config
```

で設定を検証してください。

実機環境を変更する危険があるコマンドは勝手に実行せず、必要なら「実行予定のコマンド」と「影響範囲」を説明してください。

最後に、

```text
git clone後にユーザーが実行するコマンド
```

をREADMEとは別に簡潔にまとめてください。
