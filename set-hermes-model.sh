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

echo "✅ Hermes 已配置: ${PROVIDER_ID} → ${MODEL} @ ${BASE_URL}"
