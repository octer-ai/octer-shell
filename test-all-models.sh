#!/usr/bin/env bash
# Test every model exposed by the Octer Hermes configuration.
# Usage: ./test-all-models.sh <API_KEY> [BASE_URL]
set -uo pipefail

DEFAULT_BASE_URL="https://oclaw.octer.ai/v1"
DEFAULT_MODELS=(
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

usage() {
  cat <<'EOF'
用法:
  ./test-all-models.sh <API_KEY> [BASE_URL]

默认对每个模型测试：
  1. 普通 Chat Completions（非流式）
  2. SSE + function tools（Hermes 关键路径）

环境变量:
  OCTER_API_KEY             API Key，也可代替第一个参数
  OCTER_MODELS              逗号分隔的模型列表，用于只测指定模型
  OCTER_EXTENDED=1          增加非流式工具、普通 SSE、reasoning+工具、Responses 测试
  OCTER_CONNECT_TIMEOUT=10  连接超时秒数
  OCTER_REQUEST_TIMEOUT=120 单次请求总超时秒数
  OCTER_DELAY_SECONDS=0     两次请求之间的等待秒数
  OCTER_KEEP_RESULTS=1      保留响应头、响应体和请求载荷

示例:
  ./test-all-models.sh evo_xxx
  OCTER_MODELS='gpt-5.5,glm-5.2' ./test-all-models.sh evo_xxx
  OCTER_EXTENDED=1 ./test-all-models.sh evo_xxx
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

API_KEY="${1:-${OCTER_API_KEY:-}}"
BASE_URL="${2:-${OCTER_BASE_URL:-$DEFAULT_BASE_URL}}"
BASE_URL="${BASE_URL%/}"
CONNECT_TIMEOUT="${OCTER_CONNECT_TIMEOUT:-10}"
REQUEST_TIMEOUT="${OCTER_REQUEST_TIMEOUT:-120}"
DELAY_SECONDS="${OCTER_DELAY_SECONDS:-0}"
EXTENDED="${OCTER_EXTENDED:-0}"
KEEP_RESULTS="${OCTER_KEEP_RESULTS:-0}"

if [ -z "$API_KEY" ]; then
  usage >&2
  echo "❌ 缺少 API Key" >&2
  exit 2
fi
if ! printf '%s' "$API_KEY" | grep -qE '^evo_[A-Za-z0-9]{26,}$'; then
  echo "❌ API Key 必须以 evo_ 开头，且长度至少 30 个字符" >&2
  exit 2
fi
command -v curl >/dev/null 2>&1 || { echo "❌ 未找到 curl" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "❌ 未找到 python3" >&2; exit 1; }

MODELS=("${DEFAULT_MODELS[@]}")
if [ -n "${OCTER_MODELS:-}" ]; then
  IFS=',' read -r -a MODELS <<< "$OCTER_MODELS"
fi
CLEAN_MODELS=()
for model in "${MODELS[@]}"; do
  model="$(printf '%s' "$model" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [ -n "$model" ] && CLEAN_MODELS+=("$model")
done
MODELS=("${CLEAN_MODELS[@]}")
if [ "${#MODELS[@]}" -eq 0 ]; then
  echo "❌ 模型列表为空" >&2
  exit 2
fi

CASES=("chat-basic" "chat-stream-tool")
if [ "$EXTENDED" = "1" ]; then
  CASES=(
    "chat-basic"
    "chat-tool"
    "chat-stream"
    "chat-stream-tool"
    "chat-reasoning-tool"
    "responses-basic"
  )
fi

RESULT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/octer-model-test.XXXXXX")" || exit 1
SUMMARY_FILE="$RESULT_DIR/summary.tsv"
: > "$SUMMARY_FILE"

cleanup() {
  if [ "$KEEP_RESULTS" = "1" ]; then
    echo "📁 测试原始结果: $RESULT_DIR"
  elif [ -n "$RESULT_DIR" ] && [ -d "$RESULT_DIR" ]; then
    rm -rf -- "$RESULT_DIR"
  fi
}
trap cleanup EXIT INT TERM

case_label() {
  case "$1" in
    chat-basic) echo "Chat" ;;
    chat-tool) echo "Tools" ;;
    chat-stream) echo "SSE" ;;
    chat-stream-tool) echo "SSE+Tools" ;;
    chat-reasoning-tool) echo "Reason+Tools" ;;
    responses-basic) echo "Responses" ;;
  esac
}

build_payload() {
  local model="$1" test_case="$2" output="$3"
  python3 - "$model" "$test_case" > "$output" <<'PY'
import json
import sys

model, case = sys.argv[1:3]
tool = {
    "type": "function",
    "function": {
        "name": "ping",
        "description": "Return pong. Always call this function.",
        "parameters": {"type": "object", "properties": {}, "additionalProperties": False},
    },
}

if case == "responses-basic":
    payload = {"model": model, "input": "请只回复 OK", "max_output_tokens": 32}
else:
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": "请只回复 OK"}],
        "max_tokens": 64,
    }
    if case in ("chat-tool", "chat-stream-tool", "chat-reasoning-tool"):
        payload["messages"][0]["content"] = "请调用 ping 函数，不要直接回答。"
        payload["tools"] = [tool]
        payload["tool_choice"] = {"type": "function", "function": {"name": "ping"}}
    if case in ("chat-stream", "chat-stream-tool"):
        payload["stream"] = True
    if case == "chat-reasoning-tool":
        payload["reasoning_effort"] = "medium"

json.dump(payload, sys.stdout, ensure_ascii=False, separators=(",", ":"))
PY
}

parse_result() {
  local test_case="$1" http_code="$2" headers="$3" body="$4" curl_error="$5" output="$6"
  python3 - "$test_case" "$http_code" "$headers" "$body" "$curl_error" > "$output" <<'PY'
import json
import re
import sys

case, http_text, headers_path, body_path, curl_error_path = sys.argv[1:6]
headers = open(headers_path, encoding="utf-8", errors="replace").read()
body = open(body_path, encoding="utf-8", errors="replace").read()
curl_error = open(curl_error_path, encoding="utf-8", errors="replace").read().strip()

request_id = "-"
for pattern in (
    r"(?im)^(?:x-request-id|request-id|cf-ray):\s*([^\r\n]+)",
    r"(?i)request id\s*[:(]\s*([A-Za-z0-9_-]+)",
):
    match = re.search(pattern, headers + "\n" + body)
    if match:
        request_id = match.group(1).strip().rstrip(")")
        break

def clean(value):
    return re.sub(r"\s+", " ", str(value)).strip()[:220] or "-"

def json_error(text):
    try:
        data = json.loads(text)
    except Exception:
        return clean(text)
    error = data.get("error", data) if isinstance(data, dict) else data
    if isinstance(error, dict):
        return clean(error.get("message") or error.get("detail") or error)
    return clean(error)

try:
    http_code = int(http_text or 0)
except ValueError:
    http_code = 0

status, detail = "FAIL", "未知响应"
if curl_error and http_code == 0:
    detail = clean(curl_error)
elif not 200 <= http_code < 300:
    detail = json_error(body) if body else clean(curl_error or f"HTTP {http_code}")
elif case in ("chat-stream", "chat-stream-tool"):
    events, done = [], False
    for line in body.splitlines():
        if not line.startswith("data:"):
            continue
        data = line[5:].strip()
        if data == "[DONE]":
            done = True
            continue
        try:
            events.append(json.loads(data))
        except json.JSONDecodeError:
            pass
    if not events:
        detail = "HTTP 2xx，但没有可解析的 SSE data 事件"
    elif not done:
        detail = "SSE 未收到 [DONE]"
    elif case == "chat-stream":
        status, detail = "PASS", f"{len(events)} 个 SSE 事件"
    else:
        names = {}
        for event in events:
            for choice in event.get("choices", []):
                for call in choice.get("delta", {}).get("tool_calls", []) or []:
                    index = call.get("index", 0)
                    names[index] = names.get(index, "") + call.get("function", {}).get("name", "")
        if "ping" in names.values():
            status, detail = "PASS", "SSE 工具调用 ping"
        else:
            detail = "SSE 成功，但未收到 ping 工具调用"
else:
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        data = None
    if not isinstance(data, dict):
        detail = "HTTP 2xx，但响应不是 JSON 对象"
    elif case == "responses-basic":
        if data.get("object") == "response" or (data.get("id") and "output" in data):
            status, detail = "PASS", "Responses JSON"
        else:
            detail = json_error(body)
    elif not data.get("choices"):
        detail = json_error(body)
    elif case in ("chat-tool", "chat-reasoning-tool"):
        message = data["choices"][0].get("message", {})
        names = [item.get("function", {}).get("name") for item in message.get("tool_calls", []) or []]
        if "ping" in names:
            status, detail = "PASS", "工具调用 ping"
        else:
            detail = "Chat 成功，但未收到 ping 工具调用"
    else:
        status, detail = "PASS", "Chat JSON"

print(status)
print(clean(request_id))
print(clean(detail))
PY
}

total=$(( ${#MODELS[@]} * ${#CASES[@]} ))
current=0
failures=0

echo "Octer 全模型兼容性测试"
echo "接口: $BASE_URL"
echo "模型: ${#MODELS[@]} 个；场景: ${#CASES[@]} 个；请求: $total 次"
echo "API Key: 已读取（不会打印）"
echo

for model in "${MODELS[@]}"; do
  for test_case in "${CASES[@]}"; do
    current=$((current + 1))
    slug="$(printf '%s-%s' "$model" "$test_case" | tr -c 'A-Za-z0-9._-' '_')"
    payload="$RESULT_DIR/$slug.request.json"
    headers="$RESULT_DIR/$slug.headers.txt"
    body="$RESULT_DIR/$slug.body.txt"
    curl_error="$RESULT_DIR/$slug.curl.txt"
    verdict="$RESULT_DIR/$slug.verdict.txt"
    build_payload "$model" "$test_case" "$payload"

    label="$(case_label "$test_case")"
    printf '[%d/%d] %-26s %-12s ' "$current" "$total" "$model" "$label"

    endpoint="$BASE_URL/chat/completions"
    [ "$test_case" = "responses-basic" ] && endpoint="$BASE_URL/responses"
    http_code="$(curl -sS --no-buffer \
      --connect-timeout "$CONNECT_TIMEOUT" \
      --max-time "$REQUEST_TIMEOUT" \
      -D "$headers" -o "$body" -w '%{http_code}' \
      "$endpoint" \
      -H "Authorization: Bearer $API_KEY" \
      -H 'Content-Type: application/json' \
      --data-binary "@$payload" 2> "$curl_error")"
    curl_rc=$?
    [ -f "$headers" ] || : > "$headers"
    [ -f "$body" ] || : > "$body"

    parse_result "$test_case" "$http_code" "$headers" "$body" "$curl_error" "$verdict"
    status="$(sed -n '1p' "$verdict")"
    request_id="$(sed -n '2p' "$verdict")"
    detail="$(sed -n '3p' "$verdict")"
    [ "$curl_rc" -eq 0 ] || detail="curl=$curl_rc; $detail"

    if [ "$status" = "PASS" ]; then
      printf '✅ PASS  HTTP %s' "${http_code:-000}"
    else
      printf '❌ FAIL  HTTP %s' "${http_code:-000}"
      failures=$((failures + 1))
    fi
    [ "$request_id" = "-" ] || printf '  request-id=%s' "$request_id"
    printf '  %s\n' "$detail"

    safe_detail="$(printf '%s' "$detail" | tr '\t\r\n' '   ')"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$model" "$test_case" "$status" "${http_code:-000}" "$request_id" "$safe_detail" >> "$SUMMARY_FILE"

    if [ "$DELAY_SECONDS" != "0" ]; then
      sleep "$DELAY_SECONDS"
    fi
  done
done

echo
python3 - "$SUMMARY_FILE" "${CASES[@]}" <<'PY'
import csv
import sys

path, cases = sys.argv[1], sys.argv[2:]
labels = {
    "chat-basic": "Chat",
    "chat-tool": "Tools",
    "chat-stream": "SSE",
    "chat-stream-tool": "SSE+Tools",
    "chat-reasoning-tool": "Reason+Tools",
    "responses-basic": "Responses",
}
rows = list(csv.reader(open(path, encoding="utf-8"), delimiter="\t"))
models = list(dict.fromkeys(row[0] for row in rows))
lookup = {(row[0], row[1]): row for row in rows}
headers = ["Model"] + [labels[item] for item in cases] + ["Result"]
table = []
for model in models:
    states = [lookup.get((model, item), ["", "", "SKIP"])[2] for item in cases]
    table.append([model] + states + ["PASS" if all(x == "PASS" for x in states) else "FAIL"])
widths = [max(len(headers[i]), *(len(row[i]) for row in table)) for i in range(len(headers))]
print("汇总")
print("  ".join(headers[i].ljust(widths[i]) for i in range(len(headers))))
print("  ".join("-" * width for width in widths))
for row in table:
    print("  ".join(row[i].ljust(widths[i]) for i in range(len(headers))))

failed = [row for row in rows if row[2] != "PASS"]
if failed:
    print("\n失败明细")
    for model, case, _, http, request_id, detail in failed:
        request = "" if request_id == "-" else f", request-id={request_id}"
        print(f"- {model} / {labels.get(case, case)}: HTTP {http}{request} — {detail}")
PY

passes=$((total - failures))
echo
echo "结果: PASS=$passes  FAIL=$failures  TOTAL=$total"
[ "$failures" -eq 0 ]
