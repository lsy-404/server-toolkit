#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

awk '/^do_self_update\(\) \{/ {inside=1} inside {print} inside && /^}/ {exit}' \
  "$ROOT/menu.sh" >"$TMP/update-function.sh"
source "$TMP/update-function.sh"
get_install_dir() { printf '%s\n' "$INSTALL_DIR"; }
version_ge() { [[ "$1" == 1.0.0 || "$1" == 2.0.0 ]]; }
log_success() { :; }
COLOR_CYAN=""
COLOR_RESET=""
COLOR_GREEN=""
COLOR_YELLOW=""
RAW_REPO_URL="https://updates.invalid/server-toolkit/main"

create_payload() {
  local target=$1 version=$2
  mkdir -p "$target/system"
  printf 'menu %s\n' "$version" >"$target/menu.sh"
  printf ': # helper %s\n' "$version" >"$target/helper.sh"
  printf '{"version":"%s","modules":[]}\n' "$version" >"$target/config.json"
  printf 'device config %s\n' "$version" >"$target/system/device-config.sh"
}

# Git update mode
git init --bare --initial-branch=main "$TMP/origin.git" >/dev/null
git clone "$TMP/origin.git" "$TMP/source" >/dev/null 2>&1
git -C "$TMP/source" config user.name Test
git -C "$TMP/source" config user.email test@example.invalid
git -C "$TMP/source" config commit.gpgsign false
create_payload "$TMP/source" 1.0.0
git -C "$TMP/source" add .
git -C "$TMP/source" commit -m initial >/dev/null
git -C "$TMP/source" push -u origin main >/dev/null 2>&1
mkdir -p "$TMP/git-install"
printf '{"version":"1.0.0","modules":[]}\n' >"$TMP/git-install/config.json"
git clone "$TMP/origin.git" "$TMP/git-install/scripts" >/dev/null 2>&1
create_payload "$TMP/source" 2.0.0
git -C "$TMP/source" add .
git -C "$TMP/source" commit -m update >/dev/null
git -C "$TMP/source" push origin main >/dev/null 2>&1

cat >"$TMP/bin/curl" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"
INSTALL_DIR="$TMP/git-install"
do_self_update >/dev/null
[[ "$(cat "$INSTALL_DIR/device-config.sh")" == 'device config 2.0.0' ]]
[[ "$(stat -c '%a' "$INSTALL_DIR/device-config.sh")" == 700 ]]

# Direct download mode
create_payload "$TMP/download-source" 2.0.0
mkdir -p "$TMP/download-install"
printf '{"version":"1.0.0","modules":[]}\n' >"$TMP/download-install/config.json"
cat >"$TMP/bin/curl" <<'MOCK'
#!/usr/bin/env bash
output=""
url=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then output=$2; shift 2; else url=$1; shift; fi
done
if [ -z "$output" ]; then
  if [[ "$url" == *api.github.com* ]]; then exit 0; fi
  cat "$UPDATE_SOURCE_DIR/config.json"
else
  if [[ "$url" == */system/device-config.sh ]]; then
    cp "$UPDATE_SOURCE_DIR/system/device-config.sh" "$output"
  else
    cp "$UPDATE_SOURCE_DIR/${url##*/}" "$output"
  fi
fi
MOCK
chmod +x "$TMP/bin/curl"
export UPDATE_SOURCE_DIR="$TMP/download-source"
INSTALL_DIR="$TMP/download-install"
do_self_update >/dev/null
[[ "$(cat "$INSTALL_DIR/device-config.sh")" == 'device config 2.0.0' ]]
[[ "$(stat -c '%a' "$INSTALL_DIR/device-config.sh")" == 700 ]]
echo "menu self-update tests passed"
