# Server Toolkit
> 最后更新：2026-10-22

## 项目目标
在 Ubuntu 服务器通过统一脚本管理 SSH 白名单、系统维护及 Vault 设备配置。

## 技术栈
Bash、curl/jq、iptables/ipset；Vault 使用 Cloudflare Worker/KV 认证与 D1 数据。测试位于根目录 /test。

## 本次范围
仅部署东京两台 AMD 和一台 A1。保留私钥显示用途与服务异常撤回拦截的 fallback。优先改善授权注册及数据库依赖，允许普通管理用户通过 sudo 执行特权操作。
