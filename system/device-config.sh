#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${SYS_TOOLKIT_DEVICE_CONFIG:-/etc/server-toolkit/device.env}"

usage() { echo "Usage: device-config.sh --doctor | --configure [protected-json-file]"; }

read_input() {
    if [ "$#" -gt 0 ]; then
        [ -f "$1" ] || { echo "设备配置文件不可读" >&2; return 1; }
        local mode; mode=$(stat -c '%a' "$1")
        (( (8#$mode & 077) == 0 )) || { echo "设备配置文件权限过宽，请设置为 600 或更严格" >&2; return 1; }
        cat -- "$1"
    else
        cat
    fi
}

validate_payload() {
    local payload="$1" url token status body
    command -v curl >/dev/null && command -v jq >/dev/null || { echo "依赖缺失：需要 curl 和 jq" >&2; return 1; }
    url=$(jq -er '.vault_url | strings | select(length > 0)' <<<"$payload") || { echo "配置缺少 vault_url" >&2; return 1; }
    token=$(jq -er '.device_uuid | strings | select(length > 0)' <<<"$payload") || { echo "配置缺少 device_uuid" >&2; return 1; }
    [[ "$url" == https://* && "$url" != *$'\n'* && "$url" != *$'\r'* && "$url" != *'"'* && "$url" != *"'"* && "$url" != *'\'* ]] || {
        echo "Vault URL 必须是无引号、无换行的 HTTPS 地址" >&2; return 1;
    }
    [[ "$token" =~ ^[A-Za-z0-9._~+/-]+=*$ ]] || { echo "设备授权格式无效" >&2; return 1; }
    local response_file curl_config; response_file=$(mktemp); curl_config=$(mktemp)
    chmod 600 "$curl_config"
    local curl_url=${url//\\/\\\\}; curl_url=${curl_url//\"/\\\"}
    printf 'url = "%s"\nheader = "Authorization: Bearer %s"\n' "$curl_url" "$token" >"$curl_config"
    status=$(curl --silent --show-error --max-time 15 --config "$curl_config" --output "$response_file" --write-out '%{http_code}' \
        -X POST -H 'Content-Type: application/json' \
        --data '{"ops":[{"id":"get_wl","type":"read","module":"ip","key":"whitelist"}]}' 2>/dev/null) || {
            rm -f "$response_file" "$curl_config"; echo "网络失败：无法连接 Vault" >&2; return 1;
        }
    rm -f "$curl_config"
    body=$(cat "$response_file"); rm -f "$response_file"
    case "$status" in
      200) ;;
      401) echo "授权无效（HTTP 401）" >&2; return 1 ;;
      403) echo "授权无权读取 /ip/whitelist（HTTP 403）" >&2; return 1 ;;
      404) echo "白名单或数据库缺失（HTTP 404）" >&2; return 1 ;;
      5*) echo "Vault/数据库服务错误（HTTP $status）" >&2; return 1 ;;
      *) echo "Vault 请求失败（HTTP $status）" >&2; return 1 ;;
    esac
    local operation_status
    operation_status=$(jq -r 'if type == "array" and length > 0 then (.[0].status // "") | tostring else "" end' <<<"$body" 2>/dev/null || true)
    case "$operation_status" in
      401) echo "授权无效（API operation 401）" >&2; return 1 ;;
      403) echo "授权无权读取 /ip/whitelist（API operation 403）" >&2; return 1 ;;
      404) echo "白名单或数据库缺失（API operation 404）" >&2; return 1 ;;
      5*) echo "Vault/数据库服务错误（API operation $operation_status）" >&2; return 1 ;;
      200) ;;
      *) echo "Vault operation 响应状态无效（$operation_status）" >&2; return 1 ;;
    esac
    jq -e 'type == "array" and length > 0 and (.[0].data.content | type == "string" and length > 0)' <<<"$body" >/dev/null 2>&1 || {
        echo "白名单数据缺失或响应格式无效" >&2; return 1;
    }
    local content; content=$(jq -r '.[0].data.content' <<<"$body")
    local item count=0
    while IFS= read -r item; do
        [ -n "$item" ] || continue
        [[ "$item" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]] || { echo "白名单包含无效 IPv4/CIDR" >&2; return 1; }
        local octet; IFS=. read -r -a octets <<<"${item%%/*}"
        for octet in "${octets[@]}"; do (( 10#$octet <= 255 )) || { echo "白名单包含无效 IPv4/CIDR" >&2; return 1; }; done
        if [[ "$item" == */* ]]; then local mask=${item##*/}; (( 10#$mask <= 32 )) || { echo "白名单包含无效 IPv4/CIDR" >&2; return 1; }; fi
        ((count+=1))
    done < <(tr ', ' '\n\n' <<<"$content" | tr -d '\r')
    (( count > 0 )) || { echo "白名单为空" >&2; return 1; }
}

write_config() {
    local payload="$1" url token dir tmp
    url=$(jq -r '.vault_url' <<<"$payload"); token=$(jq -r '.device_uuid' <<<"$payload")
    dir=$(dirname "$CONFIG_FILE"); install -d -m 700 "$dir"
    tmp=$(mktemp "$dir/device.env.XXXXXX")
    printf "SYS_VAULT_URL='%s'\nSYS_DEVICE_UUID='%s'\n" "$url" "$token" >"$tmp"
    if [ "$CONFIG_FILE" = "/etc/server-toolkit/device.env" ] && [ -f /etc/environment ]; then
        sed -i '/^SYS_VAULT_URL=/d; /^SYS_DEVICE_UUID=/d' /etc/environment
    fi
    chmod 600 "$tmp"; mv -f "$tmp" "$CONFIG_FILE"
}

config_payload() {
    printf '{"vault_url":'
    printf '%s' "$SYS_VAULT_URL" | jq -Rs .
    printf ',"device_uuid":'
    printf '%s' "$SYS_DEVICE_UUID" | jq -Rs .
    printf '}'
}

main() {
    [ "$EUID" -eq 0 ] || { echo "请使用 sudo 运行设备注册/预检" >&2; return 1; }
    case "${1:-}" in
      --configure)
        local payload
        if [ "$#" -ge 2 ]; then payload=$(read_input "$2"); else payload=$(read_input); fi
        validate_payload "$payload"
        write_config "$payload"
        echo "设备授权有效，配置已安全保存。"
        ;;
      --doctor)
        [ -r "$CONFIG_FILE" ] || { echo "设备尚未注册" >&2; return 1; }
        # 设备文件使用 shell quoted 值，source 仅用于读取该 root-only 文件。
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
        [ -n "${SYS_VAULT_URL:-}" ] && [ -n "${SYS_DEVICE_UUID:-}" ] || { echo "设备配置缺少 URL 或授权" >&2; return 1; }
        payload=$(config_payload)
        validate_payload "$payload"
        echo "设备配置、授权与非空 IPv4 白名单均正常。"
        ;;
      *) usage >&2; return 2 ;;
    esac
}

main "$@"
