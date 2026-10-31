#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/work"

cat >"$TMP/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
user_agent=""
payload=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -A) user_agent=$2; shift 2 ;;
    -d) payload=$2; shift 2 ;;
    -w|-m|-X|-H) shift 2 ;;
    *) shift ;;
  esac
done
[[ "$user_agent" == "server-toolkit" ]] || exit 90
[[ "${CURL_FAIL:-0}" != 1 ]] || exit 7
status=${CURL_STATUS:-200}
if [[ -n "${CURL_BODY+x}" ]]; then
  body=$CURL_BODY
else
  body=$(jq --arg bad_id "${CURL_BAD_ID:-}" \
            --arg bad_status "${CURL_BAD_STATUS:-403}" \
            --arg missing_id "${CURL_MISSING_ID:-}" \
            --arg omit_id "${CURL_OMIT_ID:-}" \
            '[.ops[] | select(.id != $omit_id) | {id, status: (if .id == $bad_id then ($bad_status | tonumber) else 200 end), data: (if .id == $missing_id then {} else {content: ("test-" + .id)} end)}]' <<<"$payload")
fi
printf '%s\n%s' "$body" "$status"
MOCK
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"

prepare_worker() {
  rm -rf "$TMP/work"
  rm -f "$TMP/reloaded"
  mkdir -p "$TMP/work/storage/cert/local"
  cat >"$TMP/environment" <<'ENV'
SYS_VAULT_URL='https://vault.example/api'
SYS_DEVICE_UUID='test-token'
ENV
  jq -n --arg reload "touch $TMP/reloaded" \
    '{production:["example.test"],cf_origin:["origin.test"],symlinks:{etc_ssl:false,nginx_ssl:false},reload_command:$reload}' \
    >"$TMP/work/storage/cert/sync-config.json"
  sed \
    -e "s|source /etc/environment|source \"$TMP/environment\"|" \
    -e "s|/srv/server-toolkit/storage/cert/sync.log|$TMP/work/storage/cert/sync.log|g" \
    -e "s|/srv/server-toolkit/storage/cert/sync-config.json|$TMP/work/storage/cert/sync-config.json|g" \
    -e "s|/srv/server-toolkit/storage/cert/local|$TMP/work/storage/cert/local|g" \
    "$ROOT/cert/worker.sh" >"$TMP/worker.sh"
}

run_success() {
  prepare_worker
  bash "$TMP/worker.sh" >"$TMP/out" 2>&1
  for file in example.test-cert example.test-fullchain example.test-privkey origin.test-cf-cert origin.test-cf-privkey; do
    [[ -s "$TMP/work/storage/cert/local/$file" ]]
    if [[ "$(uname -s)" != MINGW* ]]; then
      [[ "$(stat -c '%a' "$TMP/work/storage/cert/local/$file")" == 600 ]]
    fi
  done
  grep -q '证书同步完成' "$TMP/out"
  [[ -e "$TMP/reloaded" ]]
}

run_http_failure() {
  prepare_worker
  if CURL_STATUS=403 bash "$TMP/worker.sh" >"$TMP/out" 2>&1; then
    echo 'expected HTTP failure' >&2; exit 1
  fi
  grep -q 'HTTP 403' "$TMP/out"
  grep -q '证书同步失败' "$TMP/out"
  [[ ! -e "$TMP/reloaded" ]]
}

run_operation_failure() {
  prepare_worker
  if CURL_BAD_ID=cert bash "$TMP/worker.sh" >"$TMP/out" 2>&1; then
    echo 'expected operation failure' >&2; exit 1
  fi
  grep -q 'cert 操作失败 (状态 403)' "$TMP/out"
  grep -q '证书同步失败' "$TMP/out"
  [[ ! -e "$TMP/reloaded" ]]
}

run_missing_content() {
  prepare_worker
  if CURL_MISSING_ID=fullchain bash "$TMP/worker.sh" >"$TMP/out" 2>&1; then
    echo 'expected missing-content failure' >&2; exit 1
  fi
  grep -q 'fullchain 内容缺失' "$TMP/out"
  [[ ! -e "$TMP/reloaded" ]]
}

run_missing_operation() {
  prepare_worker
  if CURL_OMIT_ID=privkey bash "$TMP/worker.sh" >"$TMP/out" 2>&1; then
    echo 'expected missing-operation failure' >&2; exit 1
  fi
  grep -q '操作数量不匹配' "$TMP/out"
  [[ ! -e "$TMP/reloaded" ]]
}

run_invalid_body() {
  prepare_worker
  if CURL_BODY='not-json' bash "$TMP/worker.sh" >"$TMP/out" 2>&1; then
    echo 'expected invalid-body failure' >&2; exit 1
  fi
  grep -q '响应格式无效' "$TMP/out"
  [[ ! -e "$TMP/reloaded" ]]
}

run_transport_failure() {
  prepare_worker
  if CURL_FAIL=1 bash "$TMP/worker.sh" >"$TMP/out" 2>&1; then
    echo 'expected transport failure' >&2; exit 1
  fi
  grep -q '网络请求失败 (curl 7)' "$TMP/out"
  [[ ! -e "$TMP/reloaded" ]]
}

run_success
run_http_failure
run_operation_failure
run_missing_content
run_missing_operation
run_invalid_body
run_transport_failure
echo 'certificate worker response tests passed'
