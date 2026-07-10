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
BASE_URL="https://oclaw.octer.ai/v1"  # 接口地址（正式）
MODEL="gpt-5.5"                       # 模型名称
MAX_TOKENS="65536"
# ────────────────────────────────────────────────────────

command -v hermes >/dev/null 2>&1 || { echo "❌ 未找到 hermes CLI（需在装了 hermes 的机器执行）"; exit 1; }

CFG="$(hermes config path)"
echo "config: $CFG"
[ -f "$CFG" ] && cp -f "$CFG" "${CFG}.bak.$(date +%s)"

# 选一个带 pyyaml 的 python（系统 python3 常常没装；hermes 自己的 venv 一定有）。
HERMES_BIN="$(command -v hermes)"
HERMES_DIR="$(dirname "$HERMES_BIN")"
HERMES_HOME="$(dirname "$CFG")"                       # 通常是 ~/.hermes
HERMES_PY_SHEBANG="$(head -1 "$HERMES_BIN" 2>/dev/null | sed 's|^#!||' | awk '{print $1}')"
PY=""
for cand in \
  "$HERMES_HOME/hermes-agent/venv/bin/python" \
  "$HERMES_HOME/hermes-agent/venv/bin/python3" \
  "$HERMES_PY_SHEBANG" "$HERMES_DIR/python" "$HERMES_DIR/python3" \
  python3 python; do
  [ -n "$cand" ] || continue
  if "$cand" -c "import yaml" >/dev/null 2>&1; then PY="$cand"; break; fi
done
if [ -z "$PY" ]; then
  # 兜底：给系统 python3 装 pyyaml（--user，无需 sudo）
  echo "⚠️ 未找到带 pyyaml 的 python，尝试 pip 安装..."
  python3 -m pip install --user pyyaml >/dev/null 2>&1 && python3 -c "import yaml" >/dev/null 2>&1 && PY="python3"
fi
[ -n "$PY" ] || { echo "❌ 仍找不到带 pyyaml 的 python。手动装一个再重试，例如: python3 -m pip install pyyaml"; exit 1; }
echo "python: $PY"

# provider slug = 名字归一化（小写、空格转 -），custom provider 解析按它匹配
SLUG="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"

API_KEY="$API_KEY" NAME="$NAME" SLUG="$SLUG" BASE_URL="$BASE_URL" MODEL="$MODEL" MAX_TOKENS="$MAX_TOKENS" \
"$PY" - "$CFG" <<'PY'
import os, sys, yaml
path = sys.argv[1]
try:
    with open(path) as f:
        cfg = yaml.safe_load(f) or {}
except FileNotFoundError:
    cfg = {}

NAME = os.environ["NAME"]
SLUG = os.environ["SLUG"]
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
    "provider": SLUG,        # 关键：按 provider slug 匹配命名 custom provider，而非字面量 "custom"
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
echo "🧪 自测(最多等 60s): hermes -z \"你好\""
TIMEOUT_BIN=""
command -v timeout  >/dev/null 2>&1 && TIMEOUT_BIN=timeout
command -v gtimeout >/dev/null 2>&1 && TIMEOUT_BIN=gtimeout
if [ -n "$TIMEOUT_BIN" ]; then
  "$TIMEOUT_BIN" 60 hermes -z "你好" \
    || echo "⚠️ 自测超时/失败。配置已写好；卡住多半是端点没响应，手动排查见下方提示。"
else
  echo "（本机无 timeout 命令，跳过自动自测）手动测: hermes -z \"你好\"（卡住可 Ctrl-C）"
fi
echo
echo "若 hermes -z 一直卡住，直接 curl 端点看是不是端点本身的问题："
echo "  curl -sS ${BASE_URL}/chat/completions \\"
echo "    -H \"Authorization: Bearer <KEY>\" -H \"Content-Type: application/json\" \\"
echo "    -d '{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"你好\"}]}'"
