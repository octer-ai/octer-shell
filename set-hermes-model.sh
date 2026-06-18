#!/usr/bin/env bash
# 配置 Hermes Agent 使用 Octer 自定义大模型，并选中它。
# 用法: ./set-hermes-model.sh <API_KEY>
#
# 关键：Hermes 取凭证时只认「命名的 custom provider」(custom_providers 列表条目)，
# 光设 model.* 会报 "No LLM provider configured"。本脚本按 hermes 自己 _save_custom_provider
# 的结构，往 config.yaml 写 custom_providers 列表条目 + model 块。
set -euo pipefail

API_KEY="${1:?用法: $0 <API_KEY>}"

# ── 固定部分 ────────────────────────────────────────────
NAME="Octer"
BASE_URL="https://octer.ai/api/llm"   # 接口地址（正式）
MODEL="Octer-1.0-lite"                # 模型名称
MAX_TOKENS="65536"
# ────────────────────────────────────────────────────────

command -v hermes >/dev/null 2>&1 || { echo "❌ 未找到 hermes CLI（需在装了 hermes 的机器执行）"; exit 1; }

CFG="$(hermes config path)"
echo "config: $CFG"
[ -f "$CFG" ] && cp -f "$CFG" "${CFG}.bak.$(date +%s)"

API_KEY="$API_KEY" NAME="$NAME" BASE_URL="$BASE_URL" MODEL="$MODEL" MAX_TOKENS="$MAX_TOKENS" \
python3 - "$CFG" <<'PY'
import os, sys, yaml
path = sys.argv[1]
try:
    with open(path) as f:
        cfg = yaml.safe_load(f) or {}
except FileNotFoundError:
    cfg = {}

NAME = os.environ["NAME"]
BASE = os.environ["BASE_URL"].rstrip("/")
KEY  = os.environ["API_KEY"]
MODEL = os.environ["MODEL"]
MAXT = int(os.environ["MAX_TOKENS"])

# 1) custom_providers 列表条目（按 base_url 去重，命中则更新）
cps = cfg.get("custom_providers")
if not isinstance(cps, list):
    cps = []
entry = None
for e in cps:
    if isinstance(e, dict) and str(e.get("base_url", "")).rstrip("/") == BASE:
        entry = e; break
if entry is None:
    entry = {}
    cps.append(entry)
entry.update({"name": NAME, "base_url": BASE, "api_key": KEY, "model": MODEL})
cfg["custom_providers"] = cps

# 2) model 块：选中该 custom 端点
m = cfg.get("model")
if not isinstance(m, dict):
    m = {}
m.update({
    "provider": "custom",
    "base_url": BASE,
    "default": MODEL,
    "api_key": KEY,
    "max_tokens": MAXT,
})
cfg["model"] = m

# 3) Octer 不支持 fast 模式 —— 关闭 reasoning
a = cfg.get("agent")
if not isinstance(a, dict):
    a = {}
a["reasoning_effort"] = "none"
cfg["agent"] = a

with open(path, "w") as f:
    yaml.safe_dump(cfg, f, allow_unicode=True, sort_keys=False)
print("✅ config.yaml 已写入 custom_providers[Octer] + model 块")
PY

echo "✅ 已配置并选中: ${NAME} → ${MODEL} @ ${BASE_URL}（已关闭 fast/reasoning）"

# ── 启用：启动/刷新 gateway 让新模型生效 ─────────────────
echo "🔄 启动 hermes gateway..."
hermes gateway start
hermes gateway status

echo "── 当前配置 ──"
hermes config show | grep -iE "Model:|provider|reasoning" || true

echo
echo "🧪 自测一次: hermes -z \"你好\""
hermes -z "你好" || echo "⚠️ 自测失败，检查 API Key / base_url（hermes config show）"
