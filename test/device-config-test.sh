#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat >"$TMP/bin/curl" <<'MOCK'
#!/usr/bin/env bash
[[ " $* " != *"Bearer test-token"* ]] || exit 90
[[ " $* " != *"vault.example/api"* ]] || exit 91
if [[ " ${*} " == *"--config "* ]]; then
  config=$(printf '%s\n' "$@" | awk 'last {print; exit} $0=="--config" {last=1}')
  grep -q '^url = "https://vault.example/api"$' "$config"
  grep -q '^header = "Authorization: Bearer test-token"$' "$config"
fi
[[ "${CURL_FAIL:-0}" != 1 ]] || exit 7
status=${CURL_STATUS:-200}
output=$(printf '%s\n' "$@" | awk 'last {print; exit} $0=="--output" {last=1}')
case "$status" in
  200)
    if [[ -n "${CURL_BODY:-}" ]]; then printf '%s' "$CURL_BODY" >"$output"
    else printf '%s' '[{"id":"get_wl","status":200,"data":{"content":"192.0.2.10, 198.51.100.0/24"}}]' >"$output"; fi
    ;;
  *) printf '%s' '{}' >"$output" ;;
esac
printf '%s' "$status"
MOCK
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH" SYS_TOOLKIT_DEVICE_CONFIG="$TMP/device.env"
SCRIPT="$SCRIPT_DIR/system/device-config.sh"
payload='{"vault_url":"https://vault.example/api","device_uuid":"test-token"}'

run_fail() {
  local expected=$1 status=$2
  rm -f "$SYS_TOOLKIT_DEVICE_CONFIG"
  if CURL_STATUS=$status bash "$SCRIPT" --configure <<<"$payload" >"$TMP/out" 2>&1; then
    echo "expected failure for HTTP $status" >&2; exit 1
  fi
  grep -q "$expected" "$TMP/out"
  [[ ! -e "$SYS_TOOLKIT_DEVICE_CONFIG" ]]
}

bash "$SCRIPT" --configure <<<"$payload" >"$TMP/out"
if grep -q 'test-token' "$TMP/out"; then exit 1; fi
[[ "$(stat -c %a "$SYS_TOOLKIT_DEVICE_CONFIG")" == 600 ]]
grep -q "SYS_DEVICE_UUID='test-token'" "$SYS_TOOLKIT_DEVICE_CONFIG"
sh -c '. "$1"; test "$SYS_DEVICE_UUID" = test-token' sh "$SYS_TOOLKIT_DEVICE_CONFIG"
bash "$SCRIPT" --doctor >"$TMP/out"
if command -v runuser >/dev/null 2>&1; then
  if runuser -u nobody -- bash "$SCRIPT" --doctor >"$TMP/out" 2>&1; then exit 1; fi
  grep -q 'sudo' "$TMP/out"
fi
export SYS_TOOLKIT_DEVICE_CONFIG="$TMP/helper.env"
source "$SCRIPT_DIR/helper.sh"
set_config_value SYS_VAULT_URL 'https://vault.example/api'
set_config_value SYS_DEVICE_UUID 'first-token'
set_config_value SYS_VAULT_URL 'https://vault.example/new-api'
[[ "$(get_device_uuid)" == 'first-token' ]]
set_config_value SYS_DEVICE_UUID 'second-token'
[[ "$(get_vault_url)" == 'https://vault.example/new-api' ]]
sh -c '. "$1"; test "$SYS_DEVICE_UUID" = second-token' sh "$SYS_TOOLKIT_DEVICE_CONFIG"
export SYS_TOOLKIT_DEVICE_CONFIG="$TMP/device.env"
rm -f "$SYS_TOOLKIT_DEVICE_CONFIG"
printf '%s' "$payload" >"$TMP/protected.json"
chmod 600 "$TMP/protected.json"
bash "$SCRIPT" --configure "$TMP/protected.json" >"$TMP/out"
rm -f "$SYS_TOOLKIT_DEVICE_CONFIG"
chmod 644 "$TMP/protected.json"
if bash "$SCRIPT" --configure "$TMP/protected.json" >"$TMP/out" 2>&1; then exit 1; fi
[[ ! -e "$SYS_TOOLKIT_DEVICE_CONFIG" ]]
run_fail '授权无效' 401
run_fail '无权读取' 403
run_fail '白名单或数据库缺失' 404
run_fail '服务错误' 500
run_operation_fail() {
  local expected=$1 operation_status=$2
  rm -f "$SYS_TOOLKIT_DEVICE_CONFIG"
  if CURL_BODY='[{"status":'"$operation_status"'}]' bash "$SCRIPT" --configure <<<"$payload" >"$TMP/out" 2>&1; then exit 1; fi
  grep -q "$expected" "$TMP/out"
  [[ ! -e "$SYS_TOOLKIT_DEVICE_CONFIG" ]]
}
run_operation_fail '无权读取' 403
run_operation_fail '白名单或数据库缺失' 404
run_operation_fail '服务错误' 500
rm -f "$SYS_TOOLKIT_DEVICE_CONFIG"
if CURL_BODY='[{"status":202,"data":{"content":"192.0.2.1"}}]' bash "$SCRIPT" --configure <<<"$payload" >"$TMP/out" 2>&1; then exit 1; fi
grep -q 'operation 响应状态无效' "$TMP/out"
if bash "$SCRIPT" --configure <<<'{"vault_url":"http://vault.example","device_uuid":"test-token"}' >/dev/null 2>&1; then exit 1; fi
if bash "$SCRIPT" --configure <<<'{"vault_url":"https://vault.example/\"bad","device_uuid":"test-token"}' >/dev/null 2>&1; then exit 1; fi
CURL_BODY='[{"data":{"content":"192.0.2.1"}}]' bash "$SCRIPT" --configure <<<"$payload" >"$TMP/out" 2>&1 && exit 1
grep -q 'operation 响应状态无效' "$TMP/out"
CURL_BODY='[{"id":"get_wl","status":200,"data":{"content":""}}]' bash "$SCRIPT" --configure <<<"$payload" >/dev/null 2>&1 && exit 1
CURL_BODY='[{"id":"get_wl","status":200,"data":{"content":"999.2.3.4"}}]' bash "$SCRIPT" --configure <<<"$payload" >/dev/null 2>&1 && exit 1
CURL_BODY='[{"id":"get_wl","status":200,"data":{"content":"192.0.2.0/33"}}]' bash "$SCRIPT" --configure <<<"$payload" >/dev/null 2>&1 && exit 1
CURL_FAIL=1 bash "$SCRIPT" --configure <<<"$payload" >"$TMP/out" 2>&1 && exit 1
grep -q '网络失败' "$TMP/out"

mkdir -p "$TMP/work/scripts/firewall-whitelist" "$TMP/bin"
cp "$SCRIPT_DIR/helper.sh" "$TMP/work/helper.sh"
cat >"$TMP/work/device-config.sh" <<'DOCTOR'
#!/usr/bin/env bash
echo "白名单为空" >&2
exit 1
DOCTOR
chmod +x "$TMP/work/device-config.sh"
sed "s|WORKDIR=\"/srv/server-toolkit\"|WORKDIR=\"$TMP/work\"|" \
  "$SCRIPT_DIR/firewall-whitelist/deploy.sh" >"$TMP/work/scripts/firewall-whitelist/deploy.sh"
cat >"$TMP/bin/iptables" <<'IPTABLES'
#!/usr/bin/env bash
touch "$IPTABLES_MARKER"
IPTABLES
chmod +x "$TMP/bin/iptables"
export IPTABLES_MARKER="$TMP/iptables-called" PATH="$TMP/bin:$PATH"
if bash "$TMP/work/scripts/firewall-whitelist/deploy.sh" --mode loose >"$TMP/out" 2>&1; then exit 1; fi
grep -q '尚未更改防火墙规则' "$TMP/out"
[[ ! -e "$IPTABLES_MARKER" ]]
echo "device-config tests passed"
