#!/usr/bin/env bash
# 把 OpenClaw 切换到 Octer 自定义大模型（OpenAI 兼容接口）。比照 set-hermes-model.sh。
# 用法: ./set-openclaw-model.sh <API_KEY>
#
# ⚠️ 占位说明：本机未安装 openclaw，其「自定义模型」的确切 config key 尚未最终确认。
#    下面 model.* 路径是按 Hermes 模式的推测；若 OpenClaw 实际 schema 不同
#    （例如 providers.octer.* / llm.*），只改这几行 config set 即可，其余逻辑通用。
set -euo pipefail

API_KEY="${1:?用法: $0 <API_KEY>}"

# ── 固定部分 ────────────────────────────────────────────
SLUG="octer"
BASE_URL="https://octer.ai/api/llm"   # 接口地址（OpenAI 兼容）
MODEL="Octer-1.0-lite"                # 模型名称
# ────────────────────────────────────────────────────────

command -v openclaw >/dev/null 2>&1 || { echo "❌ 未找到 openclaw CLI（需在装了 OpenClaw 的机器执行）"; exit 1; }

echo "🔧 写入自定义模型配置..."
openclaw config set model.provider "${SLUG}"
openclaw config set model.baseURL  "${BASE_URL}"
openclaw config set model.apiKey   "${API_KEY}"
openclaw config set model.model    "${MODEL}"

echo "🔄 重启 gateway 让变更生效..."
openclaw gateway restart

echo "── 当前配置 ──"
openclaw config get model 2>/dev/null || true

echo
echo "✅ 已把 OpenClaw 切到: ${SLUG} → ${MODEL} @ ${BASE_URL}"
echo "🔑 没有 Key? 在 https://octer.ai/workspace → Me → Settings → API Keys 创建"
