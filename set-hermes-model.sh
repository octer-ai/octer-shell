#!/usr/bin/env bash
# 配置 Hermes Agent 使用 Octer 自定义大模型，并选中它。
# 用法: ./set-hermes-model.sh <API_KEY>
set -euo pipefail

API_KEY="${1:?用法: $0 <API_KEY>}"

# ── 固定部分 ────────────────────────────────────────────
BASE_URL="https://octer.ai/api/llm"   # 接口地址（正式）
MODEL="Octer-1.0-lite"                # 模型名称
PROVIDER_ID="octer"                   # 自定义 provider 标识
MAX_TOKENS="65536"
# ────────────────────────────────────────────────────────

# 选中 Octer 自定义模型（OpenAI 兼容协议）。
# Hermes 这版把模型配置全部平铺在 model.* 下，没有 custom_providers 块。
hermes config set model.provider           custom
hermes config set model.base_url           "$BASE_URL"
hermes config set model.custom_provider_id "$PROVIDER_ID"
hermes config set model.default            "$MODEL"
hermes config set model.max_tokens         "$MAX_TOKENS"

# API Key —— custom 端点走 OpenAI 兼容鉴权。两处都写做兜底，确保被读到。
hermes config set model.api_key   "$API_KEY"
hermes config set OPENAI_API_KEY  "$API_KEY"

# Octer 模型不支持 fast 模式 —— 关闭 reasoning_effort，避免发送相关参数。
hermes config set agent.reasoning_effort none

echo "✅ 已配置并选中: ${PROVIDER_ID} → ${MODEL} @ ${BASE_URL}（已关闭 fast/reasoning）"

# ── 启用：启动/刷新 gateway 让新模型生效 ─────────────────
# 改过 config 后 launchd service 定义会变 stale，必须用 start 重新生成（restart 不会）。
echo "🔄 启动 hermes gateway..."
hermes gateway start
hermes gateway status

echo "── 当前配置（hermes config show | grep Model）──"
# hermes config 没有 get 子命令，用 show 查看
hermes config show | grep -iE "Model:|provider|reasoning" || true

echo
echo "验证: hermes chat（进入后输入“你好”），或一次性: hermes -z \"你好\""
