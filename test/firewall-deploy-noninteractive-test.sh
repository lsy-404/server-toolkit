#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

awk 'found || /^# 6\. 交互式卸载 Fail2ban$/ { found = 1 } found { print }' \
    "$ROOT_DIR/firewall-whitelist/deploy.sh" > "$TEMP_DIR/optional-cleanup.sh"
test -s "$TEMP_DIR/optional-cleanup.sh"

mkdir -p "$TEMP_DIR/bin"
cat > "$TEMP_DIR/bin/dpkg" <<'EOF'
#!/bin/sh
printf 'ii  fail2ban  installed\n'
EOF
cat > "$TEMP_DIR/bin/apt" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$APT_CALLS"
EOF
chmod +x "$TEMP_DIR/bin/dpkg" "$TEMP_DIR/bin/apt"

PATH="$TEMP_DIR/bin:$PATH" INPUT_CALLS="$TEMP_DIR/noninteractive-input" \
    APT_CALLS="$TEMP_DIR/noninteractive-apt" bash -c '
        REQUESTED_MODE=loose
        input_single_char() { touch "$INPUT_CALLS"; read -r answer; printf "%s\n" "$answer"; }
        source "$1"
    ' bash "$TEMP_DIR/optional-cleanup.sh" <<< 'y' > "$TEMP_DIR/noninteractive-output"

test ! -e "$TEMP_DIR/noninteractive-input"
test ! -e "$TEMP_DIR/noninteractive-apt"
grep -q '保留 Fail2ban' "$TEMP_DIR/noninteractive-output"

PATH="$TEMP_DIR/bin:$PATH" INPUT_CALLS="$TEMP_DIR/interactive-input" \
    APT_CALLS="$TEMP_DIR/interactive-apt" bash -c '
        REQUESTED_MODE=
        input_single_char() { touch "$INPUT_CALLS"; read -r answer; printf "%s\n" "$answer"; }
        source "$1"
    ' bash "$TEMP_DIR/optional-cleanup.sh" <<< 'n' > "$TEMP_DIR/interactive-output"

test -e "$TEMP_DIR/interactive-input"
test ! -e "$TEMP_DIR/interactive-apt"
grep -q '已跳过卸载' "$TEMP_DIR/interactive-output"
printf 'firewall noninteractive deploy test passed\n'
