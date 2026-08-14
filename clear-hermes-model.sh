#!/usr/bin/env bash
# Remove the Octer model/provider configuration from Hermes Agent.
set -euo pipefail

command -v hermes >/dev/null 2>&1 || { echo "❌ 未找到 hermes CLI（需在 hermes 所在机器执行）"; exit 1; }

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
HELPER="$SCRIPT_DIR/hermes_config.py"
[ -f "$HELPER" ] || { echo "❌ 缺少共享配置器: $HELPER"; exit 1; }

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

"$PY" "$HELPER" clear --config "$CFG" --env "$ENVF"

echo "🔄 完整重载 Hermes Gateway..."
hermes gateway stop || true
hermes gateway start
hermes gateway status

echo "当前配置："
hermes config show | grep -iE "provider|model|reasoning|octer" || true
echo "✅ 清除完成。如需恢复 Octer 模型，重新运行 ./set-hermes-model.sh <API_KEY>"
