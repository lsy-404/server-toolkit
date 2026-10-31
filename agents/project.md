# Server Toolkit
> 最后更新：2026-10-30

## 项目目标
在 Ubuntu 服务器通过统一脚本管理 SSH 白名单、系统维护及 Vault 设备配置。

## 技术栈
Bash、curl/jq、iptables/ipset；Vault 使用 Cloudflare Worker/KV 认证与 D1 数据。测试位于根目录 /test。

## 模块结构
- `cert/`: 从 Vault 同步生产与源站 TLS 证书，管理本地文件、符号链接和服务重载。
- `firewall-whitelist/`: 通过 Vault 设备身份同步 SSH 白名单。
- `setup/`, `system/`: 主机引导及系统维护。

## 项目约定
测试存放在根目录 `/test`。设备 Vault 配置优先读取 `/etc/server-toolkit/device.env`，再回退到 `/etc/environment`。

## 既有部署范围
东京两台 AMD 和一台 A1；设备注册支持私钥显示和服务异常撤回拦截 fallback，普通管理用户可通过 sudo 执行特权操作。
