# octer-shell

[English](README.md) · **中文**

配置 [Hermes Agent](https://github.com/nousresearch/hermes-agent) 使用 [Octer.ai](https://octer.ai) 自定义大模型的 shell 脚本，只需传入一个 API Key,其余固定。

| 脚本 | 平台 | 作用 |
|------|------|------|
| `set-hermes-model.sh` | Linux / macOS | 把 Hermes Agent 切到 Octer 的 OpenAI 兼容接口 |
| `set-hermes-model.ps1` | Windows / PowerShell | 行为与 `.sh` 一致的 PowerShell 版 |
| `set-openclaw-model.sh` | Linux / macOS | 把 OpenClaw 切到 Octer 自定义大模型(OpenAI 兼容) |
| `set-openclaw-model.ps1` | Windows / PowerShell | 行为与 OpenClaw `.sh` 一致的 PowerShell 版 |
| `clear-hermes-model.sh` | Linux / macOS | 清除 Octer 相关配置,恢复默认 |
| `clear-openclaw-model.sh` | Linux / macOS | 清除 OpenClaw 里的 Octer 模型配置,恢复默认 |
| `clear-openclaw-model.ps1` | Windows / PowerShell | 行为与 OpenClaw 清除 `.sh` 一致的 PowerShell 版 |

## set-hermes-model.sh

把 Hermes Agent 的 LLM 切换到 Octer 的 OpenAI 兼容接口，只需传入 API Key。

### 用法

```bash
./set-hermes-model.sh <API_KEY>
```

示例：

```bash
./set-hermes-model.sh evo_xxxxxxxxxxxxxxxx
```

### 固定配置

| 项目 | 值 |
|------|-----|
| 接口地址 | `https://octer.ai/api/llm` |
| API 协议类型 | OpenAI 兼容协议（custom provider） |
| 模型名称 | `Octer-1.0-lite` |
| Provider 标识 | `octer` |

只有 **API Key** 是参数，其余固定。

### 脚本做了什么

直接改 `config.yaml`(由 `hermes config path` 解析),同时写「命名的 custom provider」和「选中的 model」—— Hermes 取凭证时只认 `custom_providers` 列表里的命名条目,光设 `model.*` 会报 `No LLM provider configured`：

1. **custom provider 条目**：往 `custom_providers` 列表加/更新一项（`name: Octer`、`base_url`、`api_key`、`model`），按 `base_url` 去重。
2. **选中模型**：写 `model` 块 —— `provider=octer`（用 provider slug,而非字面量 `custom`）、`base_url`、`default=Octer-1.0-lite`、`api_key`、`max_tokens=65536`。
3. **关闭 fast 模式**：设 `agent.reasoning_effort=none`（Octer 模型不支持 reasoning/fast 模式）。
4. **生效**：跑 `hermes gateway start` 让新模型立即生效（改配置后 service 会 stale,必须 `start` 重新生成,`restart` 不行），打印当前配置,再自测一次（`hermes -z "你好"`,最多等 60s）。

改动前会写一份带时间戳的 `config.yaml` 备份。

### 前置条件

- 已安装 `hermes` CLI 并可在 `PATH` 中调用。
- 拥有 Octer.ai API Key（在 [octer.ai/workspace](https://octer.ai/workspace) → Me → Settings → API Keys 创建）。
- Python 3 且带 `pyyaml`。脚本会自动挑合适的解释器（优先 Hermes 自带 venv,一定有 `pyyaml`），没有则用 `pip install --user pyyaml` 兜底。

## set-hermes-model.ps1（Windows / PowerShell）

Windows 上用这个 PowerShell 版，行为与 `set-hermes-model.sh` 完全一致：同样往 `config.yaml` 写 `custom_providers[Octer]` 列表条目 + `model` 块、关闭 `agent.reasoning_effort`，再 `hermes gateway start` 并自测。

### 用法

```powershell
.\set-hermes-model.ps1 <API_KEY>
```

示例：

```powershell
.\set-hermes-model.ps1 evo_xxxxxxxxxxxxxxxx
```

若系统禁止运行脚本（报“无法加载……在此系统上禁止运行脚本”），用：

```powershell
powershell -ExecutionPolicy Bypass -File .\set-hermes-model.ps1 <API_KEY>
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

把 OpenClaw 切到 Octer 自定义大模型 —— 思路同 Hermes 脚本,只是落到 OpenClaw 自己的配置(`~/.openclaw/openclaw.json`),通过 `openclaw config set` 写入。固定参数:接口地址 `https://octer.ai/api/llm`、模型 `Octer-1.0-lite`、OpenAI 兼容、provider slug `octer`。

> ⚠️ **占位说明**:编写机器上未安装 openclaw,其自定义模型的确切 config key 尚未最终确认。脚本按 Hermes 模式用 `model.*`;若 OpenClaw 实际 schema 不同(如 `providers.octer.*` / `llm.*`),只改 `config set` 那几行即可。

### 用法

```bash
# Linux / macOS
./set-openclaw-model.sh <API_KEY>
```

```powershell
# Windows / PowerShell
.\set-openclaw-model.ps1 <API_KEY>
```

### 脚本做了什么

1. `openclaw config set model.provider octer`
2. `openclaw config set model.baseURL https://octer.ai/api/llm`
3. `openclaw config set model.apiKey <API_KEY>`
4. `openclaw config set model.model Octer-1.0-lite`
5. `openclaw gateway restart` —— 生效,并打印当前模型配置。

### 前置条件

- 已安装 `openclaw` CLI 并可在 `PATH` 中调用。
- 拥有 Octer.ai API Key(在 [octer.ai/workspace](https://octer.ai/workspace) → Me → Settings → API Keys 创建)。

## clear-hermes-model.sh

清除 Hermes Agent 里的 Octer 自定义大模型配置，恢复到默认。Hermes 没有 `config unset/remove`，只能直接改 `config.yaml`（会先备份）。

### 用法

```bash
./clear-hermes-model.sh
```

它会把所有 Octer 相关项清掉，保留 `qwen` 等其它 provider：

1. 当 `model.base_url` 指向 Octer 时，清掉 `model` 覆盖键。
2. 删除 `providers` / `custom_providers` 里 key 名或 `api`/`base_url` 命中 `octer` 的条目。
3. 删除 `agent.reasoning_effort` 覆盖。
4. 若 `.env` 里有 `OCTER_LLM_API_KEY` 则删掉，再 `hermes gateway start` 生效。

之后想恢复 Octer 模型，重新跑 `./set-hermes-model.sh <API_KEY>` 即可。

## clear-openclaw-model.sh / clear-openclaw-model.ps1

`clear-hermes-model.sh` 的 OpenClaw 版：清除 Octer 自定义大模型配置，把 OpenClaw 恢复到默认。OpenClaw 配置在 `~/.openclaw/openclaw.json`，脚本直接改文件（会先备份）。

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

1. 先备份 `~/.openclaw/openclaw.json`，当 `model.baseURL` 指向 Octer 时，清掉 `set-openclaw-model.sh` 写入的 `model.*`（`provider` / `baseURL` / `apiKey` / `model`），其余配置保留。
2. 跑 `openclaw gateway restart` 生效，并打印当前模型配置。

清除后用 `openclaw onboard`（或 `openclaw setup`）重新选模型；想恢复 Octer 模型，重新跑 `./set-openclaw-model.sh <API_KEY>` 即可。

> ⚠️ **占位说明**：同 `set-openclaw-model.sh`——编写机器上未安装 openclaw，确切 config key 尚未最终确认。若实际 schema 不同（如 `providers.octer.*` / `llm.*`），只改脚本里的 key 判断即可。

## 排查

若 `hermes -z` 一直卡住，直接 `curl` 端点看是不是端点本身的问题：

```bash
curl -sS https://octer.ai/api/llm/chat/completions \
  -H "Authorization: Bearer <KEY>" -H "Content-Type: application/json" \
  -d '{"model":"Octer-1.0-lite","messages":[{"role":"user","content":"你好"}]}'
```
