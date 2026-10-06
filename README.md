# MC 开服器 (mcserv) v1.6

Termux / Linux 上跑 Minecraft 服务端的脚本型启动器。手机也能开服。

## 许可证

**GNU General Public License v3.0 or later** —— 见 `LICENSE`。

一句话概括：随便用、随便改、甚至可以拿去卖钱，
**但只要分发给别人，就必须同时给出完整源码，并以同样的 GPL-3.0 授权。**

## 内置云端公告源

脚本内置了作者维护的公告源，开箱即用，不用手动填：

```
https://siyt.de5.net
```

启动时会在任何依赖检查之前先弹公告，新用户第一次运行就能看到。

**想换成你自己的？** 完全可以：

- 菜单 `27` → `3` 填你的 Worker 地址
- 按 `d` 随时恢复内置源
- 不想看公告：菜单 `27` → `4` 关掉

**但请注意**：你把公告地址改成自己的、再把改过的版本发给别人用（收费或免费），
按 GPL-3.0 你必须一并提供修改后的完整源码。这不是限制，这正是本项目选择 GPL 的原因。

## 主要功能

| 菜单 | 功能 |
|---|---|
| 1-3 | 新建 / 选择 / 删除服务器 |
| 4 | 核心安装（Fabric / Forge / NeoForge / Paper 等），自动配 Java |
| 5 | 启动服务端 |
| 6-7 | 备份 / 恢复存档 |
| 10 | 设置（内存、JVM 参数、MOTD） |
| 15 | 白名单 |
| 18 | 后台保活（唤醒锁） |
| 21-22 | 模组 / 插件管理 |
| 23 | FRP 内网穿透 |
| 24 | 守护（崩溃自动拉起 + 定时备份） |
| 25 | 一键自检 |
| 26 | 安卓权限中心（root / Shizuku / proot） |
| 27 | 云端公告 |

## 快速开始

```sh
# Termux 里
pkg install bash curl
bash mcserv.sh
```

首次运行会自动补齐依赖（curl / python3 / unzip / termux-api 等），
每个包装完都会显示结果，不会闷头装。

> **MT 管理器用户**：脚本已内置 bash 自举守卫，但 MT 自带终端只有 `sh`，
> 建议装 Termux 后运行。

## 配套文件

- `mcserv.sh` —— 主脚本
- `perm.sh` —— 安卓权限 API 独立版（主脚本已内置，可单独 source）
- `announce-worker.js` —— Cloudflare Worker 公告服务端，带网页后台
- `公告后台部署说明.md` —— Worker 部署步骤
- `LICENSE` —— GPL-3.0 全文
