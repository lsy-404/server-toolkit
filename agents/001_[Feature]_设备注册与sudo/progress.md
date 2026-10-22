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
