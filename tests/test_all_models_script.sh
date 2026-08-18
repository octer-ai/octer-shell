#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/octer-all-models-test.XXXXXX")"
trap 'rm -rf -- "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin"

cat > "$TEST_DIR/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
headers=""
body=""
payload=""
endpoint=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -D) headers="$2"; shift 2 ;;
    -o) body="$2"; shift 2 ;;
    -w) shift 2 ;;
    --data-binary) payload="${2#@}"; shift 2 ;;
    http*) endpoint="$1"; shift ;;
    *) shift ;;
  esac
done
printf 'HTTP/1.1 200 OK\r\nx-request-id: mock-request-id\r\n\r\n' > "$headers"
if printf '%s' "$endpoint" | grep -q '/responses$'; then
  printf '%s\n' '{"id":"resp_mock","object":"response","output":[]}' > "$body"
elif grep -q '"stream":true' "$payload" && grep -q '"tools"' "$payload"; then
  printf '%s\n' \
    'data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"name":"ping","arguments":"{}"}}]}}]}' \
    'data: [DONE]' > "$body"
elif grep -q '"stream":true' "$payload"; then
  printf '%s\n' \
    'data: {"choices":[{"index":0,"delta":{"content":"OK"}}]}' \
    'data: [DONE]' > "$body"
elif grep -q '"tools"' "$payload"; then
  printf '%s\n' '{"choices":[{"index":0,"message":{"role":"assistant","tool_calls":[{"id":"call_mock","type":"function","function":{"name":"ping","arguments":"{}"}}]},"finish_reason":"tool_calls"}]}' > "$body"
else
  printf '%s\n' '{"choices":[{"index":0,"message":{"role":"assistant","content":"OK"},"finish_reason":"stop"}]}' > "$body"
fi
printf '200'
MOCK
chmod +x "$TEST_DIR/bin/curl"

OUTPUT="$TEST_DIR/output.txt"
PATH="$TEST_DIR/bin:$PATH" \
  OCTER_MODELS='model-a,model-b' \
  OCTER_EXTENDED=1 \
  "$REPO_DIR/test-all-models.sh" 'evo_abcdefghijklmnopqrstuvwxyz' 'https://example.test/v1' > "$OUTPUT"

grep -q 'model-a' "$OUTPUT"
grep -q 'model-b' "$OUTPUT"
grep -q 'request-id=mock-request-id' "$OUTPUT"
grep -q '结果: PASS=12  FAIL=0  TOTAL=12' "$OUTPUT"

python3 - "$REPO_DIR" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
pattern = re.compile(r'^(?:  )?"([^"\n]+)"$', re.MULTILINE)

def models(path, variable):
    text = path.read_text(encoding="utf-8")
    block = re.search(rf'{variable}=\(\n(.*?)\n\)', text, re.DOTALL)
    if not block:
        raise SystemExit(f"missing {variable} in {path.name}")
    return pattern.findall(block.group(1))

configured = models(root / "set-hermes-model.sh", "MODELS")
tested = models(root / "test-all-models.sh", "DEFAULT_MODELS")
if configured != tested:
    raise SystemExit(f"model lists differ: configured={configured!r}, tested={tested!r}")
PY

if "$REPO_DIR/test-all-models.sh" '' >/dev/null 2>&1; then
  echo 'missing API key should fail' >&2
  exit 1
fi
if OCTER_MODELS=', ,' "$REPO_DIR/test-all-models.sh" 'evo_abcdefghijklmnopqrstuvwxyz' >/dev/null 2>&1; then
  echo 'empty model list should fail' >&2
  exit 1
fi

echo 'test_all_models_script: PASS'
