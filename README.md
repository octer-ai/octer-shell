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
