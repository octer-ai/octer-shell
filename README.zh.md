# octer-shell

[English](README.md) · **中文**

配置 [Hermes Agent](https://github.com/nousresearch/hermes-agent) 使用 [Octer.ai](https://octer.ai) 自定义大模型的 shell 脚本，传入 API Key（模型名称可选），其余固定。

| 脚本 | 平台 | 作用 |
|------|------|------|
| `set-hermes-model.sh` | Linux / macOS | 把 Hermes Agent 切到 Octer 的 OpenAI 兼容接口 |
| `set-hermes-model.ps1` | Windows / PowerShell | 行为与 `.sh` 一致的 PowerShell 版 |
| `set-openclaw-model.sh` | Linux / macOS | 把 OpenClaw 切到 Octer 自定义大模型(OpenAI 兼容) |
| `set-openclaw-model.ps1` | Windows / PowerShell | 行为与 OpenClaw `.sh` 一致的 PowerShell 版 |
| `test-all-models.sh` | Linux / macOS | 测试全部内置模型的 Chat 与 Hermes 工具流式关键路径 |
| `clear-hermes-model.sh` | Linux / macOS | 清除 Octer 相关配置,恢复默认 |
| `clear-openclaw-model.sh` | Linux / macOS | 清除 OpenClaw 里的 Octer 模型配置,恢复默认 |
| `clear-openclaw-model.ps1` | Windows / PowerShell | 行为与 OpenClaw 清除 `.sh` 一致的 PowerShell 版 |

## set-hermes-model.sh

把 Hermes Agent 的 LLM 切换到 Octer 的 OpenAI 兼容接口，传入 API Key。模型不传时会弹出**交互式菜单**（「下拉」）让你从支持列表里选，也可以用第二个参数直接指定。

### 用法

```bash
./set-hermes-model.sh <API_KEY> [MODEL]
```

示例：

```bash
./set-hermes-model.sh evo_xxxxxxxxxxxxxxxx            # 弹交互式模型菜单（默认 gpt-5.5）
./set-hermes-model.sh evo_xxxxxxxxxxxxxxxx claude-opus-4-8    # 显式指定模型，跳过菜单
```

不传模型参数时，脚本会打印带编号的支持模型菜单让你选（直接回车用默认项）。在非交互环境（管道 / CI）下会回退到默认 `gpt-5.5`。

### 支持的模型

菜单（第一项为默认）提供：

- `gpt-5.5`（默认）
- `gpt-5.6-sol`
- `gpt-5.6-terra`
- `gpt-5.6-luna`
- `claude-opus-4-8`
- `gemini-3.1-pro-preview`
- `gemini-3-flash-preview`
- `gemini-3.5-flash`
- `deepseek-v4-flash`
- `deepseek-v4-pro`
- `glm-5.2`
- `qwen3.8-max`

你仍可用第二个参数显式传任意其它模型名；若不在列表里，会给出提示并按你指定的使用。

**这些模型会全部注册到 provider 上**，所以客户端的模型选择器（下拉）里会列出全部模型 —— 菜单/参数只决定哪个是**当前激活/默认**模型。之后在客户端里可随时切换，无需重跑脚本。

### 测试全部模型

```bash
./test-all-models.sh <API_KEY>
```

脚本默认逐个测试全部内置模型的普通 Chat 请求，以及 Hermes 最关键的 `SSE + function tools` 请求，并在最后输出汇总表、HTTP 状态、错误摘要和上游 request ID。测试按顺序执行，API Key 不会打印。

可用环境变量缩小或扩展测试范围：

```bash
# 只测两个模型
OCTER_MODELS='gpt-5.5,glm-5.2' ./test-all-models.sh <API_KEY>

# 运行完整协议矩阵：Chat、Tools、SSE、SSE+Tools、reasoning+Tools、Responses
OCTER_EXTENDED=1 ./test-all-models.sh <API_KEY>
```

任一场景失败时脚本返回非零退出码，适合直接放进 CI。设置 `OCTER_KEEP_RESULTS=1` 可保留每次请求的载荷、响应头和响应体，便于把 request ID 交给网关排查。

### 固定配置

| 项目 | 值 |
|------|-----|
| 接口地址 | `https://oclaw.octer.ai/v1` |
| API 协议类型 | OpenAI 兼容 Chat Completions API（`chat_completions`） |
| 模型名称 | 从菜单选择，或用第二个参数指定（默认 `gpt-5.5`） |
| Provider 标识 | `custom:octer` |

**API Key** 必填；**模型名称**来自交互式菜单或可选的第二个参数（缺省 `gpt-5.5`），其余固定。

### 脚本做了什么

直接改 `config.yaml`(由 `hermes config path` 解析),同时写「命名的 custom provider」和「选中的 model」—— Hermes 取凭证时只认 `custom_providers` 列表里的命名条目,光设 `model.*` 会报 `No LLM provider configured`：

通过 `curl | bash` 执行时，脚本会自动把仓库中的 `hermes_config.py` 下载到临时文件，并在安装退出时删除；从完整仓库执行时仍优先使用脚本旁边的本地 helper。

1. **唯一 custom provider**：通过 provider 身份（包括 `Octer-2` 等带后缀的旧别名）、任意 `*.octer.ai` 接口地址或 Octer Key 环境变量识别旧渠道；从两种 Hermes provider 配置结构中全部移除，再写入唯一一项。重复执行安装脚本仍保持幂等。所有支持模型仍会注册到下拉列表，并设置 `discover_models: false`。
2. **统一 Chat Completions 路由**：所有模型都写入 `provider=custom:octer` 和 `api_mode=chat_completions`。Octer 的 `/responses` 尚未覆盖全部模型（例如 GLM-5.2），而 `/chat/completions` 可以正常调用。
3. **GPT-5.x 兼容处理**：为 GPT-5.x 写入按模型的 `agent.reasoning_overrides: false`。Chat Completions 支持 GPT 工具调用，但不接受工具与启用的 `reasoning_effort` 同时出现；其它模型仍保留服务端默认 reasoning 行为。
4. **安全保存 Key**：只在 Hermes `.env` 中保存一次 `OCTER_LLM_API_KEY`，provider 通过 `key_env` 引用，不再把 Key 重复写进 `config.yaml`。
5. **生效并验证**：检查并启用已安装的 Octer 平台插件，执行 `gateway stop` + `gateway start` 清理残留进程；`hermes -z` 失败或超时会让脚本明确返回失败。

改动前会写一份带时间戳的 `config.yaml` 备份。

### 前置条件

- 已安装 `hermes` CLI 并可在 `PATH` 中调用。
- 拥有 OClaw API Key（在 [Octer 控制台 OClaw 页面](https://octer.ai/workspace/o/?next=/o)复制或重置）。
- Python 3 且带 `pyyaml`。脚本会自动挑合适的解释器，优先使用 Hermes 自带 venv。

## set-hermes-model.ps1（Windows / PowerShell）

Windows 上用这个 PowerShell 版，行为与 `set-hermes-model.sh` 完全一致：写入唯一的 `custom:octer` provider、选择 Chat Completions、把 Key 保存到 `.env`、完整重载 Gateway，并执行同样的限时自测。

### 用法

```powershell
.\set-hermes-model.ps1 <API_KEY> [MODEL]
```

示例：

```powershell
.\set-hermes-model.ps1 evo_xxxxxxxxxxxxxxxx            # 弹交互式模型菜单（默认 gpt-5.5）
.\set-hermes-model.ps1 evo_xxxxxxxxxxxxxxxx claude-opus-4-8    # 显式指定模型，跳过菜单
```

若系统禁止运行脚本（报“无法加载……在此系统上禁止运行脚本”），用：

```powershell
powershell -ExecutionPolicy Bypass -File .\set-hermes-model.ps1 <API_KEY> [MODEL]
```

### 与 .sh 版的差异（仅实现细节，写入结果一致）

- 找 python：优先 hermes 自带 venv 的 `hermes-agent\venv\Scripts\python.exe`，否则依次试 `py -3` / `python` / `python3`；都没 `pyyaml` 时用 `pip install --user pyyaml` 兜底。
- 60s 自测超时用 PowerShell 后台 job 实现（Windows 没有 `timeout <命令>` 这种语义）。
- 临时改写脚本以 UTF-8 无 BOM 写入，避免中文注释/输出乱码。

### 前置条件（Windows）

- 已安装 `hermes` CLI 且在 `PATH` 中（`hermes` 可直接调用）。
- 已装 Python 3（`py -3` 或 `python` 可用）；脚本会自动查找/安装 `pyyaml`。
- 拥有 Octer.ai API Key。

## set-openclaw-model.sh / set-openclaw-model.ps1

把 OpenClaw 切到 Octer 自定义大模型 —— 思路同 Hermes 脚本,只是落到 OpenClaw 自己的配置(`~/.openclaw/openclaw.json`),通过 `openclaw config set` 写入。固定参数:接口地址 `https://oclaw.octer.ai/v1`、OpenAI 兼容适配器(`openai-completions`)、provider slug `octer`。模型不传时弹出与 Hermes 相同的交互式菜单（默认 `gpt-5.5`，见[支持的模型](#支持的模型)），也可用第二个参数直接指定。

### 用法

```bash
# Linux / macOS
./set-openclaw-model.sh <API_KEY> [MODEL]
```

```powershell
# Windows / PowerShell
.\set-openclaw-model.ps1 <API_KEY> [MODEL]
```

示例(Linux / macOS):

```bash
./set-openclaw-model.sh evo_xxxxxxxxxxxxxxxx            # 弹交互式模型菜单（默认 gpt-5.5）
./set-openclaw-model.sh evo_xxxxxxxxxxxxxxxx claude-opus-4-8    # 显式指定模型，跳过菜单
```

### 脚本做了什么

1. **注册 provider** —— `openclaw config set models.providers.octer '<json>' --strict-json --merge`,其中 `<json>` 的 `models` 数组包含**全部**支持的模型(`[{"id":"gpt-5.5","name":"gpt-5.5"}, …]`),让客户端下拉能列全;若你传了列表外的模型也会一并注册。
2. **选默认模型** —— `openclaw models set octer/<MODEL>`(只设激活/默认,下拉仍显示全部已注册模型)。
3. **生效 & 自测** —— `openclaw gateway restart`,打印 `openclaw models status`,再跑一次容错自测(`openclaw agent --agent main -m "你好"`,最多 60s,不通过不影响配置)—— 对齐 Hermes 脚本的 `hermes -z` 检查。

### 前置条件

- 已安装 `openclaw` CLI 并可在 `PATH` 中调用。
- 拥有 OClaw API Key（在 [Octer 控制台 OClaw 页面](https://octer.ai/workspace/o/?next=/o)复制或重置）。

## clear-hermes-model.sh

清除 Hermes Agent 里的 Octer 自定义大模型配置，恢复到默认。Hermes 没有 `config unset/remove`，只能直接改 `config.yaml`（会先备份）。

### 用法

```bash
./clear-hermes-model.sh

# 或直接通过管道执行
curl -fsSL https://raw.githubusercontent.com/octer-ai/octer-shell/refs/heads/master/clear-hermes-model.sh | bash
```

通过 `curl | bash` 执行时，脚本会临时下载同仓库的 `hermes_config.py`，退出时自动删除。下载有明确的连接和总时限；GitHub Raw 不可用时会自动切换到 jsDelivr 镜像，避免长期卡在“下载共享配置器”。安装脚本使用相同的下载策略。

它会把所有 Octer 相关项清掉，保留 `qwen` 等其它 provider：

1. 当 `model.provider` 或 `model.base_url` 指向 Octer 时，清掉模型覆盖键。
2. 同时清理列表形式的 `custom_providers` 和字典形式的 `providers` 中的 Octer 条目。
3. 从 `.env` 删除 `OCTER_LLM_API_KEY`。
4. 通过 `gateway stop` + `gateway start` 完整重载服务。

之后想恢复 Octer 模型，重新跑 `./set-hermes-model.sh <API_KEY>` 即可。

## clear-openclaw-model.sh / clear-openclaw-model.ps1

`clear-hermes-model.sh` 的 OpenClaw 版：删除 Octer provider,把 OpenClaw 恢复到默认 —— 用 `openclaw config unset`。

### 用法

```bash
# Linux / macOS
./clear-openclaw-model.sh
```

```powershell
# Windows / PowerShell
.\clear-openclaw-model.ps1
```

### 脚本做了什么

1. `openclaw config unset models.providers.octer` —— 删掉 `set-openclaw-model.sh` 写入的 provider(其它 provider 不动)。
2. `openclaw gateway restart`,再打印 `openclaw models status`。

若默认模型仍指向 `octer`,用 `openclaw models set <model>`(或 `openclaw onboard`)重新选;想恢复 Octer 模型,重新跑 `./set-openclaw-model.sh <API_KEY>` 即可。

## 排查

若 `hermes -z` 一直卡住，直接 `curl` 端点看是不是端点本身的问题：

```bash
curl -sS https://oclaw.octer.ai/v1/chat/completions \
  -H "Authorization: Bearer <KEY>" -H "Content-Type: application/json" \
  -d '{"model":"gemini-3-flash-preview","messages":[{"role":"user","content":"你好"}]}'
```
