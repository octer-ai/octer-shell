#!/usr/bin/env bash
# 清除 set-hermes-model.sh 写入的 Octer 自定义大模型配置，恢复到 Hermes 默认。
# hermes 没有 config unset/remove，配置在 ~/.hermes/config.yaml，只能直接改文件。
# 用法: ./clear-hermes-model.sh
set -euo pipefail

PROVIDER_ID="octer"
API_KEY_ENV="OCTER_LLM_API_KEY"

command -v hermes >/dev/null 2>&1 || { echo "❌ 未找到 hermes CLI（需在 hermes 所在机器执行）"; exit 1; }

CFG="$(hermes config path)"
ENVF="$(hermes config env-path)"
echo "config: $CFG"
echo "env:    $ENVF"

# ── 1) 从 config.yaml 删掉 octer provider / model 选择 / reasoning_effort ──
if [ -f "$CFG" ]; then
  cp -f "$CFG" "${CFG}.bak.$(date +%s)"
  python3 - "$CFG" "$PROVIDER_ID" <<'PY'
import sys, yaml
path, pid = sys.argv[1], sys.argv[2]
with open(path) as f:
    cfg = yaml.safe_load(f) or {}

cp = cfg.get("custom_providers")
if isinstance(cp, dict):
    cp.pop(pid, None)
    if not cp:
        cfg.pop("custom_providers", None)

m = cfg.get("model")
if isinstance(m, dict):
    for k in ("provider", "custom_provider_id", "default"):
        m.pop(k, None)
    if not m:
        cfg.pop("model", None)

a = cfg.get("agent")
if isinstance(a, dict):
    a.pop("reasoning_effort", None)
    if not a:
        cfg.pop("agent", None)

with open(path, "w") as f:
    yaml.safe_dump(cfg, f, allow_unicode=True, sort_keys=False)
print("✅ config.yaml 已清除 custom_providers.%s / model.* / agent.reasoning_effort" % pid)
PY
else
  echo "⚠️ 未找到 $CFG，跳过 config 清理"
fi

# ── 2) 从 .env 删掉 API Key ──
if [ -f "$ENVF" ] && grep -q "^${API_KEY_ENV}=" "$ENVF"; then
  sed -i.bak "/^${API_KEY_ENV}=/d" "$ENVF"
  echo "✅ 已从 .env 移除 ${API_KEY_ENV}"
else
  echo "ℹ️ .env 中无 ${API_KEY_ENV}，跳过"
fi

# ── 3) 重启 gateway 让变更生效 ──
echo "🔄 重启 hermes gateway..."
hermes gateway start
hermes gateway status

echo "当前配置（grep model）："
hermes config show | grep -iE "provider|model|reasoning" || true
echo "✅ 清除完成。如需恢复 Octer 模型，重新跑 ./set-hermes-model.sh <API_KEY>"
