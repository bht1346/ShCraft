#!/usr/bin/env bash
# ============================================================
#  mcserv 安卓权限 API (独立版, 主脚本已内置同名功能)
#
#  Copyright (C) 2026  bwt1346 <ok819@qq.com>
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
#  SPDX-License-Identifier: GPL-3.0-or-later
# ============================================================

#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  perm.sh —— 安卓权限 API (给 Termux / mcserv.sh 用)
#
#  高版本安卓(11/12/13/14+)权限越收越紧, 这个模块统一处理:
#    1) 能静默拿到就静默拿 (root / Shizuku)
#    2) 拿不到就弹窗/跳转设置页让用户自己点
#    3) 用户不想管就记进跳过名单, 以后不再烦他
#
#  用法:
#    source perm.sh
#    perm_ensure storage          # 申请某一项, 0=已有 1=申请中 2=跳过
#    perm_exec "pm grant ..."     # 用最高可用权限执行
#    perm_menu                    # 交互式权限中心
#
#  依赖: 全部可选, 没有就自动降级
#    su (root)  rish (Shizuku)  proot  termux-*(Termux:API)
# ============================================================

PERM_VER="1.0"
PERM_PKG="${PERM_PKG:-com.termux}"
PERM_CONF="${PERM_CONF:-${HOME}/.mcserv}"
PERM_SKIP_FILE="${PERM_CONF}/perm_skip"
PERM_LOG="${PERM_CONF}/logs/perm.log"

[ -d "$PERM_CONF" ] || mkdir -p "$PERM_CONF" 2>/dev/null
[ -d "${PERM_CONF}/logs" ] || mkdir -p "${PERM_CONF}/logs" 2>/dev/null

# ---------- 颜色/输出 (没有就给套最简的, 方便单独 source) ----------
: "${R:=$'\033[0m'}"; : "${G:=$'\033[32m'}"; : "${Y:=$'\033[33m'}"
: "${C:=$'\033[36m'}"; : "${B:=$'\033[1m'}"; : "${RD:=$'\033[31m'}"
type say  >/dev/null 2>&1 || say()  { echo -e "${G}[+]${R} $*"; }
type warn >/dev/null 2>&1 || warn() { echo -e "${Y}[!]${R} $*"; }
type err  >/dev/null 2>&1 || err()  { echo -e "${RD}[x]${R} $*"; }
type ask  >/dev/null 2>&1 || ask()  { echo -ne "${C}[?]${R} $* "; }
type title >/dev/null 2>&1 || title(){ echo -e "\n${B}===== $* =====${R}"; }
type press >/dev/null 2>&1 || press(){ echo -e "\n${C}按回车继续...${R}"; read -r; }

perm_log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$PERM_LOG" 2>/dev/null; }

# ============================================================
#  第一部分: 能力探测 —— 这台机器到底有哪些提权手段
# ============================================================

# root (Magisk / KernelSU / APatch 都算)
perm_has_root() {
    [ -n "${PERM_ROOT:-}" ] && { [ "$PERM_ROOT" = 1 ]; return; }
    PERM_ROOT=0
    command -v su >/dev/null 2>&1 || { return 1; }
    local u
    u=$(su -c 'id -u' 2>/dev/null | tr -d ' \r\n')
    if [ "$u" = "0" ]; then
        PERM_ROOT=1; PERM_ROOT_TAG=$(su -c 'su --version 2>/dev/null || echo root' 2>/dev/null | head -1)
        perm_log "root 可用"
        return 0
    fi
    return 1
}

# Shizuku (rish shell): 比 root 轻, 不用解锁 bootloader
perm_has_shizuku() {
    [ -n "${PERM_SHIZUKU:-}" ] && { [ "$PERM_SHIZUKU" = 1 ]; return; }
    PERM_SHIZUKU=0
    local rish=""
    for c in rish shizuku; do
        if command -v "$c" >/dev/null 2>&1; then rish="$c"; break; fi
    done
    [ -z "$rish" ] && for p in "/data/local/tmp/rish" "$HOME/rish" "${PREFIX:-/data/data/com.termux/files/usr}/bin/rish"; do
        [ -x "$p" ] && { rish="$p"; break; }
    done
    [ -z "$rish" ] && { return 1; }
    # rish 要真能跑通才算 (Shizuku app 必须正在运行)
    if "$rish" -c 'id -u' >/dev/null 2>&1; then
        PERM_SHIZUKU=1; PERM_RISH="$rish"
        perm_log "Shizuku 可用: $rish"
        return 0
    fi
    return 1
}

# proot / proot-distro: 不是提权, 是换个运行环境
perm_has_proot() {
    command -v proot >/dev/null 2>&1 && return 0
    command -v proot-distro >/dev/null 2>&1 && return 0
    return 1
}

# Termux:API: 弹通知/弹窗/打开文件选择器都靠它
perm_has_tapi() {
    command -v termux-toast >/dev/null 2>&1 && return 0
    command -v termux-notification >/dev/null 2>&1 && return 0
    command -v termux-dialog >/dev/null 2>&1 && return 0
    return 1
}

# 汇总探测, 打印一张能力表
perm_probe() {
    title "权限能力探测"
    echo -e "  包名      : ${C}$PERM_PKG${R}"
    echo -ne "  Root      : "
    if perm_has_root; then echo -e "${G}可用${R}"; else echo -e "${Y}无${R}"; fi
    echo -ne "  Shizuku   : "
    if perm_has_shizuku; then echo -e "${G}可用${R} (${PERM_RISH})"; else echo -e "${Y}无${R}"; fi
    echo -ne "  proot     : "
    if perm_has_proot; then echo -e "${G}可用${R}"; else echo -e "${Y}无${R}"; fi
    echo -ne "  TermuxAPI : "
    if perm_has_tapi; then echo -e "${G}可用${R}"; else echo -e "${Y}无${R}"; fi
    echo
}

# ============================================================
#  第二部分: 执行层 —— 用当前能拿到的最高权限跑命令
# ============================================================

# perm_exec <命令>  自动选 root > shizuku > 普通
# 返回: 0=跑通了(不论哪种方式) 1=都跑不通
perm_exec() {
    local cmd="$1" out rc=1
    if perm_has_root; then
        out=$(su -c "$cmd" 2>&1); rc=$?
        [ $rc -eq 0 ] && { perm_log "[root] $cmd"; printf '%s' "$out"; return 0; }
    fi
    if perm_has_shizuku; then
        out=$("$PERM_RISH" -c "$cmd" 2>&1); rc=$?
        [ $rc -eq 0 ] && { perm_log "[shizuku] $cmd"; printf '%s' "$out"; return 0; }
    fi
    out=$(eval "$cmd" 2>&1); rc=$?
    [ $rc -eq 0 ] && { perm_log "[plain] $cmd"; printf '%s' "$out"; return 0; }
    perm_log "[FAIL] $cmd :: $out"
    return 1
}

# perm_mode: 输出当前用的是哪种提权方式
perm_mode() {
    if   perm_has_root;    then echo "root"
    elif perm_has_shizuku; then echo "shizuku"
    else echo "plain"; fi
}

# ============================================================
#  第三部分: 跳过名单 —— 用户不想管的权限, 记下来别再烦
# ============================================================

perm_skip_load() {
    [ -f "$PERM_SKIP_FILE" ] || { : > "$PERM_SKIP_FILE" 2>/dev/null; return; }
}
perm_is_skipped() { perm_skip_load; grep -qx "$1" "$PERM_SKIP_FILE" 2>/dev/null; }
perm_do_skip() {
    perm_skip_load
    grep -qx "$1" "$PERM_SKIP_FILE" 2>/dev/null || echo "$1" >> "$PERM_SKIP_FILE" 2>/dev/null
    perm_log "跳过: $1"
    warn "已记入跳过名单, 以后不再提示 ($1)"
}
perm_unskip_all() { : > "$PERM_SKIP_FILE" 2>/dev/null; say "跳过名单已清空"; }

# ============================================================
#  第四部分: 弹窗 / 跳设置页 —— 让用户自己点
# ============================================================

# perm_open <intent> —— 能用 am 就用, 没有就提示手动
perm_open() {
    local intent="$1" desc="${2:-设置页}"
    echo -e "  ${Y}需要手动允许: ${desc}${R}"
    if perm_exec "am start $intent" >/dev/null 2>&1; then
        echo -e "  ${C}已跳转设置页, 允许后回来按回车${R}"
    elif command -v termux-open >/dev/null 2>&1; then
        echo -e "  ${Y}试试手动进: 系统设置 → 应用 → Termux → 权限${R}"
    else
        echo -e "  ${Y}手动进: 系统设置 → 应用 → Termux → 权限${R}"
    fi
    perm_log "跳转设置: $desc"
}

# 通知提示 (有 Termux:API 就弹, 没有就打屏)
perm_hint() {
    local msg="$1"
    if command -v termux-toast >/dev/null 2>&1; then
        termux-toast -g middle "$msg" 2>/dev/null && return 0
    fi
    if command -v termux-notification >/dev/null 2>&1; then
        termux-notification -t "mcserv 权限" -c "$msg" 2>/dev/null && return 0
    fi
    return 1
}

# ============================================================
#  第五部分: 各项权限 —— 每项三个办法 静默 → 弹窗 → 跳过
# ============================================================

# ---- 存储读写 (Android 11+ scoped storage 最坑的一项) ----
perm_storage() {
    local dir="${1:-${HOME}}"
    # 已经能写就直接过
    if [ -w "$dir" ] 2>/dev/null && touch "$dir/.permprobe" 2>/dev/null; then
        rm -f "$dir/.permprobe" 2>/dev/null
        say "存储可写 ✅  $dir"
        return 0
    fi
    warn "存储不可写: $dir"
    echo
    # ① root/shizuku 静默给
    if perm_has_root || perm_has_shizuku; then
        echo -ne "  ${C}尝试用 $(perm_mode) 授予存储权限...${R}"
        perm_exec "pm grant $PERM_PKG android.permission.READ_EXTERNAL_STORAGE" >/dev/null 2>&1
        perm_exec "pm grant $PERM_PKG android.permission.WRITE_EXTERNAL_STORAGE" >/dev/null 2>&1
        perm_exec "appops set $PERM_PKG MANAGE_EXTERNAL_STORAGE allow" >/dev/null 2>&1
        perm_exec "appops set --uid $PERM_PKG MANAGE_EXTERNAL_STORAGE allow" >/dev/null 2>&1
        printf "\r\033[K"
        if touch "$dir/.permprobe" 2>/dev/null; then
            rm -f "$dir/.permprobe" 2>/dev/null
            say "已通过 $(perm_mode) 拿到存储权限 ✅"
            return 0
        fi
        warn "$(perm_mode) 授予了但还是写不了 (可能是 ROM 限制)"
    fi
    # ② 没装 Termux:API 先让装
    if ! perm_has_tapi; then
        echo -e "  ${Y}建议先装 Termux:API 并给存储权限:${R}"
        echo -e "     ${C}pkg install termux-api${R}"
        echo -e "     ${C}termux-setup-storage${R}"
    fi
    # ③ 弹窗/跳设置
    echo
    perm_open "-a android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION -d package:$PERM_PKG" "所有文件访问权限"
    perm_hint "请允许 Termux 的文件访问权限"
    return 1
}

# ---- 电池优化白名单 (后台保活的关键, 不加就一会就被杀) ----
perm_battery() {
    # 检测: 有 root/shizuku 看白名单, 没有就靠 dumpsys 猜
    if perm_has_root || perm_has_shizuku; then
        local st
        st=$(perm_exec "dumpsys deviceidle whitelist" 2>/dev/null | grep -c "$PERM_PKG")
        if [ "${st:-0}" -gt 0 ]; then say "电池优化已豁免 ✅"; return 0; fi
    else
        # 没提权就查不到, 直接问用户
        echo -e "  ${Y}没有 root/Shizuku, 查不到电池优化状态${R}"
    fi
    warn "建议把 Termux 加进电池优化白名单 (否则后台容易被杀)"
    echo
    if perm_has_root || perm_has_shizuku; then
        echo -ne "  ${C}尝试用 $(perm_mode) 加白名单...${R}"
        perm_exec "dumpsys deviceidle whitelist +$PERM_PKG" >/dev/null 2>&1
        printf "\r\033[K"
        local st2
        st2=$(perm_exec "dumpsys deviceidle whitelist" 2>/dev/null | grep -c "$PERM_PKG")
        if [ "${st2:-0}" -gt 0 ]; then say "已加进白名单 ✅"; return 0; fi
        warn "$(perm_mode) 加了但没生效"
    fi
    echo
    perm_open "-a android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS -d package:$PERM_PKG" "电池优化 → 选「允许」/「不优化」"
    return 1
}

# ---- 通知 (Android 13+ 要 POST_NOTIFICATIONS) ----
perm_notify() {
    if perm_has_root || perm_has_shizuku; then
        local st
        st=$(perm_exec "dumpsys package $PERM_PKG" 2>/dev/null | grep -c "POST_NOTIFICATIONS: granted=true")
        if [ "${st:-0}" -gt 0 ]; then say "通知权限已有 ✅"; return 0; fi
        echo -ne "  ${C}尝试用 $(perm_mode) 授予通知权限...${R}"
        perm_exec "pm grant $PERM_PKG android.permission.POST_NOTIFICATIONS" >/dev/null 2>&1
        printf "\r\033[K"
        st=$(perm_exec "dumpsys package $PERM_PKG" 2>/dev/null | grep -c "POST_NOTIFICATIONS: granted=true")
        [ "${st:-0}" -gt 0 ] && { say "通知权限已授予 ✅"; return 0; }
    fi
    warn "通知权限可能没开 (崩溃提醒/掉线提醒会收不到)"
    perm_open "-a android.settings.APP_NOTIFICATION_SETTINGS --extra android.provider.extra.APP_PACKAGE $PERM_PKG" "通知权限"
    return 1
}

# ---- 后台弹出界面 / 悬浮窗 (MIUI、ColorOS、OriginOS 常见杀手) ----
perm_overlay() {
    if perm_has_root || perm_has_shizuku; then
        echo -ne "  ${C}尝试用 $(perm_mode) 开后台弹出/悬浮窗...${R}"
        perm_exec "appops set $PERM_PKG SYSTEM_ALERT_WINDOW allow" >/dev/null 2>&1
        perm_exec "appops set $PERM_PKG START_ACTIVITIES_FROM_BACKGROUND allow" >/dev/null 2>&1
        perm_exec "pm grant $PERM_PKG android.permission.SYSTEM_ALERT_WINDOW" >/dev/null 2>&1
        printf "\r\033[K"
        say "已尝试开启 (部分 ROM 只认设置页里手动开)"
        return 0
    fi
    warn "后台弹出界面: 国产 ROM 常拦, 建议手动开"
    echo -e "  ${Y}路径: 设置 → 应用 → Termux → 权限管理 → 后台弹出界面/悬浮窗 → 允许${R}"
    perm_open "-a android.settings.action.MANAGE_OVERLAY_PERMISSION -d package:$PERM_PKG" "悬浮窗/后台弹出"
    return 1
}

# ---- 唤醒锁 (CPU 常驻, 屏灭了也别停) ----
perm_wakelock() {
    if command -v termux-wake-lock >/dev/null 2>&1; then
        termux-wake-lock 2>/dev/null && { say "唤醒锁已获取 ✅"; return 0; }
        warn "termux-wake-lock 调不动 (Termux:API 没装?)"
    else
        warn "没有 termux-wake-lock"
    fi
    echo -e "  ${Y}装: pkg install termux-api${R}"
    echo -e "  ${Y}另外手机设置里把 Termux 设成「允许后台高耗电/锁定后台」${R}"
    return 1
}

# ---- 自启动 / 关联启动 (国产 ROM 杀后台元凶) ----
perm_autostart() {
    warn "自启动/关联启动只能手动开 (各家 ROM 没有统一开关)"
    echo
    echo -e "  ${C}小米/红米${R} 设置 → 应用设置 → 应用管理 → Termux → 自启动 + 省电策略选「无限制」"
    echo -e "  ${C}华为/荣耀${R} 手机管家 → 应用启动管理 → Termux → 手动管理(三项全开)"
    echo -e "  ${C}OPPO/一加${R} 设置 → 电池 → 应用耗电管理 → Termux → 允许后台运行"
    echo -e "  ${C}vivo/iQOO${R} 设置 → 电池 → 后台管理 → Termux → 允许后台高耗电"
    echo -e "  ${C}三星${R}  设置 → 电池 → 后台使用限制 → 从不休眠应用 加上 Termux"
    echo
    echo -e "  ${Y}还有个通用狠招: 多任务界面把 Termux 卡片往下拉锁住${R}"
    return 1
}

# ---- 安装未知应用 (装 Termux:API / Shizuku 时会卡这) ----
perm_install() {
    if perm_has_root || perm_has_shizuku; then
        echo -ne "  ${C}尝试用 $(perm_mode) 开「允许安装未知应用」...${R}"
        perm_exec "appops set $PERM_PKG REQUEST_INSTALL_PACKAGES allow" >/dev/null 2>&1
        perm_exec "pm grant $PERM_PKG android.permission.REQUEST_INSTALL_PACKAGES" >/dev/null 2>&1
        printf "\r\033[K"
        say "已尝试开启"
        return 0
    fi
    warn "安装未知应用权限"
    perm_open "-a android.settings.MANAGE_UNKNOWN_APP_SOURCES -d package:$PERM_PKG" "允许安装未知应用"
    return 1
}

# ---- VPN 权限 (Android 12+ 部分联机工具需要) ----
perm_vpn() {
    if perm_has_root || perm_has_shizuku; then
        perm_exec "appops set $PERM_PKG ACTIVATE_VPN allow" >/dev/null 2>&1
    fi
    warn "VPN 类权限: 首次使用会弹系统框, 点允许即可"
    echo -e "  ${Y}注意: 安卓同一时刻只允许一个 VPN 存活${R}"
    return 1
}

# ---- 网络 (个别 ROM 会禁 Termux 联网) ----
perm_net() {
    if ! curl -fsS --max-time 8 https://www.baidu.com -o /dev/null 2>/dev/null; then
        warn "联网测试失败"
        echo -e "  ${Y}检查: 系统设置 → 流量管理 → Termux 是否允许 WLAN/移动数据${R}"
        perm_open "-a android.settings.APPLICATION_DETAILS_SETTINGS -d package:$PERM_PKG" "Termux 联网权限"
        return 1
    fi
    say "联网正常 ✅"
    return 0
}

# ============================================================
#  第六部分: proot 兜底 —— 二进制跑不起来时换个环境
# ============================================================

# perm_proot_run <命令> —— 二进制 Bionic 不兼容时用 proot 兜底
perm_proot_run() {
    local cmd="$1"
    if ! perm_has_proot; then
        err "没有 proot, 装: pkg install proot"
        return 1
    fi
    warn "二进制可能不兼容 Bionic, 试试用 proot 兜底"
    if command -v proot-distro >/dev/null 2>&1; then
        echo -e "  ${C}有 proot-distro, 建议进容器跑:${R}"
        echo -e "     ${C}proot-distro install ubuntu${R}"
        echo -e "     ${C}proot-distro login ubuntu${R}"
        return 1
    fi
    proot -0 "$cmd" 2>/dev/null && return 0
    return 1
}

# ============================================================
#  第七部分: 统一入口
# ============================================================

# perm_ensure <权限名> [参数]
# 返回: 0=已搞定 1=需要用户处理 2=用户选择跳过
perm_ensure() {
    local name="$1" arg="${2:-}"
    if perm_is_skipped "$name"; then
        echo -e "  ${Y}$name 已跳过 (之前选过不再管)${R}"
        return 2
    fi
    echo
    echo -e "${B}--- $name ---${R}"
    local rc=0
    case "$name" in
        storage)  perm_storage "${arg:-$HOME}"; rc=$?;;
        battery)  perm_battery; rc=$?;;
        notify)   perm_notify; rc=$?;;
        overlay)  perm_overlay; rc=$?;;
        wakelock) perm_wakelock; rc=$?;;
        autostart)perm_autostart; rc=$?;;
        install)  perm_install; rc=$?;;
        vpn)      perm_vpn; rc=$?;;
        net)      perm_net; rc=$?;;
        *)        err "不认识的权限: $name"; return 1;;
    esac
    # 没搞定就问要不要跳过
    if [ $rc -ne 0 ]; then
        echo
        ask "这项以后不再提示? (y=跳过 / 回车=下次再说): "
        read -r s
        case "$s" in y|Y) perm_do_skip "$name"; return 2;; esac
    fi
    return $rc
}

# 开服前该有的权限, 一次性过一遍
perm_ensure_all() {
    title "权限自检 (开服前)"
    perm_probe
    local n ok=0 skip=0
    for n in storage net wakelock battery notify; do
        perm_ensure "$n" >/dev/null 2>&1
        case $? in 0) ok=$((ok+1));; 2) skip=$((skip+1));; esac
    done
    echo
    echo -e "  ${G}已就绪 ${ok}${R}   ${Y}跳过 ${skip}${R}"
    perm_log "批量自检: ok=$ok skip=$skip"
}

# ============================================================
#  第八部分: 交互式菜单
# ============================================================

perm_menu() {
    while true; do
        clear 2>/dev/null
        title "安卓权限中心"
        echo -e "  当前提权方式: ${C}$(perm_mode)${R}   包名: ${C}$PERM_PKG${R}"
        echo
        echo "   1) 能力探测 (root/Shizuku/proot/API)"
        echo "   2) 存储读写            3) 电池优化白名单"
        echo "   4) 通知权限            5) 后台弹出/悬浮窗"
        echo "   6) 唤醒锁              7) 自启动(指引)"
        echo "   8) 安装未知应用        9) VPN 权限"
        echo "  10) 联网测试"
        echo "  11) 一次性自检全部"
        echo "  12) 清空跳过名单        13) proot 兜底说明"
        echo "   0) 返回"
        echo
        ask "选择: "; read -r c || return
        case "$c" in
            1)  clear 2>/dev/null; perm_probe; press;;
            2)  clear 2>/dev/null; perm_ensure storage; press;;
            3)  clear 2>/dev/null; perm_ensure battery; press;;
            4)  clear 2>/dev/null; perm_ensure notify; press;;
            5)  clear 2>/dev/null; perm_ensure overlay; press;;
            6)  clear 2>/dev/null; perm_ensure wakelock; press;;
            7)  clear 2>/dev/null; perm_autostart; press;;
            8)  clear 2>/dev/null; perm_ensure install; press;;
            9)  clear 2>/dev/null; perm_ensure vpn; press;;
            10) clear 2>/dev/null; perm_ensure net; press;;
            11) clear 2>/dev/null; perm_ensure_all; press;;
            12) perm_unskip_all; press;;
            13) clear 2>/dev/null
                title "proot 兜底"
                echo -e "  有些二进制(比如部分 frpc 版本)在 Termux 的 Bionic 上跑不起来"
                echo -e "  这时可以: ${C}pkg install proot proot-distro${R}"
                echo -e "           ${C}proot-distro install ubuntu${R}"
                echo -e "           ${C}proot-distro login ubuntu${R}  ${Y}(进容器里再跑)${R}"
                press;;
            0)  return;;
        esac
    done
}

# 单独运行时直接进菜单
if [ "${BASH_SOURCE[0]}" = "$0" ] 2>/dev/null; then
    perm_menu
fi
