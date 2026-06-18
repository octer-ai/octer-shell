#!/usr/bin/env bash
# 配置 Hermes Agent 使用 Octer 自定义大模型。
# 用法: ./set-hermes-model.sh <API_KEY>
set -euo pipefail

API_KEY="${1:?用法: $0 <API_KEY>}"

# ── 固定部分 ────────────────────────────────────────────
BASE_URL="https://octer.ai/api/llm"   # 接口地址
MODEL="Octer-1.0-lite"                # 模型名称
PROVIDER_ID="octer"                   # 自定义 provider 标识
API_KEY_ENV="OCTER_LLM_API_KEY"       # key 存到 ~/.hermes/.env 的变量名
# ────────────────────────────────────────────────────────

# 自定义 provider（OpenAI 兼容协议）
hermes config set "custom_providers.${PROVIDER_ID}.base_url"     "$BASE_URL"
hermes config set "custom_providers.${PROVIDER_ID}.api_key_env"  "$API_KEY_ENV"
hermes config set "custom_providers.${PROVIDER_ID}.model_id"     "$MODEL"

# 让 hermes 使用该 provider
hermes config set model.provider           custom
hermes config set model.custom_provider_id "$PROVIDER_ID"
hermes config set model.default            "$MODEL"

# 存 API Key（写入 ~/.hermes/.env）
hermes config set "$API_KEY_ENV" "$API_KEY"

# Octer 模型不支持 fast 模式 —— 关闭 reasoning_effort，避免发送相关参数
hermes config set agent.reasoning_effort none

echo "✅ Hermes 已配置: ${PROVIDER_ID} → ${MODEL} @ ${BASE_URL}（已关闭 fast/reasoning）"

# ── 启用：启动/刷新 gateway 让新模型生效 ─────────────────
# 改过 config 后 service 定义会变 stale，hermes 提示直接 start 即可。
echo "🔄 启动 hermes gateway..."
hermes gateway start
hermes gateway status

echo "✅ 已启用。当前配置（grep model）："
# hermes config 没有 get 子命令，用 show 查看
hermes config show | grep -iE "provider|model|reasoning" || true
