# 进度
- 使用独立工作树 `codex/ssh-hardening`，未触碰主检出或线上防火墙。
- 新增 `system/device-config.sh`，从 stdin JSON 或权限收紧的 JSON 文件读取 Vault URL 和 token；仅对 HTTPS API 执行 read /ip/whitelist，分别识别 HTTP 与 operation 级 401/403/404/5xx，验证合法非空 IPv4/CIDR 后才以 600 权限保存配置。
- 菜单提供注册和 doctor；安装器以本地脚本路径 sudo 重入；工具菜单可由 sudo 管理员调用。
- 防火墙部署在任何拒绝规则前执行 doctor，检查 iptables/ipset/crontab，启用 cron，并验证周期和启动时同步条目；支持 `--mode loose`。
- worker 只读取受保护配置，保持 API 失败撤回行为；POSIX sh 可读取配置。
- 在东京服务器 `/tmp/server-toolkit-device-test` 执行 Bash 语法和测试套件，成功。覆盖无 sudo、操作状态分类、配置权限/引用、单项配置更新及无效预检下无 iptables 调用。
- 追加修复：worker 使用 umask 077 的临时 curl config 文件传递 Authorization，curl argv 不带 token；请求结束立即删除并由 exit trap 兜底。
- 新增 worker 隔离测试，断言 argv 无 token、配置文件为 600、worker 同步后配置文件消失；远端 Bash 语法和测试通过。

- root复核两个实现提交及diff-check，无任务号/模型署名关键词。运行时令牌已移出curl argv；保留私钥显示与API失败fallback。
- 普通管理用户仍通过sudo提权，不更改任何SSH账户/密钥，不强制root登录。
- [x] 自更新 Git 与直连下载路径同步核心 device-config.sh，并恢复 700 权限。
- [x] 使用本地 Git remote 与 curl mock 在隔离目录分别运行两条真实自更新分支，确认核心文件内容和权限更新。
- 最新部署复核发现显式 `--mode` 路径末尾仍会询问可选 Fail2ban 清理；本次补充为非交互跳过并保留 Fail2ban，交互入口维持现状。
- 远端隔离 Bash 测试通过：显式模式不调用输入函数且不触发 apt；交互模式仍读取用户选择。仅运行隔离尾段和语法检查，未执行部署或修改防火墙。
