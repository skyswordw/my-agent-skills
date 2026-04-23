#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/skills/msi-repair-status/scripts/msi-repair-query.sh"
FIXTURE_DIR="$ROOT_DIR/tests/msi-repair-status/fixtures"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$expected" != "$actual" ]]; then
    fail "$message: expected [$expected], got [$actual]"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail "$message: missing [$needle]"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    fail "$message: unexpectedly found [$needle]"
  fi
}

assert_less_than() {
  local actual="$1"
  local ceiling="$2"
  local message="$3"
  if (( actual >= ceiling )); then
    fail "$message: expected [$actual] to be less than [$ceiling]"
  fi
}

assert_line_before() {
  local text="$1"
  local first="$2"
  local second="$3"
  local message="$4"
  ASSERT_TEXT="$text" python3 - "$first" "$second" "$message" <<'PY'
import sys
import os

text = os.environ["ASSERT_TEXT"].splitlines()
first = sys.argv[1]
second = sys.argv[2]
message = sys.argv[3]

try:
    first_index = next(i for i, line in enumerate(text) if first in line)
except StopIteration:
    print(f"FAIL: {message}: missing [{first}]", file=sys.stderr)
    raise SystemExit(1)

try:
    second_index = next(i for i, line in enumerate(text) if second in line)
except StopIteration:
    print(f"FAIL: {message}: missing [{second}]", file=sys.stderr)
    raise SystemExit(1)

if first_index >= second_index:
    print(f"FAIL: {message}: [{first}] should appear before [{second}]", file=sys.stderr)
    raise SystemExit(1)
PY
}

if [[ ! -f "$SCRIPT_PATH" ]]; then
  fail "script not found at $SCRIPT_PATH"
fi

# shellcheck disable=SC1090
source "$SCRIPT_PATH"

collision_key_a="$(case_key "A/B" "C")"
collision_key_b="$(case_key "A" "B/C")"
if [[ "$collision_key_a" == "$collision_key_b" ]]; then
  fail "case_key should keep distinct RMA/serial pairs distinct"
fi

run_dir_test_root="$(mktemp -d)"
timestamp() {
  echo "20260422-180000"
}
RUNS_DIR="$run_dir_test_root"
duplicate_run_dir_a="$(make_run_dir "$collision_key_a")"
duplicate_run_dir_b="$(make_run_dir "$collision_key_a")"
if [[ "$duplicate_run_dir_a" == "$duplicate_run_dir_b" ]]; then
  fail "make_run_dir should stay unique across same-second duplicate runs"
fi
[[ -d "$duplicate_run_dir_a" ]] || fail "make_run_dir should create the first run directory"
[[ -d "$duplicate_run_dir_b" ]] || fail "make_run_dir should create the second run directory"
assert_contains "$duplicate_run_dir_a" "20260422-180000-${collision_key_a}" "make_run_dir should keep the timestamp/key prefix for the first run"
assert_contains "$duplicate_run_dir_b" "20260422-180000-${collision_key_a}" "make_run_dir should keep the timestamp/key prefix for the second run"
rm -rf "$run_dir_test_root"

token="$(extract_csrf_token < "$FIXTURE_DIR/inquiry_page.html")"
assert_eq "csrf-token-1234567890abcdef" "$token" "extract_csrf_token should parse hidden token"

plain_text="$(html_to_text < "$FIXTURE_DIR/result_ok.html")"
assert_contains "$plain_text" "当前状态：待寄送" "html_to_text should preserve status text"
assert_contains "$plain_text" "说明：请尽快寄出设备。" "html_to_text should preserve body text"

normalized_success_text="$(normalize_success_text < "$FIXTURE_DIR/result_ok_with_stage.html")"
assert_contains "$normalized_success_text" "当前状态：待寄送" "normalize_success_text should keep the status line"
assert_not_contains "$normalized_success_text" "维修状态" "normalize_success_text should drop heading chrome"
assert_not_contains "$normalized_success_text" "收件, 维修中" "normalize_success_text should drop workflow labels from current status output"

normalized_live_success_text="$(normalize_success_text < "$FIXTURE_DIR/result_ok_live_style.html")"
assert_eq "当前状态：您送修的产品已到达维修中心" "$normalized_live_success_text" "normalize_success_text should normalize live MSI success text into a current status line"

reminders="$(extra_reminders "$plain_text")"
assert_contains "$reminders" "维修单号 14 天内未寄回会失效" "extra_reminders should warn for pending shipment"
assert_contains "$reminders" "产品条码、二维码清晰完整" "extra_reminders should include packaging reminder"

no_reminders="$(extra_reminders "当前状态：维修完成")"
assert_eq "" "$no_reminders" "extra_reminders should stay quiet for normal states"

false_positive_reminders="$(extra_reminders "当前状态：无需用户操作")"
assert_eq "" "$false_positive_reminders" "extra_reminders should not warn when no user action is needed"

false_positive_reminders_2="$(extra_reminders "当前状态：不需要用户操作")"
assert_eq "" "$false_positive_reminders_2" "extra_reminders should not warn for explicit negated user-action text"

false_positive_reminders_3="$(extra_reminders "当前状态：不需要您操作")"
assert_eq "" "$false_positive_reminders_3" "extra_reminders should not warn for explicit negated polite user-action text"

unchanged="$(change_summary "当前状态：维修完成" "当前状态：维修完成")"
assert_eq "相较上次：无变化。" "$unchanged" "change_summary should detect unchanged states"

semantic_unchanged="$(change_summary $'当前状态：维修完成\n最新更新时间：2026-04-21 21:00' $'当前状态：维修完成\n最新更新时间：2026-04-22 09:00')"
assert_eq "相较上次：无变化。" "$semantic_unchanged" "change_summary should ignore timestamp-only churn"

changed="$(change_summary "当前状态：待寄送" "当前状态：维修完成")"
assert_contains "$changed" "相较上次：有变化。" "change_summary should report a change"
assert_contains "$changed" "上次记录：当前状态：待寄送" "change_summary should include previous text"

active_stage="$(extract_active_stage < "$FIXTURE_DIR/result_active_stage.html")"
assert_eq "审核" "$active_stage" "extract_active_stage should parse the active workflow step"

active_stage_multi_active="$(extract_active_stage < "$FIXTURE_DIR/result_ok_live_style.html")"
assert_eq "收件, 维修中" "$active_stage_multi_active" "extract_active_stage should use the last active workflow step inside the repair widget"

active_stage_with_unrelated_active="$(extract_active_stage < "$FIXTURE_DIR/result_ok_with_unrelated_active.html")"
assert_eq "审核" "$active_stage_with_unrelated_active" "extract_active_stage should ignore unrelated active elements outside the workflow widget"

if inactive_stage_output="$(extract_active_stage < "$FIXTURE_DIR/result_inactive_stage.html" 2>/dev/null)"; then
  fail "extract_active_stage should not false-match inactive workflow classes"
fi

tracking_number="$(extract_tracking_number < "$FIXTURE_DIR/result_live_with_tracking.html")"
assert_eq "SF123456789CN" "$tracking_number" "extract_tracking_number should parse the shipment number from the shipping section"

missing_tracking_number="$(extract_tracking_number < "$FIXTURE_DIR/result_ok_with_stage.html")"
assert_eq "" "$missing_tracking_number" "extract_tracking_number should stay empty when MSI does not expose a shipment number"

json_error_status="$(extract_json_status < "$FIXTURE_DIR/result_error_captcha.json")"
assert_eq "error" "$json_error_status" "extract_json_status should detect JSON error responses"

json_error_text="$(response_to_text < "$FIXTURE_DIR/result_error_captcha.json")"
assert_contains "$json_error_text" "验证码错误" "response_to_text should surface captcha errors"

success_status="$(extract_json_status < "$FIXTURE_DIR/result_ok.html")"
assert_eq "" "$success_status" "extract_json_status should stay empty for HTML success responses"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mock_bin_dir="$tmp_dir/mock-bin"
mkdir -p "$mock_bin_dir"

cat > "$mock_bin_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

call_file="${MOCK_CURL_CALL_FILE:?}"
mode="${MOCK_CURL_MODE:?}"
fixture_dir="${MOCK_FIXTURE_DIR:?}"
state_dir="${MOCK_CURL_STATE_DIR:?}"
expected_rma="${MOCK_EXPECTED_RMA:?}"
expected_serial="${MOCK_EXPECTED_SERIAL:?}"
expected_answer="${MOCK_EXPECTED_ANSWER:?}"
expected_token="csrf-token-1234567890abcdef"
inquiry_url="https://account.msi.cn/zh-Hans/services/inquiry-history"
detail_url="https://account.msi.cn/zh-Hans/services/inquiry-detail"
captcha_url_prefix="https://account.msi.cn/captcha/default?"
mkdir -p "$state_dir"
call_count=0
if [[ -f "$call_file" ]]; then
  call_count="$(cat "$call_file")"
fi
call_count="$((call_count + 1))"
printf '%s' "$call_count" > "$call_file"

output_path=""
url=""
cookie_write=""
cookie_read=""
referer=""
headers=()
data_fields=()
args=("$@")

contains_exact() {
  local expected="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$expected" ]]; then
      return 0
    fi
  done
  return 1
}

for ((i = 0; i < ${#args[@]}; i++)); do
  arg="${args[$i]}"
  case "$arg" in
    -o)
      ((i += 1))
      output_path="${args[$i]}"
      ;;
    -c)
      ((i += 1))
      cookie_write="${args[$i]}"
      ;;
    -b)
      ((i += 1))
      cookie_read="${args[$i]}"
      ;;
    -H)
      ((i += 1))
      headers+=("${args[$i]}")
      ;;
    -e)
      ((i += 1))
      referer="${args[$i]}"
      ;;
    --data-urlencode)
      ((i += 1))
      data_fields+=("${args[$i]}")
      ;;
    -*)
      ;;
    *)
      url="$arg"
      ;;
  esac
done

[[ -n "$output_path" ]] || {
  echo "mock curl missing -o output path" >&2
  exit 1
}

cookie_state_file="$state_dir/cookie-jar.path"

validate_detail_request() {
  expected_cookie="$(cat "$cookie_state_file")"
  [[ "$url" == "$detail_url" ]] || {
    echo "unexpected detail URL: $url" >&2
    exit 1
  }
  [[ "$cookie_write" == "$expected_cookie" && "$cookie_read" == "$expected_cookie" ]] || {
    echo "detail request should reuse the inquiry cookie jar" >&2
    exit 1
  }
  [[ "$referer" == "$inquiry_url" ]] || {
    echo "detail request should send inquiry referer" >&2
    exit 1
  }
  contains_exact "X-Requested-With: XMLHttpRequest" "${headers[@]}" || {
    echo "detail request should send X-Requested-With header" >&2
    exit 1
  }
  contains_exact "product_sn=$expected_serial" "${data_fields[@]}" || {
    echo "detail request missing product_sn field" >&2
    exit 1
  }
  contains_exact "rma_no=$expected_rma" "${data_fields[@]}" || {
    echo "detail request missing rma_no field" >&2
    exit 1
  }
  contains_exact "captcha=$expected_answer" "${data_fields[@]}" || {
    echo "detail request missing captcha field" >&2
    exit 1
  }
  contains_exact "_token=$expected_token" "${data_fields[@]}" || {
    echo "detail request missing _token field" >&2
    exit 1
  }
}

case "$call_count:$mode" in
  1:success|1:success_changed|1:success_live|1:success_tracking|1:success_unrelated_active|1:error|1:malformed|1:stage_drift)
    [[ "$url" == "$inquiry_url" ]] || {
      echo "unexpected inquiry URL: $url" >&2
      exit 1
    }
    [[ -n "$cookie_write" && "$cookie_write" == "$cookie_read" ]] || {
      echo "inquiry request should reuse one cookie jar via -c/-b" >&2
      exit 1
    }
    printf '%s' "$cookie_write" > "$cookie_state_file"
    cp "$fixture_dir/inquiry_page.html" "$output_path"
    ;;
  2:success|2:success_changed|2:success_live|2:success_tracking|2:success_unrelated_active|2:error|2:malformed|2:stage_drift)
    expected_cookie="$(cat "$cookie_state_file")"
    [[ "$url" == "$captcha_url_prefix"* ]] || {
      echo "unexpected captcha URL: $url" >&2
      exit 1
    }
    [[ "$cookie_write" == "$expected_cookie" && "$cookie_read" == "$expected_cookie" ]] || {
      echo "captcha request should reuse the inquiry cookie jar" >&2
      exit 1
    }
    printf 'captcha-bytes' > "$output_path"
    ;;
  3:success)
    validate_detail_request
    cp "$fixture_dir/result_ok_with_stage.html" "$output_path"
    ;;
  3:success_changed)
    validate_detail_request
    cp "$fixture_dir/result_ok_with_stage_completed.html" "$output_path"
    ;;
  3:success_live)
    validate_detail_request
    cp "$fixture_dir/result_ok_live_style.html" "$output_path"
    ;;
  3:success_tracking)
    validate_detail_request
    cp "$fixture_dir/result_live_with_tracking.html" "$output_path"
    ;;
  3:success_unrelated_active)
    validate_detail_request
    cp "$fixture_dir/result_ok_with_unrelated_active.html" "$output_path"
    ;;
  3:error)
    validate_detail_request
    cp "$fixture_dir/result_error_captcha.json" "$output_path"
    ;;
  3:malformed)
    validate_detail_request
    cp "$fixture_dir/result_malformed_success.html" "$output_path"
    ;;
  3:stage_drift)
    validate_detail_request
    cp "$fixture_dir/result_ok_missing_active_stage.html" "$output_path"
    ;;
  *)
    echo "unexpected mock curl invocation: $call_count ($mode)" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$mock_bin_dir/curl"

cat > "$mock_bin_dir/open" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

call_file="${MOCK_OPEN_CALL_FILE:?}"
printf '%s\n' "$*" >> "$call_file"
EOF
chmod +x "$mock_bin_dir/open"

cat > "$mock_bin_dir/node" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

call_file="${MOCK_NODE_CALL_FILE:?}"
mode="${MOCK_NODE_MODE:?}"
expected_script="${MOCK_NODE_EXPECTED_SCRIPT:?}"
expected_number="${MOCK_NODE_EXPECTED_NUMBER:?}"

printf '%s\n' "$*" >> "$call_file"

[[ "${1:-}" == "$expected_script" ]] || {
  echo "unexpected node script: ${1:-}" >&2
  exit 1
}

found_json=0
found_number=0
for arg in "$@"; do
  if [[ "$arg" == "--json" ]]; then
    found_json=1
  fi
  if [[ "$arg" == "--number=$expected_number" ]]; then
    found_number=1
  fi
done

[[ "$found_json" -eq 1 ]] || {
  echo "mock node missing --json" >&2
  exit 1
}
[[ "$found_number" -eq 1 ]] || {
  echo "mock node missing expected --number value" >&2
  exit 1
}

case "$mode" in
  success)
    printf '%s\n' "${MOCK_NODE_JSON_OUTPUT:?}"
    ;;
  hang)
    sleep "${MOCK_NODE_HANG_SECONDS:?}"
    printf '%s\n' "${MOCK_NODE_JSON_OUTPUT:?}"
    ;;
  fail)
    echo "${MOCK_NODE_ERROR_TEXT:?}" >&2
    exit 1
    ;;
  *)
    echo "unknown mock node mode: $mode" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$mock_bin_dir/node"

success_cache_dir="$tmp_dir/cache-success"
success_state_dir="$tmp_dir/state-success"
success_call_file="$tmp_dir/curl-success.count"
success_open_call_file="$tmp_dir/open-success.log"
success_output="$(
  PATH="$mock_bin_dir:$PATH" \
  MOCK_CURL_CALL_FILE="$success_call_file" \
  MOCK_CURL_MODE="success" \
  MOCK_CURL_STATE_DIR="$tmp_dir/mock-success" \
  MOCK_FIXTURE_DIR="$FIXTURE_DIR" \
  MOCK_EXPECTED_RMA="RMA-CLI-001" \
  MOCK_EXPECTED_SERIAL="SERIAL-CLI-001" \
  MOCK_EXPECTED_ANSWER="1234" \
  MOCK_OPEN_CALL_FILE="$success_open_call_file" \
  MSI_REPAIR_CACHE_DIR="$success_cache_dir" \
  MSI_REPAIR_STATE_DIR="$success_state_dir" \
  bash "$SCRIPT_PATH" --rma "RMA-CLI-001" --serial "SERIAL-CLI-001" --answer "1234"
)"
assert_line_before "$success_output" "当前状态：" "页面高亮阶段：审核" "CLI output should report current status before highlighted stage"
assert_contains "$success_output" "页面高亮阶段：审核" "CLI output should include the highlighted stage"
assert_contains "$success_output" "维修单号 14 天内未寄回会失效，寄出前确认外观完好且产品条码、二维码清晰完整。" "CLI output should include the exact reminder sentence"
assert_not_contains "$success_output" "提醒：" "CLI output should not prepend extra text to the exact reminder sentence"
assert_contains "$success_output" "相较上次：这是首次记录。" "CLI output should include the first-run change summary"
assert_not_contains "$success_output" "维修状态" "CLI output should not leak heading chrome into the current status block"
assert_not_contains "$success_output" "收件, 维修中" "CLI output should not leak workflow labels into the current status block"
assert_not_contains "$success_output" "请输入验证码答案" "CLI should treat explicit --answer as already confirmed and skip the interactive prompt"
if [[ -s "$success_open_call_file" ]]; then
  fail "CLI should not open the captcha image when --answer is already confirmed"
fi

error_cache_dir="$tmp_dir/cache-error"
error_state_dir="$tmp_dir/state-error"
error_call_file="$tmp_dir/curl-error.count"
set +e
error_output="$(
  PATH="$mock_bin_dir:$PATH" \
  MOCK_CURL_CALL_FILE="$error_call_file" \
  MOCK_CURL_MODE="error" \
  MOCK_CURL_STATE_DIR="$tmp_dir/mock-error" \
  MOCK_FIXTURE_DIR="$FIXTURE_DIR" \
  MOCK_EXPECTED_RMA="RMA-CLI-ERR" \
  MOCK_EXPECTED_SERIAL="SERIAL-CLI-ERR" \
  MOCK_EXPECTED_ANSWER="9999" \
  MSI_REPAIR_CACHE_DIR="$error_cache_dir" \
  MSI_REPAIR_STATE_DIR="$error_state_dir" \
  bash "$SCRIPT_PATH" --rma "RMA-CLI-ERR" --serial "SERIAL-CLI-ERR" --answer "9999" --no-open 2>&1
)"
error_status_code=$?
set -e
if [[ "$error_status_code" -eq 0 ]]; then
  fail "CLI should fail for JSON captcha errors"
fi
assert_contains "$error_output" "错误: 验证码错误" "CLI should surface captcha error messages"

malformed_cache_dir="$tmp_dir/cache-malformed"
malformed_state_dir="$tmp_dir/state-malformed"
malformed_call_file="$tmp_dir/curl-malformed.count"
set +e
malformed_output="$(
  PATH="$mock_bin_dir:$PATH" \
  MOCK_CURL_CALL_FILE="$malformed_call_file" \
  MOCK_CURL_MODE="malformed" \
  MOCK_CURL_STATE_DIR="$tmp_dir/mock-malformed" \
  MOCK_FIXTURE_DIR="$FIXTURE_DIR" \
  MOCK_EXPECTED_RMA="RMA-CLI-BAD" \
  MOCK_EXPECTED_SERIAL="SERIAL-CLI-BAD" \
  MOCK_EXPECTED_ANSWER="0000" \
  MSI_REPAIR_CACHE_DIR="$malformed_cache_dir" \
  MSI_REPAIR_STATE_DIR="$malformed_state_dir" \
  bash "$SCRIPT_PATH" --rma "RMA-CLI-BAD" --serial "SERIAL-CLI-BAD" --answer "0000" --no-open 2>&1
)"
malformed_status_code=$?
set -e
if [[ "$malformed_status_code" -eq 0 ]]; then
  fail "CLI should fail when no structured repair status can be extracted"
fi
assert_contains "$malformed_output" "错误: 查询结果无法提取维修状态，可能是页面改版或服务异常。" "CLI should stop on parsing drift instead of accepting malformed success"
if find "$malformed_state_dir" -type f | grep -q .; then
  fail "CLI should not persist state files for malformed success responses"
fi

stage_drift_cache_dir="$tmp_dir/cache-stage-drift"
stage_drift_state_dir="$tmp_dir/state-stage-drift"
stage_drift_call_file="$tmp_dir/curl-stage-drift.count"
set +e
stage_drift_output="$(
  PATH="$mock_bin_dir:$PATH" \
  MOCK_CURL_CALL_FILE="$stage_drift_call_file" \
  MOCK_CURL_MODE="stage_drift" \
  MOCK_CURL_STATE_DIR="$tmp_dir/mock-stage-drift" \
  MOCK_FIXTURE_DIR="$FIXTURE_DIR" \
  MOCK_EXPECTED_RMA="RMA-CLI-STAGE" \
  MOCK_EXPECTED_SERIAL="SERIAL-CLI-STAGE" \
  MOCK_EXPECTED_ANSWER="2468" \
  MSI_REPAIR_CACHE_DIR="$stage_drift_cache_dir" \
  MSI_REPAIR_STATE_DIR="$stage_drift_state_dir" \
  bash "$SCRIPT_PATH" --rma "RMA-CLI-STAGE" --serial "SERIAL-CLI-STAGE" --answer "2468" --no-open 2>&1
)"
stage_drift_status_code=$?
set -e
if [[ "$stage_drift_status_code" -eq 0 ]]; then
  fail "CLI should fail when workflow stage cannot be extracted from a success page"
fi
assert_contains "$stage_drift_output" "错误: 查询结果无法提取维修阶段，可能是页面改版或服务异常。" "CLI should stop on workflow-stage parsing drift"
if find "$stage_drift_state_dir" -type f | grep -q .; then
  fail "CLI should not persist state files for workflow-stage parsing drift"
fi

unrelated_active_cache_dir="$tmp_dir/cache-unrelated-active"
unrelated_active_state_dir="$tmp_dir/state-unrelated-active"
unrelated_active_call_file="$tmp_dir/curl-unrelated-active.count"
unrelated_active_output="$(
  PATH="$mock_bin_dir:$PATH" \
  MOCK_CURL_CALL_FILE="$unrelated_active_call_file" \
  MOCK_CURL_MODE="success_unrelated_active" \
  MOCK_CURL_STATE_DIR="$tmp_dir/mock-unrelated-active" \
  MOCK_FIXTURE_DIR="$FIXTURE_DIR" \
  MOCK_EXPECTED_RMA="RMA-CLI-OUTSIDE" \
  MOCK_EXPECTED_SERIAL="SERIAL-CLI-OUTSIDE" \
  MOCK_EXPECTED_ANSWER="9753" \
  MSI_REPAIR_CACHE_DIR="$unrelated_active_cache_dir" \
  MSI_REPAIR_STATE_DIR="$unrelated_active_state_dir" \
  bash "$SCRIPT_PATH" --rma "RMA-CLI-OUTSIDE" --serial "SERIAL-CLI-OUTSIDE" --answer "9753" --no-open
)"
assert_contains "$unrelated_active_output" "页面高亮阶段：审核" "CLI should report the workflow stage from the repair widget"
assert_not_contains "$unrelated_active_output" "页面高亮阶段：导航标签" "CLI should ignore unrelated active elements outside the workflow widget"

live_success_cache_dir="$tmp_dir/cache-live-success"
live_success_state_dir="$tmp_dir/state-live-success"
live_success_call_file="$tmp_dir/curl-live-success.count"
live_success_output="$(
  PATH="$mock_bin_dir:$PATH" \
  MOCK_CURL_CALL_FILE="$live_success_call_file" \
  MOCK_CURL_MODE="success_live" \
  MOCK_CURL_STATE_DIR="$tmp_dir/mock-live-success" \
  MOCK_FIXTURE_DIR="$FIXTURE_DIR" \
  MOCK_EXPECTED_RMA="RMA-CLI-LIVE" \
  MOCK_EXPECTED_SERIAL="SERIAL-CLI-LIVE" \
  MOCK_EXPECTED_ANSWER="1122" \
  MSI_REPAIR_CACHE_DIR="$live_success_cache_dir" \
  MSI_REPAIR_STATE_DIR="$live_success_state_dir" \
  bash "$SCRIPT_PATH" --rma "RMA-CLI-LIVE" --serial "SERIAL-CLI-LIVE" --answer "1122" --no-open
)"
assert_contains "$live_success_output" "当前状态：" "CLI should print a current status header for live MSI success responses"
assert_contains "$live_success_output" "当前状态：您送修的产品已到达维修中心" "CLI should normalize live MSI success responses into a current status line"
assert_contains "$live_success_output" "页面高亮阶段：收件, 维修中" "CLI should report the furthest active workflow stage from live MSI success responses"
assert_contains "$live_success_output" "相较上次：这是首次记录。" "CLI should treat the first live-style success response as an initial record"

tracking_success_cache_dir="$tmp_dir/cache-tracking-success"
tracking_success_state_dir="$tmp_dir/state-tracking-success"
tracking_success_call_file="$tmp_dir/curl-tracking-success.count"
tracking_success_node_call_file="$tmp_dir/node-tracking-success.log"
tracking_success_output="$(
  PATH="$mock_bin_dir:$PATH" \
  MOCK_CURL_CALL_FILE="$tracking_success_call_file" \
  MOCK_CURL_MODE="success_tracking" \
  MOCK_CURL_STATE_DIR="$tmp_dir/mock-tracking-success" \
  MOCK_FIXTURE_DIR="$FIXTURE_DIR" \
  MOCK_EXPECTED_RMA="RMA-CLI-SHIP" \
  MOCK_EXPECTED_SERIAL="SERIAL-CLI-SHIP" \
  MOCK_EXPECTED_ANSWER="5566" \
  MOCK_NODE_CALL_FILE="$tracking_success_node_call_file" \
  MOCK_NODE_MODE="success" \
  MOCK_NODE_EXPECTED_SCRIPT="$ROOT_DIR/skills/express-tracking/scripts/run.mjs" \
  MOCK_NODE_EXPECTED_NUMBER="SF123456789CN" \
  MOCK_NODE_JSON_OUTPUT='{"provider":"kuaidi100","number":"SF123456789CN","carrier":{"code":"shunfeng","source":"auto"},"state":{"code":"0","label":"在途"},"status":{"code":"200","message":"ok"},"latestEvent":{"time":"2026-04-23 10:20:00","context":"快件已到达上海转运中心"},"recentEvents":[{"time":"2026-04-23 10:20:00","context":"快件已到达上海转运中心"}]}' \
  MSI_REPAIR_CACHE_DIR="$tracking_success_cache_dir" \
  MSI_REPAIR_STATE_DIR="$tracking_success_state_dir" \
  bash "$SCRIPT_PATH" --rma "RMA-CLI-SHIP" --serial "SERIAL-CLI-SHIP" --answer "5566" --no-open
)"
assert_contains "$tracking_success_output" "寄送单号：SF123456789CN" "CLI should report the MSI shipment number when present"
assert_contains "$tracking_success_output" "物流补充：" "CLI should add a logistics supplement when express-tracking succeeds"
assert_contains "$tracking_success_output" "当前物流状态：在途" "CLI should summarize the live logistics state"
assert_contains "$tracking_success_output" "最新时间：2026-04-23 10:20:00" "CLI should include the latest logistics timestamp"
assert_contains "$tracking_success_output" "最新轨迹：快件已到达上海转运中心" "CLI should include the latest logistics event"

tracking_fallback_cache_dir="$tmp_dir/cache-tracking-fallback"
tracking_fallback_state_dir="$tmp_dir/state-tracking-fallback"
tracking_fallback_call_file="$tmp_dir/curl-tracking-fallback.count"
tracking_fallback_node_call_file="$tmp_dir/node-tracking-fallback.log"
tracking_fallback_output="$(
  PATH="$mock_bin_dir:$PATH" \
  MOCK_CURL_CALL_FILE="$tracking_fallback_call_file" \
  MOCK_CURL_MODE="success_tracking" \
  MOCK_CURL_STATE_DIR="$tmp_dir/mock-tracking-fallback" \
  MOCK_FIXTURE_DIR="$FIXTURE_DIR" \
  MOCK_EXPECTED_RMA="RMA-CLI-SHIP-FALLBACK" \
  MOCK_EXPECTED_SERIAL="SERIAL-CLI-SHIP-FALLBACK" \
  MOCK_EXPECTED_ANSWER="6677" \
  MOCK_NODE_CALL_FILE="$tracking_fallback_node_call_file" \
  MOCK_NODE_MODE="fail" \
  MOCK_NODE_EXPECTED_SCRIPT="$ROOT_DIR/skills/express-tracking/scripts/run.mjs" \
  MOCK_NODE_EXPECTED_NUMBER="SF123456789CN" \
  MOCK_NODE_ERROR_TEXT="缺少 EXPRESS_TRACKING_KUAIDI100_KEY。" \
  MSI_REPAIR_CACHE_DIR="$tracking_fallback_cache_dir" \
  MSI_REPAIR_STATE_DIR="$tracking_fallback_state_dir" \
  bash "$SCRIPT_PATH" --rma "RMA-CLI-SHIP-FALLBACK" --serial "SERIAL-CLI-SHIP-FALLBACK" --answer "6677" --no-open
)"
assert_contains "$tracking_fallback_output" "寄送单号：SF123456789CN" "CLI should still report the shipment number when express-tracking is misconfigured"
assert_not_contains "$tracking_fallback_output" "物流补充：" "CLI should stay quiet about logistics progress when express-tracking fails"
assert_not_contains "$tracking_fallback_output" "当前物流状态：" "CLI should not invent a logistics state when express-tracking fails"
assert_not_contains "$tracking_fallback_output" "缺少 EXPRESS_TRACKING_KUAIDI100_KEY" "CLI should not leak express-tracking configuration errors into the MSI summary"

tracking_timeout_cache_dir="$tmp_dir/cache-tracking-timeout"
tracking_timeout_state_dir="$tmp_dir/state-tracking-timeout"
tracking_timeout_call_file="$tmp_dir/curl-tracking-timeout.count"
tracking_timeout_node_call_file="$tmp_dir/node-tracking-timeout.log"
tracking_timeout_start_ms="$(python3 -c 'import time; print(int(time.time() * 1000))')"
tracking_timeout_output="$(
  PATH="$mock_bin_dir:$PATH" \
  MOCK_CURL_CALL_FILE="$tracking_timeout_call_file" \
  MOCK_CURL_MODE="success_tracking" \
  MOCK_CURL_STATE_DIR="$tmp_dir/mock-tracking-timeout" \
  MOCK_FIXTURE_DIR="$FIXTURE_DIR" \
  MOCK_EXPECTED_RMA="RMA-CLI-SHIP-TIMEOUT" \
  MOCK_EXPECTED_SERIAL="SERIAL-CLI-SHIP-TIMEOUT" \
  MOCK_EXPECTED_ANSWER="7788" \
  MOCK_NODE_CALL_FILE="$tracking_timeout_node_call_file" \
  MOCK_NODE_MODE="hang" \
  MOCK_NODE_EXPECTED_SCRIPT="$ROOT_DIR/skills/express-tracking/scripts/run.mjs" \
  MOCK_NODE_EXPECTED_NUMBER="SF123456789CN" \
  MOCK_NODE_HANG_SECONDS="4" \
  MOCK_NODE_JSON_OUTPUT='{"provider":"kuaidi100","number":"SF123456789CN","carrier":{"code":"shunfeng","source":"auto"},"state":{"code":"0","label":"在途"},"status":{"code":"200","message":"ok"},"latestEvent":{"time":"2026-04-23 10:20:00","context":"快件已到达上海转运中心"},"recentEvents":[{"time":"2026-04-23 10:20:00","context":"快件已到达上海转运中心"}]}' \
  MSI_REPAIR_CACHE_DIR="$tracking_timeout_cache_dir" \
  MSI_REPAIR_STATE_DIR="$tracking_timeout_state_dir" \
  MSI_REPAIR_EXPRESS_TIMEOUT_SECONDS="1" \
  bash "$SCRIPT_PATH" --rma "RMA-CLI-SHIP-TIMEOUT" --serial "SERIAL-CLI-SHIP-TIMEOUT" --answer "7788" --no-open
)"
tracking_timeout_end_ms="$(python3 -c 'import time; print(int(time.time() * 1000))')"
tracking_timeout_elapsed_ms="$((tracking_timeout_end_ms - tracking_timeout_start_ms))"
assert_contains "$tracking_timeout_output" "寄送单号：SF123456789CN" "CLI should still report the shipment number when express-tracking times out"
assert_not_contains "$tracking_timeout_output" "物流补充：" "CLI should skip logistics enrichment when express-tracking times out"
assert_less_than "$tracking_timeout_elapsed_ms" 3000 "CLI should not wait for a hung express-tracking subprocess"

stateful_cache_dir_1="$tmp_dir/cache-stateful-1"
stateful_cache_dir_2="$tmp_dir/cache-stateful-2"
stateful_state_dir="$tmp_dir/state-stateful"
stateful_call_file_1="$tmp_dir/curl-stateful-1.count"
stateful_call_file_2="$tmp_dir/curl-stateful-2.count"
stateful_key="$(case_key "RMA-CLI-STATE" "SERIAL-CLI-STATE")"
stateful_snapshot_file="$stateful_state_dir/${stateful_key}.last.snapshot.txt"
stateful_text_file="$stateful_state_dir/${stateful_key}.last.txt"

first_stateful_output="$(
  PATH="$mock_bin_dir:$PATH" \
  MOCK_CURL_CALL_FILE="$stateful_call_file_1" \
  MOCK_CURL_MODE="success" \
  MOCK_CURL_STATE_DIR="$tmp_dir/mock-stateful-1" \
  MOCK_FIXTURE_DIR="$FIXTURE_DIR" \
  MOCK_EXPECTED_RMA="RMA-CLI-STATE" \
  MOCK_EXPECTED_SERIAL="SERIAL-CLI-STATE" \
  MOCK_EXPECTED_ANSWER="1357" \
  MSI_REPAIR_CACHE_DIR="$stateful_cache_dir_1" \
  MSI_REPAIR_STATE_DIR="$stateful_state_dir" \
  bash "$SCRIPT_PATH" --rma "RMA-CLI-STATE" --serial "SERIAL-CLI-STATE" --answer "1357" --no-open
)"
assert_contains "$first_stateful_output" "相较上次：这是首次记录。" "first successful CLI run should create the initial state snapshot"
[[ -f "$stateful_snapshot_file" ]] || fail "first successful CLI run should persist the snapshot file"
[[ -f "$stateful_text_file" ]] || fail "first successful CLI run should persist the text result file"
assert_contains "$(cat "$stateful_snapshot_file")" "当前状态：待寄送" "snapshot file should store the first status"

second_stateful_output="$(
  PATH="$mock_bin_dir:$PATH" \
  MOCK_CURL_CALL_FILE="$stateful_call_file_2" \
  MOCK_CURL_MODE="success_changed" \
  MOCK_CURL_STATE_DIR="$tmp_dir/mock-stateful-2" \
  MOCK_FIXTURE_DIR="$FIXTURE_DIR" \
  MOCK_EXPECTED_RMA="RMA-CLI-STATE" \
  MOCK_EXPECTED_SERIAL="SERIAL-CLI-STATE" \
  MOCK_EXPECTED_ANSWER="1357" \
  MSI_REPAIR_CACHE_DIR="$stateful_cache_dir_2" \
  MSI_REPAIR_STATE_DIR="$stateful_state_dir" \
  bash "$SCRIPT_PATH" --rma "RMA-CLI-STATE" --serial "SERIAL-CLI-STATE" --answer "1357" --no-open
)"
assert_contains "$second_stateful_output" "相较上次：有变化。" "second successful CLI run should compare against the persisted state"
assert_contains "$second_stateful_output" "上次记录：当前状态：待寄送" "second successful CLI run should report the previous persisted status"
assert_line_before "$second_stateful_output" "当前状态：" "当前状态：维修完成" "second successful CLI run should report the new status block"
assert_contains "$second_stateful_output" "页面高亮阶段：完成" "second successful CLI run should report the new workflow stage"
assert_contains "$(cat "$stateful_snapshot_file")" "当前状态：维修完成" "snapshot file should update to the latest status after the second run"
assert_contains "$(cat "$stateful_snapshot_file")" "页面高亮阶段：完成" "snapshot file should update to the latest stage after the second run"

echo "PASS"
