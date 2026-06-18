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

基于 Hermes 官方 `hermes config set` 命令：

1. 注册自定义 provider `octer`（`base_url` / `api_key_env` / `model_id`）
2. 把当前模型切到该 provider，默认模型 `Octer-1.0-lite`
3. 把 API Key 写入 `~/.hermes/.env`（变量名 `OCTER_LLM_API_KEY`）

### 前置条件

- 已安装 `hermes` CLI 并可在 `PATH` 中调用
- 拥有 Octer.ai API Key（在 [octer.ai/workspace](https://octer.ai/workspace) → Me → Settings → API Keys 创建）
