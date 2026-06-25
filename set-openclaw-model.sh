#!/usr/bin/env bash
# 把 OpenClaw 切换到 Octer 自定义大模型（OpenAI 兼容接口）。比照 set-hermes-model.sh。
# 用法: ./set-openclaw-model.sh <API_KEY>
#
# 往 ~/.openclaw/openclaw.json 写一个自定义 provider（models.providers.octer），
# 选中 octer/Octer-1.0-lite 为默认模型，再重启 gateway。全程走 openclaw 自带 CLI
# （config set 带 schema 校验）。
set -euo pipefail

API_KEY="${1:?用法: $0 <API_KEY>}"

# ── 固定部分 ────────────────────────────────────────────
PROVIDER="octer"
BASE_URL="https://octer.ai/api/llm"   # 接口地址（OpenAI 兼容）
MODEL="Octer-1.0-lite"                # 模型名称
MODEL_ID="${PROVIDER}/${MODEL}"       # OpenClaw 的 model id 形如 provider/model
# ────────────────────────────────────────────────────────

command -v openclaw >/dev/null 2>&1 || { echo "❌ 未找到 openclaw CLI（需在装了 OpenClaw 的机器执行）"; exit 1; }

# provider 配置（schema 校验过的结构：baseUrl/apiKey/auth/api + models 数组）
JSON="{\"baseUrl\":\"${BASE_URL}\",\"apiKey\":\"${API_KEY}\",\"auth\":\"api-key\",\"api\":\"openai-completions\",\"models\":[{\"id\":\"${MODEL}\",\"name\":\"${MODEL}\"}]}"

echo "🔧 写入 provider ${PROVIDER}（${MODEL} @ ${BASE_URL}）..."
openclaw config set "models.providers.${PROVIDER}" "${JSON}" --strict-json --merge

echo "🎯 选中默认模型 ${MODEL_ID}..."
openclaw models set "${MODEL_ID}"

echo "🔄 重启 gateway 让变更生效..."
openclaw gateway restart

echo "── 当前模型状态 ──"
openclaw models status 2>/dev/null || true

echo
echo "✅ 已把 OpenClaw 切到: ${MODEL_ID} @ ${BASE_URL}"
echo "🔑 没有 Key? 在 https://octer.ai/workspace → Me → Settings → API Keys 创建"
