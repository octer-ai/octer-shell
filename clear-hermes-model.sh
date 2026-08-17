#!/usr/bin/env bash
# Remove the Octer model/provider configuration from Hermes Agent.
set -euo pipefail

command -v hermes >/dev/null 2>&1 || { echo "❌ 未找到 hermes CLI（需在 hermes 所在机器执行）"; exit 1; }

CFG="$(hermes config path)"
ENVF="$(hermes config env-path)"
HERMES_HOME="$(dirname "$CFG")"
echo "config: $CFG"
echo "env:    $ENVF"

PY=""
for cand in \
  "$HERMES_HOME/hermes-agent/venv/bin/python" \
  "$HERMES_HOME/hermes-agent/venv/bin/python3" \
  python3 python; do
  [ -n "$cand" ] || continue
  if "$cand" -c "import yaml" >/dev/null 2>&1; then PY="$cand"; break; fi
done
[ -n "$PY" ] || { echo "❌ 找不到带 PyYAML 的 Python"; exit 1; }

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

download_helper() {
  local target="$1"
  local primary="https://raw.githubusercontent.com/octer-ai/octer-shell/refs/heads/master/hermes_config.py"
  local mirror="https://cdn.jsdelivr.net/gh/octer-ai/octer-shell@master/hermes_config.py"
  local override="${OCTER_HERMES_CONFIG_URL:-}"
  local connect_timeout="${OCTER_DOWNLOAD_CONNECT_TIMEOUT:-8}"
  local max_time="${OCTER_DOWNLOAD_MAX_TIME:-20}"
  local retries="${OCTER_DOWNLOAD_RETRIES:-1}"
  local urls=()
  local url

  [ -n "$override" ] && urls+=("$override")
  [ "$override" = "$primary" ] || urls+=("$primary")
  [ "$override" = "$mirror" ] || urls+=("$mirror")

  for url in "${urls[@]}"; do
    if curl -fsSL --proto '=https' --tlsv1.2 \
      --connect-timeout "$connect_timeout" \
      --max-time "$max_time" \
      --retry "$retries" --retry-delay 1 \
      "$url" -o "$target"; then
      return 0
    fi
    echo "⚠️  当前下载源不可用，尝试备用地址..." >&2
  done
  return 1
}

SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [ -n "$SCRIPT_SOURCE" ] && [ -f "$SCRIPT_SOURCE" ]; then
  SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$SCRIPT_SOURCE")" && pwd)"
  [ -f "$SCRIPT_DIR/hermes_config.py" ] && HELPER="$SCRIPT_DIR/hermes_config.py"
fi

if [ -z "$HELPER" ]; then
  command -v curl >/dev/null 2>&1 || {
    echo "❌ curl 管道清理需要 curl 来下载共享配置器" >&2
    exit 1
  }
  TEMP_HELPER="$(mktemp "${TMPDIR:-/tmp}/octer-hermes-config.XXXXXX")"
  echo "⬇️  下载共享配置器..."
  if ! download_helper "$TEMP_HELPER"; then
    echo "❌ 共享配置器下载失败；请检查网络后重试" >&2
    exit 1
  fi
  HELPER="$TEMP_HELPER"
fi

"$PY" -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), filename=sys.argv[1])' "$HELPER"

"$PY" "$HELPER" clear --config "$CFG" --env "$ENVF"

echo "🔄 完整重载 Hermes Gateway..."
hermes gateway stop || true
hermes gateway start
hermes gateway status

echo "当前配置："
hermes config show | grep -iE "provider|model|reasoning|octer" || true
echo "✅ 清除完成。如需恢复 Octer 模型，重新运行 ./set-hermes-model.sh <API_KEY>"
