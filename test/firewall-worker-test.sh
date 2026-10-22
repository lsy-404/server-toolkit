#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/work/storage/firewall-whitelist"
export TEST_DEVICE_CONFIG="$TMP/device.env"
export SYS_TOOLKIT_DEVICE_CONFIG="$TEST_DEVICE_CONFIG"
export CURL_CONFIG_PATH_FILE="$TMP/curl-config-path"
export IPTABLES_MARKER="$TMP/iptables-called"
cat >"$TEST_DEVICE_CONFIG" <<EOF
SYS_VAULT_URL='https://vault.example/api'
SYS_DEVICE_UUID='unit-test-secret'
SYS_TOOLKIT_DIR='$TMP/work'
EOF
chmod 600 "$TEST_DEVICE_CONFIG"

cat >"$TMP/bin/curl" <<'MOCK'
#!/usr/bin/env bash
[[ " $* " != *"unit-test-secret"* ]] || exit 90
config=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--config" ]; then config=$2; shift 2; else shift; fi
done
[[ -n "$config" && -f "$config" ]]
[[ "$(stat -c '%a' "$config")" == 600 ]]
grep -q '^header = "Authorization: Bearer unit-test-secret"$' "$config"
printf '%s' "$config" >"$CURL_CONFIG_PATH_FILE"
printf '%s' '[{"data":{"content":"192.0.2.0/24"}}]'
MOCK
cat >"$TMP/bin/iptables" <<'MOCK'
#!/usr/bin/env bash
touch "$IPTABLES_MARKER"
MOCK
cat >"$TMP/bin/ipset" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$TMP/bin/curl" "$TMP/bin/iptables" "$TMP/bin/ipset"
export PATH="$TMP/bin:$PATH"

sed "s|/etc/server-toolkit/device.env|$TEST_DEVICE_CONFIG|g" \
  "$ROOT/firewall-whitelist/worker.sh" >"$TMP/worker.sh"
sh "$TMP/worker.sh"
config_path=$(cat "$CURL_CONFIG_PATH_FILE")
[[ ! -e "$config_path" ]]
[[ -e "$IPTABLES_MARKER" ]]
echo "firewall worker credential test passed"
