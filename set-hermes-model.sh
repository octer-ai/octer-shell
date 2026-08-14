#!/usr/bin/env bash
# Configure Hermes Agent to use the Octer OpenAI-compatible Responses API.
# Usage: ./set-hermes-model.sh <API_KEY> [MODEL] [BASE_URL]
set -euo pipefail

API_KEY="${1:?用法: $0 <API_KEY> [MODEL] [BASE_URL]}"
if ! printf '%s' "$API_KEY" | grep -qE '^evo_[A-Za-z0-9]{26,}$'; then
  echo "❌ API Key 必须以 evo_ 开头，且长度至少 30 个字符" >&2
  exit 2
fi

NAME="Octer"
BASE_URL="${3:-https://oclaw.octer.ai/v1}"
MAX_TOKENS="65536"
MODELS=(
  "gpt-5.5"
  "gpt-5.6-sol"
  "gpt-5.6-terra"
  "gpt-5.6-luna"
  "claude-opus-4-8"
  "gemini-3.1-pro-preview"
  "gemini-3-flash-preview"
  "gemini-3.5-flash"
  "deepseek-v4-flash"
  "deepseek-v4-pro"
  "glm-5.2"
)
DEFAULT_MODEL="${MODELS[0]}"

select_model() {
  if [ "${1:-}" != "" ]; then
    MODEL="$1"
    local in_list=0 m
    for m in "${MODELS[@]}"; do [ "$m" = "$MODEL" ] && in_list=1 && break; done
    [ "$in_list" -eq 1 ] || echo "⚠️ '$MODEL' 不在内置列表里，仍按你指定的使用。"
    return
  fi
  if [ ! -t 0 ]; then
    MODEL="$DEFAULT_MODEL"
    echo "（非交互环境，未传 MODEL，使用默认 ${MODEL}）"
    return
  fi
  echo "请选择要使用的模型（直接回车用默认 ${DEFAULT_MODEL}）："
  local i=1 m choice=""
  for m in "${MODELS[@]}"; do
    if [ "$m" = "$DEFAULT_MODEL" ]; then printf "  %d) %s（默认）\n" "$i" "$m"
    else printf "  %d) %s\n" "$i" "$m"; fi
    i=$((i+1))
  done
  printf "输入编号 [1-%d]: " "${#MODELS[@]}"
  read -r choice || true
  if [ -z "$choice" ]; then
    MODEL="$DEFAULT_MODEL"
  elif printf '%s' "$choice" | grep -qE '^[0-9]+$' && [ "$choice" -ge 1 ] && [ "$choice" -le "${#MODELS[@]}" ]; then
    MODEL="${MODELS[$((choice-1))]}"
  else
    echo "⚠️ 无效输入 '$choice'，使用默认 ${DEFAULT_MODEL}"
    MODEL="$DEFAULT_MODEL"
  fi
}

select_model "${2:-}"
echo "→ 选定模型: ${MODEL}"

command -v hermes >/dev/null 2>&1 || { echo "❌ 未找到 hermes CLI（需在装了 hermes 的机器执行）"; exit 1; }

CFG="$(hermes config path)"
ENVF="$(hermes config env-path)"
HERMES_BIN="$(command -v hermes)"
HERMES_HOME="$(dirname "$CFG")"
echo "config: $CFG"
echo "env:    $ENVF"

HERMES_DIR="$(dirname "$HERMES_BIN")"
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
  echo "❌ 找不到带 PyYAML 的 Python；请先修复 Hermes 自带 venv" >&2
  exit 1
fi
echo "python: $PY"

# In a repository checkout the helper lives beside this script. When the
# script is piped to Bash there is no script file, so download the helper to a
# temporary path and remove it automatically on exit.
HELPER=""
TEMP_HELPER=""
cleanup_temp_helper() {
  if [ -n "$TEMP_HELPER" ] && [ -f "$TEMP_HELPER" ]; then
    rm -f -- "$TEMP_HELPER"
  fi
}
trap cleanup_temp_helper EXIT

SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [ -n "$SCRIPT_SOURCE" ] && [ -f "$SCRIPT_SOURCE" ]; then
  SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd)"
  [ -f "$SCRIPT_DIR/hermes_config.py" ] && HELPER="$SCRIPT_DIR/hermes_config.py"
fi

if [ -z "$HELPER" ]; then
  command -v curl >/dev/null 2>&1 || {
    echo "❌ curl 管道安装需要 curl 来下载共享配置器" >&2
    exit 1
  }
  HELPER_URL="${OCTER_HERMES_CONFIG_URL:-https://raw.githubusercontent.com/octer-ai/octer-shell/refs/heads/master/hermes_config.py}"
  TEMP_HELPER="$(mktemp "${TMPDIR:-/tmp}/octer-hermes-config.XXXXXX")"
  echo "⬇️  下载共享配置器..."
  curl -fsSL --proto '=https' --tlsv1.2 "$HELPER_URL" -o "$TEMP_HELPER"
  HELPER="$TEMP_HELPER"
fi

"$PY" -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), filename=sys.argv[1])' "$HELPER"

MODELS_CSV="$(IFS=,; printf '%s' "${MODELS[*]}")"
printf '%s' "$API_KEY" | "$PY" "$HELPER" set \
  --config "$CFG" \
  --env "$ENVF" \
  --base-url "$BASE_URL" \
  --model "$MODEL" \
  --models-csv "$MODELS_CSV" \
  --max-tokens "$MAX_TOKENS"

echo "✅ 已配置 ${NAME} → ${MODEL}（Responses API）"

# If the optional Octer WebSocket platform plugin is installed, validate and
# re-enable it. Hermes plugins are opt-in after upgrades.
if [ -f "$HERMES_HOME/plugins/platforms/octer/plugin.yaml" ]; then
  echo "🔌 检查已安装的 Octer 平台插件..."
  hermes plugins doctor platforms/octer
  hermes plugins enable platforms/octer </dev/null
fi

# A detached gateway can block a service-managed start. Stop first so the new
# config and .env are always loaded by a clean, supervised process.
echo "🔄 完整重载 Hermes Gateway..."
hermes gateway stop || true
hermes gateway start
hermes gateway status

echo "── 当前配置 ──"
hermes config show | grep -iE "Model:|provider|reasoning" || true

echo
echo "🧪 自测（最多 60s）: hermes -z \"请只回复 OK\""
"$PY" "$HELPER" self-test --hermes-bin "$HERMES_BIN" --timeout 60
echo "✅ Hermes + Octer Responses API 自测通过"
