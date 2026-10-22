# 发现
- Vault Worker 可在 HTTP 200 响应中返回每项 operation 状态；只检查 HTTP 状态会把 403/404/500 误报成白名单缺失，注册需要同时要求 operation status 200。
- worker 由 `/bin/sh` 调用，设备配置必须用 POSIX 安全赋值格式，不能使用 Bash `%q`。
- `cron_add` 会将定时任务写入 crontab；防火墙拒绝规则前应确认 cron 服务和任务已运行/保存。
- 首轮测试发现 stdin 分支把空参数当作文件名、测试 mock JSON 缺少 operation status；已修正并复测通过。
- 新设备 token 虽通过 doctor 配置文件隐藏了注册过程 argv，但周期 worker 原先仍把 Bearer 头放在 curl argv；同步进程对同机普通用户可见。已改为临时 curl config 并在请求后清理。

- 已核实真实Vault Worker与KV/D1绑定、生产域名；D1 ip/whitelist存在，13条合法IPv4/CIDR。三台独立设备只获/ip/whitelist:r，实测跨模块403、无效token401，三台当前SSH来源均被覆盖。凭据未进入源码或审计。
- 三台均尚未安装toolkit，ubuntu sudo管理可用、现有密码认证禁用；Tokyo02 runner活跃，其余两台无运行runner。只计划loose模式，保留现有其他端口/服务。
- main保护状态经GitHub API确认false；主检出干净，允许快进合并和push。
- core device-config.sh 在初次安装后会位于安装根目录；自更新若不覆盖，会使 doctor 保持旧版。现两条更新路径同时纳入复制/下载和 chmod 700。
