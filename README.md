# ShCraft v1.6.1

> 品牌名 **ShCraft** = 脚本文件 `mcserv.sh`

Termux / Linux 上跑 Minecraft 服务端的脚本型启动器。手机也能开服。

**English:** ShCraft (`mcserv.sh`) is a bash-based launcher that runs a Minecraft
server on Termux / Linux — yes, on your phone. Install server cores, download mods,
back up worlds, set up FRP tunneling and manage whitelists, all from a menu.

---

## 下载

**只要 `ShCraft-v1.6.zip`**，解压后：

```sh
bash mcserv.sh
```

首次运行会自动补齐依赖（curl / python3 / unzip / termux-api 等），每个包装完都会显示结果，不会闷头装。

> **MT 管理器用户**：脚本已内置 bash 自举守卫，但 MT 自带终端只有 `sh`，建议装 Termux 后运行。

---

## 本次更新

### 新增

- **守护中心（菜单 24）**
  - 崩溃自动拉起：java 进程没了自动重启，连续崩溃上限可设（默认 3 次）
  - 定时备份：运行中每 N 分钟自动备份，复用保留份数设置
  - 开服自动挂守护，停服前自动撤掉
- **安卓权限中心（菜单 26）**：按序号获取权限
  - 存储 / 电池优化白名单 / 通知 / 悬浮窗 / 自启动 / 未知应用 / VPN
  - 提权自动择优：root → Shizuku → 普通
  - 每项三级降级：静默授予 → 跳设置页 → 记进跳过名单
- **云端公告（菜单 27）**：Cloudflare Worker + KV，带网页后台
  - 依赖安装之前就弹，新用户第一次运行就能看到
  - 每次启动直接拉取，改了公告立刻生效
- **目录浏览器（图标菜单 7）**：扫不到图时逐层翻目录选
- **`bundle/` 离线兜底**：下载 frpc 失败自动找本地包，附 `fetch-frpc.sh`（4 源自动切换）

### 修复

- **主菜单崩溃**：meta 缺字段时 `set -u` 直接炸，改为安全读取
- **选图扫不到**：扫描目录写死，Android 11+ 的 `sdcard/Pictures` 不在列表，改为动态生成 + 自动申请存储权限
- **MT 管理器报 `syntax error: unexpected '(('`**：脚本被 `sh` 执行，加了 bash 自举守卫
- **公告源默认空**：老配置的空串会覆盖默认值，改为空即填默认
- **termux-api 只提示不装**：改为自动安装
- **下载卡死**：加 `--speed-limit/--speed-time`，卡住自动切下一个源，镜像源 2 个扩到 4 个
- **Java 误报"必须配置"**：装核心时会自动装 openjdk，自检改为提示而非标红
- **后台登录误锁**：刷新页面也被计失败，5 次误锁，已修

---

## 内置云端公告源

```
https://siyt.de5.net
```

开箱即用，不用手动填。想换成自己的：菜单 `27` → `3`。

**但请注意**：把公告地址改成自己的、再把改过的版本发给别人用（收费或免费），
按 GPL-3.0 你必须一并提供修改后的完整源码。这正是本项目选择 GPL 的原因。

---

## 免责声明 / Disclaimer

本项目是独立的第三方开源工具，**与 Mojang Studios、Microsoft Corporation，
以及 NeoForge / Forge / Fabric / Paper / Spigot / Bukkit 等各服务端与加载器
项目及其开发团队，均无任何隶属、授权、赞助或合作关系**。

"Minecraft" 是 Mojang Studios 的注册商标，本项目仅在描述性语境下使用。
本项目不分发任何游戏本体、服务端 jar、模组或插件的副本，所有游戏文件
由使用者自行从官方或第三方源获取，著作权归各自权利人所有。

**This project is an independent third-party open source tool. It is NOT affiliated
with, authorized by, endorsed by, or sponsored by Mojang Studios, Microsoft
Corporation, or any mod loader / server software project mentioned herein.
"Minecraft" is a trademark of Mojang Studios and is used here for descriptive
purposes only. This project does not distribute any copyrighted game files —
all game files are downloaded by the user at runtime from official or
third-party sources, and remain the property of their respective owners.**

---

## 许可证

**GNU General Public License v3.0 or later** —— 见包内 `LICENSE` 全文。

随便用、随便改、甚至可以拿去卖钱，但只要分发给别人，
就必须同时给出完整源码，并以同样的 GPL-3.0 授权。
