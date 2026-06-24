# octer-shell

配置 [Hermes Agent](https://github.com/nousresearch/hermes-agent) 使用 [Octer.ai](https://octer.ai) 自定义大模型的 shell 脚本。

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

基于 `hermes config set`，模型配置全部平铺在 `model.*` 下（这版 Hermes 没有 `custom_providers` 块）：

1. 选中 custom 模型：`model.provider=custom`、`model.base_url`、`model.custom_provider_id=octer`、`model.default=Octer-1.0-lite`、`model.max_tokens=65536`
2. 写 API Key：同时设 `model.api_key` 和 `OPENAI_API_KEY` 兜底
3. 关闭 `agent.reasoning_effort`（Octer 模型不支持 fast 模式）
4. **`hermes gateway start` 让新模型立即生效**（改配置后 service 会 stale，必须 `start` 重新生成，`restart` 不行），并打印当前配置

### 前置条件

- 已安装 `hermes` CLI 并可在 `PATH` 中调用
- 拥有 Octer.ai API Key（在 [octer.ai/workspace](https://octer.ai/workspace) → Me → Settings → API Keys 创建）

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

- 找 python：优先 hermes 自带 venv 的 `hermes-agent\venv\Scripts\python.exe`，否则依次试 `py -3` / `python` / `python3`；都没 `pyyaml` 时用 `pip install --user pyyaml` 兜底
- 60s 自测超时用 PowerShell 后台 job 实现（Windows 没有 `timeout <命令>` 这种语义）
- 临时改写脚本以 UTF-8 无 BOM 写入，避免中文注释/输出乱码

### 前置条件（Windows）

- 已安装 `hermes` CLI 且在 `PATH` 中（`hermes` 可直接调用）
- 已装 Python 3（`py -3` 或 `python` 可用）；脚本会自动查找/安装 `pyyaml`
- 拥有 Octer.ai API Key
