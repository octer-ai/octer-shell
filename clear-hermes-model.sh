#!/usr/bin/env bash
# 清除 Hermes Agent 里的 Octer 自定义大模型配置，恢复到默认。
# hermes 没有 config unset/remove，配置在 ~/.hermes/config.yaml，只能直接改文件。
#
# 实际配置可能落在两处（取决于是 set-hermes-model.sh 还是手动/setup 写的）：
#   model.base_url / model.max_tokens（模型覆盖，指向 *.octer.ai/api/llm）
#   providers.<name>（api 指向 octer 的 provider，含 api_key/default_model）
#   custom_providers.octer（set 脚本旧写法）
# 本脚本把以上 octer 相关项全部清掉，保留 qwen 等其它 provider。
#
# 用法: ./clear-hermes-model.sh
set -euo pipefail

command -v hermes >/dev/null 2>&1 || { echo "❌ 未找到 hermes CLI（需在 hermes 所在机器执行）"; exit 1; }

CFG="$(hermes config path)"
ENVF="$(hermes config env-path 2>/dev/null || true)"
echo "config: $CFG"
[ -n "${ENVF:-}" ] && echo "env:    $ENVF"

# ── 1) 改 config.yaml（python 安全改写 + 备份）──
if [ -f "$CFG" ]; then
  cp -f "$CFG" "${CFG}.bak.$(date +%s)"
  python3 - "$CFG" <<'PY'
import sys, yaml
path = sys.argv[1]
with open(path) as f:
    cfg = yaml.safe_load(f) or {}

def is_octer(v):
    if isinstance(v, dict):
        blob = (str(v.get("api","")) + str(v.get("base_url","")) + str(v.get("name",""))).lower()
        return "octer" in blob
    return False

# 1. model 顶层覆盖：base_url 指向 octer 时清掉模型覆盖键
m = cfg.get("model")
if isinstance(m, dict):
    if "octer" in str(m.get("base_url","")).lower():
        for k in ("base_url","max_tokens","provider","custom_provider_id","default","api_key","model"):
            m.pop(k, None)
    if not m:
        cfg.pop("model", None)

# 2. providers / custom_providers 里 octer 相关条目整块删除（按 key 名或 api 命中）
for section in ("providers","custom_providers"):
    d = cfg.get(section)
    if isinstance(d, dict):
        for name in [k for k,v in list(d.items()) if "octer" in str(k).lower() or is_octer(v)]:
            d.pop(name, None)
            print(f"  removed {section}.{name}")
        if not d:
            cfg.pop(section, None)

# 3. agent.reasoning_effort 覆盖（set 脚本会设 none）
a = cfg.get("agent")
if isinstance(a, dict):
    a.pop("reasoning_effort", None)

with open(path, "w") as f:
    yaml.safe_dump(cfg, f, allow_unicode=True, sort_keys=False)
print("✅ config.yaml 已清除 octer 模型 / provider 相关配置")
PY
else
  echo "⚠️ 未找到 $CFG，跳过 config 清理"
fi

# ── 2) 从 .env 删掉 set 脚本写的 API Key（如有）──
if [ -n "${ENVF:-}" ] && [ -f "$ENVF" ] && grep -q "^OCTER_LLM_API_KEY=" "$ENVF"; then
  sed -i.bak "/^OCTER_LLM_API_KEY=/d" "$ENVF"
  echo "✅ 已从 .env 移除 OCTER_LLM_API_KEY"
fi

# ── 3) 重启 gateway 让变更生效 ──
echo "🔄 重启 hermes gateway..."
hermes gateway start
hermes gateway status

echo "当前配置（grep model）："
hermes config show | grep -iE "provider|model|reasoning|octer" || true
echo
echo "验证: hermes chat（进入后输入“你好”），或一次性: hermes -z \"你好\""
echo "✅ 清除完成。如需恢复 Octer 模型，重新跑 ./set-hermes-model.sh <API_KEY>"
