#!/usr/bin/env bash
# 清除 OpenClaw 里的 Octer 自定义大模型配置，恢复到默认。比照 clear-hermes-model.sh。
# OpenClaw 配置在 ~/.openclaw/openclaw.json；set-openclaw-model.sh 写的是
#   model.provider / model.baseURL / model.apiKey / model.model。
# 本脚本在 model.baseURL 命中 octer 时，把这些 octer 相关项清掉，保留其它配置。
#
# ⚠️ 占位说明：编写机器上未安装 openclaw，确切 config key 以实际 schema 为准；
#    若不是 model.*（如 providers.octer.* / llm.*），只改下面 python 里的 KEY 判断即可，其余逻辑通用。
#
# 用法: ./clear-openclaw-model.sh
set -euo pipefail

command -v openclaw >/dev/null 2>&1 || { echo "❌ 未找到 openclaw CLI（需在装了 OpenClaw 的机器执行）"; exit 1; }

CFG="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"
echo "config: $CFG"

# ── 1) 改 openclaw.json（python 安全改写 + 备份）──
if [ -f "$CFG" ]; then
  cp -f "$CFG" "${CFG}.bak.$(date +%s)"
  python3 - "$CFG" <<'PY'
import sys, json
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    cfg = json.load(f)

m = cfg.get("model")
if isinstance(m, dict):
    blob = (str(m.get("baseURL", "")) + str(m.get("base_url", "")) + str(m.get("provider", ""))).lower()
    if "octer" in blob:
        for k in ("provider", "baseURL", "base_url", "apiKey", "api_key", "model"):
            m.pop(k, None)
        print("✅ openclaw.json 已清除 model.* 里的 Octer 配置")
    else:
        print("ℹ️ model.* 未指向 octer，未改动")
    if not m:
        cfg.pop("model", None)
else:
    print("ℹ️ 未发现 model.* 配置，跳过")

with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
PY
else
  echo "⚠️ 未找到 $CFG，跳过 config 清理"
fi

# ── 2) 重启 gateway 让变更生效 ──
echo "🔄 重启 openclaw gateway..."
openclaw gateway restart || true

echo "── 当前配置 ──"
openclaw config get model 2>/dev/null || true

echo
echo "✅ 清除完成。重新选模型: openclaw onboard（或 openclaw setup）"
echo "   想恢复 Octer 模型，重新跑 ./set-openclaw-model.sh <API_KEY>"
