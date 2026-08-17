#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/octer-pipe-test.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/home" "$TEST_ROOT/tmp" "$TEST_ROOT/run"
printf '# downloaded helper\n' >"$TEST_ROOT/helper.py"

# Run the full stdin installer against fakes so this test cannot modify a real
# Hermes installation. The stubs record helper download, config, and self-test.
sed "s|TEST_ROOT_PLACEHOLDER|$TEST_ROOT|g" >"$TEST_ROOT/bin/hermes" <<'SH'
#!/usr/bin/env bash
set -e
case "${1:-} ${2:-}" in
  "config path") printf '%s\n' "TEST_ROOT_PLACEHOLDER/home/config.yaml" ;;
  "config env-path") printf '%s\n' "TEST_ROOT_PLACEHOLDER/home/.env" ;;
  "config show") printf '%s\n' 'Model: gpt-5.5 provider: custom:octer' ;;
  "gateway stop"|"gateway start"|"gateway status") : ;;
  *) exit 3 ;;
esac
SH

sed "s|TEST_ROOT_PLACEHOLDER|$TEST_ROOT|g" >"$TEST_ROOT/bin/python3" <<'SH'
#!/usr/bin/env bash
set -e
if [ "${1:-}" = "-c" ]; then exit 0; fi
helper="$1"
operation="$2"
test -s "$helper"
printf '%s\n' "$operation" >>"TEST_ROOT_PLACEHOLDER/python.log"
if [ "$operation" = "set" ]; then
  key=""
  IFS= read -r key || true
  case "$key" in evo_*) : ;; *) exit 4 ;; esac
fi
SH

sed "s|TEST_ROOT_PLACEHOLDER|$TEST_ROOT|g" >"$TEST_ROOT/bin/curl" <<'SH'
#!/usr/bin/env bash
set -e
output=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    https://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
test -n "$output"
test -n "$url"
printf '%s\n' "$url" >>"TEST_ROOT_PLACEHOLDER/curl.log"
if [ "${FAIL_PRIMARY_DOWNLOAD:-}" = "1" ] && [ "$url" = "https://primary.invalid/hermes_config.py" ]; then
  exit 22
fi
cp "TEST_ROOT_PLACEHOLDER/helper.py" "$output"
SH

chmod +x "$TEST_ROOT/bin/hermes" "$TEST_ROOT/bin/python3" "$TEST_ROOT/bin/curl"
DUMMY_KEY="evo_$(printf '0%.0s' {1..26})"

(
  cd "$TEST_ROOT/run"
  PATH="$TEST_ROOT/bin:/usr/bin:/bin" \
  TMPDIR="$TEST_ROOT/tmp" \
  OCTER_HERMES_CONFIG_URL="https://example.test/hermes_config.py" \
    bash -s -- "$DUMMY_KEY" gpt-5.5 \
    <"$REPO_DIR/set-hermes-model.sh"
)

test "$(wc -l <"$TEST_ROOT/curl.log" | tr -d ' ')" = "1"
grep -qx set "$TEST_ROOT/python.log"
grep -qx self-test "$TEST_ROOT/python.log"
if find "$TEST_ROOT/tmp" -name 'octer-hermes-config.*' -print -quit | grep -q .; then
  echo "temporary helper was not cleaned up" >&2
  exit 1
fi

(
  cd "$TEST_ROOT/run"
  PATH="$TEST_ROOT/bin:/usr/bin:/bin" \
  TMPDIR="$TEST_ROOT/tmp" \
  OCTER_HERMES_CONFIG_URL="https://primary.invalid/hermes_config.py" \
  FAIL_PRIMARY_DOWNLOAD=1 \
    bash -s <"$REPO_DIR/clear-hermes-model.sh"
)

test "$(wc -l <"$TEST_ROOT/curl.log" | tr -d ' ')" = "3"
tail -n 2 "$TEST_ROOT/curl.log" | grep -qx "https://primary.invalid/hermes_config.py"
tail -n 1 "$TEST_ROOT/curl.log" | grep -qx "https://raw.githubusercontent.com/octer-ai/octer-shell/refs/heads/master/hermes_config.py"
grep -qx clear "$TEST_ROOT/python.log"
if find "$TEST_ROOT/tmp" -name 'octer-hermes-config.*' -print -quit | grep -q .; then
  echo "temporary clear helper was not cleaned up" >&2
  exit 1
fi

echo "OK: set and clear curl | bash flows download, fall back, and clean up the helper"
