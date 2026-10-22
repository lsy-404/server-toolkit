#!/bin/bash
# Firewall Whitelist Deployment Script
# (Formerly: SSH Security)

# Configuration constants
DOCKER_NETWORK_CIDR="172.16.0.0/12"
HTTP_PORTS="80,443"  # Publicly accessible web service ports in strict mode
SSH_PORT="22"        # SSH port, always restricted to whitelist
REQUESTED_MODE=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --mode)
            [ "$#" -ge 2 ] || { echo "用法: $0 [--mode loose|strict]"; exit 2; }
            case "$2" in loose|strict) REQUESTED_MODE="$2" ;; *) echo "防火墙模式必须是 loose 或 strict"; exit 2 ;; esac
            shift 2
            ;;
        *) echo "未知参数: $1"; echo "用法: $0 [--mode loose|strict]"; exit 2 ;;
    esac
done

# Module identifiers (for backward compatibility)
MODULE_ID="firewall-whitelist"
LEGACY_MODULE_ID="ssh-security"
IPTABLES_TAG="#firewall-whitelist"
LEGACY_IPTABLES_TAG="#ssh-security"

# ===== 工作目录保护（强制要求） =====
WORKDIR="/srv/server-toolkit"
# 确保工作目录存在
mkdir -p "$WORKDIR"
# 强制设置工作目录，如果失败则修改权限
if ! cd "$WORKDIR" 2>/dev/null; then
    # 如果无法进入，尝试修复权限
    chmod 755 "$WORKDIR" 2>/dev/null || mkdir -p "$WORKDIR"
    cd "$WORKDIR" || { echo "错误: 无法访问工作目录 $WORKDIR"; exit 1; }
fi
# ====================================

# 加载 helper 函数
if [ -f "$WORKDIR/helper.sh" ]; then
    source "$WORKDIR/helper.sh"
else
    echo "错误: 找不到 helper.sh"
    exit 1
fi

# Storage directory for persistent data (with backward compatibility)
STORAGE_DIR="$WORKDIR/storage/$MODULE_ID"
LEGACY_STORAGE_DIR="$WORKDIR/storage/$LEGACY_MODULE_ID"

# Migrate from old storage directory if it exists
if [ -d "$LEGACY_STORAGE_DIR" ] && [ ! -d "$STORAGE_DIR" ]; then
    echo -e "${COLOR_YELLOW}检测到旧版本数据目录，正在迁移...${COLOR_RESET}"
    mv "$LEGACY_STORAGE_DIR" "$STORAGE_DIR"
    echo -e "${COLOR_GREEN}✓ 数据迁移完成${COLOR_RESET}"
fi

mkdir -p "$STORAGE_DIR"

echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"
echo -e "${COLOR_BLUE}      防火墙白名单部署脚本${COLOR_RESET}"
echo -e "${COLOR_BLUE}========================================${COLOR_RESET}"

# Verify authorization and a non-empty valid whitelist before changing firewall rules.
echo -e "\n${COLOR_BLUE}步骤 1: 校验设备授权与白名单${COLOR_RESET}"
DEVICE_CONFIG="$WORKDIR/device-config.sh"
[ -x "$DEVICE_CONFIG" ] || { echo "错误: 找不到设备预检程序"; exit 1; }
"$DEVICE_CONFIG" --doctor || { echo "错误: 预检失败，尚未更改防火墙规则"; exit 1; }
# shellcheck disable=SC1091
. /etc/server-toolkit/device.env

# 2. 安装依赖
echo -e "\n${COLOR_BLUE}步骤 2: 安装依赖软件包${COLOR_RESET}"
missing_packages=()
command -v ipset >/dev/null 2>&1 || missing_packages+=(ipset)
command -v iptables >/dev/null 2>&1 || missing_packages+=(iptables)
command -v crontab >/dev/null 2>&1 || missing_packages+=(cron)
if [ "${#missing_packages[@]}" -gt 0 ]; then
    command -v apt-get >/dev/null 2>&1 || { echo -e "${COLOR_RED}错误: 缺少依赖 ${missing_packages[*]}，且找不到 apt-get${COLOR_RESET}"; exit 1; }
    echo -e "${COLOR_YELLOW}缺少命令: ${missing_packages[*]}；正在安装对应软件包${COLOR_RESET}"
    apt-get update && apt-get install -y "${missing_packages[@]}" || {
        echo -e "${COLOR_RED}错误: 无法安装防火墙依赖 ${missing_packages[*]}${COLOR_RESET}"; exit 1;
    }
fi
if ! command -v systemctl >/dev/null 2>&1 || ! systemctl enable --now cron || ! systemctl is-active --quiet cron; then
    echo -e "${COLOR_RED}错误: cron 服务无法启用并运行，尚未更改防火墙规则${COLOR_RESET}"
    exit 1
fi

# 3. 部署 worker 脚本
echo -e "\n${COLOR_BLUE}步骤 3: 部署同步 worker 脚本${COLOR_RESET}"
WORKER_SCRIPT="$STORAGE_DIR/worker.sh"
LOG_FILE="$STORAGE_DIR/sync.log"

# 复制 worker 脚本模板到 storage 目录
cp "$WORKDIR/scripts/$MODULE_ID/worker.sh" "$WORKER_SCRIPT"
chmod +x "$WORKER_SCRIPT"

echo -e "${COLOR_GREEN}✓ Worker 脚本已部署到: $WORKER_SCRIPT${COLOR_RESET}"

# Register periodic synchronization before enabling any default-deny rule.
echo -e "\n${COLOR_BLUE}步骤 3.4: 配置并验证定时同步${COLOR_RESET}"
cron_remove "$LEGACY_MODULE_ID"
cron_add "$MODULE_ID" "*/10 * * * *" "/bin/sh $WORKER_SCRIPT >> $LOG_FILE 2>&1" || {
    echo -e "${COLOR_RED}错误: 无法创建白名单同步任务，尚未更改防火墙规则${COLOR_RESET}"; exit 1;
}
cron_remove "$MODULE_ID-boot"
cron_add "$MODULE_ID-boot" "@reboot" "/bin/sh $WORKER_SCRIPT >> $LOG_FILE 2>&1" || {
    echo -e "${COLOR_RED}错误: 无法创建启动时白名单同步任务，尚未更改防火墙规则${COLOR_RESET}"; exit 1;
}
crontab -l 2>/dev/null | grep -F "#server-toolkit-$MODULE_ID" >/dev/null || {
    echo -e "${COLOR_RED}错误: 未找到已保存的白名单同步任务，尚未更改防火墙规则${COLOR_RESET}"; exit 1;
}
crontab -l 2>/dev/null | grep -F "#server-toolkit-$MODULE_ID-boot" >/dev/null || {
    echo -e "${COLOR_RED}错误: 未找到已保存的启动时同步任务，尚未更改防火墙规则${COLOR_RESET}"; exit 1;
}

# 3.5. 选择防火墙模式
echo -e "\n${COLOR_BLUE}步骤 3.5: 选择防火墙模式${COLOR_RESET}"
echo -e "${COLOR_YELLOW}请选择 IP 白名单策略模式:${COLOR_RESET}"
echo -e "${COLOR_CYAN}  [1] 宽松模式 (loose)${COLOR_RESET} - 仅限制 SSH 端口 22 到白名单"
echo -e "${COLOR_CYAN}  [2] 严格模式 (strict)${COLOR_RESET} - SSH 仅限白名单，HTTP/HTTPS 公开，其他端口仅限本机/Docker/白名单"
echo ""

# 读取用户选择并存储到配置文件
MODE_CONFIG="$STORAGE_DIR/firewall_mode.conf"
if [ -f "$MODE_CONFIG" ]; then
    CURRENT_MODE=$(cat "$MODE_CONFIG")
    echo -e "${COLOR_YELLOW}当前模式: $CURRENT_MODE${COLOR_RESET}"
fi

if [ -n "$REQUESTED_MODE" ]; then
    FIREWALL_MODE="$REQUESTED_MODE"
elif [ "$(input_single_char "请输入选择 (1=宽松, 2=严格)" "1")" = "2" ]; then
    FIREWALL_MODE="strict"
else
    FIREWALL_MODE="loose"
fi

if [ "$FIREWALL_MODE" = "strict" ]; then
    echo -e "${COLOR_GREEN}✓ 已选择严格模式${COLOR_RESET}"
else
    echo -e "${COLOR_GREEN}✓ 已选择宽松模式${COLOR_RESET}"
fi

# 保存模式到配置文件
echo "$FIREWALL_MODE" > "$MODE_CONFIG"

# 3.6. 设置默认拒绝规则（在白名单同步前先拒绝）
echo -e "\n${COLOR_BLUE}步骤 3.6: 设置默认拒绝规则${COLOR_RESET}"
# 清理旧的规则（包括旧版本的标签）
iptables -S INPUT | grep "$LEGACY_IPTABLES_TAG" | sed "s/-A/iptables -D/" | bash 2>/dev/null || true
iptables -S INPUT | grep "$IPTABLES_TAG" | sed "s/-A/iptables -D/" | bash 2>/dev/null || true

# 根据模式设置规则
if [ "$FIREWALL_MODE" = "strict" ]; then
    echo -e "${COLOR_YELLOW}严格模式: 配置全局防火墙规则${COLOR_RESET}"
    # 严格模式：SSH 仅限白名单，HTTP/HTTPS 公开，其他端口仅限本机、Docker和白名单
    # 注意：这些规则会被 worker.sh 维护和更新
    
    # 基础规则：允许已建立的连接（系统可能已有此规则，但显式添加确保一致性）
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT -m comment --comment "$IPTABLES_TAG" 2>/dev/null || true
    
    # 允许本机访问
    iptables -A INPUT -i lo -j ACCEPT -m comment --comment "$IPTABLES_TAG"
    
    # 允许 Docker 网络访问
    iptables -A INPUT -s "$DOCKER_NETWORK_CIDR" -j ACCEPT -m comment --comment "$IPTABLES_TAG"
    
    # 严格模式: 仅允许 HTTP/HTTPS 从任何来源访问，SSH 仅限白名单
    iptables -A INPUT -p tcp -m multiport --dports "$HTTP_PORTS" -j ACCEPT -m comment --comment "$IPTABLES_TAG"
    
    # SSH 端口拒绝（会被白名单规则优先覆盖）
    iptables -A INPUT -p tcp --dport "$SSH_PORT" -j DROP -m comment --comment "$IPTABLES_TAG"
    
    # 其他所有端口拒绝（会被白名单规则优先覆盖）
    iptables -A INPUT -j DROP -m comment --comment "$IPTABLES_TAG"
    
    echo -e "${COLOR_GREEN}✓ 严格模式规则已设置${COLOR_RESET}"
else
    echo -e "${COLOR_YELLOW}宽松模式: 仅限制 SSH 端口${COLOR_RESET}"
    # 宽松模式：只限制 SSH 端口
    iptables -A INPUT -p tcp --dport "$SSH_PORT" -j DROP -m comment --comment "$IPTABLES_TAG"
    echo -e "${COLOR_GREEN}✓ 宽松模式规则已设置（仅限制 SSH）${COLOR_RESET}"
fi

# 5. 立即执行首次同步
echo -e "\n${COLOR_BLUE}步骤 5: 执行首次同步${COLOR_RESET}"
/bin/sh "$WORKER_SCRIPT"

echo -e "\n${COLOR_GREEN}========================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}         部署完成！层级防护已就绪${COLOR_RESET}"
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}防火墙模式: $FIREWALL_MODE${COLOR_RESET}"
if [ "$FIREWALL_MODE" = "strict" ]; then
    echo -e "${COLOR_GREEN}严格模式规则:${COLOR_RESET}"
    echo -e "${COLOR_GREEN}  • 白名单 IP: 可访问所有端口 (最高优先级)${COLOR_RESET}"
    echo -e "${COLOR_GREEN}  • 本机 (localhost): 可访问所有端口${COLOR_RESET}"
    echo -e "${COLOR_GREEN}  • Docker 网络 ($DOCKER_NETWORK_CIDR): 可访问所有端口${COLOR_RESET}"
    echo -e "${COLOR_GREEN}  • HTTP/HTTPS (80/443): 任意来源可访问${COLOR_RESET}"
    echo -e "${COLOR_RED}  • SSH (22): 仅限白名单 ⚠️${COLOR_RESET}"
    echo -e "${COLOR_RED}  • 其他端口: 拒绝 ⚠️${COLOR_RESET}"
else
    echo -e "${COLOR_GREEN}宽松模式规则:${COLOR_RESET}"
    echo -e "${COLOR_GREEN}  • 白名单 IP: 可访问所有端口${COLOR_RESET}"
    echo -e "${COLOR_RED}  • SSH 端口 22: 仅限白名单 ⚠️${COLOR_RESET}"
    echo -e "${COLOR_GREEN}  • 其他端口: 遵循系统默认规则${COLOR_RESET}"
fi
echo -e "${COLOR_YELLOW}熔断: 若 API 异常，层级防护自动失效，确保管理入口可用${COLOR_RESET}"
echo -e "Worker 脚本: $WORKER_SCRIPT"
echo -e "日志文件: $LOG_FILE"
echo -e "模式配置: $MODE_CONFIG"
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"

# 6. 交互式卸载 Fail2ban
echo -e "\n${COLOR_BLUE}可选操作: 清理旧策略${COLOR_RESET}"
if [ -n "$REQUESTED_MODE" ]; then
    echo -e "${COLOR_YELLOW}非交互部署，保留 Fail2ban${COLOR_RESET}"
elif dpkg -l | grep -q fail2ban; then
    confirm=$(input_single_char "检测到 Fail2ban 已安装，是否需要卸载以清理旧策略? (y/n)" "n")
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        apt purge fail2ban -y && apt autoremove -y
        echo -e "${COLOR_GREEN}Fail2ban 已卸载${COLOR_RESET}"
    else
        echo -e "${COLOR_YELLOW}已跳过卸载${COLOR_RESET}"
    fi
else
    echo -e "${COLOR_YELLOW}未检测到 Fail2ban，跳过卸载${COLOR_RESET}"
fi
