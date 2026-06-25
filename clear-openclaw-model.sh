#!/usr/bin/env bash
# 清除 OpenClaw 里的 Octer 自定义模型 provider，恢复到默认。比照 clear-hermes-model.sh。
# set-openclaw-model.sh 写的是 models.providers.octer；本脚本用 openclaw config unset 删掉它。
# 用法: ./clear-openclaw-model.sh
set -euo pipefail

PROVIDER="octer"

command -v openclaw >/dev/null 2>&1 || { echo "❌ 未找到 openclaw CLI（需在装了 OpenClaw 的机器执行）"; exit 1; }

echo "🧹 删除 provider models.providers.${PROVIDER}..."
openclaw config unset "models.providers.${PROVIDER}" || echo "ℹ️ 未发现该 provider（可能已清除）"

echo "🔄 重启 gateway 让变更生效..."
openclaw gateway restart || true

echo "── 当前模型状态 ──"
openclaw models status 2>/dev/null || true

echo
echo "✅ 清除完成。若默认模型原来指向 ${PROVIDER}，请重新选: openclaw models set <model>（或 openclaw onboard）"
echo "   想恢复 Octer 模型，重新跑 ./set-openclaw-model.sh <API_KEY>"
