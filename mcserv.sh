#!/usr/bin/env bash
# ------------------------------------------------------------
#  [自举] 必须用 bash 运行, 不能用 sh
#  很多终端(比如 MT 管理器)会执行: sh /path/mcserv.sh
#  这种写法会忽略上面的 shebang, 直接用 sh 解析本文件。
#  而本脚本用了大量 bash 专有语法(for ((;;))、数组、local、
#  ${var//} 等), sh 解析到第一行就会报:
#      syntax error: unexpected '(('
#  所以这里先自检: 如果不是 bash, 就找个 bash 重新 exec 自己。
#  注意: 这段必须放在文件最顶部, 且只能用 POSIX 语法写。
# ------------------------------------------------------------
if [ -z "${BASH_VERSION:-}" ]; then
    for _mcserv_bash in \
        /data/data/com.termux/files/usr/bin/bash \
        /usr/local/bin/bash \
        /usr/bin/bash \
        /bin/bash \
        /system/bin/bash \
        /sbin/bash
    do
        if [ -x "$_mcserv_bash" ]; then
            exec "$_mcserv_bash" "$0" "$@"
        fi
    done
    # 找不到 bash: 给出明确指引, 而不是丢一句语法错误让人猜
    echo ""
    echo "  [x] 本脚本需要 bash, 当前 shell 不支持。"
    echo ""
    echo "  你现在用的是: $(command -v sh 2>/dev/null)"
    echo ""
    echo "  解决办法(任选一个):"
    echo "    1. 在 Termux 里运行:      bash $0"
    echo "    2. 装 bash 后再运行:      pkg install bash"
    echo "    3. 给执行权限后直接跑:    chmod +x $0 && $0"
    echo ""
    echo "  MT 管理器自带的终端只有 sh, 建议改用 Termux 运行本脚本。"
    echo ""
    exit 1
fi
# ============================================================
#  MC 开服器 (mcserv) v1.6 —— 脚本型启动器 (Termux / Linux 通用)
#  功能: 新建服务器 / 核心安装 / 模组插件云端下载(支持镜像)
#        整合包导入 / 存档切换 / 缺失文件按历史重下
#        云端公告(菜单27) / 安卓权限中心(菜单26) / 守护与自检
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
#
#  ---------------------------------------------------------------
#  为什么选 GPL-3.0:
#    本工具完全免费, 且内置了作者自建的云端公告源。
#    任何人都可以随意使用、修改、分发, 但只要你把改过的版本
#    (哪怕只是换了个公告地址) 提供给别人 —— 无论收费还是免费 ——
#    都必须一并提供完整源码, 并以同样的 GPL-3.0 授权。
#
#    想拿去卖钱可以, 但别想藏着源码卖。这就是 copyleft。
#  ---------------------------------------------------------------
#
#  ---------------------------------------------------------------
#  免责声明 / DISCLAIMER:
#    本脚本为独立的第三方社群开发作品, 与下列各方均无任何隶属、
#    授权、赞助、认可或合作关系, 亦非其官方产品:
#      - Mojang Studios (Mojang AB)
#      - Microsoft Corporation
#      - NeoForge / MinecraftForge / Fabric / Quilt / Paper /
#        Spigot / Bukkit / Purpur / Folia 等各服务端与加载器项目
#        及其开发团队
#      - 本脚本所下载/安装的任何模组、插件、整合包之原作者与发行方
#
#    "Minecraft" 是 Mojang Studios 的注册商标, 本脚本仅在描述性
#    语境下使用该名称, 用以说明本工具所服务的软件对象, 不构成任何
#    商标主张。其余各项目名、商标均归各自权利人所有。
#
#    本脚本不分发、不包含、不内置任何游戏本体、服务端 jar、模组或
#    插件的副本。所有游戏文件均在运行时由使用者自行从官方或第三方
#    源下载, 其著作权归各自权利人所有; 本脚本仅提供下载与安装通道,
#    不主张任何权利, 亦不对其内容负责。
#
#    使用本脚本即表示你确认: 你已合法取得 Minecraft 及所使用之模组、
#    插件, 并已自行接受其 EULA 与许可条款。因使用本脚本所产生之存档
#    损坏、数据丢失或服务中断等一切风险, 由使用者自行承担。
#  ---------------------------------------------------------------
# ============================================================

set -uo pipefail

# ---------- 全局路径 ----------
CONF_DIR="${HOME}/.mcserv"
LOGDIR="${CONF_DIR}/logs"
CONF_FILE="${CONF_DIR}/config"
HIST_DIR="${CONF_DIR}/servers"
LOG_FILE="${CONF_DIR}/mcserv.log"
TMP_DIR="${CONF_DIR}/tmp"

mkdir -p "$CONF_DIR" "$HIST_DIR" "$TMP_DIR"

# ---------- 默认值 ----------
# 默认根目录: /storage/emulated/0/dtmcbp  (安卓公共存储)
# 若不存在则退回 $HOME/dtmcbp
DEFAULT_ROOT="/storage/emulated/0/dtmcbp"
if [ ! -d "/storage/emulated/0" ]; then
    DEFAULT_ROOT="${HOME}/dtmcbp"
fi
ROOT="$DEFAULT_ROOT"             # 服务器根目录(可改,会记住)
CUR=""                          # 当前服务器名
MAX_RETRY=3                     # 下载重试次数(用户要求: 3次)
PORT=25565                      # MC 默认端口(显示在联机地址里)
ANIM=1                          # 动效开关 (1=开 0=关, 可在设置里改)
LOGCOLOR=1                      # 服务器日志着色开关 (1=开 0=关)
STATBAR=1                       # 底部运行状态栏 (1=开 0=关)
SAVELOG=1                       # 保存运行日志到文件 (1=开 0=关)
LOGKEEP=10                      # 运行日志保留份数 (超出自动删最旧的)
# 版本号: 改这里即可, banner / UA / 公告 ?v= 都会跟着变
MCSERV_VER="1.6.1"
UA="ShCraft/${MCSERV_VER} (mcserv)"

# ---------- 颜色 ----------
R=$'\033[0m'; G=$'\033[32m'; Y=$'\033[33m'; C=$'\033[36m'; B=$'\033[1m'; RD=$'\033[31m'

say()  { echo -e "${G}[+]${R} $*"; }
warn() { echo -e "${Y}[!]${R} $*"; }
err()  { echo -e "${RD}[x]${R} $*"; }
ask()  { echo -ne "${C}[?]${R} $* "; }
title(){ echo -e "\n${B}===== $* =====${R}"; }

# ============================================================
#  动效 (可在 [设置] 里关闭: ANIM=0)
# ============================================================
#  说明: 所有动效输出一律走 stderr, 以免污染 $(...) 捕获的返回值。
#        手机竖屏较窄, 宽度保守取 34~56。

# 终端宽度
term_w() {
    local w
    w=$(tput cols 2>/dev/null)
    case "$w" in ''|*[!0-9]*) w=${COLUMNS:-44};; esac
    [ "$w" -gt 56 ] && w=56
    [ "$w" -lt 34 ] && w=34
    echo "$w"
}

# 进度条: bar <百分比> [宽度]
bar() {
    local pct=$1 w=${2:-28} i fill
    fill=$((pct * w / 100))
    printf "  ${C}[${R}" >&2
    for ((i=0; i<w; i++)); do
        if [ "$i" -lt "$fill" ]; then printf "${G}█${R}" >&2
        else printf "${Y}░${R}" >&2; fi
    done
    printf "${C}] %3d%%${R}" "$pct" >&2
}

# 转圈开始: spin_start "提示文字"
SPIN_PID=""
spin_start() {
    [ "$ANIM" != "1" ] && return 0
    local msg="$1"
    (
        local i=0 d; d=$(spin_tick)
        while true; do
            spin_frame "$i"
            printf "\r  ${C}%b${R} %s   \033[K" "$SP_CH" "$msg" >&2
            i=$((i+1))
            sleep "$d"
        done
    ) &
    SPIN_PID=$!
}

# 转圈结束: spin_stop "结果文字" (留空则只清行)
spin_stop() {
    [ "$ANIM" != "1" ] && return 0
    if [ -n "$SPIN_PID" ]; then
        kill "$SPIN_PID" 2>/dev/null
        wait "$SPIN_PID" 2>/dev/null
    fi
    SPIN_PID=""
    if [ -n "$1" ]; then
        printf "\r  ${G}✔${R} %s\033[K\n" "$1" >&2
    else
        printf "\r\033[K" >&2
    fi
}

# 启动动画 (约 1.5 秒, 可关闭)
boot_anim() {
    [ "$ANIM" != "1" ] && return 0
    clear 2>/dev/null
    echo
    local art=(
        ' ███╗   ███╗ ██████╗'
        ' ████╗ ████║██╔════╝'
        ' ██╔████╔██║██║     '
        ' ██║╚██╔╝██║██║     '
        ' ██║ ╚═╝ ██║╚██████╗'
        ' ╚═╝     ╚═╝ ╚═════╝'
    )
    local i
    for ((i=0; i<${#art[@]}; i++)); do
        printf "  ${G}%s${R}\n" "${art[$i]}"
        sleep 0.06
    done
    echo
    local sub="  ShCraft · MC 开服器 · Termux  v${MCSERV_VER}"
    local j n=${#sub}
    for ((j=0; j<n; j++)); do
        printf "%s" "${sub:$j:1}"
        sleep 0.018
    done
    echo; echo
    local s p=0
    for s in "加载配置" "检查环境" "就绪"; do
        p=$((p + 34)); [ "$p" -gt 100 ] && p=100
        printf "\r"; bar "$p" 28; printf "  ${C}%s${R}" "$s"
        sleep 0.18
    done
    echo; echo
    sleep 0.15
}

# 菜单横幅 (静态, 不拖慢刷新)
banner() {
    echo -e "${B}${C}"
    echo "  ╔═══════════════════════════════════╗"
    echo -e "  ║   ${G}▐▌${C}  S h C r a f t  ${G}▐▌${C}   v${MCSERV_VER}  ║"
    echo "  ╚═══════════════════════════════════╝"
    echo -e "${R}"
}

# ============================================================
#  配置读写
# ============================================================
# 内置公告源(多源空格分隔). 开箱即用, 不用手动填。
# 注意: 这个值必须在 load_conf 之后再兜底一次 —— 否则老配置里
# 存着的 ANN_URL="" 会把默认值覆盖成空, 导致升级后永远显示"未配置"。
ANN_DEFAULT_URL="https://siyt.de5.net"

load_conf() {
    [ -f "$CONF_FILE" ] && source "$CONF_FILE" 2>/dev/null
    mkdir -p "$ROOT" "$ROOT/tmp" "$ROOT/cache"
    TMP_DIR="${ROOT}/tmp"

    # ---- 公告源兜底 ----
    # 只要读到的是空, 就填内置默认值。包括老配置里残留的 ANN_URL=""
    # (那是没有内置源的老版本写进去的, 不是用户主动清空的)。
    # 想彻底不拉公告, 用开关 ANN_ON=0 / 菜单 27 选 4, 别靠清空 URL。
    [ -n "${ANN_URL:-}" ] || ANN_URL="$ANN_DEFAULT_URL"
}
save_conf() {
    cat > "$CONF_FILE" <<EOF
ROOT="$ROOT"
CUR="$CUR"
MAX_RETRY=$MAX_RETRY
MR_API="$MR_API"
JAVA_ARGS="$JAVA_ARGS"
ANIM=${ANIM:-1}
LOGCOLOR=${LOGCOLOR:-1}
STATBAR=${STATBAR:-1}
SAVELOG=${SAVELOG:-1}
LOGKEEP=${LOGKEEP:-10}
SPIN_STYLE=${SPIN_STYLE:-12}
ANN_URL="${ANN_URL:-$ANN_DEFAULT_URL}"
ANN_ON=${ANN_ON:-1}
ANN_TTL=${ANN_TTL:-6}
ANN_ALWAYS=${ANN_ALWAYS:-1}
AUTO_DEPS=${AUTO_DEPS:-1}
AUTO_MIRROR=${AUTO_MIRROR:-1}
EOF
}

# ============================================================
#  安装日志智能分类器
# ------------------------------------------------------------
#  java -jar installer 的输出又长又杂, 全是英文, 出问题根本看不懂。
#  这里做三件事:
#    1) 把每一行归类 —— 正在装 / 装好了 / 装失败 / 普通日志
#    2) 每类用不同颜色和缩进, 层次一眼可见
#    3) 结束后统计 + 自动诊断, 直接告诉你该怎么修
# ============================================================

# 分类输出 (从 stdin 逐行读)
# 统计结果写入 $JAR_STAT, 完整原文写入 $JAR_RAW
JAR_STAT=""
JAR_RAW=""

jar_classify() {
    local -i ok=0 bad=0 skip=0 retry=0 dup=0
    local line low dep="" name="" prev=""

    while IFS= read -r line; do
        # 去掉 ANSI 与回车符
        line="${line//$'\r'/}"
        [ -z "${line// /}" ] && continue

        # installer 同时写终端和日志文件, 同一条会来两次 —— 相邻去重
        if [ "$line" = "$prev" ]; then
            dup=$((dup+1))
            continue
        fi
        prev="$line"
        low="${line,,}"

        # ---------- ① 开始处理某个依赖 ----------
        if [[ "$low" == *"considering"* || "$low" == *"downloading"* \
           || "$low" == *"processing:"* || "$low" == *"installing"* \
           || "$low" == *"extracting"* || "$low" == *"patching"* \
           || "$low" == *"copying"* ]]; then
            name=""
            # Considering library group:artifact:version
            #   -> 去掉 group, 只留 artifact:version, 屏幕窄也好认
            if [[ "$line" =~ [Cc]onsidering\ library\ (.+) ]]; then
                name="${BASH_REMATCH[1]// /}"
                [[ "$name" == *:* ]] && name="${name#*:}"
            elif [[ "$low" == *"minecraft server jar"* ]]; then
                name="minecraft server.jar"
            fi
            if [ -z "$name" ]; then
                if [[ "$line" =~ ([A-Za-z0-9_.\-]+\.(jar|zip)) ]]; then
                    name="${BASH_REMATCH[1]}"
                else
                    name="${line##*[: ]}"
                    name="${name##*/}"
                    name="${name%%[ ,;]*}"
                fi
            fi
            [ "${#name}" -gt 46 ] && name="${name:0:46}..."
            [ -z "$name" ] && name="组件"
            dep="$name"
            printf "  ${C}▸${R} ${B}正在安装${R} ${C}%s${R}\n" "$name"
            continue
        fi

        # ---------- ①b 全局完成标记(优先, 别被当成某个依赖完成) ----------
        if [[ "$low" == *"installed successfully"* || "$low" == *"successfully"* \
           || "$low" == *"done!"* ]]; then
            ok=$((ok+1))
            printf "  ${G}${B}★ %s${R}\n" "$line"
            dep=""
            continue
        fi

        # ---------- ② 依赖装好了 ----------
        # 注意: 必须覆盖 "Checksum valid." 这种写法(少了 d),
        #       否则大半成功日志会漏掉, 全落到"其它"层。
        if [[ "$low" == *"checksum valid"* || "$low" == *"checksum validated"* \
           || "$low" == *"validated"* || "$low" == *"already exists"* \
           || "$low" == *"up to date"* || "$low" == *"exists. checksum"* \
           || "$low" == *"installed"* ]]; then
            ok=$((ok+1))
            if [ -n "$dep" ]; then
                printf "      ${G}✔${R} ${G}%s${R}  ${Y}已就绪${R}\n" "$dep"
                dep=""
            else
                printf "    ${G}✔${R} ${G}%s${R}\n" "$line"
            fi
            continue
        fi

        # ---------- ③a 可恢复的超时/重试 (不算失败!) ----------
        # NeoForge installer 下 maven 库超时后会自动重试并最终成功,
        # 这类日志若标红, 会让人误以为装崩了。单独用黄色"重试"呈现。
        if [[ "$low" == *"timed out"* || "$low" == *"timeout"* \
           || "$low" == *"connection reset"* || "$low" == *"retrying"* \
           || "$low" == *"retry"* || "$low" == *"trying again"* \
           || "$low" == *"attempt"* || "$low" == *"reconnect"* ]]; then
            retry=$((retry+1))
            printf "      ${Y}↻${R} ${Y}网络超时, 正在自动重试...${R}\n"
            continue
        fi

        # ---------- ③ 出错 ----------
        # 关键: 库名可能自带 error/failed 字样
        #   (如 com.google.errorprone:error_prone_annotations)
        #   所以"库坐标行 / 文件路径行"一律不算错误, 只在其它行里找错。
        if [[ "$low" != *"considering"* && "$low" != *"libraries/"* ]]; then
          if [[ "$low" == *"failed"* || "$low" == *"error"* \
             || "$low" == *"exception"* || "$low" == *"unable to"* \
             || "$low" == *"could not"* || "$low" == *"cannot"* \
             || "$low" == *"denied"* || "$low" == *"corrupt"* ]]; then
            bad=$((bad+1))
            if [ -n "$dep" ]; then
                printf "      ${RD}✘${R} ${RD}%s 安装失败${R}\n" "$dep"
                dep=""
            fi
            printf "      ${RD}✘${R} %s\n" "$line"
            continue
          fi
        fi

        # ---------- ④ 跳过/无操作 ----------
        if [[ "$low" == *"skipping"* || "$low" == *"skipped"* ]]; then
            skip=$((skip+1))
            printf "      ${Y}○${R} %s\n" "$line"
            continue
        fi

        # ---------- ⑤ 其它原始日志(暗色缩进) ----------
        printf "      ${Y}·${R} ${Y}%s${R}\n" "$line"
    done

    printf "%d %d %d %d %d" "$ok" "$bad" "$skip" "$retry" "$dup" > "$JAR_STAT"
}

# 从原始日志自动诊断, 给出可执行的建议
# 用法: jar_diagnose <原始日志文件>
jar_diagnose() {
    local raw="$1"
    [ -s "$raw" ] || return 0
    local low
    low=$(tr 'A-Z' 'a-z' < "$raw" 2>/dev/null)
    echo
    echo -e "  ${B}${RD}── 自动诊断 ──${R}"

    if [[ "$low" == *"failed to download"* || "$low" == *"could not download"* \
       || "$low" == *"download failed"* ]]; then
        err "原因: 依赖库下载失败 (网络/镜像源问题)"
        echo -e "      ${C}→${R} 换网络后重跑 (WiFi / 流量互切)"
        echo -e "      ${C}→${R} 已下载的库会缓存, 重试不会从头开始"
    elif [[ "$low" == *"checksum"* || "$low" == *"corrupt"* ]]; then
        err "原因: 文件校验失败 (下载不完整或被截断)"
        echo -e "      ${C}→${R} 删掉 libraries/ 里对应文件后重跑"
        echo -e "      ${C}→${R} 锁屏会掐断网络, 先执行 termux-wake-lock"
    elif [[ "$low" == *"unsupported class file"* || "$low" == *"class file version"* \
         || "$low" == *"unsupported major"* ]]; then
        err "原因: Java 版本不匹配"
        echo -e "      ${C}→${R} 1.21 需要 Java 21, 重新安装: pkg install openjdk-21"
    elif [[ "$low" == *"outofmemory"* || "$low" == *"heap space"* ]]; then
        err "原因: 内存不足"
        echo -e "      ${C}→${R} 降低安装时内存, 或清理后台应用"
    elif [[ "$low" == *"permission denied"* || "$low" == *"read-only"* ]]; then
        err "原因: 目录没有写入权限"
        echo -e "      ${C}→${R} 执行 termux-setup-storage 后重试"
    elif [[ "$low" == *"no space left"* ]]; then
        err "原因: 存储空间不足"
        echo -e "      ${C}→${R} 清理手机存储后重试"
    elif [[ "$low" == *"timed out"* || "$low" == *"timeout"* || "$low" == *"connection reset"* ]]; then
        err "原因: 网络超时/被重置"
        echo -e "      ${C}→${R} 换网络重试; 已下载的库会保留"
    else
        warn "未能自动识别原因, 完整日志已保存:"
        echo -e "      ${C}$raw${R}"
        echo -e "      ${C}→${R} 把最后 20 行发出来可帮你定位"
    fi
}

# 带分类的 jar 执行器
# 用法: run_jar <标题> <命令...>
run_jar() {
    local label="$1"; shift
    local tmp statf rawf rc
    tmp=$(mktemp 2>/dev/null) || tmp="${TMP_DIR}/jar.$$"
    statf="${tmp}.stat"; rawf="${tmp}.raw"
    JAR_STAT="$statf"; JAR_RAW="$rawf"
    : > "$rawf"

    echo
    printf "  ${B}${C}▶ %s${R}\n" "$label"
    printf "  ${Y}%s${R}\n" "$(printf '─%.0s' $(seq 1 46) 2>/dev/null)"

    # stdbuf 强制行缓冲, 否则 java 输出会被块缓冲导致进度不实时
    if command -v stdbuf >/dev/null 2>&1; then
        stdbuf -oL -eL "$@" 2>&1 | tee -a "$rawf" | jar_classify
        rc=${PIPESTATUS[0]}
    else
        "$@" 2>&1 | tee -a "$rawf" | jar_classify
        rc=${PIPESTATUS[0]}
    fi

    local o b s r d
    read -r o b s r d < "$statf" 2>/dev/null
    : "${o:=0}" "${b:=0}" "${s:=0}" "${r:=0}" "${d:=0}"

    printf "  ${Y}%s${R}\n" "$(printf '─%.0s' $(seq 1 46) 2>/dev/null)"

    if [ "$rc" -ne 0 ]; then
        # 进程确实非零退出 —— 真失败
        printf "  ${RD}${B}✘ %s 未完成${R}  ${Y}(成功 %d, 失败 %d, 跳过 %d" \
            "$label" "$o" "$b" "$s"
        [ "$r" -gt 0 ] && printf ", 重试 %d" "$r"
        printf ")${R}\n"
        jar_diagnose "$rawf"
        # 保留日志供排查
        local keep="${CONF_DIR}/install-failed-$(date +%m%d-%H%M%S).log"
        cp "$rawf" "$keep" 2>/dev/null
        [ -f "$keep" ] && echo -e "  ${Y}完整日志: ${C}$keep${R}"

    elif [ "$b" -gt 0 ]; then
        # 进程退出码为 0, 但日志里抓到疑似错误 —— 可能是误报, 明确标注
        printf "  ${Y}${B}⚠ %s 已结束, 但日志有 %d 处可疑${R}  ${Y}(成功 %d 项)${R}\n" \
            "$label" "$b" "$o"
        printf "    ${Y}注: 退出码为 0, 安装多半是成功的${R}\n"
        printf "    ${Y}    若服务器能正常启动, 这些可忽略${R}\n"
        local keep2="${CONF_DIR}/install-warn-$(date +%m%d-%H%M%S).log"
        cp "$rawf" "$keep2" 2>/dev/null
        [ -f "$keep2" ] && echo -e "  ${Y}完整日志: ${C}$keep2${R}"

    else
        # 干净成功
        printf "  ${G}${B}✔ %s 已完成${R}  ${Y}(成功 %d 项" "$label" "$o"
        [ "$s" -gt 0 ] && printf ", 跳过 %d 项" "$s"
        [ "$r" -gt 0 ] && printf ", 中途重试 %d 次" "$r"
        printf ")${R}\n"
        if [ "$r" -gt 0 ]; then
            printf "    ${Y}注: 出现 %d 次网络超时, 已自动重试成功, 属正常现象${R}\n" "$r"
        fi
    fi

    rm -f "$tmp" "$statf" "$rawf"
    return $rc
}

# ============================================================
#  MC 服务器运行日志分类器
# ------------------------------------------------------------
#  服务端日志格式: [时:分:秒] [线程/级别]: 内容
#  按级别 + 关键词染色, 并在关键节点主动提示:
#    启动完成   -> 绿色高亮 + 直接打出联机地址(不用再去菜单13)
#    玩家进出   -> 青色高亮
#    崩溃/端口占用/内存不足/EULA -> 退出后自动诊断
# ============================================================

MC_STAT=""
MC_RAW=""
MC_XMX=""

# 精简版联机地址(启动完成时内联显示, 不暂停)
quick_addr() {
    local dev ip4 kind out=()
    while read -r dev ip4; do
        [ -z "$dev" ] && continue
        ip4="${ip4%%/*}"
        case "$ip4" in ''|127.*) continue;; esac
        case "$dev" in
            lo|eth*|wlan*|rmnet*|dummy*|ifb*|p2p*|sit*|ip6tnl*) continue;;
            tun*|utun*|zt*|tailscale*|easytier*|wg*|ppp*) ;;
            *) continue;;
        esac
        if [[ "$ip4" =~ ^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\. ]]; then
            kind="Tailscale"
        elif [[ "$dev" == zt* ]]; then kind="ZeroTier"
        elif [[ "$dev" == wg* ]]; then kind="WireGuard"
        else kind="组网"; fi
        out+=("${kind} ${ip4}:${PORT}")
    done < <(ip -o -4 addr show 2>/dev/null | awk '{print $2, $4}')
    local lan
    lan=$(ip -o -4 addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | grep -E '^192\.168\.' | head -1)
    [ -n "$lan" ] && out+=("局域网 ${lan}:${PORT}")
    if [ "${#out[@]}" -gt 0 ]; then
        local a
        for a in "${out[@]}"; do
            printf "  ${G}▸${R} ${B}%s${R}  ${Y}← 朋友填这个${R}\n" "$a"
        done
    else
        echo -e "  ${Y}▸ 未检测到组网地址, 菜单 13 查看详情${R}"
    fi
}

# ---------- 进度条 ----------
# 亚格块字符: 由细到满 (让进度条能 1/8 格地平滑推进)
MC_SUB=('\u258f' '\u258e' '\u258d' '\u258c' '\u258b' '\u258a' '\u2589' '\u2588')
# 三档渐变色: 低=黄 中=青 高=绿
mc_pct_color() {  # $1=百分比 -> 颜色序列
    local n=${1:-0}
    if   [ "$n" -ge 100 ] 2>/dev/null; then printf '\033[1;32m'
    elif [ "$n" -ge 67  ] 2>/dev/null; then printf '\033[32m'
    elif [ "$n" -ge 34  ] 2>/dev/null; then printf '\033[36m'
    else                                     printf '\033[33m'
    fi
}
# ---- 终端宽度 ----
term_cols() {
    local w
    w=$(tput cols 2>/dev/null)
    case "$w" in ''|*[!0-9]*) w=${COLUMNS:-0};; esac
    case "$w" in ''|*[!0-9]*) w=0;; esac
    [ "$w" -lt 20 ] 2>/dev/null && w=44
    [ "$w" -gt 200 ] 2>/dev/null && w=200
    printf '%s' "$w"
}
# ---- 单字符显示宽度: ASCII=1, 中文/全角=2 ----
_chw() {
    local ch="$1" b
    b=$(printf '%s' "$ch" | wc -c)
    [ "$b" -le 1 ] && { printf 1; return; }
    printf 2
}
# ---- 按显示宽度截断字符串 (超出补 …), 保证整行不换行 ----
# $1=文本 $2=最大显示宽度
wcut() {
    local s="$1" maxw="$2" out="" cw=0 i=0 n c ch
    [ -z "$maxw" ] && { printf '%s' "$s"; return; }
    [ "$maxw" -le 0 ] 2>/dev/null && { printf ''; return; }
    n=${#s}
    while [ "$i" -lt "$n" ]; do
        ch="${s:$i:1}"
        c=$(_chw "$ch")
        if [ $((cw + c)) -gt "$maxw" ]; then
            # 留 1 格给省略号
            printf '%s…' "$out"
            return
        fi
        out="${out}${ch}"; cw=$((cw + c)); i=$((i+1))
    done
    printf '%s' "$out"
}
# ---- 转圈: 16 帧平滑圆周 (零 fork, 高帧率) ----
# 亮点沿 Braille 2x4 点阵的圆周走 16 个位置:
#   单点(角/边) 与 双点(中间过渡) 交替, 所以过渡是连续的, 不像 |/-\\ 那样跳
#   ⠁ → ⠉ → ⠈ → ⠘ → ⠐ → ⠰ → ⠠ → ⢠ → ⢀ → ⣀ → ⡀ → ⢄ → ⠄ → ⠆ → ⠂ → ⠃ → 回到 ⠁
SPIN16=('\u2801' '\u2809' '\u2808' '\u2818' '\u2810' '\u2830' '\u2820' '\u28a0'
        '\u2880' '\u28c0' '\u2840' '\u2844' '\u2804' '\u2806' '\u2802' '\u2803')
# 经典线条风格: | / - \
SPIN_CLS=('|' '/' '-' '\\')
SPIN_STYLE=${SPIN_STYLE:-16}      # 16=平滑圆周(默认)  4=经典线条
[ "${SPIN_STYLE:-16}" = "12" ] && SPIN_STYLE=16   # 旧的 12 帧自动升级到 16 帧
SPIN_SPEED=${SPIN_SPEED:-fast}    # fast / normal / slow
# 当前帧字符(全局), 由 spin_frame 写入 —— 不 fork 子进程
SP_CH=''
# 取帧: 结果写进 $SP_CH (纯 bash 数组索引, 不 fork)
spin_frame() {  # $1=序号
    local i=${1:-0}
    if [ "${SPIN_STYLE:-16}" = "4" ]; then
        SP_CH="${SPIN_CLS[$(( i % 4 ))]}"
    else
        SP_CH="${SPIN16[$(( i % 16 ))]}"
    fi
}
# 兼容旧调用 (会 fork, 仅非热路径用)
spin_ch() { spin_frame "${1:-0}"; printf '%b' "$SP_CH"; }
# 每帧停留秒数
#   16 帧: fast=0.03 (一圈 0.48s)  normal=0.05 (0.8s)  slow=0.10 (1.6s)
#   经典 4 帧: 稍慢一点才不抖
spin_tick() {
    local want_ms
    if [ "${SPIN_STYLE:-16}" = "4" ]; then
        case "${SPIN_SPEED:-fast}" in
            normal) want_ms=90;;  slow) want_ms=150;;  *) want_ms=60;;
        esac
    else
        case "${SPIN_SPEED:-fast}" in
            normal) want_ms=50;;  slow) want_ms=100;;  *) want_ms=25;;
        esac
    fi
    # 系统不支持比这更细的 sleep 时, 退到系统能做到的最小值
    [ "$want_ms" -lt "${TICK_MS:-1000}" ] 2>/dev/null && want_ms=${TICK_MS:-1000}
    case "$want_ms" in
        20)  printf 0.02;;  25)  printf 0.025;; 30) printf 0.03;;
        40)  printf 0.04;;  50)  printf 0.05;;
        60)  printf 0.06;;  90)  printf 0.09;;  100) printf 0.1;;
        150) printf 0.15;;  200) printf 0.2;;   300) printf 0.3;;
        500) printf 0.5;;   *)   printf 1;;
    esac
}
# 按帧间隔换算总帧数 (上限 180 秒)
max_ticks() {  # $1=帧间隔秒
    case "$1" in
        0.02) printf 9000;; 0.025) printf 7200;; 0.03) printf 6000;;
        0.04) printf 4500;; 0.05) printf 3600;;
        0.06) printf 3000;; 0.09) printf 2000;; 0.1)  printf 1800;;
        0.15) printf 1200;; 0.2)  printf 900;;  0.3)  printf 600;;
        0.5)  printf 360;;  *)    printf 180;;
    esac
}
# 取当前秒数 (bash 内置优先, 避免每帧 fork 一次 date —— 这是流畅度的关键)
NOW_BUILTIN=0
if printf -v _now_t '%(%s)T' -1 2>/dev/null; then NOW_BUILTIN=1; fi
NOW=0
now_secs() {
    if [ "$NOW_BUILTIN" = "1" ]; then printf -v NOW '%(%s)T' -1; else NOW=$(date +%s); fi
}
# 一圈耗时(秒), 供菜单显示真实值
spin_circle() {
    local d n
    d=$(spin_tick)
    if [ "${SPIN_STYLE:-16}" = "4" ]; then n=4; else n=16; fi
    printf '%s' "$(awk -v a="$d" -v b="$n" 'BEGIN{printf "%.2f", a*b}' 2>/dev/null || echo '?')"
}
# 进度条缓存(懒加载): 同一个百分比只生成一次, 运行期零 fork
declare -a BAR_CACHE=()
BAR_STR=''
bar_cached() {  # $1=百分比 $2=宽度 -> 写全局 BAR_STR
    if [ -z "${BAR_CACHE[$1]:-}" ]; then
        BAR_CACHE[$1]=$(mc_bar "$1" "$2")
    fi
    BAR_STR="${BAR_CACHE[$1]}"
}

mc_bar() {   # $1=百分比 $2=宽度  (自动带渐变色 + 扫光头)
    local n=${1:-0} w=${2:-14} f k
    [ "$n" -lt 0 ] 2>/dev/null && n=0
    [ "$n" -gt 100 ] 2>/dev/null && n=100
    # 亚格: 总共 w*8 份, 取满格与余量
    local tot=$(( n * w * 8 / 100 ))
    f=$(( tot / 8 ))
    local sub=$(( tot % 8 ))
    [ "$f" -ge "$w" ] && { f=$w; sub=0; }
    local col; col=$(mc_pct_color "$n")
    printf '['
    printf '%b' "$col"
    for ((k=0;k<f;k++)); do
        # 扫光头: 最后一格用反色高亮, 视觉上像有个光点在推进
        if [ "$k" -eq $((f-1)) ] && [ "$n" -lt 100 ]; then
            printf '\033[1;97m\u2588\033[0m'; printf '%b' "$col"
        else
            printf '\u2588'
        fi
    done
    if [ "$sub" -gt 0 ] && [ "$f" -lt "$w" ]; then
        printf '%b' "${MC_SUB[$((sub-1))]}"
    fi
    printf '\033[0m'
    local rest=$(( w - f ))
    [ "$sub" -gt 0 ] && rest=$(( rest - 1 ))
    [ "$rest" -lt 0 ] && rest=0
    printf '\033[2m'
    for ((k=0;k<rest;k++)); do printf '\u2591'; done
    printf '\033[0m'
    printf ']'
}

# ---------- 启动阶段 -> 名称|进度起点|进度终点 ----------
mc_stage_of() {
    local m="$1"
    case "$m" in
        *"launching wrapped"*|*"libraries"*|*"loading minecraft"*)
            echo "加载依赖库|3|14";;
        *"datafixer"*)            echo "构建数据修复器|14|20";;
        *"loading mod"*|*"mod file"*|*"mods"*)
            echo "加载模组|20|48";;
        *"resourcemanager"*|*"holder lookups"*|*"datapack"*|*"tags"*)
            echo "加载数据包|48|62";;
        *"preparing level"*)      echo "准备世界|62|70";;
        *"preparing start region"*)
            echo "生成出生点区块|70|97";;
        *"time elapsed"*)         echo "收尾|97|99";;
        *) echo "";;
    esac
}

mc_classify() {
    local -i errn=0 warnn=0 joins=0 ready=0 players=0
    local line low msg msglow st sub pct=0 ss=3 se=14
    local cur_stage="初始化"

    while IFS= read -r line; do
        line="${line//$'\r'/}"
        [ -z "${line// /}" ] && continue
        low="${line,,}"
        msg="${line#*\]*: }"
        [ "$msg" = "$line" ] && msg="$line"
        msglow="${msg,,}"

        # ---------- TPS 查询的回显: 取数值, 但不刷屏 ----------
        if [[ "$msglow" == *tps* ]]; then
            local tv=""
            # 优先取小数形式 (20.0 / 19.85), 排除 "1m, 5m, 15m" 里的整数
            if [[ "$msg" =~ ([0-9]{1,2}\.[0-9]+) ]]; then
                tv="${BASH_REMATCH[1]}"
            elif [[ "$msg" =~ [Tt][Pp][Ss][^0-9]*([0-9]{1,2})([^0-9]|$) ]]; then
                tv="${BASH_REMATCH[1]}"
            fi
            if [ -n "$tv" ]; then
                # 合理范围才认 (1~30)
                if awk -v v="$tv" 'BEGIN{exit !(v>0 && v<=30)}'; then
                    printf '%s' "$tv" > "$MC_TPSF" 2>/dev/null
                fi
            fi
            continue
        fi
        case "$msg" in *"[stdin]"*) continue;; esac

        # ---------- ① 崩溃 / 致命 ----------
        if [[ "$low" == *"/error]"* || "$low" == *"/fatal]"* \
           || "$low" == *"exception"* || "$low" == *"crash report"* \
           || "$low" == *"encountered an unexpected"* \
           || "$low" == *"failed to bind"* || "$low" == *"address already in use"* \
           || "$low" == *"outofmemory"* || "$low" == *"eula"* ]]; then
            errn=$((errn+1))
            printf "  ${RD}${B}✘ %s${R}\n" "$line"
            continue
        fi

        # ---------- ② 阶段进度 ----------
        st=$(mc_stage_of "$msglow")
        if [ -n "$st" ]; then
            cur_stage="${st%%|*}"; st="${st#*|}"
            ss="${st%%|*}"; se="${st##*|}"
            pct=$ss
        fi
        if [[ "$msg" =~ ([0-9]{1,3})[[:space:]]*% ]]; then
            sub="${BASH_REMATCH[1]}"
            [ "$sub" -gt 100 ] 2>/dev/null && sub=100
            pct=$(( ss + (se - ss) * sub / 100 ))
        elif [ "$pct" -lt "$((se - 1))" ]; then
            pct=$((pct + 1))
        fi

        # ---------- ③ 启动完成 ----------
        if [[ "$msg" == *"Done ("* || "$msg" == *"For help, type"* ]]; then
            if [ "$ready" -eq 0 ]; then
                ready=1; pct=100; cur_stage="启动完成"
                printf "  ${G}${B}★ 服务器已就绪!  %s${R}\n" "$msg"
                printf "  ${G}------------------------------${R}\n"
                quick_addr
                printf "  ${G}------------------------------${R}\n"
            else
                printf "  ${G}★ %s${R}\n" "$msg"
            fi
            printf '%d|%s|%d' "$pct" "$cur_stage" "$ready" > "$MC_STF" 2>/dev/null
            continue
        fi

        # ---------- ④ 玩家进出 (顺便维护在线数) ----------
        if [[ "$msg" == *"joined the game"* || "$msg" == *"logged in with entity id"* ]]; then
            players=$((players+1)); joins=$((joins+1))
            printf '%d' "$players" > "$MC_PLF" 2>/dev/null
            printf "  ${C}⇢ %s${R}\n" "$msg"
            printf '%d|%s|%d' "$pct" "$cur_stage" "$ready" > "$MC_STF" 2>/dev/null
            continue
        fi
        if [[ "$msg" == *"left the game"* || "$msg" == *"lost connection"* ]]; then
            [ "$players" -gt 0 ] && players=$((players-1))
            printf '%d' "$players" > "$MC_PLF" 2>/dev/null
            printf "  ${C}⇠ %s${R}\n" "$msg"
            printf '%d|%s|%d' "$pct" "$cur_stage" "$ready" > "$MC_STF" 2>/dev/null
            continue
        fi

        # ---------- ⑤ 警告 ----------
        if [[ "$low" == *"/warn]"* ]]; then
            warnn=$((warnn+1))
            printf "  ${Y}⚠ %s${R}\n" "$msg"
            printf '%d|%s|%d' "$pct" "$cur_stage" "$ready" > "$MC_STF" 2>/dev/null
            continue
        fi

        # ---------- ⑥ 阶段行 (青色) ----------
        if [[ "$msglow" == *"starting minecraft server"* \
           || "$msglow" == *"preparing"* || "$msglow" == *"loading "* \
           || "$msglow" == *"building "* || "$msglow" == *"reloading "* \
           || "$msglow" == *"applying "* ]]; then
            printf "  ${C}▸ %s${R}\n" "$msg"
            printf '%d|%s|%d' "$pct" "$cur_stage" "$ready" > "$MC_STF" 2>/dev/null
            continue
        fi

        # ---------- ⑦ 停止相关 ----------
        if [[ "$msglow" == *"stopping server"* || "$msglow" == *"all chunks are saved"* \
           || "$msglow" == *"closing server"* ]]; then
            printf "  ${Y}▸ %s${R}\n" "$msg"
            continue
        fi

        # ---------- ⑧ 其它 ----------
        printf "  ${Y}· %s${R}\n" "$msg"
        printf '%d|%s|%d' "$pct" "$cur_stage" "$ready" > "$MC_STF" 2>/dev/null
    done

    printf "%d %d %d %d" "$errn" "$warnn" "$joins" "$ready" > "$MC_STAT"
}

# ---------- 底部常驻状态栏 ----------
mc_status_daemon() {
    local stf="$1" tpsf="$2" pidf="$3" donef="$4" plf="$5"
    local lines cols w last="" cur pct stage ready tps pl
    local pid r1 r2 cpu mem rss dt u1 s1 u2 s2
    local cores; cores=$(nproc 2>/dev/null)
    [ -z "$cores" ] && cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null)
    : "${cores:=8}"; [ "$cores" -lt 1 ] && cores=1
    lines=$(tput lines 2>/dev/null); : "${lines:=${LINES:-40}}"
    cols=$(tput cols  2>/dev/null);  : "${cols:=${COLUMNS:-50}}"
    # 屏幕太小就不启用状态栏, 免得挤压日志
    if [ "$lines" -lt 12 ] 2>/dev/null; then return 0; fi
    # 设置滚动区 1..lines-1, 末行留给状态栏
    printf '\033[1;%dr\033[%d;1H' $((lines-1)) $((lines-1))
    trap 'printf "\033[r"' EXIT TERM INT

    while [ ! -f "$donef" ]; do
        IFS='|' read -r pct stage ready < "$stf" 2>/dev/null
        : "${pct:=0}" "${stage:=初始化}" "${ready:=0}"

        if [ "$ready" = "1" ]; then
            # ===== 运行中: 实时指标 =====
            tps=$(cat "$tpsf" 2>/dev/null); [ -z "$tps" ] && tps="--"
            pl=$(cat "$plf" 2>/dev/null);   : "${pl:=0}"
            pid=$(cat "$pidf" 2>/dev/null)
            # 管道里 $! 拿到的是最后一个命令(mc_classify), 不是 java,
            # 所以这里直接扫 /proc 找 java 进程 (取 rss 最大的那个)
            if [ ! -r "/proc/$pid/stat" ] 2>/dev/null; then
                pid=$(for d in /proc/[0-9]*; do
                        [ -r "$d/comm" ] || continue
                        [ "$(cat "$d/comm" 2>/dev/null)" = "java" ] && echo "${d##*/}"
                      done | tail -1)
            fi
            cpu="--"; mem="--"
            if [ -n "$pid" ] && [ -r "/proc/$pid/stat" ]; then
                r1=$(cat "/proc/$pid/stat" 2>/dev/null); r1="${r1##*) }"
                set -- $r1; u1=${12:-0}; s1=${13:-0}
                sleep 0.8
                r2=$(cat "/proc/$pid/stat" 2>/dev/null); r2="${r2##*) }"
                set -- $r2; u2=${12:-0}; s2=${13:-0}
                # 0.8s @100Hz = 80 ticks; 换算成"占用了几个核"
                # 100% = 吃满一个核, 多线程可超过 100%
                dt=$(( (u2 + s2) - (u1 + s1) )); [ "$dt" -lt 0 ] && dt=0
                cpu=$(( dt * 100 / 80 ))
                [ "$cpu" -lt 0 ] && cpu=0
                [ "$cpu" -gt 999 ] && cpu=999
                rss=$(awk '/VmRSS/{print $2; exit}' "/proc/$pid/status" 2>/dev/null)
                if [ -n "$rss" ]; then
                    local mbm=$(( rss / 1024 ))
                    if [ -n "$MC_XMX" ] && [ "$MC_XMX" -gt 0 ]; then
                        mem="$(( mbm * 100 / MC_XMX ))%"
                        [ "$cols" -ge 52 ] && mem="${mem}(${mbm}M)"
                    else
                        mem="${mbm}M"
                    fi
                fi
            fi
            cur="运行中 内存${mem} CPU${cpu}% TPS ${tps} 在线${pl}"
            [ "$cols" -lt 42 ] && cur="运行 CPU${cpu}% TPS ${tps} 人${pl}"
        else
            # ===== 启动中: 阶段进度 =====
            [ "$cols" -lt 42 ] && w=8 || w=14
            cur="$(mc_bar "$pct" "$w") ${pct}%  ${stage}"
        fi

        if [ "$cur" != "$last" ]; then
            last="$cur"
            printf '\0337\033[%d;1H\033[2K' "$lines" 2>/dev/null
            if [ "$ready" = "1" ]; then printf "${G}${B}%s${R}" "$cur"
            else                        printf "${C}%s${R}"     "$cur"; fi
            printf '\0338'
        fi
        [ "$ready" = "1" ] && sleep 0.8 || sleep 0.4
    done
    # 退出前清掉状态行并恢复滚动区
    printf '\0337\033[%d;1H\033[2K\0338\033[r' "$lines" 2>/dev/null
}

# 从原始日志诊断停止原因
mc_diagnose() {
    local raw="$1" rc="$2" ready="$3"
    [ -s "$raw" ] || return 0
    local low
    low=$(tr 'A-Z' 'a-z' < "$raw" 2>/dev/null)
    echo
    echo -e "  ${B}${RD}-- 停止原因诊断 --${R}"
    if [[ "$low" == *"eula"* ]]; then
        err "原因: 未同意 EULA"
        echo -e "      ${C}->${R} 编辑 eula.txt: eula=true"
    elif [[ "$low" == *"address already in use"* || "$low" == *"failed to bind"* ]]; then
        err "原因: 端口 $PORT 被占用 (多半是上一个服务端还没关)"
        echo -e "      ${C}->${R} 先彻底停掉旧进程: pkill -f server.jar"
        echo -e "      ${C}->${R} 或在设置里换一个端口"
    elif [[ "$low" == *"outofmemory"* ]]; then
        err "原因: 内存不足"
        echo -e "      ${C}->${R} 设置里调低内存(如 1024), 或删掉多余模组"
    elif [[ "$low" == *"mixin"* && "$low" == *"failed"* ]]; then
        err "原因: 模组注入失败 (常见为模组版本不匹配)"
        echo -e "      ${C}->${R} 检查该模组是否支持当前 MC/NeoForge 版本"
    elif [[ "$low" == *"missing mod"* || "$low" == *"requires"* && "$low" == *"version"* ]]; then
        err "原因: 模组缺少依赖"
        echo -e "      ${C}->${R} 日志里会写明缺哪个, 用菜单 5 装上对应版本"
    elif [[ "$low" == *"corrupt"* || "$low" == *"exception reading"* ]]; then
        err "原因: 存档损坏或不兼容"
        echo -e "      ${C}->${R} 菜单 8 切回上一个备份"
    elif [[ "$low" == *"unsupported class file"* || "$low" == *"class file version"* ]]; then
        err "原因: Java 版本不匹配 (1.21 需要 Java 21)"
        echo -e "      ${C}->${R} pkg install openjdk-21"
    elif [ "$ready" -eq 1 ]; then
        echo -e "  ${G}服务器曾成功启动, 属正常停止${R}"
        echo -e "      ${C}->${R} 若是按 Ctrl+C 或 /stop, 无需处理"
    else
        warn "未能自动识别原因, 完整日志已保存:"
        echo -e "      ${C}$raw${R}"
        echo -e "      ${C}->${R} 把最后 20 行发出来可帮你定位"
    fi
}

# ============================================================
#  运行日志: 保存 / 清理 / 查看
# ============================================================
log_prune() {
    [ -d "$LOGDIR" ] || return 0
    local keep=${LOGKEEP:-10}
    [ "$keep" -lt 1 ] 2>/dev/null && return 0
    ls -1t "$LOGDIR"/server-*.log 2>/dev/null | tail -n +$((keep+1)) | while read -r f; do
        rm -f "$f"
    done
}

log_size() {
    local f="$1" b
    b=$(wc -c < "$f" 2>/dev/null); : "${b:=0}"
    if [ "$b" -ge 1048576 ] 2>/dev/null; then echo "$((b/1048576))M"
    elif [ "$b" -ge 1024 ] 2>/dev/null; then echo "$((b/1024))K"
    else echo "${b}B"; fi
}

log_menu() {
    while true; do
        title "运行日志"
        local n=0 total="0"
        if [ -d "$LOGDIR" ]; then
            n=$(ls -1 "$LOGDIR"/server-*.log 2>/dev/null | wc -l)
            total=$(du -sh "$LOGDIR" 2>/dev/null | cut -f1)
        fi
        : "${total:=0}"
        echo -e "  目录  : ${C}$LOGDIR${R}"
        echo -e "  共 ${C}$n${R} 份, 占用 ${C}$total${R}   ${Y}(自动保留最近 ${LOGKEEP} 份)${R}"
        echo
        echo "  1) 查看最新日志 (末尾 40 行)"
        echo "  2) 实时跟踪日志 (Ctrl+C 退出)"
        echo "  3) 列出全部日志"
        echo "  4) 打开指定日志"
        echo "  5) 删除全部日志"
        echo "  0) 返回"
        echo
        ask "选择: "; rd c || return
        [ -z "$c" ] && continue
        local latest
        latest=$(ls -1t "$LOGDIR"/server-*.log 2>/dev/null | head -1)
        case "$c" in
        1) if [ -n "$latest" ]; then
               echo; echo -e "  ${C}--- $latest ($(log_size "$latest")) ---${R}"
               tail -n 40 "$latest" 2>/dev/null
           else warn "还没有运行日志"; fi
           press;;
        2) if [ -n "$latest" ]; then
               echo -e "  ${C}跟踪 $latest${R}  ${Y}(Ctrl+C 退出)${R}"; echo
               tail -n 20 -f "$latest" 2>/dev/null
           else warn "还没有运行日志"; press; fi;;
        3) if [ "$n" -eq 0 ]; then warn "还没有运行日志"; else
               echo; local i=1
               while read -r f; do
                   echo -e "  ${C}$i)${R} $(basename "$f")  ${Y}$(log_size "$f")${R}  ${Y}$(wc -l < "$f") 行${R}"
                   i=$((i+1))
               done < <(ls -1t "$LOGDIR"/server-*.log 2>/dev/null)
           fi
           press;;
        4) if [ "$n" -eq 0 ]; then warn "还没有运行日志"; else
               echo; local arr=(); local i=1
               while read -r f; do
                   echo -e "  ${C}$i)${R} $(basename "$f")  ${Y}$(log_size "$f")${R}"
                   arr+=("$f"); i=$((i+1))
               done < <(ls -1t "$LOGDIR"/server-*.log 2>/dev/null)
               echo; ask "序号: "; rd k
               local sel="${arr[$((k-1))]}"
               [ -n "$sel" ] && { echo; echo -e "  ${C}--- $sel ---${R}"; cat "$sel" 2>/dev/null | head -200
                   echo -e "  ${Y}(仅显示前 200 行, 完整文件: $sel)${R}"; }
           fi
           press;;
        5) ask "确认删除全部运行日志? (y/N): "; rd k
           case "$k" in y|Y) rm -f "$LOGDIR"/server-*.log "$LOGDIR"/latest.log 2>/dev/null; say "已清空";; esac
           press;;
        0|q|Q) return;;
        esac
    done
}

# 带分类 + 状态栏的 MC 启动器
run_mc() {
    local tmp statf rawf rc persist=0
    tmp=$(mktemp 2>/dev/null) || tmp="${TMP_DIR}/mc.$$"
    statf="${tmp}.stat"
    # 运行日志落盘: 每次启动一份, latest.log 指向最新的
    if [ "$SAVELOG" = "1" ]; then
        mkdir -p "$LOGDIR" 2>/dev/null
        rawf="${LOGDIR}/server-$(date +%m%d-%H%M%S).log"
        persist=1
        ln -sf "$rawf" "${LOGDIR}/latest.log" 2>/dev/null
        printf '=== MC 开服器运行日志 ===\n' > "$rawf"
        printf '服务器: %s   启动: %s\n' "${CUR:-?}" "$(date '+%F %T')" >> "$rawf"
        printf '内存: %sM   \n' "${MC_XMX:-?}" >> "$rawf"
        printf '========================\n' >> "$rawf"
    else
        rawf="${tmp}.raw"
    fi
    MC_STAT="$statf"; MC_RAW="$rawf"
    MC_STF="${tmp}.st"; MC_TPSF="${tmp}.tps"
    MC_PLF="${tmp}.pl"; MC_PIDF="${tmp}.pid"; MC_DONEF="${tmp}.done"
    : > "$MC_STF"; : > "$MC_TPSF"; : > "$MC_PLF"; : > "$MC_PIDF"
    rm -f "$MC_DONEF"
    printf '0|初始化|0' > "$MC_STF"

    if [ "$LOGCOLOR" != "1" ]; then
        # 关着色也要照常存日志
        if [ "$persist" = "1" ]; then
            stdbuf -oL -eL "$@" 2>&1 | tee -a "$rawf"
            rc=${PIPESTATUS[0]}
            echo; echo -e "  ${C}运行日志已保存: ${R}$rawf  ${Y}($(wc -l < "$rawf") 行, $(log_size "$rawf"))${R}"
            log_prune
            rm -f "$tmp" "$statf"
            return $rc
        fi
        "$@"
        return $?
    fi

    # ---- 输入转发: 用普通管道, 保证 /stop 与 Ctrl+C 一定能送达 ----
    #  (之前用 FIFO, 写端打开时序不稳定, 会导致命令送不进去、关不掉服)
    local dmn_pid=0 java_pid=0
    local fwd_pid=0

    # 退出清理: 无论如何都要恢复滚动区并收掉后台进程
    mc_cleanup() {
        trap - INT TERM
        printf '\033[r' 2>/dev/null
        [ "$dmn_pid" -gt 0 ] && kill "$dmn_pid" 2>/dev/null
        [ "$fwd_pid" -gt 0 ] && kill "$fwd_pid" 2>/dev/null
        : > "${MC_DONEF:-/dev/null}" 2>/dev/null
    }
    trap 'mc_cleanup; return 130' INT
    trap 'mc_cleanup; return 143' TERM

    # 记录启动前已有的 java, 之后靠差集精确定位本次的 java 进程
    local pre_javas="" jp=""
    for d in /proc/[0-9]*; do
        [ -r "$d/comm" ] || continue
        [ "$(cat "$d/comm" 2>/dev/null)" = "java" ] && pre_javas="$pre_javas ${d##*/}"
    done

    if [ "$STATBAR" = "1" ]; then
        mc_status_daemon "$MC_STF" "$MC_TPSF" "$MC_PIDF" "$MC_DONEF" "$MC_PLF" &
        dmn_pid=$!
    fi

    # java 前台运行(不丢后台), stdin 直接继承脚本
    #  -> /stop、/op 直接进服务端; Ctrl+C 送到整个前台进程组, java 优雅关闭
    #  -> 只有 stdout 走管道(着色 + 落盘), 不碰 stdin, 所以绝不会卡死
    #
    # 注意: 之前把 java 放后台再 wait,  stdin 虽继承但命令送不进去,
    #       结果就是 /stop 无效、Ctrl+C 也关不掉 —— 已改为前台。
    #
    # 后台只放一个 pid 探测器(不读 stdin, 不干扰运行)
    {
        local i3=0
        while [ "$i3" -lt 40 ]; do
            for d in /proc/[0-9]*; do
                [ -r "$d/comm" ] || continue
                [ "$(cat "$d/comm" 2>/dev/null)" = "java" ] || continue
                local pid3="${d##*/}" old=0
                for oj in $pre_javas; do [ "$oj" = "$pid3" ] && old=1; done
                if [ "$old" = "0" ]; then
                    printf '%s' "$pid3" > "$MC_PIDF"; break 2
                fi
            done
            [ -s "$MC_PIDF" ] && break
            sleep 0.5; i3=$((i3+1))
        done
    } &
    local pfind=$!

    if command -v stdbuf >/dev/null 2>&1; then
        stdbuf -oL -eL "$@" 2>&1 | tee -a "$rawf" | mc_classify
        rc=${PIPESTATUS[0]}
    else
        "$@" 2>&1 | tee -a "$rawf" | mc_classify
        rc=${PIPESTATUS[0]}
    fi

    kill $pfind 2>/dev/null
    mc_cleanup

    : > "$MC_DONEF"
    [ "$dmn_pid" -gt 0 ] && { sleep 0.8; kill $dmn_pid 2>/dev/null; wait $dmn_pid 2>/dev/null; }
    printf '\033[r' 2>/dev/null
    [ "$fwd_pid" -gt 0 ] && kill $fwd_pid 2>/dev/null

    local e w j r
    read -r e w j r < "$statf" 2>/dev/null
    : "${e:=0}" "${w:=0}" "${j:=0}" "${r:=0}"

    echo
    printf "  ${Y}%s${R}\n" "$(printf '─%.0s' $(seq 1 40) 2>/dev/null)"
    if [ "$r" -eq 1 ] && [ "$e" -eq 0 ]; then
        printf "  ${G}${B}✔ 服务器已停止${R}  ${Y}(玩家进出 %d 次, 警告 %d 条)${R}\n" "$j" "$w"
    elif [ "$r" -eq 1 ]; then
        printf "  ${Y}${B}⚠ 服务器已停止, 运行期间有 %d 条错误${R}  ${Y}(警告 %d 条)${R}\n" "$e" "$w"
        mc_diagnose "$rawf" "$rc" "$r"
        if [ "$persist" != "1" ]; then
            local keep1="${CONF_DIR}/server-warn-$(date +%m%d-%H%M%S).log"
            cp "$rawf" "$keep1" 2>/dev/null
            [ -f "$keep1" ] && echo -e "  ${Y}完整日志: ${C}$keep1${R}"
        fi
    else
        printf "  ${RD}${B}✘ 服务器未能启动${R}  ${Y}(错误 %d 条, 警告 %d 条)${R}\n" "$e" "$w"
        mc_diagnose "$rawf" "$rc" "$r"
        if [ "$persist" != "1" ]; then
            local keep="${CONF_DIR}/server-crash-$(date +%m%d-%H%M%S).log"
            cp "$rawf" "$keep" 2>/dev/null
            [ -f "$keep" ] && echo -e "  ${Y}完整日志: ${C}$keep${R}"
        fi
    fi

    # 日志已落盘则报告位置; 否则删临时文件
    if [ "$persist" = "1" ]; then
        local lln lsz
        lln=$(wc -l < "$rawf" 2>/dev/null); : "${lln:=0}"
        lsz=$(log_size "$rawf")
        echo -e "  ${C}运行日志: ${R}$rawf  ${Y}(${lln} 行, ${lsz})${R}"
        echo -e "  ${Y}快捷入口: ${C}${LOGDIR}/latest.log${R}  ${Y}(菜单 14 可查看/清理)${R}"
        log_prune
    else
        rm -f "$rawf"
    fi

    rm -f "$tmp" "$statf"
    return $rc
}

# ============================================================
#  下载器: 多镜像 + 卡死自动切源 + 重试
# ============================================================
# 卡死判定: 连续 DL_STALL 秒速度低于 DL_MINSPEED 字节/秒 就掐断换下一个源,
#           不再傻等 --max-time 耗尽(旧版一个卡死源能拖 300 秒)
DL_STALL="${DL_STALL:-15}"        # 低速持续多少秒算卡死
DL_MINSPEED="${DL_MINSPEED:-1024}" # 低于多少 B/s 算低速
DL_MAXTIME="${DL_MAXTIME:-180}"   # 单源硬超时

# dl <保存路径> <url1> [url2 ...]
dl() {
    local out="$1"; shift
    local urls=("$@")
    local i u code n=0
    local total=${#urls[@]}
    for ((i=1; i<=MAX_RETRY; i++)); do
        for u in "${urls[@]}"; do
            [ -z "$u" ] && continue
            n=$((n+1))
            local host; host=$(printf '%s' "$u" | sed -n 's|https\?://\([^/]*\).*|\1|p')
            printf "  \r  ${C}[%s/%s]${R} 正在下载 %s ... " \
                   "$i" "$MAX_RETRY" "$(basename "$out")"
            code=$(curl -sL --max-time "$DL_MAXTIME" \
                        --speed-limit "$DL_MINSPEED" --speed-time "$DL_STALL" \
                        --connect-timeout 10 -A "$UA" "$u" -o "$out" -w "%{http_code}" 2>/dev/null)
            if [ "$code" = "200" ] && [ -s "$out" ]; then
                printf "\r\033[K"
                say "下载成功: $(basename "$out")  ${Y}(源: ${host})${R}"
                return 0
            fi
            printf "\r\033[K"
            rm -f "$out" 2>/dev/null
            local why=""
            case "$code" in
                000) why="超时或卡死(已掐断)";;
                403) why="被拒绝(403)";;
                404) why="地址不存在(404)";;
                *)   why="HTTP:$code";;
            esac
            warn "源 ${host} → ${why}"
            [ "$total" -gt 1 ] && echo -e "       ${Y}自动切换下一个源...${R}"
        done
        warn "第 $i 轮全部失败, 重试中..."
        sleep 2
    done
    err "下载失败已达 $MAX_RETRY 轮: $(basename "$out")"
    err "HTTP:000=超时/卡死 403=被拒绝 404=地址不存在"
    echo -e "  ${Y}可尝试:${R} 菜单 → 镜像连通性自检, 换个能通的镜像"
    echo -e "  ${Y}或手动下载后放入目录${R}"
    return 1
}

# 带致命退出版本
dlx() {
    dl "$@" || { err "程序终止."; press; exit 1; }
}

# ============================================================
#  JSON 解析 (依赖 python3)
# ============================================================
need_py() {
    command -v python3 >/dev/null 2>&1 && return 0
    auto_pkg python3 python && command -v python3 >/dev/null 2>&1 && return 0
    err "需要 python3, 请手动: pkg install python"
    exit 1
}
need_curl() {
    command -v curl >/dev/null 2>&1 && return 0
    auto_pkg curl curl && command -v curl >/dev/null 2>&1 && return 0
    err "需要 curl, 请手动: pkg install curl"
    exit 1
}

# ============================================================
#  依赖自动安装
# ============================================================
#  设计原则:
#    - 缺什么自己装, 不再丢一句"请先 pkg install xxx"就退出
#    - Termux 用 pkg, 普通 Linux 依次试 apt-get / apk / dnf / yum / pacman
#    - 装不上才报错; 非核心工具装不上只警告, 不阻断启动
#    - AUTO_DEPS=0 可关掉自动安装(回到纯提示模式)

AUTO_DEPS="${AUTO_DEPS:-1}"      # 1=自动装依赖  0=只提示不装

# 底层: 执行一次安装, 成功返回 0
_pkg_do() {
    local log="${TMP_DIR}/pkg.$$.log"
    mkdir -p "$TMP_DIR" 2>/dev/null
    if command -v pkg >/dev/null 2>&1; then
        pkg install -y "$@" >"$log" 2>&1 && { rm -f "$log" 2>/dev/null; return 0; }
    fi
    if command -v apt-get >/dev/null 2>&1; then
        if [ "$(id -u 2>/dev/null)" = 0 ]; then
            apt-get install -y "$@" >"$log" 2>&1 && { rm -f "$log" 2>/dev/null; return 0; }
        elif command -v sudo >/dev/null 2>&1; then
            sudo apt-get install -y "$@" >"$log" 2>&1 && { rm -f "$log" 2>/dev/null; return 0; }
        fi
    fi
    local m
    for m in apk dnf yum pacman; do
        if command -v "$m" >/dev/null 2>&1; then
            case "$m" in
                apk)    $m add --no-cache "$@" >"$log" 2>&1 && { rm -f "$log" 2>/dev/null; return 0; };;
                pacman) $m -S --noconfirm "$@" >"$log" 2>&1 && { rm -f "$log" 2>/dev/null; return 0; };;
                *)      $m install -y "$@"     >"$log" 2>&1 && { rm -f "$log" 2>/dev/null; return 0; };;
            esac
        fi
    done
    rm -f "$log" 2>/dev/null
    return 1
}

# 自动装包. $1=显示名, $2..=实际包名
# 装之前会先说明"缺什么、要装什么、大概多久", 装的过程有转圈,
# 装完有结果行 —— 不让用户对着黑屏干等
auto_pkg() {
    [ "${AUTO_DEPS:-1}" = 1 ] || return 1
    local show="$1"; shift
    local pkgs="$*"
    echo
    echo -e "  ${Y}[!]${R} 检测到缺少 ${C}${show}${R}"
    echo -e "      准备安装: ${C}${pkgs}${R}"
    echo -e "      ${Y}首次安装需要下载, 视网速可能要几分钟${R}"
    spin_start "正在安装 ${show}"
    if _pkg_do "$@"; then
        spin_stop ""
        echo -e "      ${G}✔${R} 安装完成: ${show}"
        return 0
    fi
    spin_stop ""
    echo -e "      ${RD}✘${R} 安装失败"
    echo -e "      可手动执行: ${C}pkg install ${pkgs}${R}"
    return 1
}

# 常用小工具批量补齐(非核心, 失败不阻断)
# ---------- termux-api 统一入口: 缺了就自动装, 不再只打印提示 ----------
# 原来脚本里五六个地方都写着"pkg install termux-api"让用户手动跑,
# 其实命令行包是完全可以自动装的 —— 只有那个 App 必须手动装(F-Droid)。
# 现在统一走这里: 能装就装, 装完提示还差 App 那一步。
# 返回 0=已有/刚装好   1=装不上(才会打印手动命令)
need_tapi() {
    # 已有命令(通常意味着包已装)
    command -v termux-wake-lock >/dev/null 2>&1 && return 0
    command -v termux-toast    >/dev/null 2>&1 && return 0

    [ "${AUTO_DEPS:-1}" = 1 ] || return 1   # 关闭自动装就沿用老行为

    echo
    echo -e "  ${Y}[!]${R} 未检测到 ${C}Termux:API${R} 命令行组件 (唤醒锁/通知/弹窗都依赖它)"
    echo -e "      正在自动安装 ${C}termux-api${R} ..."
    spin_start "安装 termux-api"
    if _pkg_do termux-api; then
        spin_stop ""
        echo -e "      ${G}✔${R} termux-api 包已装好"
        echo -e "      ${Y}!${R} 还需装 ${C}Termux:API${R} 这个 App (F-Droid / 官网), 否则命令仍调不动"
        return 0
    fi
    spin_stop ""
    echo -e "      ${RD}✘${R} 自动安装失败, 可手动执行: ${C}pkg install termux-api${R}"
    echo -e "      ${Y}!${R} 装完包还要装 ${C}Termux:API${R} App, 两个都要装才生效"
    return 1
}

need_bins() {
    local miss="" b
    for b in unzip tar wget; do
        command -v "$b" >/dev/null 2>&1 || miss="$miss $b"
    done
    [ -z "$miss" ] && return 0
    if [ "${AUTO_DEPS:-1}" != 1 ]; then
        warn "缺少工具:${miss}  (设 AUTO_DEPS=1 可自动安装)"
        return 1
    fi
    echo
    echo -e "  ${Y}[!]${R} 检测到缺少工具: ${C}${miss}${R}"
    echo -e "      这些是解压/下载用的小工具, 体积很小"
    spin_start "正在安装 ${miss}"
    if _pkg_do $miss; then
        spin_stop ""
        echo -e "      ${G}✔${R} 安装完成"
        return 0
    fi
    spin_stop ""
    echo -e "      ${RD}✘${R} 部分工具未装上, 相关功能(解压/下载)可能受限"
    echo -e "      可手动执行: ${C}pkg install${miss}${R}"
    return 1
}

# Modrinth 版本列表: 输出 "版本号<TAB>文件名<TAB>下载URL"
mr_versions() {
    local slug="$1" loader="$2" mc="$3"
    local url="${MR_API}/project/${slug}/version"
    curl -fsSL --max-time 30 -A "$UA" -G "$url" \
        --data-urlencode "loaders=[\"${loader}\"]" \
        --data-urlencode "game_versions=[\"${mc}\"]" 2>/dev/null | python3 -c '
import sys,json
try: d=json.load(sys.stdin)
except: sys.exit()
if not isinstance(d,list): sys.exit()
for v in d[:15]:
    for f in v.get("files",[]):
        n=f.get("filename","")
        if n.endswith("-sources.jar"): continue
        if n.endswith("-api.jar"): continue
        print("%s\t%s\t%s" % (v.get("version_number"), n, f.get("url")))
        break
' 2>/dev/null
}

# ---------- 统一安全读取 rd() ----------
# 专治两个顽疾:
#   1) 一进菜单就自己退出 —— read 失败(EOF/被中断)时变量会留着上一次的
#      值, 比如上次按过 0, 下次进菜单直接命中 0 分支就退出了。
#      这里不管成功失败, 先把变量清空, 失败一律返回非 0。
#   2) 要连按两次才返回 —— 子菜单和外层的 read 抢同一个 stdin,
#      输入被别处吃掉一次。这里统一从 /dev/tty 读, 跟外层隔离。
#  用法: rd 变量名   (成功返回 0; 失败/EOF 返回 1 且变量为空)
rd() {
    local __rd_v="${1:-}"
    [ -n "$__rd_v" ] || return 1
    printf -v "$__rd_v" '' 2>/dev/null || eval "$__rd_v=''"
    if [ -r /dev/tty ]; then
        IFS= read -r "$__rd_v" < /dev/tty 2>/dev/null || { printf -v "$__rd_v" ''; return 1; }
    else
        IFS= read -r "$__rd_v" 2>/dev/null || { printf -v "$__rd_v" ''; return 1; }
    fi
    return 0
}
# 按回车继续: 同样走 rd, 不吃掉下一次菜单的输入
press() { [ -n "${NOMENU:-}" ] && return 0; echo -e "\n${C}按回车继续...${R}"; rd _press_k; return 0; }

# 查看本机联机地址(自动识别 Astral/EasyTier/Tailscale/ZeroTier 等)
net_info() {
    title "联机地址"
    local found=0
    echo -e "  ${C}扫描虚拟网卡 (任何组网工具都能识别)...${R}"
    echo

    # 通用扫描: 不硬编码某款工具, 遍历所有虚拟网卡
    # Android 上 VpnService 建的网卡通常叫 tun0,
    # 所以按 IP 段 + 网卡名共同推断类型。
    local dev ip4 kind
    while read -r dev ip4; do
        [ -z "$dev" ] && continue
        ip4="${ip4%%/*}"
        case "$ip4" in ''|127.*) continue;; esac
        case "$dev" in
            lo|eth*|wlan*|rmnet*|dummy*|ifb*|p2p*|sit*|ip6tnl*) continue;;
        esac
        case "$dev" in
            tun*|utun*|zt*|tailscale*|easytier*|wg*|ppp*) ;;
            *) continue;;
        esac
        # 推断类型
        if [[ "$ip4" =~ ^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\. ]]; then
            kind="Tailscale"
        elif [[ "$dev" == zt* ]]; then
            kind="ZeroTier"
        elif [[ "$dev" == wg* ]]; then
            kind="WireGuard"
        else
            kind="组网虚拟网卡 (EasyTier 等)"
        fi
        echo -e "  ${G}${kind}${R}  ${Y}(${dev})${R}"
        echo -e "    朋友填: ${C}${ip4}:${PORT}${R}"
        found=1
    done < <(ip -o -4 addr show 2>/dev/null | awk '{print $2, $4}')

    if [ "$found" -eq 0 ]; then
        echo -e "  ${Y}未检测到组网虚拟网卡${R}"
        echo "  装下面任意一个并连接, 这里会自动出现地址:"
        echo -e "    ${C}Astral${R}      免费·无设备限制·安卓老机友好 (推荐)"
        echo -e "    ${C}EasyTier${R}    免费·无设备限制·官方内核"
        echo -e "    ${C}ZeroTier${R}    免费·10台设备上限"
        echo -e "    ${C}Tailscale${R}   免费·6用户上限, 设备不限"
        echo
        echo "  均不需要 root, 但安卓同一时刻只允许一个 VPN 存活。"
    fi
    echo

    # 局域网
    local lan
    lan=$(ip -o -4 addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | grep -E '^192\.168\.' | head -1)
    [ -n "$lan" ] && { echo -e "  ${G}局域网${R}  同 WiFi 的朋友填: ${C}${lan}:${PORT}${R}"; found=1; }

    # 公网 IPv6 (仅作参考)
    local v6
    v6=$(ip -6 addr show scope global 2>/dev/null | grep inet6 | grep -v temporary | grep -v deprecated | awk '{print $2}' | cut -d/ -f1 | head -1)
    [ -n "$v6" ] && { echo; echo -e "  ${Y}公网 IPv6${R} (不推荐: 裸奔端口, 有家宽合规风险)"; echo "    ${v6}"; }
    echo

    if [ "$found" -ne 0 ]; then
        warn "提醒: server-ip 需留空, 服务端才监听虚拟网卡"
    fi
    press
}

# 查询项目许可证 (Modrinth project.license.id, SPDX)
mr_license() {
    local slug="$1"
    curl -fsSL --max-time 20 -A "$UA" "${MR_API}/project/${slug}" 2>/dev/null | python3 -c '
import sys,json
try:
    d=json.load(sys.stdin)
    lic=d.get("license") or {}
    print(lic.get("id") or "UNKNOWN")
except Exception:
    print("UNKNOWN")
' 2>/dev/null
}

# 判断是否受限许可 (ARR / 未知)
is_restricted() {
    case "$1" in
        *ARR*|*All-Rights-Reserved*|*AllRightsReserved*) return 0;;
        UNKNOWN|"") return 0;;
        *) return 1;;
    esac
}

# 许可证审计: 列出已装资源的许可证, 标出受限项
license_audit() {
    local sdir="$1"
    local hist="${HIST_DIR}/${CUR}.list"
    if [ ! -f "$hist" ]; then warn "无历史记录"; press; return; fi
    local slugs; slugs=$(cut -d'|' -f2 "$hist" | sort -u | grep -v '^local$')
    [ -z "$slugs" ] && { warn "无云端下载记录"; press; return; }
    title "许可证审计"
    echo "  (Modrinth 项目许可证, SPDX 标识)"
    echo
    local bad=0
    while read -r s; do
        [ -z "$s" ] && continue
        printf "  %-28s " "$s"
        local lic; lic=$(mr_license "$s")
        if is_restricted "$lic"; then
            echo -e "${Y}${lic}  ← 受限${R}"
            bad=$((bad+1))
        else
            echo -e "${G}${lic}${R}"
        fi
    done <<< "$slugs"
    echo
    if [ $bad -gt 0 ]; then
        warn "有 $bad 项为 ARR(保留所有权利) 或许可未知:"
        warn "  · 自用 / 本地开服  —— 可以"
        warn "  · 打包成整合包对外发布 —— 需作者授权, 请勿擅自分发"
    fi
    press
}

# 镜像连通性自检
# 已知镜像候选(可自行在设置里增删)
# 注: 清华 TUNA 镜像站不提供 Modrinth 镜像, 其为 Linux 发行版 /
#     编程语言包仓库; Minecraft 资源需用 MCIM / BMCLAPI 一类。
MIRRORS=(
    "https://api.modrinth.com/v2|Modrinth 官方(国外)"
    "https://mod.mcimirror.top/modrinth/v2|MCIM 国内镜像"
    "https://bmclapi2.bangbang93.com|BMCLAPI 国内镜像"
    "https://api.modrinth.com|Modrinth 备用(无/v2)"
)

probe() {
    curl -s -o /dev/null -w "%{http_code}" --max-time 15 -A "$UA" \
        -G "$1/project/create/version" \
        --data-urlencode 'loaders=["neoforge"]' \
        --data-urlencode 'game_versions=["1.21.1"]'
}

mirror_pick() {
    title "探测可用镜像"
    local best="" bestdesc=""
    for m in "${MIRRORS[@]}"; do
        local url="${m%%|*}" desc="${m##*|}"
        printf "  %-46s " "$desc"
        local c; c=$(probe "$url")
        case "$c" in
            200) echo -e "${G}$c 可用${R}"; [ -z "$best" ] && { best="$url"; bestdesc="$desc"; };;
            403) echo -e "${Y}$c 被拦截${R}";;
            000) echo -e "${Y}$c 超时${R}";;
            *)   echo -e "${Y}$c${R}";;
        esac
    done
    echo
    if [ -n "$best" ]; then
        if [ "${AUTO_MIRROR:-1}" = 1 ]; then
            [ "$best" != "$MR_API" ] && { MR_API="$best"; save_conf; }
            say "已自动切换到最优镜像: $bestdesc"
        else
            ask "是否切换到 [$bestdesc]? [Y/n]: "
            rd y
            case "$y" in n|N) ;; *) MR_API="$best"; save_conf; say "已切换";; esac
        fi
    else
        err "全部不可用, 请检查网络或自行填写镜像地址"
    fi
    press
}

# 静默自动选镜像(不打印探测过程, 供启动时调用)
# 返回 0=已切到可用源  1=全挂
mirror_auto() {
    [ "${AUTO_MIRROR:-1}" = 1 ] || return 1
    local best="" m url c
    for m in "${MIRRORS[@]}"; do
        url="${m%%|*}"
        c=$(probe "$url")
        [ "$c" = "200" ] && { best="$url"; break; }
    done
    [ -z "$best" ] && return 1
    [ "$best" != "$MR_API" ] && { MR_API="$best"; save_conf; }
    return 0
}

test_mirror() {
    title "镜像连通性自检"
    local code; code=$(probe "$MR_API")
    echo "当前 API: $MR_API"
    echo "返回码  : $code"
    case "$code" in
        200) say "连通正常 ✅";;
        403) err "被拒绝(403) —— 当前出口IP被拦截, 建议换镜像";;
        000) err "无响应 —— 网络不可达或超时";;
        *)   warn "异常返回码: $code";;
    esac
    echo
    if [ "$code" != "200" ]; then
        ask "是否自动探测并切换可用镜像? [Y/n]: "
        rd y
        case "$y" in n|N) ;; *) mirror_pick; return;; esac
    fi
    press
}

# ============================================================
#  核心安装
# ============================================================
#  ---- GPL-3.0 声明 (重申) ----
#  本文件自此处起的所有代码, 包括 install_core / cloud_add /
#  import_pack / world_menu / repair / start_server / license_audit
#  等函数, 均为 mcserv 项目的一部分, 依 GPL-3.0-or-later 授权。
#  你可自由使用、修改、分发本脚本, 包括用于商业目的。
#  但只要你把修改过的版本提供给他人, 就必须同时提供完整源码,
#  并以同样的 GPL-3.0 授权 —— 不能闭源。
#  详见: https://www.gnu.org/licenses/gpl-3.0.html
#  ---- 声明结束 ----
install_core() {
    local sdir="$1" type="$2" loader="$3" mc="$4"
    mkdir -p "$sdir"; cd "$sdir" || return 1

    case "$loader" in
    paper|purpur|folia|velocity)
        # PaperMC 系: 用官方 API 取最新构建
        local proj="$loader"
        [ "$loader" = "velocity" ] && proj="velocity"
        local builds
        if [ "$loader" = "purpur" ]; then
            builds=$(curl -fsSL --max-time 30 -A "$UA" "https://api.purpurmc.org/v2/purpur/${mc}" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["builds"]["latest"])' 2>/dev/null)
        else
            builds=$(curl -fsSL --max-time 30 -A "$UA" "https://api.papermc.io/v2/projects/${proj}/versions/${mc}" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["builds"][-1])' 2>/dev/null)
        fi
        [ -z "$builds" ] && { err "获取 ${loader} 构建号失败"; return 1; }
        if [ "$loader" = "purpur" ]; then
            dlx "server.jar" "https://api.purpurmc.org/v2/purpur/${mc}/${builds}/download"
        else
            dlx "server.jar" "https://api.papermc.io/v2/projects/${proj}/versions/${mc}/builds/${builds}/downloads/${proj}-${mc}-${builds}.jar"
        fi
        ;;
    neoforge)
        # 若用户已手动放置 installer, 直接跳过下载
        local pre
        pre=$(ls neoforge-*-installer.jar 2>/dev/null | head -1)
        if [ -n "$pre" ] && [ -s "$pre" ]; then
            say "检测到已存在的安装器: $pre"
            ask "直接使用它? [Y/n]: "; rd y
            case "$y" in n|N) pre="";; esac
        fi
        if [ -z "$pre" ]; then
            local nf
            nf=$(curl -fsSL --max-time 30 -A "$UA" "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml" 2>/dev/null \
                 | grep -o "<version>21\.1\.[0-9]*</version>" | tail -1 | sed 's/<[^>]*>//g')
            [ -z "$nf" ] && nf="21.1.252"
            say "NeoForge 版本: $nf"
            warn "官方源 maven.neoforged.net 在国内常无法访问,"
            warn "将依次尝试多个镜像..."
            # 多镜像轮询(官方 + BMCLAPI + ForgeCDN)
            dlx "neoforge-installer.jar" \
                "https://maven.neoforged.net/releases/net/neoforged/neoforge/${nf}/neoforge-${nf}-installer.jar" \
                "https://bmclapi2.bangbang93.com/maven/net/neoforged/neoforge/${nf}/neoforge-${nf}-installer.jar" \
                "https://download.mcbbs.net/maven/net/neoforged/neoforge/${nf}/neoforge-${nf}-installer.jar"
            pre="neoforge-installer.jar"
        fi
        # 放宽 JVM 网络超时: installer 默认超时偏短, 国内下 maven 库
        # 容易触发一次假失败再重试。放宽后多数情况一次就能下完。
        if ! run_jar "安装 NeoForge ${nf} 服务端" java \
                -Dsun.net.client.defaultConnectTimeout=60000 \
                -Dsun.net.client.defaultReadTimeout=300000 \
                -jar "$pre" --installServer .; then
            echo
            warn "提示: NeoForge 的依赖库走 maven, 国内常下不动"
            echo -e "      ${C}→${R} 换网络(流量/WiFi 互切)后重跑即可, 已下的库会保留"
            echo -e "      ${C}→${R} 锁屏会掐断网络, 建议先 termux-wake-lock"
            return 1
        fi
        ;;
    fabric)
        local inst loader_ver
        inst=$(curl -fsSL --max-time 30 -A "$UA" "https://meta.fabricmc.net/v2/versions/installer" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d[0]["version"])' 2>/dev/null)
        loader_ver=$(curl -fsSL --max-time 30 -A "$UA" "https://meta.fabricmc.net/v2/versions/loader/${mc}" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d[0]["loader"]["version"])' 2>/dev/null)
        [ -z "$inst" ] && inst="1.0.1"
        dlx "fabric-installer.jar" \
            "https://maven.fabricmc.net/net/fabricmc/fabric-installer/${inst}/fabric-installer-${inst}.jar"
        run_jar "安装 Fabric 服务端 (MC $mc)" \
            java -Dsun.net.client.defaultConnectTimeout=60000 \
                 -Dsun.net.client.defaultReadTimeout=300000 \
                 -jar fabric-installer.jar server -mcversion "$mc" -loader "$loader_ver" -downloadMinecraft || return 1
        ;;
    forge)
        warn "Forge 在 1.21 之后已停止维护, 强烈建议改用 NeoForge!"
        rd c
        [ "${c,,}" != "y" ] && return 1
        dlx "forge-installer.jar" \
            "https://maven.minecraftforge.net/net/minecraftforge/forge/${mc}-latest/forge-${mc}-latest-installer.jar"
        run_jar "安装 Forge 服务端 (MC $mc)" \
            java -Dsun.net.client.defaultConnectTimeout=60000 \
                 -Dsun.net.client.defaultReadTimeout=300000 \
                 -jar forge-installer.jar --installServer . || return 1
        ;;
    *)
        err "未知加载器: $loader"; return 1;;
    esac
    echo "eula=true" > eula.txt
    return 0
}

# ============================================================
#  模组 / 插件 云端下载
# ============================================================
# kind=mod|plugin
cloud_add() {
    local sdir="$1" kind="$2" loader="$3" mc="$4"
    local hist="${HIST_DIR}/${CUR}.list"
    mkdir -p "$sdir/mods" "$sdir/plugins"

    title "云端添加 ${kind} (加载器: $loader / MC: $mc)"
    ask "输入项目名(slug, 多个用空格分开): "
    read -r -a slugs
    [ ${#slugs[@]} -eq 0 ] && return

    for slug in "${slugs[@]}"; do
        say "查询: $slug"
        local res
        res=$(mr_versions "$slug" "$loader" "$mc")
        if [ -z "$res" ]; then
            err "未找到 [$slug] 在 ${mc}+${loader} 下的版本, 跳过"
            continue
        fi
        echo "$res" | head -5 | cat -n
        ask "选择序号 (1=最新, 直接回车=1, s=跳过): "
        rd no
        [ "$no" = "s" ] && continue
        [ -z "$no" ] && no=1
        local line ver fname furl
        line=$(echo "$res" | sed -n "${no}p")
        ver=$(echo "$line" | cut -f1)
        fname=$(echo "$line" | cut -f2)
        furl=$(echo "$line" | cut -f3)

        local dest="$sdir/mods/$fname"
        [ "$kind" = "plugin" ] && dest="$sdir/plugins/$fname"

        local lic
        lic=$(mr_license "$slug")
        say "许可证: $lic"
        if is_restricted "$lic"; then
            warn "该资源为 ARR(保留所有权利) 或许可未知:"
            warn "  自用可以, 打包成整合包对外发布需作者授权"
        fi
        say "下载: $fname ($ver)"
        if dl "$dest" "$furl"; then
            echo "$kind|$slug|$ver|$fname|$furl|$lic" >> "$hist"
            say "完成: $fname"
        fi
    done
    sort -u "$hist" -o "$hist" 2>/dev/null
}

# ============================================================
#  整合包导入
# ============================================================
import_pack() {
    local sdir="$1"
    title "导入整合包"
    ask "整合包文件路径 (.mrpack / .zip): "
    rd pf
    pf=$(eval echo "${pf/#\~/$HOME}")
    [ ! -f "$pf" ] && { err "文件不存在"; return; }

    local wd="${TMP_DIR}/pack_$$"
    rm -rf "$wd"; mkdir -p "$wd"
    unzip -qo "$pf" -d "$wd" || { err "解压失败"; rm -rf "$wd"; return; }

    # 世界整合包检测
    if [ -d "$wd/world" ] || [ -d "$wd/overrides/world" ] || [ -d "$wd/overrides/saves" ]; then
        err "检测到存档数据 —— 该整合包为【世界整合包】"
        err "无法拉入模组 (会覆盖现有世界), 已中止."
        warn "如需导入世界, 请使用主菜单的 [存档管理]"
        rm -rf "$wd"; press; return
    fi

    local src=""
    [ -d "$wd/overrides/mods" ] && src="$wd/overrides/mods"
    [ -d "$wd/overrides/plugins" ] && src="$wd/overrides/plugins"
    [ -d "$wd/mods" ] && src="$wd/mods"

    if [ -z "$src" ]; then
        err "未找到 mods/ 或 plugins/ 目录"
        rm -rf "$wd"; press; return
    fi

    mkdir -p "$sdir/mods" "$sdir/plugins"
    cp -rn "$src"/* "$sdir/mods/" 2>/dev/null
    cp -rn "$src"/* "$sdir/plugins/" 2>/dev/null
    cp -rn "$wd/overrides/config" "$sdir/" 2>/dev/null

    # 记录到历史(无URL, 修复时跳过)
    local hist="${HIST_DIR}/${CUR}.list"
    for f in "$src"/*; do
        [ -f "$f" ] && echo "local|$(basename "$src")|imported|$(basename "$f")|" >> "$hist"
    done
    sort -u "$hist" -o "$hist" 2>/dev/null

    say "已导入: $(ls "$src" | wc -l) 个文件"
    warn "提醒: 其中若有 ARR(保留所有权利) 资源, 仅可自用,"
    warn "      打包对外发布需获得原作者授权。"
    warn "      可用菜单 [12] 许可证审计 核查云端下载的部分。"
    rm -rf "$wd"
}


# ============================================================
#  存档与种子工具 (依赖 python3)
# ============================================================
WT_PY="${CONF_DIR}/wttool.py"

wt_py() {
    [ -s "$WT_PY" ] && return 0
    mkdir -p "$CONF_DIR" 2>/dev/null
    cat > "$WT_PY" <<'PYEOF'
import gzip,struct,sys,os

def java_hash(t):
    h=0
    for c in t:
        h=(31*h+ord(c))&0xFFFFFFFF
    if h>=0x80000000: h-=0x100000000
    return h

def nbt_seed(path):
    try: raw=gzip.open(path,'rb').read()
    except Exception:
        try: raw=open(path,'rb').read()
        except Exception: return None
    pat=b'\x04\x00\x0bRandomSeed'
    i=raw.find(pat)
    if i>=0:
        try: return struct.unpack('>q',raw[i+len(pat):i+len(pat)+8])[0]
        except Exception: return None
    i=raw.find(b'RandomSeed')
    if i>=0:
        try: return struct.unpack('>q',raw[i+11:i+19])[0]
        except Exception: return None
    return None

def nbt_str(raw,key):
    i=raw.find(b'\x08'+struct.pack('>H',len(key))+key.encode())
    if i<0: return None
    p=i+3+len(key)
    try:
        n=struct.unpack('>H',raw[p:p+2])[0]
        return raw[p+2:p+2+n].decode('utf-8','replace')
    except Exception: return None

def world_info(d):
    info={}
    lv=os.path.join(d,'level.dat')
    if os.path.exists(lv):
        sd=nbt_seed(lv)
        if sd is not None: info['seed']=sd
        try: raw=gzip.open(lv,'rb').read()
        except Exception: raw=b''
        v=nbt_str(raw,'Name')
        if v: info['ver']=v
    # 体积
    tot=0
    for r,ds,fs in os.walk(d):
        for f in fs:
            try: tot+=os.path.getsize(os.path.join(r,f))
            except Exception: pass
    info['size']=tot
    # 玩家数
    pd=os.path.join(d,'playerdata')
    info['players']=len([x for x in os.listdir(pd) if x.endswith('.dat')]) if os.path.isdir(pd) else 0
    # 维度
    dims=[]
    for sub in ('region','DIM-1/region','DIM1/region'):
        rp=os.path.join(d,sub)
        if os.path.isdir(rp):
            dims.append(sub.split('/')[0] or 'overworld')
    info['dims']=dims
    return info

cmd=sys.argv[1]
if cmd=="seed":
    print(nbt_seed(sys.argv[2]) if os.path.exists(sys.argv[2]) else "")
elif cmd=="hash":
    print(java_hash(sys.argv[2]))
elif cmd=="info":
    i=world_info(sys.argv[2])
    print(i.get('seed',''))
    print(i.get('ver',''))
    print(i.get('size',0))
    print(i.get('players',0))
    print(','.join(i.get('dims',[])))
PYEOF
}

wt_seed()  { wt_py; [ -f "$1" ] || { echo ""; return; }; python3 "$WT_PY" seed "$1" 2>/dev/null; }
wt_hash()  { wt_py; python3 "$WT_PY" hash "$1" 2>/dev/null; }

# 人类可读体积
wt_hsize() {
    local b="$1"
    if [ "$b" -ge 1073741824 ]; then
        echo "$((b/1073741824))GB"
    elif [ "$b" -ge 1048576 ]; then
        echo "$((b/1048576))MB"
    elif [ "$b" -ge 1024 ]; then
        echo "$((b/1024))KB"
    else
        echo "${b}B"
    fi
}

# ============================================================
#  服务器图标 / 简介 (MOTD)
# ============================================================
IC_PY="${CONF_DIR}/icontool.py"

ic_py() {
    # ---------------------------------------------------------------
    #  坑: 原来只判断 [ -s "$IC_PY" ] 就直接用。
    #  后果: mcserv.sh 升级后 ~/.mcserv/icontool.py 仍是旧版,
    #  缺新能力或带旧 bug —— 表现就是"选图一直失败",
    #  而且重装主脚本也修不好, 因为那个缓存文件从没被更新过。
    #  现在: 带版本号, 版本对不上(或文件空/损坏)就重建。
    # ---------------------------------------------------------------
    local stamp="${CONF_DIR}/icontool.ver"
    local want="ic${MCSERV_VER:-1.6}"
    local have=""; [ -f "$stamp" ] && have=$(tr -d ' \r\n' < "$stamp" 2>/dev/null)
    if [ -s "$IC_PY" ] && [ "$have" = "$want" ]; then return 0; fi
    mkdir -p "$CONF_DIR" 2>/dev/null
    cat > "$IC_PY" <<'PYEOF'
import zlib,struct,sys,os,hashlib

def png_size(path):
    try:
        with open(path,'rb') as f:
            h=f.read(24)
        if h[:8]!=b'\x89PNG\r\n\x1a\n': return None
        w,h2=struct.unpack('>II',h[16:24])
        return (w,h2)
    except Exception: return None

def chunk(t,d):
    c=t+d
    return struct.pack('>I',len(d))+c+struct.pack('>I',zlib.crc32(c)&0xFFFFFFFF)

def write_png(path,w,h,px):   # px: bytearray RGBA
    raw=bytearray()
    for y in range(h):
        raw.append(0)
        raw+=px[y*w*4:(y+1)*w*4]
    out=b'\x89PNG\r\n\x1a\n'
    out+=chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))
    out+=chunk(b'IDAT',zlib.compress(bytes(raw),9))
    out+=chunk(b'IEND',b'')
    open(path,'wb').write(out)

# ---- 纯 python PNG 解码 (无 Pillow 时兜底) ----
def read_png(path):
    d=open(path,'rb').read()
    if d[:8]!=b'\x89PNG\r\n\x1a\n': return None
    pos=8; idat=b''; w=h=bd=ct=None
    while pos<len(d):
        ln=struct.unpack('>I',d[pos:pos+4])[0]; typ=d[pos+4:pos+8]
        data=d[pos+8:pos+8+ln]; pos+=12+ln
        if typ==b'IHDR':
            w,h,bd,ct=struct.unpack('>IIBB',data[:10])
        elif typ==b'IDAT': idat+=data
        elif typ==b'IEND': break
    if bd!=8: return None
    nch={0:1,2:3,3:1,4:2,6:4}.get(ct)
    if not nch: return None
    raw=zlib.decompress(idat)
    bpp=nch; stride=w*bpp
    out=bytearray(h*stride); prev=bytearray(stride); i=0
    for y in range(h):
        ft=raw[i]; i+=1
        line=bytearray(raw[i:i+stride]); i+=stride
        if ft==1:
            for x in range(bpp,stride): line[x]=(line[x]+line[x-bpp])&255
        elif ft==2:
            for x in range(stride): line[x]=(line[x]+prev[x])&255
        elif ft==3:
            for x in range(stride):
                a=line[x-bpp] if x>=bpp else 0
                line[x]=(line[x]+((a+prev[x])>>1))&255
        elif ft==4:
            for x in range(stride):
                a=line[x-bpp] if x>=bpp else 0
                b=prev[x]; c=prev[x-bpp] if x>=bpp else 0
                pp=a+b-c
                pa,pb,pc=abs(pp-a),abs(pp-b),abs(pp-c)
                pr=a if (pa<=pb and pa<=pc) else (b if pb<=pc else c)
                line[x]=(line[x]+pr)&255
        out[y*stride:(y+1)*stride]=line
        prev=line
    # 统一成 RGBA
    res=bytearray(w*h*4)
    if nch==4:
        res=out
    elif nch==3:
        for i2 in range(w*h):
            res[i2*4:i2*4+3]=out[i2*3:i2*3+3]; res[i2*4+3]=255
    elif nch==2:
        for i2 in range(w*h):
            g,a=out[i2*2],out[i2*2+1]
            res[i2*4:i2*4+4]=bytes([g,g,g,a])
    else:
        for i2 in range(w*h):
            g=out[i2]
            res[i2*4:i2*4+4]=bytes([g,g,g,255])
    return (w,h,res)

def crop_square(w,h,px):
    if w==h: return (w,px)
    s=min(w,h)
    ox=(w-s)//2; oy=(h-s)//2
    out=bytearray(s*s*4)
    for y in range(s):
        src=(oy+y)*w*4+ox*4
        out[y*s*4:(y+1)*s*4]=px[src:src+s*4]
    return (s,out)

def resize_nn(w,h,px,n):
    out=bytearray(n*n*4)
    for y in range(n):
        sy=y*h//n
        for x in range(n):
            sx=x*w//n
            si=(sy*w+sx)*4; di=(y*n+x)*4
            out[di:di+4]=px[si:si+4]
    return out

def do_resize(src,dst):
    r=read_png(src)
    if r is None: return False
    w,h,px=r
    s,px=crop_square(w,h,px)
    px=resize_nn(s,s,px,64)
    write_png(dst,64,64,px)
    return True

# ---- 生成方块风格图标 ----
def gen_icon(name,dst):
    hv=int(hashlib.md5(name.encode('utf-8')).hexdigest()[:8],16)
    hue=hv%360
    def hsv2rgb(hh,ss,vv):
        import colorsys
        r,g,b=colorsys.hsv_to_rgb(hh/360.0,ss,vv)
        return (int(r*255),int(g*255),int(b*255))
    base=hsv2rgb(hue,0.55,0.85)
    dark=tuple(int(c*0.72) for c in base)
    dark2=tuple(int(c*0.55) for c in base)
    grass=hsv2rgb((hue+40)%360,0.60,0.70)
    grass2=hsv2rgb((hue+40)%360,0.60,0.55)
    N=64; px=bytearray(N*N*4)
    def put(x,y,c):
        if 0<=x<N and 0<=y<N:
            i=(y*N+x)*4
            px[i:i+4]=bytes(c+(255,))
    # 立方体: 顶面菱形 + 左面 + 右面
    for y in range(N):
        for x in range(N):
            # 归一化到立方体坐标
            cx=(x-31.5)/30.0; cy=(y-31.5)/30.0
            # 顶面: |cx|+|cy|<=0.72 且 在上方
            if abs(cx)+abs(cy)<=0.62 and cy<=0.05:
                c=base if ((x+y)//4)%2==0 else tuple(min(255,int(v*1.08)) for v in base)
                put(x,y,c)
            elif cx<-0.02 and cy>abs(cx)*0.4-0.35:
                put(x,y,grass if ((x+y)//4)%2==0 else grass2)
            elif cx>0.02:
                put(x,y,dark if ((x+y)//4)%2==0 else dark2)
    write_png(dst,N,N,px)

cmd=sys.argv[1]
if cmd=="size":
    r=png_size(sys.argv[2])
    print("%dx%d" % r if r else "")
elif cmd=="resize":
    ok=False
    try:
        from PIL import Image
        im=Image.open(sys.argv[2])
        im=im.convert("RGBA")
        w,hh=im.size
        s=min(w,hh)
        im=im.crop(((w-s)//2,(hh-s)//2,(w-s)//2+s,(hh-s)//2+s))
        im=im.resize((64,64),Image.LANCZOS)
        im.save(sys.argv[3])
        ok=True
    except Exception:
        ok=do_resize(sys.argv[2],sys.argv[3])
    print("ok" if ok else "fail")
elif cmd=="gen":
    gen_icon(sys.argv[2],sys.argv[3]); print("ok")
PYEOF
    printf '%s' "$want" > "$stamp" 2>/dev/null
}

ic_size()  { ic_py; python3 "$IC_PY" size "$1" 2>/dev/null; }
ic_hsize() {
    local b="${1:-0}"
    if [ "$b" -ge 1048576 ]; then echo "$((b/1048576))MB"
    elif [ "$b" -ge 1024 ]; then echo "$((b/1024))KB"
    else echo "${b}B"; fi
}

# 安全读取服务器 meta 字段
# ---------------------------------------------------------------
#  原来到处直接 `source xxx.meta` 再用 $type $loader $mc。
#  脚本开头是 set -uo pipefail, 只要 meta 缺一个字段(老版本写的、
#  手动改过、导入整合包生成的), 引用到就整段崩 —— 主菜单直接挂掉,
#  表现就是"进不去 / 什么都点不了"。
#  这里统一走 grep 取值, 读不到返回空, 永远不炸。
# ---------------------------------------------------------------
mg() {
    local k="$1" nn="${2:-${CUR:-}}"
    [ -n "$nn" ] || return 0
    [ -f "${HIST_DIR}/${nn}.meta" ] || return 0
    grep -m1 "^${k}=" "${HIST_DIR}/${nn}.meta" 2>/dev/null | cut -d= -f2- | tr -d '\r'
}

# 扫描本机图片供选择
# ---------------------------------------------------------------
#  原来用的是 GNU find 的 -printf '%p\n'。
#  安卓(Termux / toybox)的 find 根本不认 -printf, 遇到不认识的参数
#  直接报错退出, 整条管道没输出 -> 永远"没扫到图片"。
#  这就是"服务器无法选择图片"的根源之一。
#
#  现在改成三级兜底:
#    1) python3 扫(最可靠, 跨平台, 顺便按大小排序)
#    2) find -print(POSIX 写法, toybox 也支持)
#    3) ls 兜底(极端情况)
# ---------------------------------------------------------------
# 候选扫描目录: 优先 Termux 存储软链(一定有权限), 再试直连路径
ic_scan_dirs() {
    local d seen=" "
    local -a c1 c2 c3
    c1=("$HOME/storage/shared" "$HOME/storage/pictures" "$HOME/storage/dcim"
        "$HOME/storage/downloads" "$HOME/storage/movies" "$HOME/storage/music"
        "$HOME/storage/shared/Pictures" "$HOME/storage/shared/DCIM"
        "$HOME/storage/shared/Download" "$HOME/storage/shared/Pictures/Screenshots")
    c2=(/sdcard/Pictures /sdcard/DCIM /sdcard/Download
        /storage/emulated/0/Pictures /storage/emulated/0/DCIM
        /storage/emulated/0/Download /storage/emulated/0/Android/media)
    c3=("$ROOT" "$ROOT/cache" "$HOME" "$HOME/Download" "$HOME/downloads")
    for d in "${c1[@]}" "${c2[@]}" "${c3[@]}"; do
        [ -n "$d" ] || continue
        [ -d "$d" ] && [ -r "$d" ] || continue
        case "$seen" in *"|$d|"*) continue;; esac
        seen="$seen|$d|"; printf '%s\n' "$d"
    done
}

# 确保有存储权限; 没有就试着申请一次
ic_ensure_storage() {
    [ -d "$HOME/storage/shared" ] || [ -d "$HOME/storage/pictures" ] && return 0
    echo -e "  ${Y}[!]${R} 还没给 Termux 存储权限, 读不到手机里的图片" >&2
    if command -v termux-setup-storage >/dev/null 2>&1; then
        echo -e "  ${C}正在申请, 请在弹窗里点「允许」...${R}" >&2
        termux-setup-storage >/dev/null 2>&1
        sleep 1
        if [ -d "$HOME/storage/shared" ] || [ -d "$HOME/storage/pictures" ]; then
            say "存储权限已就绪" >&2; return 0
        fi
        echo -e "  ${Y}没拿到权限。回主菜单按要求授权后再来${R}" >&2
        return 1
    fi
    perm_ensure storage >/dev/null 2>&1
    echo -e "  ${Y}没找到 termux-setup-storage, 请手动授权存储${R}" >&2
    return 1
}

ic_scan() {
    local dirs=() d
    while IFS= read -r d; do
        [ -n "$d" ] && dirs+=("$d")
    done < <(ic_scan_dirs)
    [ ${#dirs[@]} -eq 0 ] && return
    mkdir -p "$TMP_DIR" 2>/dev/null

    # ---- 1) python3 扫 ----
    if command -v python3 >/dev/null 2>&1; then
        local pyf="${TMP_DIR}/icscan.$$.py"
        cat > "$pyf" <<'ICPYEOF'
import os,sys
dirs=[d for d in sys.argv[1:] if os.path.isdir(d)]
ext=('.png','.jpg','.jpeg','.webp','.bmp','.gif')
out=[];seen=set()
for d in dirs:
    try:
        for root,dn,fn in os.walk(d):
            depth=root[len(d):].count(os.sep)
            if depth>=3:
                dn[:]=[];continue
            for f in fn:
                if not f.lower().endswith(ext):continue
                pp=os.path.join(root,f)
                if pp in seen:continue
                seen.add(pp)
                try:sz=os.path.getsize(pp)
                except Exception:continue
                if sz==0 or sz>20971520:continue
                out.append((sz,pp))
            if len(out)>=60:break
    except Exception:pass
    if len(out)>=60:break
out.sort(key=lambda x:-x[0])
for sz,pp in out[:40]:
    if sz>=1048576:t="%dMB"%(sz//1048576)
    elif sz>=1024:t="%dKB"%(sz//1024)
    else:t="%dB"%sz
    print("%s\t%s"%(pp,t))
ICPYEOF
        local got
        got=$(python3 "$pyf" "${dirs[@]}" 2>/dev/null)
        rm -f "$pyf" 2>/dev/null
        if [ -n "$got" ]; then printf '%s\n' "$got"; return 0; fi
    fi

    # ---- 2) find -print (POSIX 写法, toybox 支持) ----
    local f sz found=0
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        sz=$(stat -c %s "$f" 2>/dev/null || echo 0)
        case "$sz" in ''|*[!0-9]*) continue;; esac
        [ "$sz" -eq 0 ] && continue
        [ "$sz" -gt 20971520 ] && continue
        printf '%s\t%s\n' "$f" "$(ic_hsize "$sz")"
        found=$((found+1))
        [ "$found" -ge 30 ] && break
    done < <(find "${dirs[@]}" -maxdepth 3 -type f \
             \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
                -o -iname '*.webp' -o -iname '*.bmp' \) \
             -print 2>/dev/null | sort | head -40)
    [ "$found" -gt 0 ] && return 0

    # ---- 3) ls 兜底 ----
    for d in "${dirs[@]}"; do
        for f in "$d"/*.png "$d"/*.jpg "$d"/*.jpeg "$d"/*.webp; do
            [ -f "$f" ] || continue
            sz=$(stat -c %s "$f" 2>/dev/null || echo 0)
            printf '%s\t%s\n' "$f" "$(ic_hsize "$sz")"
        done
    done 2>/dev/null
}

# 逐层浏览目录选图: 扫描不到时的兜底, 纯手工一步步进目录找
# 所有界面输出走 stderr, stdout 只吐最终选中的文件路径
ic_browse() {
    local cur="${1:-}"
    [ -n "$cur" ] && [ -d "$cur" ] || cur="$HOME/storage/shared"
    [ -d "$cur" ] || cur="$HOME"
    [ -d "$cur" ] || cur="/"
    local -a ents=()
    local f i n sel dn
    while true; do
        title "浏览目录选图" >&2
        echo -e "  ${C}当前:${R} $cur" >&2
        echo >&2
        ents=(); i=0
        echo -e "  ${C}..)${R} 上一级" >&2
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            ents+=("$f"); i=$((i+1))
            printf "  ${C}%2d)${R} ${Y}[目录]${R} %s\n" "$i" "$(basename "$f")" >&2
        done < <(find "$cur" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort | head -40)
        dn=$i
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            ents+=("$f"); i=$((i+1))
            printf "  ${C}%2d)${R} ${G}[图片]${R} %s\n" "$i" "$(basename "$f")" >&2
        done < <(find "$cur" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' \
                  -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.bmp' \) \
                  2>/dev/null | sort | head -40)
        echo >&2
        echo -e "  ${Y}直接输路径也行, 或按回车=返回${R}" >&2
        echo -e "  ${C} 0)${R} 取消" >&2
        echo >&2
        ask "选择: " >&2; rd n || return 1
        case "$n" in
            0|"") return 1;;
            "..") local up; up=$(dirname "$cur"); [ -n "$up" ] && cur="$up"; continue;;
        esac
        if [ -n "$n" ] && [ -f "$n" ]; then echo "$n"; return 0; fi
        if [ -n "$n" ] && [ -d "$n" ]; then cur="$n"; continue; fi
        case "$n" in
            *[!0-9]*) continue;;
        esac
        { [ "$n" -lt 1 ] || [ "$n" -gt "${#ents[@]}" ]; } && continue
        sel="${ents[$((n-1))]}"
        [ -z "$sel" ] && continue
        if [ -d "$sel" ]; then cur="$sel"; continue; fi
        echo "$sel"; return 0
    done
}

# MOTD 专用菜单
motd_menu() {
    local f="$1"
    local cur; cur=$(prop_get motd "$f")
    while true; do
        title "服务器简介 (MOTD)"
        echo -e "  MOTD = 朋友服务器列表里看到的那行字"
        echo -e "  当前: ${C}${cur:-A Minecraft Server}${R}"
        echo
        echo -e "  颜色代码: ${G}&a${R}绿 ${Y}&6${R}金 ${RD}&c${R}红 ${C}&b${R}青 ${B}&9${R}蓝 ${Y}&e${R}黄  加粗 &l"
        echo
        echo "   1) 手输一行"
        echo "   2) 双行简介 (主标题 + 副标题)"
        echo "   3) 用现成模板"
        echo "   4) 恢复默认"
        echo "   0) 返回"
        echo
        ask "选择: "; rd _mmc || return
        case "$_mmc" in
        1) ask "输入简介: "; rd mv
           [ -z "$mv" ] && continue
           mv="${mv//&/§}"
           prop_set motd "$mv" "$f"; say "已设置: $mv"; press; return;;
        2) ask "第一行 (主标题): "; rd m1
           ask "第二行 (副标题): "; rd m2
           m1="${m1//&/§}"; m2="${m2//&/§}"
           if [ -n "$m2" ]; then
               prop_set motd "${m1}\n${m2}" "$f"
               say "已设置双行简介"
           else
               prop_set motd "$m1" "$f"; say "已设置"
           fi
           press; return;;
        3) title "模板"
           echo "   1) §a欢迎来到 §6${CUR}"
           echo "   2) §6${CUR} §7— §a生存服"
           echo "   3) §c维护中 §7稍后再来"
           echo "   4) §b组队开黑 §7| §e快乐生存"
           echo "   0) 取消"
           ask "选择: "; rd mt
           local val=""
           case "$mt" in
               1) val="§a欢迎来到 §6${CUR}";;
               2) val="§6${CUR} §7— §a生存服";;
               3) val="§c维护中 §7稍后再来";;
               4) val="§b组队开黑 §7| §e快乐生存";;
               *) continue;;
           esac
           prop_set motd "$val" "$f"; say "已设置: $val"; press; return;;
        4) prop_set motd "A Minecraft Server" "$f"; say "已恢复默认"; press; return;;
        0|q|Q) return;;
        esac
    done
}

# 调安卓系统文件管理器选图 (Termux:API)
# 返回: 0 成功(打印路径)  1 用户没选/失败  2 没装 termux-api
ic_syspick() {
    local dst="$1"
    mkdir -p "$(dirname "$dst")" 2>/dev/null
    rm -f "$dst" 2>/dev/null
    if ! command -v termux-storage-get >/dev/null 2>&1; then
        return 2
    fi
    echo -e "  ${C}正在打开系统文件管理器...${R}" >&2
    echo -e "  ${Y}选一张图片, 选完会自动回到这里${R}" >&2
    echo -e "  ${Y}没弹出选择器? 说明没装 Termux:API 或没给存储权限${R}" >&2
    echo >&2
    # 多路径兜底: 不同版本的 Termux:API 命令位置不一样
    local sg=""
    for sg in termux-storage-get /data/data/com.termux/files/usr/bin/termux-storage-get; do
        command -v "$sg" >/dev/null 2>&1 || [ -x "$sg" ] || continue
        "$sg" "$dst" >/dev/null 2>&1
        [ -s "$dst" ] && { echo "$dst"; return 0; }
    done
    sg=$(command -v termux-storage-get 2>/dev/null); sg=${sg:-termux-storage-get}
    "$sg" "$dst" >/dev/null 2>&1
    if [ -s "$dst" ]; then
        echo "$dst"; return 0
    fi
    # 选不到就给个手动入口, 不然用户完全卡死
    echo -e "  ${Y}没拿到图片。${R}" >&2
    echo -e "  ${Y}也可以手动填完整路径, 例如:${R} ${C}/sdcard/Download/a.png${R}" >&2
    echo -e "  ${Y}直接回车 = 取消${R}" >&2
    local pth=""
    printf "  路径: " >&2
    rd pth
    if [ -n "$pth" ] && [ -s "$pth" ]; then
        cp "$pth" "$dst" >/dev/null 2>&1 && { echo "$dst"; return 0; }
        # cp 失败(比如 content:// 或权限问题)再试 cat 重定向
        cat "$pth" > "$dst" 2>/dev/null && [ -s "$dst" ] && { echo "$dst"; return 0; }
        echo -e "  ${RD}读不到这个文件, 检查路径和权限${R}" >&2
    fi
    return 1
}

# 统一: 裁剪 + 缩放 + 写入 server-icon.png
# 判断是不是 PNG (看文件头 8 字节签名)
ic_ispng() {
    [ -f "$1" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
    python3 - "$1" <<'ICPNGEOF' 2>/dev/null
import sys
try:
    f=open(sys.argv[1],'rb'); h=f.read(8); f.close()
except Exception: sys.exit(1)
sys.exit(0 if h==b'\x89PNG\r\n\x1a\n' else 1)
ICPNGEOF
}

# 准备图片处理能力
# ---------------------------------------------------------------
#  内置的那个纯 python 解码器只能读 PNG。
#  选 jpg / webp 时, 没有 Pillow 就必然失败, 报一句
#  "处理失败 (格式不支持?)" 就完事 —— 这是"选不了图片"的第二个坑。
#  这里先把 Pillow 备好(装不上也不纠缠), 后面再走转换兜底。
# ---------------------------------------------------------------
IC_PIL=0
ic_prepare() {
    IC_PIL=0
    command -v python3 >/dev/null 2>&1 || return 0
    if python3 -c "import PIL" >/dev/null 2>&1; then IC_PIL=1; return 0; fi
    [ "${AUTO_DEPS:-1}" = 1 ] || return 0
    echo
    echo -e "  ${Y}[!]${R} 需要图片处理库 ${C}Pillow${R} (否则只能读 png)"
    echo -e "      正在自动安装..."
    _pkg_do python-pillow >/dev/null 2>&1
    if python3 -c "import PIL" >/dev/null 2>&1; then
        IC_PIL=1
        echo -e "      ${G}✔${R} Pillow 就绪, jpg / webp 也能用了"
    else
        echo -e "      ${Y}!${R} 装不上, 只能处理 png 图片"
        echo -e "      手动装: ${C}pkg install python-pillow${R}"
    fi
}

# 把任意图片转成 PNG (Pillow -> ffmpeg -> ImageMagick -> djpeg)
ic_topng() {
    local src="$1" dst="$2"
    [ -f "$src" ] || return 1
    rm -f "$dst" 2>/dev/null
    if [ "$IC_PIL" = 1 ]; then
        python3 - "$src" "$dst" <<'ICCVEOF' 2>/dev/null
import sys
from PIL import Image
im=Image.open(sys.argv[1]); im.convert("RGBA").save(sys.argv[2])
ICCVEOF
        [ -s "$dst" ] && return 0
    fi
    if command -v ffmpeg >/dev/null 2>&1; then
        ffmpeg -y -loglevel error -i "$src" "$dst" >/dev/null 2>&1
        [ -s "$dst" ] && return 0
    fi
    local c
    for c in convert magick; do
        command -v "$c" >/dev/null 2>&1 || continue
        "$c" "$src" "$dst" >/dev/null 2>&1
        [ -s "$dst" ] && return 0
    done
    if command -v djpeg >/dev/null 2>&1; then
        djpeg "$src" > "$dst" 2>/dev/null
        [ -s "$dst" ] && return 0
    fi
    return 1
}

ic_apply() {
    local src="$1" icon="$2"
    [ -f "$src" ] || { err "文件不存在: $src"; press; return 1; }
    ic_py
    ic_prepare

    echo -e "  ${C}正在居中裁剪并缩放到 64x64...${R}"

    # 不是 png 就先转一道; 转不了才报格式不支持
    local work="$src" tp=""
    if ! ic_ispng "$src"; then
        tp="${TMP_DIR}/icconv.$$.png"
        mkdir -p "$TMP_DIR" 2>/dev/null
        if ic_topng "$src" "$tp"; then
            work="$tp"
        else
            err "这张图不是 png, 当前环境也没有可用的转换工具"
            echo
            echo -e "  ${Y}解决办法(任选):${R}"
            echo -e "    1. 选一张 ${C}.png${R} 格式的图片 (最简单)"
            echo -e "    2. 手动装 Pillow: ${C}pkg install python-pillow${R}"
            echo -e "    3. 装转换工具:   ${C}pkg install ffmpeg${R}"
            echo
            rm -f "$tp" 2>/dev/null
            press; return 1
        fi
    fi

    # 坑: 原来 2>/dev/null 把 python 的报错全吞了, 用户只看到
    # 一句"处理失败", 根本不知道是解码失败还是权限问题。
    # 现在把 stderr 收进变量, 失败时挑几行打出来。
    local ok=0 elog="${TMP_DIR}/icerr.$$"
    mkdir -p "$TMP_DIR" 2>/dev/null
    if python3 "$IC_PY" resize "$work" "$icon" 2>"$elog" | grep -q ok && [ -s "$icon" ]; then
        ok=1
    fi
    rm -f "$tp" 2>/dev/null

    if [ "$ok" = 1 ]; then
        local bs; bs=$(stat -c %s "$icon" 2>/dev/null || echo 0)
        say "已设为服务器图标: $(ic_size "$icon")  ($(ic_hsize "$bs"))"
        if [ "$bs" -gt 1048576 ]; then
            warn "超过 1MB, MC 可能拒绝加载"
        fi
        warn "重启服务端后才会生效"
    else
        err "处理失败"
        # 把真实原因挑出来, 别只丢一句"处理失败"
        if [ -s "$elog" ]; then
            echo
            echo -e "  ${Y}失败原因:${R}"
            grep -vE '^[[:space:]]*$' "$elog" 2>/dev/null | tail -4 | while IFS= rd l; do
                echo -e "    ${C}$l${R}"
            done
        fi
        rm -f "$elog" 2>/dev/null
        echo
        echo -e "  ${Y}建议(任选):${R}"
        echo -e "    1. 换一张 ${C}.png${R} 图片 (最简单)"
        echo -e "    2. 装 Pillow: ${C}pkg install python-pillow${R}"
        echo -e "    3. 重装图片工具: ${C}rm -f ~/.mcserv/icontool*${R} 后重试"
    fi
    rm -f "$elog" 2>/dev/null
    press
}

icon_menu() {
    [ -z "$CUR" ] && { warn "先选服务器"; press; return; }
    local sdir="${ROOT}/servers/${CUR}"
    [ -d "$sdir" ] || { err "目录不存在"; press; return; }
    local icon="$sdir/server-icon.png"
    local pf="$sdir/server.properties"
    mkdir -p "$TMP_DIR" 2>/dev/null
    local pickf="${TMP_DIR}/mcserv-pick.png"
    while true; do
        title "服务器图标 / 简介 —— $CUR"
        if [ -f "$icon" ]; then
            local sz; sz=$(ic_size "$icon")
            local bs; bs=$(stat -c %s "$icon" 2>/dev/null || echo 0)
            echo -e "  ${Y}图标${R}    已设置  ${G}${sz:-未知尺寸}${R}  ($(ic_hsize "$bs"))"
            case "$sz" in
                64x64) echo -e "           ${G}✔ 尺寸正确${R}";;
                *)     echo -e "           ${Y}! 非 64x64, MC 会自动拉伸${R}";;
            esac
            [ "$bs" -gt 1048576 ] && echo -e "           ${RD}! 超过 1MB, MC 可能拒绝加载${R}"
        else
            echo -e "  ${Y}图标${R}    未设置 (显示默认方块图标)"
        fi
        local mcur; mcur=$(prop_get motd "$pf")
        mcur="${mcur//\\n/ ${Y}⏎${R} }"
        [ -z "$mcur" ] && mcur="A Minecraft Server"
        echo -e "  ${Y}简介${R}    $mcur"
        echo
        echo "   1) 用系统文件管理器选图  ${G}(推荐)${R}"
        echo "   2) 从本机图片列表里挑"
        echo "   3) 手动输入图片路径"
        echo "   4) 生成方块风格图标"
        echo "   5) 删除图标"
        echo "   6) 编辑简介 (MOTD)"
        echo "   7) 逐层浏览目录找图  ${Y}(扫不到时用)${R}"
        echo "   0) 返回"
        echo
        ask "选择: "; rd c || return
        case "$c" in
        1)
            local got; got=$(ic_syspick "$pickf"); local rc=$?
            if [ "$rc" -eq 0 ] && [ -n "$got" ]; then
                ic_apply "$got" "$icon"
            elif [ "$rc" -eq 2 ]; then
                warn "没检测到 termux-storage-get"
                echo -e "  ${C}正在自动安装 termux-api ...${R}"
                if need_tapi; then
                    say "装好了, 再试一次"
                    local g2; g2=$(ic_syspick "$pickf")
                    if [ -n "$g2" ]; then ic_apply "$g2" "$icon"
                    else
                        warn "还是没选到图"
                        echo -e "  ${Y}命令装好了, 还差 ${C}Termux:API${R}${Y} 这个 App${R}"
                        echo -e "  ${C}去 F-Droid 或官网装它, 再跑 termux-setup-storage${R}"
                        echo -e "  ${Y}急着用就先走 [2] / [7] / [3]${R}"
                        press
                    fi
                else
                    echo -e "  ${RD}自动安装失败${R}"
                    echo -e "  ${C}手动:${R} pkg install termux-api"
                    echo -e "  ${C}再装${R} Termux:API 这个 App (F-Droid / 官网)"
                    echo -e "  ${C}然后${R} termux-setup-storage 给存储权限"
                    echo -e "  ${Y}急着用就先走 [2] / [7] / [3]${R}"
                    press
                fi
            else
                warn "没有选到图片 (或取消了)"
                press
            fi
            ;;
        2)
            ic_ensure_storage || { press; continue; }
            echo -e "  ${C}扫描本机图片...${R}"
            ic_py
            local -a paths=() sizes=()
            local line p z i=1
            while IFS=$'\t' read -r p z; do
                [ -z "$p" ] && continue
                paths+=("$p"); sizes+=("$z")
            done < <(ic_scan)
            if [ ${#paths[@]} -eq 0 ]; then
                warn "没扫到图片"
                echo -e "  ${Y}常见原因:${R} 图片在没权限的目录 / 刚授权还没生效"
                echo -e "  ${C}1)${R} 逐层浏览目录自己找"
                echo -e "  ${C}2)${R} 手动输入路径"
                echo -e "  ${C}0)${R} 返回"
                ask "选择: "; rd q
                case "$q" in
                    1) local bp; bp=$(ic_browse); [ -n "$bp" ] && ic_apply "$bp" "$icon"; press;;
                    2) ask "图片路径: "; rd bp; [ -n "$bp" ] && ic_apply "$bp" "$icon"; press;;
                esac
                continue
            fi
            echo
            for p in "${paths[@]}"; do
                printf "  ${C}%2d)${R} %s  ${Y}%s${R}\n" "$i" "$(basename "$p")" "${sizes[$((i-1))]}"
                i=$((i+1))
            done
            echo -e "  ${C} 0)${R} 取消"
            echo
            ask "选择: "; rd n
            case "$n" in 0|"") continue;; esac
            [[ ! "$n" =~ ^[0-9]+$ ]] && continue
            { [ "$n" -lt 1 ] || [ "$n" -gt "${#paths[@]}" ]; } && continue
            p="${paths[$((n-1))]}"
            [ -n "$p" ] && ic_apply "$p" "$icon"
            ;;
        3)
            ask "图片路径: "; rd p
            [ -z "$p" ] && continue
            p=$(eval echo "${p/#\~/$HOME}")
            ic_apply "$p" "$icon"
            ;;
        7)
            ic_ensure_storage || true
            local bp2; bp2=$(ic_browse)
            [ -n "$bp2" ] && ic_apply "$bp2" "$icon"
            press
            ;;
        4)
            ic_py
            python3 "$IC_PY" gen "$CUR" "$icon" 2>/dev/null
            if [ -f "$icon" ]; then
                say "已生成方块图标: $(ic_size "$icon")"
                warn "想要自定义图案就用 [1] 导入图片"
            else
                err "生成失败"
            fi
            press;;
        5)
            if [ -f "$icon" ]; then
                rm -f "$icon" && say "已删除图标 (重启后显示默认)" || err "删除失败"
            else
                warn "本来就没设图标"
            fi
            press;;
        6) motd_menu "$pf";;
        0|q|Q) return;;
        esac
    done
}

# ============================================================
#  服务器管理 (重命名 / 删除 / 信息)
# ============================================================
srv_list() {
    local list=() d
    for d in "$ROOT"/servers/*; do
        [ -d "$d" ] && list+=("$(basename "$d")")
    done
    printf '%s\n' "${list[@]}" 2>/dev/null
}

srv_pick() {
    local list=() i=1 n sel T=/dev/tty x
    [ -e "$T" ] || T=/dev/stderr
    while IFS= read -r x; do [ -n "$x" ] && list+=("$x"); done < <(srv_list)
    if [ ${#list[@]} -eq 0 ]; then
        echo -e "${Y}[!]${R} 还没有服务器, 请先新建" > "$T"
        return 1
    fi
    {
      title "选择服务器"
      for x in "${list[@]}"; do
          local mark=""
          [ "$x" = "$CUR" ] && mark="  ${G}<- 当前${R}"
          echo -e "  ${C}$i)${R} $x$mark"; i=$((i+1))
      done
      echo
      echo -ne "${C}[?]${R} 序号: "
    } > "$T"
    rd n || return 1
    [ -z "$n" ] && return 1
    [[ ! "$n" =~ ^[0-9]+$ ]] && return 1
    [ "$n" -lt 1 ] || [ "$n" -gt "${#list[@]}" ] && return 1
    sel="${list[$((n-1))]}"
    [ -z "$sel" ] && return 1
    echo "$sel"
}

srv_info() {
    local name="$1"
    [ -z "$name" ] && return
    local d="${ROOT}/servers/$name"
    title "服务器信息 —— $name"
    echo -e "  ${Y}核心${R}    $(mg type "$name") / $(mg loader "$name") / MC $(mg mc "$name")"
    echo -e "  ${Y}内存${R}    $(cat "${HIST_DIR}/${name}.mem" 2>/dev/null || echo 默认) MB"
    echo -e "  ${Y}世界${R}    $(cat "${HIST_DIR}/${name}.world" 2>/dev/null || echo world)"
    local mods=0 plugins=0
    [ -d "$d/mods" ]    && mods=$(ls -1 "$d"/mods/*.jar 2>/dev/null | grep -c . || echo 0)
    [ -d "$d/plugins" ] && plugins=$(ls -1 "$d"/plugins/*.jar 2>/dev/null | grep -c . || echo 0)
    echo -e "  ${Y}模组${R}    ${mods} 个      插件: ${plugins} 个"
    local w; w=$(cat "${HIST_DIR}/${name}.world" 2>/dev/null || echo world)
    if [ -d "$d/$w" ]; then
        echo -e "  ${Y}体积${R}    $(du -sh "$d/$w" 2>/dev/null | cut -f1)"
        local sd; sd=$(wt_seed "$d/$w/level.dat")
        [ -n "$sd" ] && echo -e "  ${Y}种子${R}    ${C}$sd${R}"
    fi
    echo -e "  ${Y}路径${R}    $d"
    press
}

srv_menu() {
    while true; do
        title "服务器管理"
        echo -e "  当前: ${C}${CUR:-未选择}${R}"
        echo
        echo "   1) 切换/选择服务器"
        echo "   2) 查看服务器信息"
        echo "   3) 重命名服务器"
        echo "   4) 删除服务器"
        echo "   0) 返回"
        echo
        ask "选择: "; rd c || return
        case "$c" in
        1) local n; n=$(srv_pick) || continue
           [ -n "$n" ] && { CUR="$n"; save_conf; say "当前服务器: $CUR"; }
           press;;
        2) local n; n=$(srv_pick) || continue
           [ -n "$n" ] && srv_info "$n";;
        3) local n; n=$(srv_pick) || continue
           [ -z "$n" ] && continue
           ask "新名称: "; rd nn
           [ -z "$nn" ] && continue
           [ -d "${ROOT}/servers/$nn" ] && { warn "已存在同名服务器"; press; continue; }
           if mv "${ROOT}/servers/$n" "${ROOT}/servers/$nn" 2>/dev/null; then
               for ext in meta mem world list; do
                   [ -f "${HIST_DIR}/${n}.${ext}" ] && mv "${HIST_DIR}/${n}.${ext}" "${HIST_DIR}/${nn}.${ext}" 2>/dev/null
               done
               [ "$CUR" = "$n" ] && { CUR="$nn"; save_conf; }
               say "已重命名为: $nn"
           else
               err "重命名失败 (检查存储权限)"
           fi
           press;;
        4) local n; n=$(srv_pick) || continue
           [ -z "$n" ] && continue
           warn "将删除服务器 [$n] 及其全部内容 (模组/存档/配置)"
           err "此操作不可恢复!"
           ask "确认删除? 请输入服务器名 [$n]: "; rd cf
           [ "$cf" != "$n" ] && { say "已取消"; press; continue; }
           local w; w=$(cat "${HIST_DIR}/${n}.world" 2>/dev/null || echo world)
           if [ -d "${ROOT}/servers/$n/$w" ]; then
               ask "删除前先备份存档? (Y/n): "; rd bk
               case "$bk" in n|N) ;; *)
                   mkdir -p "${ROOT}/backups"
                   cp -r "${ROOT}/servers/$n/$w" "${ROOT}/backups/${n}_${w}_$(date +%Y%m%d_%H%M%S)" 2>/dev/null \
                       && say "已备份" || warn "备份失败";;
               esac
           fi
           rm -rf "${ROOT}/servers/$n" && rm -f "${HIST_DIR}/${n}".{meta,mem,world,list} 2>/dev/null
           [ "$CUR" = "$n" ] && { CUR=""; save_conf; }
           say "已删除: $n"
           press;;
        0|q|Q) return;;
        esac
    done
}

# ============================================================
#  模组 / 插件管理 (列出 / 禁用 / 启用 / 删除)
# ============================================================
mp_menu() {
    [ -z "$CUR" ] && { warn "先选服务器"; press; return; }
    local sdir="${ROOT}/servers/${CUR}"
    while true; do
        title "模组/插件管理 —— $CUR"
        local mp
        if [ -d "$sdir/mods" ]; then mp=mods; else mp=plugins; fi
        local on off
        on=$(ls -1 "$sdir/$mp"/*.jar 2>/dev/null | grep -c . || true); [ -z "$on" ] && on=0
        off=$(ls -1 "$sdir/$mp"/*.jar.disabled 2>/dev/null | grep -c . || true); [ -z "$off" ] && off=0
        echo -e "  目录: ${C}$mp${R}    已启用: ${G}${on}${R} 个    已禁用: ${Y}${off}${R} 个"
        echo
        echo "   1) 列出全部"
        echo "   2) 禁用 (序号多选)"
        echo "   3) 启用 (序号多选)"
        echo "   4) 删除 (序号多选)"
        echo "   5) 切换目录 (mods/plugins)"
        echo "   0) 返回"
        echo
        ask "选择: "; rd c || return
        case "$c" in
        1) title "$mp 列表"
           if [ "$on" -eq 0 ] && [ "$off" -eq 0 ]; then warn "目录为空"; press; continue; fi
           local i=1 f
           for f in "$sdir/$mp"/*.jar; do
               [ -e "$f" ] || continue
               printf "  ${G}%2d)${R} %s\n" "$i" "$(basename "$f")"; i=$((i+1))
           done
           for f in "$sdir/$mp"/*.jar.disabled; do
               [ -e "$f" ] || continue
               printf "  ${Y}%2d)${R} %s  ${Y}[已禁用]${R}\n" "$i" "$(basename "$f")"; i=$((i+1))
           done
           press;;
        2) mp_toggle "$sdir/$mp" disable;;
        3) mp_toggle "$sdir/$mp" enable;;
        4) mp_toggle "$sdir/$mp" delete;;
        5) if [ "$mp" = "mods" ]; then
               mkdir -p "$sdir/plugins"; say "已切到 plugins"
           else
               mkdir -p "$sdir/mods"; say "已切到 mods"
           fi
           press;;
        0|q|Q) return;;
        esac
    done
}

mp_toggle() {
    local dir="$1" act="$2"
    local files=() i=1 f sel T=/dev/tty
    [ -e "$T" ] || T=/dev/stderr
    case "$act" in
        disable) for f in "$dir"/*.jar;         do [ -e "$f" ] && files+=("$f"); done;;
        enable)  for f in "$dir"/*.jar.disabled; do [ -e "$f" ] && files+=("$f"); done;;
        delete)  for f in "$dir"/*.jar "$dir"/*.jar.disabled; do [ -e "$f" ] && files+=("$f"); done;;
    esac
    if [ ${#files[@]} -eq 0 ]; then
        case "$act" in
            disable) warn "没有可禁用的 (全是 .jar 且已启用?)";;
            enable)  warn "没有已禁用的";;
            delete)  warn "目录为空";;
        esac
        press; return
    fi
    {
      echo
      for f in "${files[@]}"; do
          printf "  ${C}%2d)${R} %s\n" "$i" "$(basename "$f")"; i=$((i+1))
      done
      echo
      echo -e "  ${Y}支持: 1 3  或  2-5  或  all${R}"
      echo -ne "${C}[?]${R} 选择: "
    } > "$T"
    if [ "$T" = "/dev/tty" ]; then read -r sel < /dev/tty 2>/dev/null; else read -r sel; fi
    [ -z "$sel" ] && return
    local picked=() tok a b j
    if [ "$sel" = "all" ]; then
        picked=("${files[@]}")
    else
        for tok in $sel; do
            if printf '%s' "$tok" | grep -qE '^[0-9]+-[0-9]+$'; then
                a="${tok%%-*}"; b="${tok##*-}"
                [ "$a" -lt 1 ] && a=1
                [ "$b" -gt "${#files[@]}" ] && b=${#files[@]}
                for ((j=a; j<=b; j++)); do picked+=("${files[$((j-1))]}"); done
            else
                [[ ! "$tok" =~ ^[0-9]+$ ]] && continue
                [ "$tok" -ge 1 ] && [ "$tok" -le "${#files[@]}" ] && picked+=("${files[$((tok-1))]}")
            fi
        done
    fi
    [ ${#picked[@]} -eq 0 ] && { warn "没选"; press; return; }
    if [ "$act" = "delete" ]; then
        warn "将删除 ${#picked[@]} 个文件"
        ask "确认? (y/N): "; read -r cf < "$T" 2>/dev/null || read -r cf
        case "$cf" in y|Y) ;; *) say "已取消"; press; return;; esac
    fi
    local ok=0
    for f in "${picked[@]}"; do
        case "$act" in
            disable) mv "$f" "${f}.disabled" 2>/dev/null && ok=$((ok+1));;
            enable)  mv "$f" "${f%.disabled}" 2>/dev/null && ok=$((ok+1));;
            delete)  rm -f "$f" 2>/dev/null && ok=$((ok+1));;
        esac
    done
    case "$act" in
        disable) say "已禁用 $ok 个 (重启服务端生效)";;
        enable)  say "已启用 $ok 个 (重启服务端生效)";;
        delete)  say "已删除 $ok 个 (重启服务端生效)";;
    esac
    press
}

# ============================================================
#  存档管理
# ============================================================
# ---- 扫描真正的 MC 世界目录 (不再只认 world*, 任意名字都能列出来) ----
world_list() {
    local sdir="$1" d
    for d in "$sdir"/*; do
        [ -d "$d" ] || continue
        # 认这些标志中的任意一个 = 这是个世界目录
        if [ -f "$d/level.dat" ] || [ -d "$d/region" ] || [ -d "$d/data" ] \
           || [ -d "$d/DIM-1" ] || [ -d "$d/dimension" ] || [ -f "$d/level.dat_old" ]; then
            basename "$d"
        fi
    done
}

# ---- 写入 level-name (没有这行就追加), 写完回读验证 ----
world_apply() {
    local sdir="$1" name="$2" f="$sdir/server.properties"
    [ -d "$sdir" ] || return 1
    [ -f "$f" ] || : > "$f"
    prop_set "level-name" "$name" "$f" || return 1
    echo "$name" > "${HIST_DIR}/${CUR}.world" 2>/dev/null
    # 回读确认
    local now; now=$(grep -m1 '^level-name=' "$f" 2>/dev/null | cut -d= -f2-)
    if [ "$now" = "$name" ]; then
        return 0
    else
        err "写入失败: server.properties 里现在是 [$now]"
        return 1
    fi
}

# ---- server.properties 里真实的 level-name ----
world_prop() {
    local f="$1/server.properties" v
    v=$(grep -m1 '^level-name=' "$f" 2>/dev/null | cut -d= -f2-)
    [ -z "$v" ] && v="(没写, 服务端会用默认 world)"
    printf '%s' "$v"
}

# ---- 服务端在跑吗 (在跑时禁止切/改/删存档) ----
world_busy() {
    local hit
    hit=$(ps -eo args 2>/dev/null | grep -iE '(^|/)java .*(server\.jar|neoforge|fabric|forge|paper|purpur|spigot|bukkit|quilt)' \
          | grep -v grep | head -1)
    [ -n "$hit" ]
}

world_menu() {
    local sdir="$1"
    while true; do
        title "存档管理 —— $CUR"
        local cw; cw=$(cat "${HIST_DIR}/${CUR}.world" 2>/dev/null || echo world)
        local pw; pw=$(world_prop "$sdir")
        echo -e "  目录: ${Y}$sdir${R}"
        echo -e "  当前世界: ${C}${cw}${R}"
        if [ "$pw" != "$cw" ]; then
            echo
            err "不一致! server.properties 里写的是 [$pw]"
            echo -e "  ${Y}也就是服务端实际会加载 [$pw], 不是你选的 [$cw]${R}"
            echo -e "  ${Y}选 1 重新切换一次即可修复${R}"
        fi
        local -a ALLW; mapfile -t ALLW < <(world_list "$sdir")
        echo -e "  共 ${#ALLW[@]} 个存档"
        echo
        echo "   1) 切换/选择存档"
        echo "   2) 新建空存档"
        echo "   3) 备份当前存档"
        echo "   4) 列出所有存档"
        echo "   5) 查看存档详情 (种子/体积/玩家)"
        echo "   6) 重命名存档"
        echo "   7) 删除存档"
        echo "   8) 导入存档 (zip / 文件夹)"
        echo "   0) 返回"
        echo
        ask "选择: "; rd c || return
        [ -z "$c" ] && continue
        case "$c" in
        1)
            if world_busy; then
                err "服务端正在运行, 切换会导致存档错乱"
                echo -e "  ${Y}请先停止服务器 (菜单 16) 再切换${R}"
                press; continue
            fi
            local -a ws; mapfile -t ws < <(world_list "$sdir")
            [ ${#ws[@]} -eq 0 ] && { warn "没有存档 (目录里没找到 level.dat/region)"; press; continue; }
            echo -e "  ${Y}server.properties 现在写的是:${R} $(world_prop "$sdir")"
            echo
            local i=1 w mk
            for w in "${ws[@]}"; do
                mk=""
                [ "$w" = "$cw" ] && mk="  ${G}← 当前${R}"
                echo -e "  ${C}$i)${R} $w$mk"; i=$((i+1))
            done
            ask "选择存档序号: "; rd n
            case "$n" in ''|*[!0-9]*) continue;; esac
            local sel="${ws[$((n-1))]}"
            [ -z "$sel" ] && { warn "序号不对"; press; continue; }
            if world_apply "$sdir" "$sel"; then
                say "已切换到: ${G}${sel}${R}"
                echo -e "  已写入: ${Y}$sdir/server.properties${R}  ->  level-name=$sel"
                echo -e "  完整路径: ${Y}$sdir/$sel${R}"
                warn "重启服务端才生效"
            fi
            ;;
        2)
            ask "新存档名称 (回车=world2): "; rd nw
            [ -z "$nw" ] && nw="world2"
            case "$nw" in */*) err "不能带斜杠"; press; continue;; esac
            [ -d "$sdir/$nw" ] && { warn "已存在: $nw"; press; continue; }
            mkdir -p "$sdir/$nw" || { err "创建失败 (检查存储权限)"; press; continue; }
            world_apply "$sdir" "$nw" && say "已创建并切换到: ${G}${nw}${R}"
            echo -e "  ${Y}名字随便起, 不一定要 world 开头${R}"
            ;;
        3)
            local bk="${ROOT}/backups/${CUR}_${cw}_$(date +%Y%m%d_%H%M%S)"
            mkdir -p "${ROOT}/backups"
            cp -r "${sdir}/${cw}" "$bk" && say "已备份到: $bk" || err "备份失败"
            ;;
        4)
            title "全部存档"
            echo -e "  目录: ${Y}$sdir${R}"
            echo
            local -a aw; mapfile -t aw < <(world_list "$sdir")
            [ ${#aw[@]} -eq 0 ] && { warn "没找到世界目录"; press; continue; }
            local w2 sz2
            for w2 in "${aw[@]}"; do
                sz2=$(du -sh "$sdir/$w2" 2>/dev/null | cut -f1)
                if [ "$w2" = "$cw" ]; then
                    echo -e "  ${G}●${R} $w2  (${sz2})  ${G}← 当前${R}"
                else
                    echo -e "  ${C}○${R} $w2  (${sz2})"
                fi
            done
            echo
            echo -e "  ${Y}服务端实际会加载:${R} $(world_prop "$sdir")"
            press; continue;;
        5)
            local -a ws2; mapfile -t ws2 < <(world_list "$sdir")
            local j=1
            [ ${#ws2[@]} -eq 0 ] && { warn "没有存档"; press; continue; }
            for w in "${ws2[@]}"; do echo -e "  ${C}$j)${R} $w"; j=$((j+1)); done
            ask "选择: "; rd n2
            local tw="${ws2[$((n2-1))]}"
            [ -z "$tw" ] && continue
            title "存档详情 —— $tw"
            local td="$sdir/$tw"
            echo -e "  ${Y}路径${R}    $td"
            echo -e "  ${Y}体积${R}    $(du -sh "$td" 2>/dev/null | cut -f1)"
            if [ -f "$td/level.dat" ]; then
                local sd; sd=$(wt_seed "$td/level.dat")
                [ -n "$sd" ] && echo -e "  ${Y}种子${R}    ${C}${sd}${R}" || echo -e "  ${Y}种子${R}    (读取失败)"
                local inf; inf=$(wt_py; python3 "$WT_PY" info "$td" 2>/dev/null)
                [ -n "$inf" ] && {
                    local v; v=$(printf '%s\n' "$inf" | sed -n '2p')
                    local pl; pl=$(printf '%s\n' "$inf" | sed -n '4p')
                    [ -n "$v" ] && echo -e "  ${Y}版本${R}    $v"
                    echo -e "  ${Y}玩家${R}    $pl 人"
                }
            else
                warn "  还没有 level.dat (世界未生成过)"
            fi
            local rg=0
            [ -d "$td/region" ] && rg=$(ls -1 "$td/region" 2>/dev/null | grep -c . || echo 0)
            echo -e "  ${Y}区块${R}    $rg 个区域文件"
            press; continue;;
        6)
            if world_busy; then err "服务端在跑, 先停止 (菜单 16)"; press; continue; fi
            local -a ws3; mapfile -t ws3 < <(world_list "$sdir")
            local k=1
            [ ${#ws3[@]} -eq 0 ] && { warn "没有存档"; press; continue; }
            for w in "${ws3[@]}"; do echo -e "  ${C}$k)${R} $w"; k=$((k+1)); done
            ask "选择要重命名的: "; rd n3
            local ow="${ws3[$((n3-1))]}"
            [ -z "$ow" ] && continue
            ask "新名称: "; rd nw3
            [ -z "$nw3" ] && continue
            [ -d "$sdir/$nw3" ] && { warn "已存在"; press; continue; }
            if mv "$sdir/$ow" "$sdir/$nw3" 2>/dev/null; then
                if [ "$cw" = "$ow" ] || [ "$(world_prop "$sdir")" = "$ow" ]; then
                    world_apply "$sdir" "$nw3"
                fi
                say "已重命名: $ow → ${G}$nw3${R}"
            else
                err "失败 (检查存储权限)"
            fi
            ;;
        7)
            if world_busy; then err "服务端在跑, 先停止 (菜单 16)"; press; continue; fi
            local -a ws4; mapfile -t ws4 < <(world_list "$sdir")
            local m=1
            [ ${#ws4[@]} -eq 0 ] && { warn "没有存档"; press; continue; }
            for w in "${ws4[@]}"; do
                local mk2=""
                [ "$w" = "$cw" ] && mk2="  ${RD}← 当前${R}"
                echo -e "  ${C}$m)${R} $w$mk2"; m=$((m+1))
            done
            ask "选择要删除的: "; rd n4
            local dw="${ws4[$((n4-1))]}"
            [ -z "$dw" ] && continue
            [ ${#ws4[@]} -le 1 ] && { warn "只剩这一个存档了, 删了就没得玩了"; press; continue; }
            warn "将删除存档 [$dw]  $(du -sh "$sdir/$dw" 2>/dev/null | cut -f1)"
            err "世界数据不可恢复!"
            ask "确认? 请输入存档名 [$dw]: "; rd cf
            [ "$cf" != "$dw" ] && { say "已取消"; press; continue; }
            ask "删除前先备份? (Y/n): "; rd bk2
            case "$bk2" in n|N) ;; *)
                mkdir -p "${ROOT}/backups"
                cp -r "$sdir/$dw" "${ROOT}/backups/${CUR}_${dw}_$(date +%Y%m%d_%H%M%S)" 2>/dev/null && say "已备份";;
            esac
            rm -rf "$sdir/$dw" && say "已删除: $dw"
            if [ "$cw" = "$dw" ]; then
                local -a left; mapfile -t left < <(world_list "$sdir")
                if [ ${#left[@]} -gt 0 ]; then
                    warn "删的是当前存档, 自动切到 [${left[0]}]"
                    world_apply "$sdir" "${left[0]}"
                else
                    warn "没有存档了, 启动服务端会重新生成一个新世界"
                fi
            fi
            ;;
        8)
            echo
            echo -e "  ${Y}支持两种来源:${R}"
            echo -e "    ${C}zip 文件${R}  —— 解压后内含 world/ 或 level.dat 的压缩包"
            echo -e "    ${C}文件夹${R}    —— 直接指向已解压的世界目录"
            echo
            ask "路径 (zip 或文件夹): "; rd src
            [ -z "$src" ] && continue
            src=$(eval echo "${src/#\~/$HOME}")
            [ -e "$src" ] || { err "路径不存在"; press; continue; }
            ask "导入为存档名 (默认 world2): "; rd dst
            [ -z "$dst" ] && dst="world2"
            [ -d "$sdir/$dst" ] && { warn "已存在同名存档"; press; continue; }
            local tmpd="${ROOT}/tmp/imp_$$"
            mkdir -p "$tmpd"
            if [ -f "$src" ]; then
                if command -v unzip >/dev/null; then
                    unzip -q "$src" -d "$tmpd" 2>/dev/null || { err "解压失败"; rm -rf "$tmpd"; press; continue; }
                else
                    python3 -c "import zipfile;zipfile.ZipFile('$src').extractall('$tmpd')" 2>/dev/null \
                        || { err "解压失败 (需 unzip 或 python3)"; rm -rf "$tmpd"; press; continue; }
                fi
                # 若解压后是一层包裹目录, 往里找含 level.dat 的
                if [ ! -f "$tmpd/level.dat" ]; then
                    local inner
                    inner=$(find "$tmpd" -maxdepth 3 -name level.dat 2>/dev/null | head -1)
                    [ -n "$inner" ] && tmpd=$(dirname "$inner")
                fi
            else
                tmpd="$src"
            fi
            if [ ! -f "$tmpd/level.dat" ]; then
                err "没找到 level.dat —— 确认这是世界目录吗?"
                rm -rf "${ROOT}/tmp/imp_$$" 2>/dev/null
                press; continue
            fi
            cp -r "$tmpd" "$sdir/$dst" && say "已导入为: $dst" || err "复制失败"
            rm -rf "${ROOT}/tmp/imp_$$" 2>/dev/null
            ask "切换到此存档? (Y/n): "; rd sw
            case "$sw" in n|N) ;; *)
                world_apply "$sdir" "$dst" && say "已切换到: ${G}$dst${R}";;
            esac
            warn "重启服务端生效"
            ;;
        0|q|Q) return;;
        esac
        press
    done
}

# ============================================================
#  修复: 按历史记录重新下载缺失文件
# ============================================================
repair() {
    local sdir="$1"
    local hist="${HIST_DIR}/${CUR}.list"
    title "修复缺失文件 (按历史记录重下)"
    if [ ! -f "$hist" ]; then
        warn "无历史记录"; press; return
    fi
    local missing=0 fixed=0
    while IFS='|' read -r kind slug ver fname furl; do
        [ -z "${fname:-}" ] && continue
        local dest="$sdir/mods/$fname"
        [ "$kind" = "plugin" ] && dest="$sdir/plugins/$fname"
        if [ -f "$dest" ]; then continue; fi
        if [ -z "$furl" ]; then
            warn "$fname 无下载源(本地导入), 无法自动修复, 请手动放回"
            continue
        fi
        missing=$((missing+1))
        say "缺失: $fname -> 重新下载 (重试上限 $MAX_RETRY)"
        if dl "$dest" "$furl"; then
            fixed=$((fixed+1))
        else
            err "$fname 下载失败达 $MAX_RETRY 次 —— 请检查网络环境"
            err "程序终止."
            press; exit 1
        fi
    done < "$hist"
    say "修复完成: 缺失 $missing 个, 修复 $fixed 个"
    press
}

# ============================================================
#  启动服务器
# ============================================================
start_server() {
    local sdir="$1"
    [ ! -d "$sdir" ] && { err "服务器目录不存在"; press; return; }
    # 启动前先看有没有残留进程占着端口
    local pre; pre=$(java_pids 2>/dev/null | tr '\n' ' ')
    if [ -n "${pre// /}" ]; then
        warn "检测到已有服务端进程在跑: $pre"
        warn "两个实例会抢同一个端口, 新的一定起不来"
        ask "先停掉它们? (Y/n): "; rd kk
        case "$kk" in n|N) ;; *)
            for pp in $pre; do kill -TERM "$pp" 2>/dev/null; done
            local w=0
            while [ "$w" -lt 20 ]; do
                sleep 1; w=$((w+1))
                [ -z "$(java_pids 2>/dev/null | tr '\n' ' ' | tr -d ' ')" ] && break
            done
            for pp in $pre; do kill -KILL "$pp" 2>/dev/null; done
            say "已清理";;
        esac
    fi
    cd "$sdir" || return

    local mem; mem=$(cat "${HIST_DIR}/${CUR}.mem" 2>/dev/null)
    [ -z "$mem" ] && mem=1536

    bk_autolock; sp_autobk_if_on
    title "启动 $CUR (内存 ${mem}MB)"
    warn "监听地址留空=IPv4+IPv6 全收(推荐)"
    warn "停止方式: 输入 /stop 回车, 或 Ctrl+C"
    warn "万一卡住关不掉: Ctrl+C 后回主菜单按 16 强制停止"
    sleep 1

    MC_XMX="$mem"
    if [ "$LOGCOLOR" = "1" ]; then
        echo -e "  ${C}日志着色已开启${R}  ${Y}(✘红=错误 ⚠黄=警告 ▸青=阶段 ·=普通)${R}"
        echo -e "  ${C}启动完成后会自动打出联机地址${R}"
        if [ "$STATBAR" = "1" ]; then
            echo -e "  ${C}底部状态栏${R}  ${Y}启动中显示阶段进度; 运行中显示 内存/CPU/TPS/在线${R}"
        fi
        sleep 1
    fi

    if [ -f run.sh ]; then
        chmod +x run.sh
        sed -i "s/-Xmx[0-9]*[mMgG]/-Xmx${mem}M/g; s/-Xms[0-9]*[mMgG]/-Xms${mem}M/g" user_jvm_args.txt 2>/dev/null
        run_mc bash ./run.sh
    elif [ -f server.jar ]; then
        run_mc java -Xms${mem}M -Xmx${mem}M -XX:+UseG1GC -XX:MaxMetaspaceSize=256m -jar server.jar nogui
    else
        err "未找到 server.jar 或 run.sh, 请先安装核心"
        press
    fi
}

# ============================================================
# ============================================================
#  MC 版本列表 / 依赖自检
# ============================================================

# 在线取加载器支持的 MC 版本(最新在前)
fetch_mc_versions() {
    local loader="$1"
    case "$loader" in
    paper|folia|velocity)
        curl -fsSL --max-time 25 -A "$UA" "https://api.papermc.io/v2/projects/${loader}" 2>/dev/null \
        | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    print("\n".join(reversed(d.get("versions",[]))))
except Exception: pass' 2>/dev/null
        ;;
    purpur)
        curl -fsSL --max-time 25 -A "$UA" "https://api.purpurmc.org/v2/purpur" 2>/dev/null \
        | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    print("\n".join(reversed(d.get("versions",[]))))
except Exception: pass' 2>/dev/null
        ;;
    fabric)
        curl -fsSL --max-time 25 -A "$UA" "https://meta.fabricmc.net/v2/versions/game" 2>/dev/null \
        | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    print("\n".join(x["version"] for x in d if x.get("stable")))
except Exception: pass' 2>/dev/null
        ;;
    neoforge)
        # NeoForge 版本号前两段映射 MC 版本; 47.x 对应 1.20.1
        curl -fsSL --max-time 25 -A "$UA" \
        "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml" 2>/dev/null \
        | python3 -c 'import sys,re
vs=set()
for m in re.finditer(r"<version>(\d+)\.(\d+)\.(\d+)</version>", sys.stdin.read()):
    a,b=int(m.group(1)),int(m.group(2))
    if a>=21: vs.add("1.%d.%d"%(a,b))
    elif a==20: vs.add("1.20.%d"%b)
    elif a==47: vs.add("1.20.1")
print("\n".join(sorted(vs,key=lambda s:[int(x) for x in s.split(".")],reverse=True)))' 2>/dev/null
        ;;
    forge)
        curl -fsSL --max-time 25 -A "$UA" \
        "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json" 2>/dev/null \
        | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    vs={k for k in d.get("promos",{}) if "-" not in k}
    print("\n".join(sorted(vs,key=lambda s:[int(x) for x in s.split(".")],reverse=True)))
except Exception: pass' 2>/dev/null
        ;;
    esac
}

# 离线兜底列表
fallback_mc_versions() {
    printf '%s\n' 1.21.1 1.21 1.20.6 1.20.4 1.20.2 1.20.1 1.19.4 1.18.2
}

# 交互式选 MC 版本, 结果打到 stdout
# 注意: 本函数所有提示走 stderr, stdout 仅输出最终版本号,
#       以便调用方用 mc=$(pick_mc_version ...) 安全捕获。
pick_mc_version() {
    local loader="$1"
    title "选择 MC 版本" >&2
    spin_start "正在获取 ${loader} 支持的版本..."
    local list; list=$(fetch_mc_versions "$loader")
    spin_stop "版本列表已获取"
    if [ -z "$(printf '%s' "$list" | tr -d '[:space:]')" ]; then
        warn "在线获取失败, 改用内置常见版本列表(可手动输入其它版本)" >&2
        list=$(fallback_mc_versions)
    fi
    local -a arr=()
    while read -r l; do [ -n "$l" ] && arr+=("$l"); done <<< "$list"
    if [ "${#arr[@]}" -eq 0 ]; then err "无可用版本列表" >&2; return 1; fi
    local n=${#arr[@]} max=30
    [ "$n" -gt "$max" ] && n=$max
    local i
    for ((i=0; i<n; i++)); do printf "  %3d) %s\n" $((i+1)) "${arr[$i]}" >&2; done
    echo >&2
    echo "  (输入序号, 或直接敲版本号如 1.21.1)" >&2
    ask "选择 [1]: " >&2; rd c
    [ -z "$c" ] && c=1
    if [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le "$n" ]; then
        printf '%s' "${arr[$((c-1))]}"
    else
        printf '%s' "$c"
    fi
}

# 依 MC 版本推导所需 Java 主版本
need_java() {
    local mc="$1" major minor
    major=$(printf '%s' "$mc" | cut -d. -f2)
    minor=$(printf '%s' "$mc" | cut -d. -f3)
    [ -z "$major" ] && { echo 21; return; }
    # 1.20.5 起需 Java 21; 其余统一 17(Termux 主流仅提供 17/21)
    if [ "$major" -ge 21 ]; then echo 21
    elif [ "$major" -eq 20 ] && [ "${minor:-0}" -ge 5 ]; then echo 21
    elif [ "$major" -ge 18 ]; then echo 17
    else echo 17
    fi
}

# 依赖自检与补装: Java 按 MC 版本, Python 检测后补
ensure_deps() {
    local mc="$1" jv havej
    jv=$(need_java "$mc")
    title "依赖检查"

    havej=""
    if command -v java >/dev/null 2>&1; then
        havej=$(java -version 2>&1 | head -1 | grep -oE '[0-9]+' | head -1)
    fi
    echo -e "  Java   : 需要 ${C}$jv${R}  当前 ${C}${havej:-未安装}${R}"
    if [ "$havej" != "$jv" ]; then
        if [ "${AUTO_DEPS:-1}" = 1 ]; then
            say "  正在自动安装 openjdk-$jv (体积较大, 请耐心)"
            if _pkg_do "openjdk-$jv"; then
                say "  Java $jv 安装完成 ✅"
            else
                err "  Java 安装失败; 可手动: pkg install openjdk-$jv"
                warn "  服务端可能无法启动"
            fi
        else
            ask "  安装 openjdk-$jv ? [Y/n]: "; rd y
            case "$y" in
                n|N) warn "  跳过; 服务端可能无法启动";;
                *) say "  正在安装 openjdk-$jv (体积较大, 请耐心)"
                   _pkg_do "openjdk-$jv" || { err "  Java 安装失败"; return 1; };;
            esac
        fi
    else
        say "  Java 版本已满足 ✅"
    fi

    echo -ne "  Python : "
    if command -v python3 >/dev/null 2>&1; then
        echo -e "${G}已安装 $(python3 -V 2>&1 | cut -d' ' -f2)${R}"
    elif [ "${AUTO_DEPS:-1}" = 1 ]; then
        echo -e "${Y}未安装${R} → 自动安装中..."
        if _pkg_do python; then
            echo -e "  ${G}[+]${R} Python 安装完成"
        else
            err "  Python 安装失败, 云端下载与许可证审计将不可用"
        fi
    else
        echo -e "${Y}未安装${R}"
        ask "  安装 python ? [Y/n]: "; rd y
        case "$y" in
            n|N) warn "  无 python3, 云端下载与许可证审计将不可用";;
            *) _pkg_do python || { err "  Python 安装失败"; return 1; };;
        esac
    fi

    # 顺带补齐小工具
    need_bins
    press
    return 0
}

# ============================================================
#  新建服务器
# ============================================================
new_server() {
    title "新建服务器"
    ask "服务器名称: "; rd name
    [ -z "$name" ] && return
    local sdir="${ROOT}/servers/${name}"
    mkdir -p "$sdir"

    echo
    echo "  1) 插件服  (Paper/Purpur/Folia/Velocity)"
    echo "  2) 模组服  (NeoForge/Fabric/Forge)"
    ask "选择类型: "; rd t
    local type loader mc
    if [ "$t" = "1" ]; then
        type=plugin
        echo "  加载器: paper / purpur / folia / velocity"
        ask "选择: "; rd loader
        [ -z "$loader" ] && loader=paper
    else
        type=mod
        echo "  加载器: neoforge / fabric / forge"
        ask "选择: "; rd loader
        [ -z "$loader" ] && loader=neoforge
    fi

    local mc
    mc=$(pick_mc_version "$loader")
    [ -z "$mc" ] && { err "未选择 MC 版本"; return; }
    say "已选择 MC 版本: $mc"

    ensure_deps "$mc" || warn "依赖未就绪, 继续安装核心"

    ask "内存 MB (默认1536): "; rd mem
    [ -z "$mem" ] && mem=1536

    echo "$mem" > "${HIST_DIR}/${name}.mem"
    cat > "${HIST_DIR}/${name}.meta" <<EOF
type=$type
loader=$loader
mc=$mc
EOF
    echo "world" > "${HIST_DIR}/${name}.world"

    if install_core "$sdir" "$type" "$loader" "$mc"; then
        say "核心安装完成!"
        # server.properties 留空监听 = 双栈
        touch "$sdir/server.properties"
        sed -i "s/^server-ip=.*/server-ip=/" "$sdir/server.properties" 2>/dev/null
        grep -q "^server-ip=" "$sdir/server.properties" 2>/dev/null || echo "server-ip=" >> "$sdir/server.properties"
    else
        err "核心安装失败, 请检查网络环境"
    fi
    CUR="$name"; save_conf
    press
}

# ============================================================
#  选择服务器
# ============================================================
pick_server() {
    local list=(); local i=1
    for d in "$ROOT"/servers/*; do
        [ -d "$d" ] && list+=("$(basename "$d")")
    done
    [ ${#list[@]} -eq 0 ] && { warn "还没有服务器, 请先新建"; press; return; }
    title "选择服务器"
    for s in "${list[@]}"; do echo "  $i) $s"; i=$((i+1)); done
    ask "序号: "; rd n
    local sel="${list[$((n-1))]}"
    [ -n "$sel" ] && { CUR="$sel"; save_conf; say "当前服务器: $CUR"; }
    press
}

# ============================================================
#  设置
# ============================================================
settings() {
    while true; do
        title "设置"
        echo "  1) 服务器根目录  当前: $ROOT"
        echo "  2) 下载重试次数  当前: $MAX_RETRY"
        echo "  3) Modrinth API  当前: $MR_API"
        echo "  4) 一键探测并切换镜像"
        echo "  5) 当前服务器内存"
        echo "  6) 动效开关        当前: $([ "$ANIM" = "1" ] && echo 开 || echo 关)"
        echo "  7) 服务器日志着色  当前: $([ "$LOGCOLOR" = "1" ] && echo 开 || echo 关)"
        echo "  8) 底部运行状态栏  当前: $([ "$STATBAR" = "1" ] && echo 开 || echo 关)"
        echo "  9) 保存运行日志      当前: $([ "$SAVELOG" = "1" ] && echo 开 || echo 关)"
        echo "  10) 日志保留份数      当前: ${LOGKEEP} 份"
        echo "  11) 转圈样式      当前: $([ "${SPIN_STYLE:-16}" = "4" ] && echo '经典 |/-\ (4帧)' || echo '平滑圆周 (16帧)')  (一圈 $(spin_circle)s)"
        echo "  12) 转圈速度      当前: $(case "${SPIN_SPEED:-fast}" in fast) echo 快;; normal) echo 标准;; slow) echo 慢;; esac)  (一圈 $(spin_circle)s)"
        echo "  13) 依赖自动安装  当前: $([ "${AUTO_DEPS:-1}" = 1 ] && echo 开 || echo 关)"
        echo "  0) 返回"
        ask "选择: "; rd c || return
        [ -z "$c" ] && continue
        case "$c" in
        1) ask "新路径: "; rd p; [ -n "$p" ] && { ROOT=$(eval echo "${p/#\~/$HOME}"); mkdir -p "$ROOT"; save_conf; };;
        2) ask "次数: "; rd p; [ -n "$p" ] && { MAX_RETRY=$p; save_conf; };;
        3) ask "API地址: "; rd p; [ -n "$p" ] && { MR_API=$p; save_conf; };;
        4) mirror_pick;;
        5) ask "内存MB: "; rd p; [ -n "$p" ] && [ -n "$CUR" ] && { echo "$p" > "${HIST_DIR}/${CUR}.mem"; say "已保存"; } || warn "先选服务器";;
        6) if [ "$ANIM" = "1" ]; then ANIM=0; say "动效已关闭(启动更快)"; else ANIM=1; say "动效已开启"; fi; save_conf;;
        7) if [ "$LOGCOLOR" = "1" ]; then LOGCOLOR=0; say "服务器日志着色已关闭(原始输出, 延迟最低)"; else LOGCOLOR=1; say "服务器日志着色已开启"; fi; save_conf;;
        8) if [ "$STATBAR" = "1" ]; then STATBAR=0; say "底部状态栏已关闭"; else STATBAR=1; say "底部状态栏已开启"; fi; save_conf;;
        9) if [ "$SAVELOG" = "1" ]; then SAVELOG=0; say "不再保存运行日志"; else SAVELOG=1; say "运行日志将保存到 $LOGDIR"; fi; save_conf;;
        10) ask "保留份数: "; rd p; [ -n "$p" ] && { LOGKEEP=$p; save_conf; log_prune; say "已设为保留最近 $p 份"; };;
        11) if [ "${SPIN_STYLE:-16}" = "4" ]; then SPIN_STYLE=16; say "转圈样式: 平滑圆周 (16帧)"; else SPIN_STYLE=4; say "转圈样式: 经典 |/-\\ (4帧)"; fi; save_conf;;
        12) case "${SPIN_SPEED:-fast}" in fast) SPIN_SPEED=normal; say "转圈速度: 标准 (0.8s/圈)";; normal) SPIN_SPEED=slow; say "转圈速度: 慢 (1.6s/圈)";; *) SPIN_SPEED=fast; say "转圈速度: 快 (0.5s/圈)";; esac; BAR_CACHE=(); save_conf;;
        13) if [ "${AUTO_DEPS:-1}" = 1 ]; then AUTO_DEPS=0; say "依赖自动安装已关闭(缺依赖只提示)"; else AUTO_DEPS=1; say "依赖自动安装已开启(缺什么装什么)"; fi; save_conf;;
        0|q|Q) return;;
        esac
    done
}

# ============================================================
#  人员权限 (OP / 封禁)
# ============================================================
PM_PY="${CONF_DIR}/pmtool.py"

pm_py() {
    [ -s "$PM_PY" ] && return 0
    mkdir -p "$CONF_DIR" 2>/dev/null
    cat > "$PM_PY" <<'PYEOF'
import json,sys,os,datetime
def load(f):
    if not os.path.exists(f): return []
    try: d=json.load(open(f))
    except Exception: return []
    if isinstance(d,dict): d=d.get("data",[])
    return d if isinstance(d,list) else []
cmd=sys.argv[1]
if cmd=="opslist":
    for e in load(sys.argv[2]):
        if isinstance(e,dict):
            print("%s\t%s\t%s"%(e.get("name","?"), str(e.get("uuid","")), e.get("level",4)))
elif cmd=="opswrite":
    out=[];seen=set()
    for line in sys.stdin:
        line=line.rstrip("\n")
        if not line.strip(): continue
        p=line.split("\t")
        n=p[0].strip(); u=(p[1].strip() if len(p)>1 else "")
        lv=(p[2].strip() if len(p)>2 else "4")
        if not n: continue
        k=(n.lower(), u)
        if k in seen: continue
        seen.add(k)
        try: lv=int(lv)
        except Exception: lv=4
        e={"uuid":u,"name":n,"level":lv,"bypassesPlayerLimit":False}
        out.append(e)
    json.dump(out,open(sys.argv[2],"w"),indent=2,ensure_ascii=False)
    print(len(out))
elif cmd=="banlist":
    for e in load(sys.argv[2]):
        if not isinstance(e,dict): continue
        k=sys.argv[3]
        v=str(e.get(k,""))
        r=str(e.get("reason",""))[:40]
        print("%s\t%s\t%s"%(v, str(e.get("uuid","")), r))
elif cmd=="banwrite":
    mode=sys.argv[3]
    out=load(sys.argv[2])
    have=set()
    for e in out:
        if isinstance(e,dict): have.add(str(e.get(mode,"")).lower())
    for line in sys.stdin:
        line=line.rstrip("\n")
        if not line.strip(): continue
        p=line.split("\t")
        v=p[0].strip()
        if not v: continue
        if v.lower() in have: continue
        have.add(v.lower())
        now=datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S +0000")
        if mode=="ip":
            out.append({"ip":v,"created":now,"source":"mcserv","expires":"forever","reason":(p[1].strip() if len(p)>1 else "")})
        else:
            u=(p[1].strip() if len(p)>1 else "")
            r=(p[2].strip() if len(p)>2 else "")
            out.append({"uuid":u,"name":v,"created":now,"source":"mcserv","expires":"forever","reason":r})
    json.dump(out,open(sys.argv[2],"w"),indent=2,ensure_ascii=False)
    print(len(out))
elif cmd=="del":
    mode=sys.argv[3]; vals=set(x.lower() for x in sys.argv[4:])
    out=[]
    for e in load(sys.argv[2]):
        if not isinstance(e,dict): continue
        if str(e.get(mode,"")).lower() in vals: continue
        out.append(e)
    json.dump(out,open(sys.argv[2],"w"),indent=2,ensure_ascii=False)
    print(len(out))
elif cmd=="setlevel":
    name=sys.argv[3].lower(); lv=int(sys.argv[4])
    out=[]
    for e in load(sys.argv[2]):
        if isinstance(e,dict) and str(e.get("name","")).lower()==name:
            e["level"]=lv
        out.append(e)
    json.dump(out,open(sys.argv[2],"w"),indent=2,ensure_ascii=False)
    print(len(out))
PYEOF
}

pm_ops_list()   { pm_py; [ -f "$1" ] || return 0; python3 "$PM_PY" opslist "$1" 2>/dev/null; }
pm_ban_list()   { pm_py; [ -f "$1" ] || return 0; python3 "$PM_PY" banlist "$1" "$2" 2>/dev/null; }

# 序号多选: 从文件读列表, 选择从终端读 (避免被管道吃掉)
pm_pick() {   # $1=列表文件  -> stdout=选中行 (菜单走 tty, 不污染输出)
    local src="$1"
    local T=/dev/tty
    [ -e "$T" ] || T=/dev/stderr
    local rows=() r i=1 sel picked=""
    while IFS= read -r r; do [ -n "$r" ] && rows+=("$r"); done < "$src"
    if [ "${#rows[@]}" -eq 0 ]; then echo -e "${Y}[!]${R} 列表为空" > "$T"; return 1; fi
    {
      for r in "${rows[@]}"; do
          printf "  ${C}%2d)${R} %s\n" "$i" "${r%%$'\t'*}"; i=$((i+1))
      done
      echo
      echo -e "  ${Y}支持: 1 3  或  2-5  或  all${R}"
      echo -ne "${C}[?]${R} 选择: "
    } > "$T"
    if [ "$T" = "/dev/tty" ]; then read -r sel < /dev/tty 2>/dev/null; else read -r sel; fi
    [ -z "$sel" ] && return 1
    if [ "$sel" = "all" ]; then
        printf '%s\n' "${rows[@]}"; return 0
    fi
    for tok in $sel; do
        if printf '%s' "$tok" | grep -qE '^[0-9]+-[0-9]+$'; then
            local a="${tok%%-*}" b="${tok##*-}"
            [ "$a" -lt 1 ] && a=1
            [ "$b" -gt "${#rows[@]}" ] && b=${#rows[@]}
            for ((j=a; j<=b; j++)); do picked="${picked}${rows[$((j-1))]}"$'\n'; done
        else
            [[ ! "$tok" =~ ^[0-9]+$ ]] && continue
            [ "$tok" -lt 1 ] || [ "$tok" -gt "${#rows[@]}" ] && continue
            picked="${picked}${rows[$((tok-1))]}"$'\n'
        fi
    done
    [ -z "$picked" ] && return 1
    printf '%s' "$picked"
}

pm_reload_hint() {
    mc_running 2>/dev/null && warn "服务器运行中, 改动需重启服务端才生效"
}

pm_ops_menu() {
    local f="${ROOT}/servers/${CUR}/ops.json"
    while true; do
        title "OP 管理 —— $CUR"
        local n; n=$(pm_ops_list "$f" 2>/dev/null | grep -c . || true); [ -z "$n" ] && n=0
        echo -e "  当前 OP: ${C}${n}${R} 人"
        echo
        echo "   1) 查看 OP 列表"
        echo "   2) 添加 OP (从玩家里选)"
        echo "   3) 添加 OP (手动输入名字)"
        echo "   4) 删除 OP"
        echo "   5) 修改 OP 等级"
        echo "   0) 返回"
        echo
        ask "选择: "; rd c || return
        case "$c" in
        1)
            title "OP 列表"
            if [ "$n" -eq 0 ]; then warn "还没有 OP"; press; continue; fi
            pm_ops_list "$f" | while IFS=$'\t' rd nm uu lv; do
                printf "  ${C}%-20s${R}  等级 ${Y}%s${R}\n" "$nm" "$lv"
            done
            echo
            echo -e "  ${Y}等级: 1=绕过出生点保护  2=基础命令  3=大部分命令  4=全部(含/stop)${R}"
            press;;
        2)
            local cache="${ROOT}/servers/${CUR}/usercache.json"
            if [ ! -f "$cache" ]; then warn "没有玩家缓存 (服务器跑过一次才会有)"; press; continue; fi
            title "选择要设为 OP 的玩家"
            local lst; lst=$(wl_py; python3 "$WL_PY" cache "$cache" 2>/dev/null)
            local _tf; _tf=$(mktemp 2>/dev/null || echo "${CONF_DIR}/_pick.tmp")
            printf '%s\n' "$lst" > "$_tf"
            local sel; sel=$(pm_pick "$_tf") || { rm -f "$_tf"; continue; }
            rm -f "$_tf"
            [ -z "$sel" ] && { warn "没选"; press; continue; }
            local lv; ask "OP 等级 (1-4, 直接回车=4): "; rd lv
            [ -z "$lv" ] && lv=4
            { pm_ops_list "$f"; printf '%s\n' "$sel" | while IFS=$'\t' rd nm uu; do
                printf '%s\t%s\t%s\n' "$nm" "$uu" "$lv"; done
            } | python3 "$PM_PY" opswrite "$f" >/dev/null 2>&1
            say "已添加, OP 共 $(pm_ops_list "$f" 2>/dev/null | grep -c . || echo 0) 人"
            pm_reload_hint; press;;
        3)
            ask "玩家名 (多个用空格隔开): "; rd line
            [ -z "$line" ] && continue
            local lv; ask "OP 等级 (1-4, 直接回车=4): "; rd lv
            [ -z "$lv" ] && lv=4
            { pm_ops_list "$f"
              for nm in $line; do
                  local uu; uu=$(wl_uuid "$nm")
                  printf '%s\t%s\t%s\n' "$nm" "$uu" "$lv"
              done
            } | python3 "$PM_PY" opswrite "$f" >/dev/null 2>&1
            say "已添加, OP 共 $(pm_ops_list "$f" 2>/dev/null | grep -c . || echo 0) 人"
            pm_reload_hint; press;;
        4)
            title "删除 OP"
            local _tf; _tf=$(mktemp 2>/dev/null || echo "${CONF_DIR}/_pick.tmp")
            pm_ops_list "$f" > "$_tf"
            local sel; sel=$(pm_pick "$_tf") || { rm -f "$_tf"; continue; }
            rm -f "$_tf"
            [ -z "$sel" ] && { warn "没选"; press; continue; }
            local args=""; while IFS=$'\t' read -r nm uu lv; do args="$args \"$nm\""; done <<< "$sel"
            eval python3 "$PM_PY" del "$f" name $args >/dev/null 2>&1
            say "已删除, OP 剩余 $(pm_ops_list "$f" 2>/dev/null | grep -c . || echo 0) 人"
            pm_reload_hint; press;;
        5)
            title "修改 OP 等级"
            local _tf2; _tf2=$(mktemp 2>/dev/null || echo "${CONF_DIR}/_pick2.tmp")
            pm_ops_list "$f" > "$_tf2"
            local sel; sel=$(pm_pick "$_tf2") || { rm -f "$_tf2"; continue; }
            rm -f "$_tf2"
            local nm; nm=$(printf '%s' "$sel" | head -1 | cut -f1)
            [ -z "$nm" ] && { warn "没选"; press; continue; }
            echo -e "  要改的是: ${C}${nm}${R}"
            echo
            echo "   1) 等级 1  绕过出生点保护"
            echo "   2) 等级 2  基础命令"
            echo "   3) 等级 3  大部分命令"
            echo "   4) 等级 4  全部 (含 /stop)"
            ask "选择: "; rd lv
            case "$lv" in 1|2|3|4) ;; *) warn "无效"; press; continue;; esac
            python3 "$PM_PY" setlevel "$f" "$nm" "$lv" >/dev/null 2>&1
            say "已将 $nm 设为等级 $lv"
            pm_reload_hint; press;;
        0|q|Q) return;;
        esac
    done
}

pm_ban_menu() {
    local f="${ROOT}/servers/${CUR}/banned-players.json"
    while true; do
        title "封禁管理 —— $CUR"
        local n; n=$(pm_ban_list "$f" name 2>/dev/null | grep -c . || true); [ -z "$n" ] && n=0
        echo -e "  已封禁玩家: ${C}${n}${R} 人"
        echo
        echo "   1) 查看封禁列表"
        echo "   2) 封禁玩家 (从玩家里选)"
        echo "   3) 封禁玩家 (手动输入名字)"
        echo "   4) 解封玩家"
        echo "   0) 返回"
        echo
        ask "选择: "; rd c || return
        case "$c" in
        1)
            title "封禁列表"
            [ "$n" -eq 0 ] && { warn "没有封禁的人"; press; continue; }
            pm_ban_list "$f" name | while IFS=$'\t' rd nm uu rs; do
                printf "  ${RD}%-20s${R}  %s\n" "$nm" "${rs:-无理由}"
            done
            press;;
        2)
            local cache="${ROOT}/servers/${CUR}/usercache.json"
            [ -f "$cache" ] || { warn "没有玩家缓存"; press; continue; }
            title "选择要封禁的玩家"
            local _tf; _tf=$(mktemp 2>/dev/null || echo "${CONF_DIR}/_pick.tmp")
            { wl_py; python3 "$WL_PY" cache "$cache" 2>/dev/null; } > "$_tf"
            local sel; sel=$(pm_pick "$_tf") || { rm -f "$_tf"; continue; }
            rm -f "$_tf"
            [ -z "$sel" ] && { warn "没选"; press; continue; }
            ask "封禁理由 (可留空): "; rd rs
            # 合并已有条目 + 新选的, 一次性重写
            { pm_ban_list "$f" name | cut -f1-3
              printf '%s\n' "$sel" | while IFS=$'\t' rd nm uu; do printf '%s\t%s\t%s\n' "$nm" "$uu" "$rs"; done; } \
              | python3 "$PM_PY" banwrite "$f" name >/dev/null 2>&1
            say "已封禁, 共 $(pm_ban_list "$f" name 2>/dev/null | grep -c . || echo 0) 人"
            pm_reload_hint; press;;
        3)
            ask "玩家名 (多个用空格隔开): "; rd line
            [ -z "$line" ] && continue
            ask "封禁理由 (可留空): "; rd rs
            for nm in $line; do
                local uu; uu=$(wl_uuid "$nm")
                printf '%s\t%s\t%s\n' "$nm" "$uu" "$rs"
            done | python3 "$PM_PY" banwrite "$f" name >/dev/null 2>&1
            say "已封禁, 共 $(pm_ban_list "$f" name 2>/dev/null | grep -c . || echo 0) 人"
            pm_reload_hint; press;;
        4)
            title "解封玩家"
            local _tf; _tf=$(mktemp 2>/dev/null || echo "${CONF_DIR}/_pick.tmp")
            pm_ban_list "$f" name | cut -f1 > "$_tf"
            local sel; sel=$(pm_pick "$_tf") || { rm -f "$_tf"; continue; }
            rm -f "$_tf"
            [ -z "$sel" ] && { warn "没选"; press; continue; }
            local args=""; while read -r nm; do args="$args \"$nm\""; done <<< "$sel"
            eval python3 "$PM_PY" del "$f" name $args >/dev/null 2>&1
            say "已解封, 剩余 $(pm_ban_list "$f" name 2>/dev/null | grep -c . || echo 0) 人"
            pm_reload_hint; press;;
        0|q|Q) return;;
        esac
    done
}

pm_ip_menu() {
    local f="${ROOT}/servers/${CUR}/banned-ips.json"
    while true; do
        title "IP 封禁 —— $CUR"
        local n; n=$(pm_ban_list "$f" ip 2>/dev/null | grep -c . || true); [ -z "$n" ] && n=0
        echo -e "  已封禁 IP: ${C}${n}${R} 个"
        echo
        echo "   1) 查看列表"
        echo "   2) 封禁 IP"
        echo "   3) 解封 IP"
        echo "   0) 返回"
        echo
        ask "选择: "; rd c || return
        case "$c" in
        1) title "IP 封禁列表"
           [ "$n" -eq 0 ] && { warn "没有封禁的 IP"; press; continue; }
           pm_ban_list "$f" ip | while IFS=$'\t' rd ip uu rs; do
               printf "  ${RD}%-20s${R}  %s\n" "$ip" "${rs:-无理由}"; done
           press;;
        2) ask "要封禁的 IP: "; rd ip
           [ -z "$ip" ] && continue
           ask "理由 (可留空): "; rd rs
           printf '%s\t%s\n' "$ip" "$rs" | python3 "$PM_PY" banwrite "$f" ip >/dev/null 2>&1
           say "已封禁 $ip"
           pm_reload_hint; press;;
        3) title "解封 IP"
           local _tf; _tf=$(mktemp 2>/dev/null || echo "${CONF_DIR}/_pick.tmp")
           pm_ban_list "$f" ip | cut -f1 > "$_tf"
           local sel; sel=$(pm_pick "$_tf") || { rm -f "$_tf"; continue; }
           rm -f "$_tf"
           [ -z "$sel" ] && { warn "没选"; press; continue; }
           local args=""; while read -r ip; do args="$args \"$ip\""; done <<< "$sel"
           eval python3 "$PM_PY" del "$f" ip $args >/dev/null 2>&1
           say "已解封"; pm_reload_hint; press;;
        0|q|Q) return;;
        esac
    done
}

pm_menu() {
    while true; do
        title "人员权限 —— $CUR"
        local on ob
        on=$(pm_ops_list "${ROOT}/servers/${CUR}/ops.json" 2>/dev/null | grep -c . || true); [ -z "$on" ] && on=0
        ob=$(pm_ban_list "${ROOT}/servers/${CUR}/banned-players.json" name 2>/dev/null | grep -c . || true); [ -z "$ob" ] && ob=0
        local ow; ow=$(wl_list "${ROOT}/servers/${CUR}/whitelist.json" 2>/dev/null | grep -c . || true); [ -z "$ow" ] && ow=0
        echo -e "  OP: ${C}${on}${R} 人    封禁: ${C}${ob}${R} 人    白名单: ${C}${ow}${R} 人"
        echo
        echo "   1) OP 管理 (管理员权限)"
        echo "   2) 封禁管理 (拉黑玩家)"
        echo "   3) IP 封禁"
        echo "   4) 白名单管理 (菜单15)"
        echo "   0) 返回"
        echo
        echo -e "  ${Y}OP 等级说明:${R} 1=绕过出生点保护 2=基础命令 3=大部分命令 ${C}4=全部${R}"
        echo
        ask "选择: "; rd c || return
        case "$c" in
        1) pm_ops_menu;;
        2) pm_ban_menu;;
        3) pm_ip_menu;;
        4) wl_menu;;
        0|q|Q) return;;
        esac
    done
}

# ============================================================
#  定时开关服 (菜单 19 子项)
# ============================================================
SC_DIR="${CONF_DIR}/schedule"
SC_START_FILE="${SC_DIR}/start"
SC_STOP_FILE="${SC_DIR}/stop"
SC_ON_FILE="${SC_DIR}/on"

sc_on()    { [ -f "$SC_ON_FILE" ]; }
sc_start() { cat "$SC_START_FILE" 2>/dev/null; }
sc_stop()  { cat "$SC_STOP_FILE" 2>/dev/null; }

sc_cmd_ok() { command -v crontab >/dev/null 2>&1 || command -v termux-job-scheduler >/dev/null 2>&1; }

sc_install_cron() {
    if ! command -v crontab >/dev/null 2>&1; then
        warn "没找到 crontab"
        echo -e "  ${Y}装:${R} pkg install cronie"
        echo -e "  ${Y}装完再执行:${R} crond &"
        press; return 1
    fi
    if ! pgrep -x crond >/dev/null 2>&1; then
        warn "crond 没在跑"
        echo -e "  ${Y}执行:${R} crond &"
        echo -e "  ${Y}每次重启 Termux / 手机后都要重新执行一次${R}"
        echo
        ask "现在帮你启动 crond? (Y/n): "; rd k
        case "$k" in n|N) ;; *) ( crond >/dev/null 2>&1 & ) ; sleep 1
            pgrep -x crond >/dev/null 2>&1 && say "crond 已启动" || warn "启动失败";; esac
    fi
    return 0
}

sc_apply() {   # 写入 crontab
    sc_install_cron || return 1
    local st sp sh sm eh em
    st=$(sc_start); sp=$(sc_stop)
    [ -z "$st" ] || [ -z "$sp" ] && { warn "先设好启动和停止时间"; press; return 1; }
    sh="${st%%:*}"; sm="${st##*:}"
    eh="${sp%%:*}"; em="${sp##*:}"

    local self
    self=$(readlink -f "$0" 2>/dev/null || echo "${HOME}/mcserv.sh")

    # 保留其它人的 crontab, 只替换本脚本这两行
    local keep; keep=$(crontab -l 2>/dev/null | grep -v '#MCSERV' || true)
    {
        [ -n "$keep" ] && printf '%s\n' "$keep"
        printf '%s %s * * * bash "%s" __start  >>"%s/cron.log" 2>&1 #MCSERV-START\n' "$sm" "$sh" "$self" "$LOGDIR"
        printf '%s %s * * * bash "%s" __stop   >>"%s/cron.log" 2>&1 #MCSERV-STOP\n'  "$em" "$eh" "$self" "$LOGDIR"
    } | crontab - 2>/dev/null
    say "定时任务已写入"
    echo
    echo -e "  ${C}每天 ${st} 自动开服${R}"
    echo -e "  ${C}每天 ${sp} 自动关服${R}"
    echo
    echo -e "  ${Y}前提: crond 必须在跑 (菜单里按 5 可查看/启动)${R}"
    echo -e "  ${Y}手机重启后要重新执行 crond &, 否则不生效${R}"
    press
}

sc_clear() {
    sc_install_cron || return 1
    local keep; keep=$(crontab -l 2>/dev/null | grep -v '#MCSERV' || true)
    if [ -n "$keep" ]; then printf '%s\n' "$keep" | crontab - 2>/dev/null; else crontab -r 2>/dev/null; fi
    say "已取消定时开关服"
    press
}

sc_set_time() {   # $1=start|stop
    local cur; cur=$(cat "${SC_DIR}/$1" 2>/dev/null)
    [ -z "$cur" ] && { [ "$1" = "start" ] && cur="08:00" || cur="23:30"; }
    title "设置$([ "$1" = "start" ] && echo 启动 || echo 停止)时间"
    echo -e "  当前: ${C}${cur}${R}"
    echo
    echo -e "  ${Y}直接输入 HH:MM, 如 08:00 或 23:30${R}"
    echo
    echo "  快捷:"
    echo "   1) 08:00      早上开"
    echo "   2) 13:00      中午开"
    echo "   3) 18:00      傍晚开"
    echo "   4) 23:30      深夜关"
    echo "   5) 01:00      凌晨关"
    echo "   6) 04:00      凌晨关(适合通宵服)"
    echo
    ask "时间或序号: "; rd v
    case "$v" in
        1) v="08:00";; 2) v="13:00";; 3) v="18:00";;
        4) v="23:30";; 5) v="01:00";; 6) v="04:00";;
    esac
    [ -z "$v" ] && return
    if ! printf '%s' "$v" | grep -qE '^([01][0-9]|2[0-3]):[0-5][0-9]$'; then
        warn "格式不对, 要用 HH:MM (如 08:30)"
        press; return
    fi
    mkdir -p "$SC_DIR"
    printf '%s' "$v" > "${SC_DIR}/$1"
    say "已设为 $v"
    press
}

sc_status() {
    title "定时开关服"
    echo -e "  状态:   $(sc_on && echo "${G}已开启${R}" || echo "${Y}未开启${R}")"
    echo -e "  开服:   ${C}$(sc_start)${R}$( [ -z "$(sc_start)" ] && echo " ${Y}(未设)${R}" )"
    echo -e "  关服:   ${C}$(sc_stop)${R}$( [ -z "$(sc_stop)" ] && echo " ${Y}(未设)${R}" )"
    echo
    echo -e "  ${B}crond 状态:${R}"
    if pgrep -x crond >/dev/null 2>&1; then
        echo -e "  ${G}✔${R} 正在运行 (定时任务会生效)"
    else
        echo -e "  ${RD}✘${R} 没在跑"
        echo -e "      ${C}→${R} 按 5 启动它, 或手动执行: crond &"
    fi
    if command -v crontab >/dev/null 2>&1; then
        local has; has=$(crontab -l 2>/dev/null | grep -c '#MCSERV' || true)
        [ "${has:-0}" -gt 0 ] && echo -e "  ${G}✔${R} crontab 里已有本脚本的任务" \
                              || echo -e "  ${Y}!${R} crontab 里还没有任务 (按 6 写入)"
    else
        echo -e "  ${RD}✘${R} 没装 crontab: pkg install cronie"
    fi
    echo
    echo -e "  ${Y}注意:${R}"
    echo -e "   ${C}·${R} 定时开服会先自动备份 (若 19 菜单里开了)"
    echo -e "   ${C}·${R} 定时关服用优雅停止, 会保存存档"
    echo -e "   ${C}·${R} 手机重启后 crond 要重新拉起"
    press
}

sc_menu() {
    mkdir -p "$SC_DIR"
    while true; do
        title "定时开关服"
        echo -e "  状态: $(sc_on && echo "${G}已开启${R}" || echo "${Y}未开启${R}")"
        local _s _e; _s=$(sc_start); _e=$(sc_stop)
        echo -e "  ${C}${_s:-未设}${R} 自动开  →  ${C}${_e:-未设}${R} 自动关"
        echo -e "  crond: $(pgrep -x crond >/dev/null 2>&1 && echo "${G}运行中${R}" || echo "${RD}未运行${R}")"
        echo
        echo "   1) 设置开服时间  当前: $(sc_start)$( [ -z "$(sc_start)" ] && echo '(未设)' )"
        echo "   2) 设置关服时间  当前: $(sc_stop)$( [ -z "$(sc_stop)" ] && echo '(未设)' )"
        echo "   3) 开启定时      当前: $(sc_on && echo 开 || echo 关)"
        echo "   4) 写入/更新定时任务"
        echo "   5) 启动 crond"
        echo "   6) 取消定时任务"
        echo "   7) 查看状态"
        echo "   0) 返回"
        echo
        ask "选择: "; rd c || return
        case "$c" in
        1) sc_set_time start;;
        2) sc_set_time stop;;
        3) if sc_on; then rm -f "$SC_ON_FILE"; sc_clear; say "已关闭定时";
           else printf '1' > "$SC_ON_FILE"
                [ -z "$(sc_start)" ] && printf '08:00' > "$SC_START_FILE"
                [ -z "$(sc_stop)" ]  && printf '23:30' > "$SC_STOP_FILE"
                say "已开启定时: $(sc_start) 开 / $(sc_stop) 关"
                echo -e "  ${Y}按 4 写入到 crontab 才会真正生效${R}"; press; fi;;
        4) sc_on && sc_apply || { warn "先按 3 开启"; press; };;
        5) sc_install_cron && press;;
        6) sc_clear; rm -f "$SC_ON_FILE";;
        7) sc_status;;
        0|q|Q) return;;
        esac
    done
}

# ============================================================
#  存档保护 (防崩档 / 防误删)
# ============================================================
BK_DIR="${ROOT}/backups"
AUTO_BK_FILE="${CONF_DIR}/autobackup"
AUTOBK_KEEP_FILE="${CONF_DIR}/autobackup.keep"

# ---- 守护进程 (看门狗 / 定时备份) ----
WD_FILE="${CONF_DIR}/watchdog"              # 存在 = 崩溃自动拉起已开
WD_MAX_FILE="${CONF_DIR}/watchdog.max"      # 连续崩溃上限, 超过就放弃
WD_PID_FILE="${CONF_DIR}/watchdog.pid"
TBK_FILE="${CONF_DIR}/timebackup"           # 存在 = 运行中定时备份已开
TBK_MIN_FILE="${CONF_DIR}/timebackup.min"   # 备份间隔(分钟)
GUARD_LOG="${LOGDIR}/guard.log"

sp_autobk()   { [ -f "$AUTO_BK_FILE" ]; }
sp_keepn()    { local n; n=$(cat "$AUTOBK_KEEP_FILE" 2>/dev/null); echo "${n:-5}"; }

sp_world() {   # -> 当前世界名
    local w; w=$(cat "${HIST_DIR}/${CUR}.world" 2>/dev/null)
    [ -z "$w" ] && w=$(grep -m1 '^level-name=' "${ROOT}/servers/${CUR}/server.properties" 2>/dev/null | cut -d= -f2)
    [ -z "$w" ] && w="world"
    printf '%s' "$w"
}

# 让服务端立刻落盘再备份, 避免备份到半截写入的文件
sp_flush() {
    local fifo="${CONF_DIR}/stdin.fifo"
    [ -p "$fifo" ] || return 0
    printf 'save-all flush\n' > "$fifo" 2>/dev/null && sleep 3
    return 0
}

sp_prune() {   # 按保留份数清理旧备份
    local n; n=$(sp_keepn)
    local cnt; cnt=$(ls -1d "${BK_DIR}"/${CUR}_*.tar.gz 2>/dev/null | wc -l)
    [ "$cnt" -le "$n" ] && return 0
    local del=$((cnt - n))
    ls -1dt "${BK_DIR}"/${CUR}_*.tar.gz 2>/dev/null | tail -n "$del" | while read -r f; do rm -f "$f"; done
}

sp_do_backup() {   # $1=标签(可空) -> 输出文件路径
    local sdir="${ROOT}/servers/${CUR}"
    local w; w=$(sp_world)
    [ -d "${sdir}/${w}" ] || { warn "找不到世界目录: ${sdir}/${w}"; return 1; }
    mkdir -p "$BK_DIR"
    local tag="${1:-}"; [ -n "$tag" ] && tag="_${tag}"
    local out="${BK_DIR}/${CUR}_${w}_$(date +%Y%m%d_%H%M%S)${tag}.tar.gz"
    echo -ne "  ${Y}正在压缩备份...${R}"
    if tar -czf "$out" -C "$sdir" "$w" 2>/dev/null; then
        printf "\r\033[K"
        local sz; sz=$(du -h "$out" 2>/dev/null | cut -f1)
        say "已备份: $(basename "$out")  (${sz})"
        printf '%s' "$out" > "${CONF_DIR}/lastbackup" 2>/dev/null
        sp_prune
        return 0
    fi
    printf "\r\033[K"
    err "备份失败 (存储空间不足?)"
    rm -f "$out" 2>/dev/null
    return 1
}

sp_autobk_if_on() {   # 开服前自动调用
    sp_autobk || return 0
    echo -e "  ${Y}开服前自动备份...${R}"
    sp_do_backup "开服前" >/dev/null 2>&1
}

# ============================================================
#  守护进程  ① 看门狗: 崩了自动拉起  ② 定时备份: 运行中每隔 N 分钟
#  两者合并成一个后台循环, 只占一个进程, 不依赖 crond / termux-job
# ============================================================

wd_on()   { [ -f "$WD_FILE" ]; }
tbk_on()  { [ -f "$TBK_FILE" ]; }
wd_maxn() { local n; n=$(cat "$WD_MAX_FILE" 2>/dev/null); echo "${n:-3}"; }
tbk_min() { local n; n=$(cat "$TBK_MIN_FILE" 2>/dev/null); echo "${n:-120}"; }

guard_alive() {   # 守护在跑返回 0
    local p; p=$(cat "$WD_PID_FILE" 2>/dev/null)
    [ -n "$p" ] || return 1
    kill -0 "$p" 2>/dev/null || return 1
    # 确认是不是本脚本的守护, 防止 PID 复用误判
    tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q '__guard' && return 0
    return 1
}

guard_stop() {
    local p; p=$(cat "$WD_PID_FILE" 2>/dev/null)
    if [ -n "$p" ]; then
        kill "$p" 2>/dev/null
        pkill -P "$p" 2>/dev/null
        sleep 0.5
        kill -9 "$p" 2>/dev/null
    fi
    rm -f "$WD_PID_FILE"
}

guard_start_if_on() {   # 开服后调用: 任一开关打开才起守护
    wd_on || tbk_on || return 0
    local sdir="$1"
    [ -d "$sdir" ] || return 0
    guard_alive && return 0
    mkdir -p "$LOGDIR" 2>/dev/null
    local self; self=$(readlink -f "$0" 2>/dev/null || echo "${HOME}/mcserv.sh")
    # 用脚本自身重启一个 __guard 子入口, 保证 ROOT/CUR/配色都和主进程一致
    nohup bash "$self" __guard "$sdir" "$CUR" "$ROOT" >> "$GUARD_LOG" 2>&1 &
    local gp=$!
    disown "$gp" 2>/dev/null || true
    printf '%s' "$gp" > "$WD_PID_FILE"
    printf '[%s] 守护已启动 (PID %s) 看门狗:%s 定时备份:%s分钟\n' \
        "$(date +%H:%M:%S)" "$gp" \
        "$(wd_on && echo 开 || echo 关)" "$(tbk_on && echo "$(tbk_min)" || echo 关)" >> "$GUARD_LOG"
    return 0
}

guard_loop() {   # $1=服务器目录 $2=CUR $3=ROOT   (由 __guard 入口调用)
    local sdir="$1"
    CUR="$2"; ROOT="$3"
    local maxn; maxn=$(wd_maxn)
    local fail=0
    local lastbk; lastbk=$(date +%s)
    local iv; iv=$(tbk_min); iv=$(( iv * 60 ))
    [ "$iv" -lt 300 ] 2>/dev/null && iv=300     # 最快 5 分钟, 防刷盘
    local self; self=$(readlink -f "$0" 2>/dev/null || echo "${HOME}/mcserv.sh")

    mkdir -p "$LOGDIR" 2>/dev/null
    : > "$WD_PID_FILE"; printf '%s' "$$" > "$WD_PID_FILE"

    while true; do
        wd_on || tbk_on || { rm -f "$WD_PID_FILE"; exit 0; }

        # ---------- ② 定时备份 ----------
        if tbk_on; then
            local now; now=$(date +%s)
            if [ -n "$(java_pids 2>/dev/null | tr -d '\n ')" ] \
               && [ $(( now - lastbk )) -ge "$iv" ]; then
                printf '[%s] 定时备份: 开始\n' "$(date +%H:%M:%S)" >> "$GUARD_LOG"
                sp_do_backup "定时" >> "$GUARD_LOG" 2>&1
                lastbk=$now
                printf '[%s] 定时备份: 完成\n' "$(date +%H:%M:%S)" >> "$GUARD_LOG"
            fi
        fi

        # ---------- ① 看门狗 ----------
        if wd_on; then
            if [ -z "$(java_pids 2>/dev/null | tr -d '\n ')" ]; then
                fail=$(( fail + 1 ))
                printf '[%s] 服务端已退出 -> 第 %d/%d 次拉起\n' \
                    "$(date +%H:%M:%S)" "$fail" "$maxn" >> "$GUARD_LOG"
                if [ "$fail" -gt "$maxn" ]; then
                    printf '[%s] 连续崩溃 %d 次, 守护放弃 (手动排查: 菜单14看日志)\n' \
                        "$(date +%H:%M:%S)" "$maxn" >> "$GUARD_LOG"
                    rm -f "$WD_PID_FILE"
                    exit 0
                fi
                # 交给脚本自己的 __start 入口: 复用唤醒锁/frpc/备份全套逻辑
                bash "$self" __start >> "$GUARD_LOG" 2>&1
                sleep 20
            else
                fail=0
            fi
        fi

        sleep 30
    done
}

guard_status_line() {   # 主菜单底部一行: 守护状态
    local st=""
    if guard_alive; then
        st="  守护: ${G}运行中${R}"
        wd_on  && st="$st ${Y}看门狗${R}"  || st="$st ${Y}看门狗关${R}"
        tbk_on && st="$st ${Y}备份$(tbk_min)分${R}" || st="$st ${Y}定时备份关${R}"
    else
        wd_on || tbk_on || return 0
        st="  守护: ${Y}未运行${R} ${C}(开服后自动起)${R}"
    fi
    echo -e "$st"
}

guard_menu() {
    while true; do
        clear 2>/dev/null
        title "守护: 看门狗 + 定时备份"
        echo -e "  当前服: ${C}${CUR:-<未选择>}${R}"
        echo
        if guard_alive; then
            echo -e "  守护状态: ${G}${B}运行中${R} ${Y}(PID $(cat "$WD_PID_FILE" 2>/dev/null))${R}"
        else
            echo -e "  守护状态: ${Y}未运行${R}"
        fi
        echo
        echo -e "  ${B}① 看门狗${R} ${Y}崩了自动拉起, 半夜掉线不用管${R}"
        echo -e "     状态: $(wd_on && echo "${G}已开启${R}" || echo "${Y}已关闭${R}")"
        echo -e "     连续崩溃上限: ${C}$(wd_maxn)${R} 次"
        echo
        echo -e "  ${B}② 定时备份${R} ${Y}运行中每隔一段时间自动备份${R}"
        echo -e "     状态: $(tbk_on && echo "${G}已开启${R}" || echo "${Y}已关闭${R}")"
        echo -e "     间隔: ${C}$(tbk_min)${R} 分钟 ${Y}(最快5分钟)${R}"
        echo -e "     保留: ${C}$(sp_keepn)${R} 份 ${Y}(菜单19里改)${R}"
        echo
        echo "   1) 看门狗      开/关"
        echo "   2) 连续崩溃上限 (当前 $(wd_maxn))"
        echo "   3) 定时备份    开/关"
        echo "   4) 备份间隔    (当前 $(tbk_min) 分钟)"
        echo "   5) 立即启动守护"
        echo "   6) 停止守护"
        echo "   7) 查看守护日志"
        echo "   0) 返回"
        echo
        echo -e "  ${Y}说明:${R} 守护随开服自动起, 停服自动关; 手机需先开唤醒锁(菜单18)"
        echo
        ask "选择: "; rd c || return
        case "$c" in
        1) if wd_on; then rm -f "$WD_FILE"; say "看门狗已关闭";
           else printf '1' > "$WD_FILE"; say "看门狗已开启 (崩了自动拉起)"; fi; press;;
        2) ask "连续崩溃几次就放弃? (1-10): "; rd n
           case "$n" in
             [1-9]|10) printf '%s' "$n" > "$WD_MAX_FILE"; say "已设为 $n 次";;
             *) warn "只能是 1-10";;
           esac; press;;
        3) if tbk_on; then rm -f "$TBK_FILE"; say "定时备份已关闭";
           else printf '1' > "$TBK_FILE"; say "定时备份已开启"; fi; press;;
        4) ask "每隔多少分钟备份一次? (≥5): "; rd n
           case "$n" in
             ''|*[!0-9]*) warn "请输入数字";;
             *) if [ "$n" -lt 5 ]; then warn "最少 5 分钟"; else printf '%s' "$n" > "$TBK_MIN_FILE"; say "已设为每 $n 分钟"; fi;;
           esac; press;;
        5) if [ -z "$CUR" ]; then warn "先选服务器"; press; continue; fi
           guard_start_if_on "${ROOT}/servers/${CUR}" && say "守护已启动"; press;;
        6) guard_stop; say "守护已停止"; press;;
        7) if [ -f "$GUARD_LOG" ]; then
               title "守护日志 (末尾 30 行)"
               tail -n 30 "$GUARD_LOG"
           else warn "还没有守护日志"; fi; press;;
        0|q|Q) return;;
        esac
    done
}

sp_list() {
    title "备份列表"
    local fs=() f i=1 sz
    while read -r f; do [ -n "$f" ] && fs+=("$f"); done < <(ls -1dt "${BK_DIR}"/${CUR}_*.tar.gz 2>/dev/null)
    if [ "${#fs[@]}" -eq 0 ]; then
        warn "还没有备份"
        echo
        echo -e "  ${Y}建议先按 1 做一次, 之后崩了能一键回滚${R}"
        press; return
    fi
    echo -e "  ${Y}共 ${#fs[@]} 份, 新→旧${R}"
    echo
    for f in "${fs[@]}"; do
        sz=$(du -h "$f" 2>/dev/null | cut -f1)
        printf "  ${C}%2d)${R} %s   ${Y}%s${R}\n" "$i" "$(basename "$f")" "$sz"
        i=$((i+1))
    done
    echo
    ask "序号可看详情(直接回车返回): "; rd n
    [ -z "$n" ] && return
    [[ ! "$n" =~ ^[0-9]+$ ]] && return
    { [ "$n" -lt 1 ] || [ "$n" -gt "${#fs[@]}" ]; } && return
    f="${fs[$((n-1))]}"
    echo
    echo -e "  ${B}文件:${R} $f"
    echo -e "  ${B}大小:${R} $(du -h "$f" 2>/dev/null | cut -f1)"
    echo -e "  ${B}时间:${R} $(date -r "$f" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
    press
}

sp_restore() {
    local sdir="${ROOT}/servers/${CUR}"
    local fs=() f i=1
    while read -r f; do [ -n "$f" ] && fs+=("$f"); done < <(ls -1dt "${BK_DIR}"/${CUR}_*.tar.gz 2>/dev/null)
    title "恢复存档"
    if [ "${#fs[@]}" -eq 0 ]; then
        warn "没有可恢复的备份"; press; return
    fi
    echo -e "  ${Y}警告: 恢复会覆盖当前世界, 当前进度会丢失${R}"
    echo
    for f in "${fs[@]}"; do
        printf "  ${C}%2d)${R} %s\n" "$i" "$(basename "$f")"; i=$((i+1))
    done
    echo
    echo "  0) 取消"
    echo
    ask "选择要恢复的备份: "; rd n
    [ -z "$n" ] && return
    [ "$n" = "0" ] && return
    [[ ! "$n" =~ ^[0-9]+$ ]] && return
    { [ "$n" -lt 1 ] || [ "$n" -gt "${#fs[@]}" ]; } && return
    f="${fs[$((n-1))]}"

    if [ -n "$(java_pids 2>/dev/null | tr '\n' ' ' | tr -d ' ')" ]; then
        err "服务端还在运行, 必须先停止"
        echo -e "  ${C}→${R} 主菜单按 16 停止服务器"
        press; return
    fi

    local w; w=$(sp_world)
    echo
    echo -e "  ${Y}准备把当前「${w}」替换成:${R}"
    echo -e "  ${C}$(basename "$f")${R}"
    echo
    echo -e "  ${Y}当前世界会先自动存一份, 后悔了还能再回滚${R}"
    ask "确认恢复? (y/N): "; rd k
    case "$k" in y|Y) ;; *) say "已取消"; press; return;; esac

    echo -ne "  ${Y}正在备份当前世界...${R}"
    local cur_bk="${BK_DIR}/${CUR}_${w}_回滚前_$(date +%Y%m%d_%H%M%S).tar.gz"
    tar -czf "$cur_bk" -C "$sdir" "$w" 2>/dev/null
    printf "\r\033[K"

    echo -ne "  ${Y}正在恢复...${R}"
    rm -rf "${sdir}/${w}" 2>/dev/null
    if tar -xzf "$f" -C "$sdir" 2>/dev/null; then
        printf "\r\033[K"
        say "已恢复: $(basename "$f")"
        echo -e "  ${Y}旧世界存为:${R} $(basename "$cur_bk")"
    else
        printf "\r\033[K"
        err "恢复失败! 尝试从回滚备份还原..."
        tar -xzf "$cur_bk" -C "$sdir" 2>/dev/null && say "已还原回原来的世界"
    fi
    press
}

sp_check() {
    title "存档安全检查"
    local sdir="${ROOT}/servers/${CUR}"
    local w; w=$(sp_world)
    local ok=0 bad=0
    echo -e "  ${B}世界目录:${R} ${sdir}/${w}"
    echo
    if [ -d "${sdir}/${w}" ]; then
        echo -e "  ${G}✔${R} 世界目录存在"
        [ -f "${sdir}/${w}/level.dat" ] && echo -e "  ${G}✔${R} level.dat 正常" || \
            { echo -e "  ${RD}✘${R} level.dat 丢失 (世界已损坏)"; bad=$((bad+1)); }
    else
        echo -e "  ${RD}✘${R} 世界目录不存在"; bad=$((bad+1))
    fi

    case "$sdir" in
        /storage/emulated/0/*|/sdcard/*)
            echo -e "  ${G}✔${R} 存在共享存储 (卸载 Termux 也不会丢)";;
        *)
            echo -e "  ${RD}✘${R} 在 Termux 私有目录, 清除数据/卸载就没了"
            echo -e "      ${C}→${R} 设置 → 1 把根目录改到 /storage/emulated/0/dtmcbp"
            bad=$((bad+1));;
    esac

    local cnt; cnt=$(ls -1d "${BK_DIR}"/${CUR}_*.tar.gz 2>/dev/null | wc -l)
    if [ "$cnt" -gt 0 ]; then
        echo -e "  ${G}✔${R} 已有 $cnt 份备份"
        local last; last=$(ls -1dt "${BK_DIR}"/${CUR}_*.tar.gz 2>/dev/null | head -1)
        echo -e "     最新: $(basename "$last")"
    else
        echo -e "  ${RD}✘${R} 一份备份都没有"; bad=$((bad+1))
    fi

    if sp_autobk; then echo -e "  ${G}✔${R} 开服前自动备份: 开"
    else echo -e "  ${Y}!${R} 开服前自动备份: 关 (建议开)"; fi

    echo
    echo -e "  ${B}丢档的真正风险(按概率排):${R}"
    echo -e "   ${C}1.${R} 强杀进程 → 丢最后几分钟 (优雅停止不会)"
    echo -e "   ${C}2.${R} 模组不兼容写坏世界 → ${Y}唯一解是备份${R}"
    echo -e "   ${C}3.${R} 手机没电关机 → 同 1"
    echo -e "   ${C}4.${R} 清除 Termux 数据 → 存档在共享存储则没事"
    echo
    [ "$bad" -eq 0 ] && say "都没问题" || warn "$bad 项需要处理"
    press
}

sp_menu() {
    while true; do
        title "存档保护"
        local cnt; cnt=$(ls -1d "${BK_DIR}"/${CUR}_*.tar.gz 2>/dev/null | wc -l)
        echo -e "  当前服: ${C}${CUR}${R}   备份: ${C}${cnt}${R} 份   保留: ${C}$(sp_keepn)${R} 份"
        echo -e "  开服前自动备份: $(sp_autobk && echo "${G}开${R}" || echo "${Y}关${R}")"
        echo
        echo "   1) 立即备份 (会先让服务端落盘)"
        echo "   2) 开服前自动备份  开关"
        echo "   3) 备份保留份数    当前: $(sp_keepn)"
        echo "   4) 备份列表"
        echo "   5) 恢复存档 (崩了用这个回滚)"
        echo "   6) 存档安全检查"
        echo "   7) 定时开关服 (每天自动开/关)"
        echo "   0) 返回"
        echo
        ask "选择: "; rd c || return
        case "$c" in
        1) sp_flush; sp_do_backup; press;;
        2) if sp_autobk; then rm -f "$AUTO_BK_FILE"; say "已关闭自动备份";
           else printf '1' > "$AUTO_BK_FILE"; say "已开启: 每次启动服务器前自动备份"; fi;;
        3) ask "保留份数: "; rd n; [ -n "$n" ] && { printf '%s' "$n" > "$AUTOBK_KEEP_FILE"; sp_prune; say "已设为保留最近 $n 份"; };;
        4) sp_list;;
        5) sp_restore;;
        6) sp_check;;
        7) sc_menu;;
        0|q|Q) return;;
        esac
    done
}

# ============================================================
#  后台保活 (防止息屏 / 清后台后服务端掉线)
# ============================================================
WAKE_FILE="${CONF_DIR}/wakelock"
AUTO_WAKE_FILE="${CONF_DIR}/wakelock.auto"

bk_api_ok()   { command -v termux-wake-lock >/dev/null 2>&1; }
bk_locked()   { [ -f "$WAKE_FILE" ]; }
bk_autowake() { [ -f "$AUTO_WAKE_FILE" ]; }

bk_lock() {
    if ! bk_api_ok; then
        # 先尝试自动装命令行包; 装完仍可能因没装 App 而调不动, 那时再提示
        need_tapi && {
            bk_api_ok || {
                warn "包已装, 但 termux-wake-lock 仍调不动"
                echo -e "  ${Y}原因:${R} 还差 ${C}Termux:API${R} 这个 App 没装 (F-Droid / 官网)"
                echo -e "  ${Y}两个都要装, 只装一个不生效${R}"
                press; return 1
            }
            say "termux-api 就绪, 继续获取唤醒锁"
        } || {
            warn "没找到 termux-wake-lock, 且自动安装未成功"
            press; return 1
        }
    fi
    termux-wake-lock 2>/dev/null
    printf '1' > "$WAKE_FILE" 2>/dev/null
    say "已获取唤醒锁: 息屏后 CPU 继续跑, 服务端不会停"
    echo -e "  ${Y}注意:${R} 退出 Termux 或重启手机会失效, 下次开服重新点一次"
    press
}

bk_unlock() {
    bk_api_ok && termux-wake-unlock 2>/dev/null
    rm -f "$WAKE_FILE" 2>/dev/null
    say "已释放唤醒锁 (省电)"
    press
}

bk_autolock() {   # 开服前自动调用, 静默
    bk_autowake || return 0
    bk_api_ok || return 0
    termux-wake-lock 2>/dev/null
    printf '1' > "$WAKE_FILE" 2>/dev/null
}

bk_am() {   # $1=action  $2=data(可空)
    if ! command -v am >/dev/null 2>&1; then
        warn "没找到 am 命令, 无法自动打开设置页"
        echo -e "  ${Y}手动:${R} 系统设置 → 应用 → 找对应 App → 电池 / 自启动"
        press; return 1
    fi
    local out
    if [ -n "$2" ]; then out=$(am start -a "$1" -d "$2" 2>&1)
    else out=$(am start -a "$1" 2>&1); fi
    if printf '%s' "$out" | grep -qiE "error|denied|not found"; then
        warn "打开失败, 系统拦截了后台启动页面"
        echo -e "  ${Y}手动:${R} 系统设置 → 应用 → 找对应 App"
        press; return 1
    fi
    return 0
}

BK_KW='termux astral easytier mctier tailscale zerotier wireguard nebula vpn'

bk_name_of() {   # 包名 -> 中文名
    case "${1,,}" in
        *termux*)    echo "Termux";;
        *astral*)    echo "Astral";;
        *easytier*)  echo "EasyTier";;
        *mctier*)    echo "MCTier";;
        *tailscale*) echo "Tailscale";;
        *zerotier*)  echo "ZeroTier";;
        *wireguard*) echo "WireGuard";;
        *nebula*)    echo "Nebula";;
        *vpn*)       echo "VPN 类";;
        *)           echo "其它";;
    esac
}

bk_has_pm() { command -v pm >/dev/null 2>&1 || command -v cmd >/dev/null 2>&1; }

bk_raw() {   # 只列第三方应用, 系统组件直接跳过
    local r=""
    if command -v pm >/dev/null 2>&1; then
        r=$(pm list packages -3 2>/dev/null | sed 's/package://')
        [ -z "$r" ] && r=$(cmd package list packages -3 2>/dev/null | sed 's/package://')
        [ -z "$r" ] && r=$(pm list packages 2>/dev/null | sed 's/package://')
    elif command -v cmd >/dev/null 2>&1; then
        r=$(cmd package list packages -3 2>/dev/null | sed 's/package://')
    fi
    printf '%s\n' "$r"
}

bk_is_system() {   # 已知系统/厂商前缀, 一律跳过
    case "${1,,}" in
        com.android.*|com.android|android|com.google.android.*|com.google.*gms*|com.qualcomm.*|com.mediatek.*|com.samsung.*|com.huawei.android.*|com.hihonor.*|com.coloros.*|com.oppo.*|com.vivo.*|com.oem.*|com.miui.*|com.xiaomi.*|com.oneplus.*|com.bbk.*|com.android.providers.*|com.sec.android.*|com.sonyericsson.*|com.motorola.*)
            return 0;;
        *) return 1;;
    esac
}

bk_scan() {   # 扫描可能相关的第三方应用
    local p k hit
    local raw
    raw=$(bk_raw)
    [ -z "${raw// /}" ] && return 0
    while read -r p; do
        [ -z "$p" ] && continue
        bk_is_system "$p" && continue
        hit=""
        for k in $BK_KW; do
            case "${p,,}" in *"$k"*) hit=1; break;; esac
        done
        [ -z "$hit" ] && continue
        printf '%s\n' "$p"
    done <<< "$raw" | sort -u
}

bk_pick_pkg() {   # -> 输出包名
    local pkgs=() p i=1 sel
    echo -ne "  ${Y}正在扫描第三方应用...${R}"
    while read -r p; do [ -n "$p" ] && pkgs+=("$p"); done < <(bk_scan)
    printf "\r\033[K"
    title "选择应用"
    if [ "${#pkgs[@]}" -gt 0 ]; then
        echo -e "  ${Y}只列第三方应用, 系统组件已跳过${R}"
        for p in "${pkgs[@]}"; do
            printf "  ${C}%2d)${R} ${B}%s${R}   ${Y}%s${R}\n" "$i" "$(bk_name_of "$p")" "$p"
            i=$((i+1))
        done
    else
        if bk_has_pm; then
            warn "第三方应用里没匹配到组网/终端类"
        else
            warn "本机没有 pm / cmd 命令, 无法自动扫描包名"
            echo -e "  ${Y}Termux 里执行:${R} pkg install termux-api"
        fi
        echo
        echo -e "  ${Y}直接手动填包名更省事, 常见格式:${R}"
        echo -e "   ${C}com.termux${R}          ${Y}Termux${R}"
        echo -e "   ${C}com.termux.api${R}      ${Y}Termux:API${R}"
        echo -e "   ${Y}组网软件的长按图标 → 应用信息, 顶部能看到包名${R}"
    fi
    echo
    echo -e "  ${C}m)${R} 手动输入包名"
    echo "  0) 返回"
    echo
    ask "选择: "; rd sel
    [ -z "$sel" ] && return 1
    [ "$sel" = "0" ] && return 1
    if [ "$sel" = "m" ]; then
        ask "包名: "; rd sel
        [ -z "$sel" ] && return 1
        printf '%s' "$sel"; return 0
    fi
    [[ ! "$sel" =~ ^[0-9]+$ ]] && return 1
    { [ "$sel" -lt 1 ] || [ "$sel" -gt "${#pkgs[@]}" ]; } && return 1
    printf '%s' "${pkgs[$((sel-1))]}"
}


bk_open_battery() {
    local pkg; pkg=$(bk_pick_pkg) || return
    echo
    # 先试直达该应用的免优化弹窗, 失败再退回总列表
    local out
    out=$(am start -a android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS \
          -d "package:${pkg}" 2>&1) 2>/dev/null
    if printf '%s' "$out" | grep -qiE "error|denied|not found|permission"; then
        say "已打开电池优化列表页"
        echo -e "  ${Y}有些系统不给单独跳转, 需要在列表里找${R}"
        echo -e "  ${Y}要找的是: ${C}${pkg}${R}"
        echo -e "  ${Y}页面一般能切换筛选或排序, 选「所有应用」再找${R}"
        bk_am "android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS"
    else
        say "已弹出「${pkg}」的电池优化开关"
        echo -e "  ${Y}直接选「允许 / 不优化」${R}"
    fi
    echo
    echo -e "  ${Y}各家叫法不同:${R} 允许后台运行 / 无限制 / 不优化, 选最松的那个"
    press
}

bk_open_detail() {
    local pkg; pkg=$(bk_pick_pkg) || return
    echo
    say "已打开应用详情页: $pkg"
    echo -e "  ${Y}在里面检查这几项:${R}"
    echo -e "   ${C}·${R} 电池 / 耗电管理 → 允许后台活动"
    echo -e "   ${C}·${R} 自启动 / 关联启动 → 打开"
    echo -e "   ${C}·${R} 通知管理 → 允许 (有常驻通知更不容易被杀)"
    echo -e "   ${C}·${R} 权限 → 位置 (安卓12+ 的 VPN 类 App 需要)"
    bk_am "android.settings.APPLICATION_DETAILS_SETTINGS" "package:${pkg}"
    press
}

bk_check() {
    title "保活自检"
    local ok=0 bad=0
    if bk_api_ok; then
        echo -e "  ${G}✔${R} Termux:API 已装 (能用唤醒锁)"
    else
        echo -e "  ${RD}✘${R} Termux:API 未装"
        if need_tapi; then
            bk_api_ok && echo -e "      ${G}✔${R} 自动装好了, 现在可用唤醒锁" \
                       || { echo -e "      ${Y}!${R} 包已装, 还差 ${C}Termux:API${R} App"; bad=$((bad+1)); }
        else
            echo -e "      ${C}→${R} 手动: pkg install termux-api, 再装 Termux:API App"
            bad=$((bad+1))
        fi
    fi
    if bk_locked; then
        echo -e "  ${G}✔${R} 唤醒锁已持有"
    else
        echo -e "  ${RD}✘${R} 唤醒锁未持有 (息屏后服务端可能被停)"
        echo -e "      ${C}→${R} 按 1 获取"
        bad=$((bad+1))
    fi
    if [ -f "${CONF_DIR}/server.pid" ]; then
        echo -e "  ${G}✔${R} 服务端进程记录存在 (PID $(cat "${CONF_DIR}/server.pid" 2>/dev/null))"
    fi
    echo
    echo -e "  ${B}还要手动做一次(系统不让脚本代劳):${R}"
    echo -e "   ${C}1.${R} 多任务界面里把 Termux 卡片${Y}往下拉锁住${R}"
    echo -e "   ${C}2.${R} 系统设置 → 电池 → 把 Termux 设为${Y}不受限制${R}"
    echo -e "   ${C}3.${R} 组网软件(Astral/EasyTier)也要设, 否则网络会断"
    echo -e "   ${C}4.${R} 开服时别用一键清理/省电模式"
    echo
    if [ "$bad" -eq 0 ]; then
        say "软件层面都齐了, 上面 4 条手动确认一下就行"
    else
        warn "还有 $bad 项没到位"
    fi
    press
}

bk_menu() {
    while true; do
        title "后台保活"
        local w
        if bk_locked; then w="${G}已持有${R}"; else w="${Y}未持有${R}"; fi
        echo -e "  唤醒锁: $w     Termux:API: $(bk_api_ok && echo "${G}已装${R}" || echo "${RD}未装${R}")"
        echo
        echo -e "  ${Y}防止息屏 / 清后台之后服务端掉线${R}"
        echo
        echo "   1) 获取唤醒锁 (CPU 不休眠)   ← 开服必点"
        echo "   2) 释放唤醒锁"
        echo "   3) 开服时自动获取唤醒锁    当前: $(bk_autowake && echo 开 || echo 关)"
        echo "   4) 选应用 → 电池优化设置 (设为不受限制)"
        echo "   5) 选应用 → 应用详情页 (自启动/后台活动)"
        echo "   6) 打开系统电池设置总页"
        echo "   7) 保活自检"
        echo "   0) 返回"
        echo
        ask "选择: "; rd c || return
        case "$c" in
        1) bk_lock;;
        2) bk_unlock;;
        3) if bk_autowake; then rm -f "$AUTO_WAKE_FILE"; say "已关闭自动唤醒锁";
           else printf '1' > "$AUTO_WAKE_FILE"; say "已开启: 启动服务器时自动获取唤醒锁"; fi;;
        4) bk_open_battery;;
        5) bk_open_detail;;
        6) bk_am "android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS" && { say "已打开电池优化总页"; press; };;
        7) bk_check;;
        0|q|Q) return;;
        esac
    done
}

# ============================================================
#  一键自检 (把散落各菜单的检查汇总成一张体检单)
# ============================================================
diag_needjava() {   # $1=MC版本 -> 需要的 Java 主版本
    case "$1" in
        1.21*|1.20.[5-9]*|1.20.5|1.20.6) printf 21;;
        1.18*|1.19*|1.20*)               printf 17;;
        1.17*)                           printf 16;;
        *)                               printf 8;;
    esac
}

do_diag() {
    clear 2>/dev/null
    title "一键自检"
    local bad=0 warnc=0
    local mc=""; mc=$(mg mc)
    local loader=""; loader=$(mg loader)
    local sdir="${ROOT}/servers/${CUR}"
    local pf="${sdir}/server.properties"

    echo -e "  ${B}当前服:${R} ${C}${CUR:-<未选择>}${R}"
    [ -n "$mc" ] && echo -e "  ${B}版本  :${R} ${C}${mc}${R} / ${C}${loader:-?}${R}"
    echo

    # ---------- 1. Java ----------
    echo -e "  ${B}── Java ──${R}"
    if command -v java >/dev/null 2>&1; then
        local jline jnum need
        jline=$(java -version 2>&1 | head -n1)
        jnum=$(printf '%s' "$jline" | sed -n 's/.*version "\([0-9]*\).*/\1/p')
        need=$(diag_needjava "${mc:-}")
        echo -e "     已装: ${C}${jnum:-未知}${R}   ${Y}(${jline})${R}"
        if [ -n "$need" ] && [ -n "$jnum" ]; then
            if [ "$jnum" -ge "$need" ] 2>/dev/null; then
                echo -e "     MC ${mc} 需要 Java ${need} → ${G}✔ 满足${R}"
            else
                echo -e "     MC ${mc} 需要 Java ${need} → ${RD}✘ 版本过低${R}"
                echo -e "     ${Y}装:${R} pkg install openjdk-$need   (Termux)"
                bad=$((bad+1))
            fi
        fi
    else
        # 没装 java 不算"必须手动配置": 装 MC 核心时 ensure_deps 会自己装,
        # 所以这里给的是说明 + 一键安装, 而不是干巴巴标红吓人
        local needj; needj=$(diag_needjava "${mc:-}")
        echo -e "     ${Y}! 当前没装 java${R}"
        if [ -n "${mc:-}" ]; then
            echo -e "     ${C}→${R} MC ${mc} 需要 Java ${needj}"
            echo -e "     ${C}→${R} ${G}不用手动配${R}: 菜单 4 装核心时会自动装 ${C}openjdk-${needj}${R}"
        else
            echo -e "     ${C}→${R} 还没选服务器; 选定后装核心会自动装对应 Java"
        fi
        echo -e "     ${C}→${R} 想现在装: ${C}pkg install openjdk-${needj:-21}${R}"
        warnc=$((warnc+1))     # 记警告, 不记"必须处理"
    fi
    echo

    # ---------- 2. 目录与核心 ----------
    echo -e "  ${B}── 服务器目录 ──${R}"
    if [ -z "$CUR" ]; then
        echo -e "     ${RD}✘ 还没选服务器 (菜单 2)${R}"; bad=$((bad+1))
    elif [ ! -d "$sdir" ]; then
        echo -e "     ${RD}✘ 目录不存在: $sdir${R}"; bad=$((bad+1))
    else
        echo -e "     路径: ${C}$sdir${R}"
        [ -w "$sdir" ] && echo -e "     可写: ${G}✔${R}" \
                       || { echo -e "     可写: ${RD}✘ 无写权限${R}"; bad=$((bad+1)); }
        if [ -f "$sdir/server.jar" ]; then
            echo -e "     核心: ${G}✔ server.jar${R}"
        elif [ -f "$sdir/run.sh" ]; then
            echo -e "     核心: ${G}✔ run.sh${R}"
        else
            echo -e "     核心: ${RD}✘ 没有 server.jar (菜单 4 装核心)${R}"; bad=$((bad+1))
        fi
        if [ -f "$sdir/eula.txt" ] && grep -q 'eula=true' "$sdir/eula.txt" 2>/dev/null; then
            echo -e "     EULA: ${G}✔ 已同意${R}"
        else
            echo -e "     EULA: ${RD}✘ 未同意 (启动会秒退)${R}"; bad=$((bad+1))
        fi
    fi
    echo

    # ---------- 3. 安全项 ----------
    if [ -f "$pf" ]; then
        echo -e "  ${B}── 安全 ──${R}"
        local om wl rp
        om=$(grep -m1 '^online-mode=' "$pf" 2>/dev/null | cut -d= -f2)
        wl=$(grep -m1 '^white-list='  "$pf" 2>/dev/null | cut -d= -f2)
        rp=$(grep -m1 '^enable-rcon=' "$pf" 2>/dev/null | cut -d= -f2)
        if [ "$om" = "true" ]; then echo -e "     正版验证: ${G}✔ 开${R}"
        else echo -e "     正版验证: ${Y}! 关 (离线号可冒名进服)${R}"; warnc=$((warnc+1)); fi
        if [ "$wl" = "true" ]; then echo -e "     白名单  : ${G}✔ 开${R}"
        else echo -e "     白名单  : ${Y}! 关 (建议菜单 15 加人后开启)${R}"; warnc=$((warnc+1)); fi
        [ "$rp" = "true" ] && { echo -e "     RCON    : ${Y}! 开 (公网暴露有风险)${R}"; warnc=$((warnc+1)); }
        echo
    fi

    # ---------- 4. 端口 ----------
    echo -e "  ${B}── 端口 ──${R}"
    local port; port=$(grep -m1 '^server-port=' "$pf" 2>/dev/null | cut -d= -f2)
    : "${port:=25565}"
    echo -e "     server-port: ${C}$port${R}"
    if command -v ss >/dev/null 2>&1; then
        ss -ltn 2>/dev/null | grep -q ":$port " \
            && echo -e "     占用: ${G}✔ 已被监听${R}" \
            || echo -e "     占用: ${Y}- 当前没人监听 (服务端没跑就是正常)${R}"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -ltn 2>/dev/null | grep -q ":$port " \
            && echo -e "     占用: ${G}✔ 已被监听${R}" \
            || echo -e "     占用: ${Y}- 当前没人监听${R}"
    else
        echo -e "     占用: ${Y}- 无 ss/netstat, 跳过${R}"
    fi
    echo

    # ---------- 5. 资源 ----------
    echo -e "  ${B}── 资源 ──${R}"
    local mtotal mavail
    mtotal=$(awk '/MemTotal/{printf "%d",$2/1024}' /proc/meminfo 2>/dev/null)
    mavail=$(awk '/MemAvailable/{printf "%d",$2/1024}' /proc/meminfo 2>/dev/null)
    [ -n "$mtotal" ] && echo -e "     内存: 共 ${C}${mtotal}MB${R}, 可用 ${C}${mavail}MB${R}"
    local mem; mem=$(cat "${HIST_DIR}/${CUR}.mem" 2>/dev/null)
    : "${mem:=1536}"
    echo -e "     分配给服务端: ${C}${mem}MB${R}"
    if [ -n "$mavail" ] && [ "$mavail" -lt "$mem" ] 2>/dev/null; then
        echo -e "     ${RD}✘ 可用内存不够 ${mem}MB, 启动会 OOM${R}"
        echo -e "     ${Y}改小:${R} 菜单 10 设置里调内存, 或关掉别的 App"
        bad=$((bad+1))
    fi
    local dfree; dfree=$(df -h "$ROOT" 2>/dev/null | awk 'NR==2{print $4}')
    [ -n "$dfree" ] && echo -e "     磁盘剩余: ${C}$dfree${R}"
    local bkn; bkn=$(ls -1d "${BK_DIR}"/${CUR}_*.tar.gz 2>/dev/null | wc -l)
    if [ "$bkn" -eq 0 ] 2>/dev/null; then
        echo -e "     备份: ${Y}! 一份都没有 (菜单 19 建议开)${R}"; warnc=$((warnc+1))
    else
        echo -e "     备份: ${G}✔ ${bkn} 份${R}"
    fi
    echo

    # ---------- 6. 运行状态 ----------
    echo -e "  ${B}── 运行 ──${R}"
    if [ -n "$(java_pids 2>/dev/null | tr -d '\n ')" ]; then
        echo -e "     服务端: ${G}✔ 运行中${R}"
    else
        echo -e "     服务端: ${Y}- 未运行${R}"
    fi
    if command -v pgrep >/dev/null 2>&1 && pgrep -x frpc >/dev/null 2>&1; then
        echo -e "     穿透  : ${G}✔ frpc 在跑${R}"
    else
        echo -e "     穿透  : ${Y}- frpc 未运行 (菜单 23)${R}"; warnc=$((warnc+1))
    fi
    guard_alive && echo -e "     守护  : ${G}✔ 在跑${R}" \
                || echo -e "     守护  : ${Y}- 未运行 (菜单 24)${R}"
    if bk_locked 2>/dev/null; then echo -e "     唤醒锁: ${G}✔ 已持有${R}"
    else echo -e "     唤醒锁: ${Y}! 未持有 (息屏可能掉线, 菜单 18)${R}"; warnc=$((warnc+1)); fi
    echo

    # ---------- 7 安卓权限 ----------
    echo -e "  ${B}── 安卓权限 ──${R}"
    local pm_root=no pm_shi=no pm_api=no
    command -v su >/dev/null 2>&1 && su -c 'id -u' 2>/dev/null | grep -qx 0 && pm_root=yes
    command -v rish >/dev/null 2>&1 && pm_shi=yes
    command -v termux-toast >/dev/null 2>&1 && pm_api=yes
    echo -e "     提权  : root=${C}${pm_root}${R}  Shizuku=${C}${pm_shi}${R}  TermuxAPI=${C}${pm_api}${R}"
    if [ -w "$ROOT" ] 2>/dev/null; then
        echo -e "     存储  : ${G}✔ 根目录可写${R}"
    else
        echo -e "     存储  : ${RD}✘ 根目录不可写${R}"
        echo -e "     ${Y}处理:${R} termux-setup-storage  或菜单 26 权限中心"
        bad=$((bad+1))
    fi
    if [ "$pm_api" = no ]; then
        echo -e "     TermuxAPI: ${Y}! 未装 (唤醒锁/通知/弹窗都用不了)${R}"
        if need_tapi; then
            command -v termux-toast >/dev/null 2>&1 \
                && echo -e "     ${G}✔${R} 已自动装好 termux-api" \
                || { echo -e "     ${Y}!${R} 包已装, 还差 ${C}Termux:API${R} App (F-Droid)"; warnc=$((warnc+1)); }
        else
            echo -e "     ${Y}装:${R} pkg install termux-api  +  Termux:API App"
            warnc=$((warnc+1))
        fi
    fi
    echo

    # ---------- 汇总 ----------
    printf "  ${B}%s${R}\n" "$(printf '─%.0s' $(seq 1 40) 2>/dev/null)"
    if [ "$bad" -eq 0 ] && [ "$warnc" -eq 0 ]; then
        echo -e "  ${G}${B}✔ 全部检查通过${R}"
    else
        [ "$bad" -gt 0 ]   && echo -e "  ${RD}${B}✘ ${bad} 项必须处理${R}"
        [ "$warnc" -gt 0 ] && echo -e "  ${Y}${B}! ${warnc} 项建议处理${R}"
    fi
    echo
    press
}

# ============================================================
#  停止服务器 (兜底: 关不掉时用来强制收尾)
# ============================================================
# 找 java 进程: 优先 comm=java, 兜底按命令行含 server.jar
java_pids() {
    local pids="" d cmd
    for d in /proc/[0-9]*; do
        [ -r "$d/comm" ] || continue
        [ "$(cat "$d/comm" 2>/dev/null)" = "java" ] && pids="$pids ${d##*/}"
    done
    [ -n "$pids" ] && { printf '%s\n' $pids; return 0; }
    for d in /proc/[0-9]*; do
        [ -r "$d/cmdline" ] || continue
        cmd=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
        case "$cmd" in *server.jar*) printf '%s\n' "${d##*/}";; esac
    done
}

stop_server() {
    title "停止服务器"
    guard_stop            # 先撤守护, 否则刚停就被看门狗拉起来
    local pids; pids=$(java_pids | tr '\n' ' ')
    if [ -z "${pids// /}" ]; then
        say "当前没有运行中的 MC 服务端"
        press; return
    fi
    echo -e "  发现进程: ${C}${pids}${R}"
    echo
    echo "   1) 优雅停止 (SIGTERM, 会保存存档)   ← 推荐"
    echo "   2) 强制杀死 (SIGKILL, 可能丢档)"
    echo "   0) 取消"
    echo
    ask "选择: "; rd k
    case "$k" in
    1) for p in $pids; do kill -TERM "$p" 2>/dev/null; done
       local i=0 secs2=0 ss2; ss2=$(date +%s)
       local mt2; mt2=$(spin_tick)
       local lim; lim=$(max_ticks "$mt2"); lim=$(( lim / 6 ))   # 上限 30 秒
       [ "$lim" -lt 4 ] 2>/dev/null && lim=4
       while [ "$i" -lt "$lim" ]; do
           secs2=$(( $(date +%s) - ss2 ))
           spin_frame "$i"
           printf "\r  ${C}%b${R} 正在保存存档  ${Y}(%ds/30s)\033[K" "$SP_CH" "$secs2"
           sleep "$mt2"; i=$((i+1))
           [ -z "$(java_pids | tr '\n' ' ' | tr -d ' ')" ] && break
           [ "$secs2" -ge 30 ] && break
       done
       printf "\r\033[K"
       if [ -z "$(java_pids | tr '\n' ' ' | tr -d ' ')" ]; then
           say "已停止"
       else
           warn "30 秒仍未退出, 改用强制杀死"
           for p in $pids; do kill -KILL "$p" 2>/dev/null; done
           say "已强制结束"
       fi;;
    2) for p in $pids; do kill -KILL "$p" 2>/dev/null; done; say "已强制结束";;
    esac
    local hp; hp=$(cat "${CONF_DIR}/stdin.pid" 2>/dev/null)
    if [ -n "$hp" ]; then
        { kill -9 "$hp" 2>/dev/null; wait "$hp" 2>/dev/null; } 2>/dev/null
    fi
    rm -f "${CONF_DIR}/stdin.pid" "${CONF_DIR}/server.pid" "${CONF_DIR}/stdin.fifo" 2>/dev/null
    press
}

# ============================================================
#  白名单管理 (纯文件操作, 不需要 root / proot)
# ============================================================
#  whitelist.json 格式 (MC 1.21): [{"uuid":"xxx","name":"Steve"}]
#  usercache.json (服务器自动生成, 记录所有进过服的玩家):
#    [{"name":"Steve","uuid":"xxx","expiresOn":"..."}]

# 列出白名单: 输出 "name<TAB>uuid"
# 独立的 JSON 工具 (放文件里, 避免 heredoc 占用管道 stdin)
WL_PY="${CONF_DIR}/wltool.py"
wl_py() {
    [ -s "$WL_PY" ] && return 0
    mkdir -p "$CONF_DIR" 2>/dev/null
    cat > "$WL_PY" <<'PYEOF'
import json,sys
def load(f):
    try: d=json.load(open(f))
    except Exception: return []
    if isinstance(d,dict): d=d.get("data",[])
    return d if isinstance(d,list) else []
cmd=sys.argv[1]
if cmd=="list":
    for e in load(sys.argv[2]):
        if isinstance(e,dict):
            print("%s\t%s"%(e.get("name","?"), str(e.get("uuid",""))))
elif cmd=="write":
    out=[]; seen=set()
    for line in sys.stdin:
        line=line.rstrip("\n")
        if not line.strip(): continue
        p=line.split("\t")
        n=p[0].strip(); u=(p[1].strip() if len(p)>1 else "")
        if not n: continue
        k=(n.lower(), u)
        if k in seen: continue
        seen.add(k); out.append({"uuid":u,"name":n})
    json.dump(out, open(sys.argv[2],"w"), indent=2, ensure_ascii=False)
    print(len(out))
elif cmd=="cache":
    seen=set()
    for e in load(sys.argv[2]):
        if not isinstance(e,dict): continue
        n=e.get("name",""); u=str(e.get("uuid",""))
        if n and n not in seen:
            seen.add(n); print("%s\t%s"%(n,u))
elif cmd=="find":
    n=sys.argv[3].lower()
    for e in load(sys.argv[2]):
        if isinstance(e,dict) and str(e.get("name","")).lower()==n:
            print(e.get("uuid","")); break
PYEOF
}

# 列出白名单: 输出 "name<TAB>uuid"
wl_list() {
    wl_py || return 0
    [ -f "$1" ] || return 0
    python3 "$WL_PY" list "$1" 2>/dev/null
}

# 写白名单: stdin 收 "name<TAB>uuid" 行 (自动去重, 保留顺序)
wl_write() {
    wl_py || return 0
    python3 "$WL_PY" write "$1" 2>/dev/null
}

# 本地 UUID 缓存: ~/.mcserv/uuidcache  行格式 name<TAB>uuid
wl_cache_put() {
    [ -n "$1" ] && [ -n "$2" ] || return 0
    local f="${CONF_DIR}/uuidcache"
    touch "$f" 2>/dev/null || return 0
    grep -qi "^$1	" "$f" 2>/dev/null && return 0
    printf '%s\t%s\n' "$1" "$2" >> "$f" 2>/dev/null
}
wl_cache_get() {
    [ -n "$1" ] || return 0
    [ -f "${CONF_DIR}/uuidcache" ] || return 0
    grep -i "^$1	" "${CONF_DIR}/uuidcache" 2>/dev/null | head -1 | cut -f2
}

# 查 UUID: 本地缓存 -> usercache.json -> 联网 API
wl_uuid() {
    local name="$1" uuid=""
    [ -n "$name" ] || return 0
    uuid=$(wl_cache_get "$name")
    if [ -z "$uuid" ] && [ -n "${CUR:-}" ] && [ -f "${ROOT}/servers/${CUR}/usercache.json" ]; then
        wl_py
        uuid=$(python3 "$WL_PY" find "${ROOT}/servers/${CUR}/usercache.json" "$name" 2>/dev/null)
    fi
    if [ -z "$uuid" ]; then
        local raw=""
        for api in "https://playerdb.co/api/player/minecraft/${name}" \
                   "https://api.mojang.com/users/profiles/minecraft/${name}" \
                   "https://api.ashcon.app/mojang/v2/user/${name}"; do
            raw=$(curl -fsS --max-time 12 "$api" 2>/dev/null) && [ -n "$raw" ] && break
            raw=""
        done
        [ -n "$raw" ] && uuid=$(printf '%s' "$raw" | python3 -c '
import sys,json,re
t=sys.stdin.read()
try:
    j=json.loads(t)
    def dig(o):
        if isinstance(o,dict):
            for k in ("id","uuid","raw_id"):
                if k in o and isinstance(o[k],str) and len(o[k])>=32: return o[k]
            for v in o.values():
                r=dig(v)
                if r: return r
        elif isinstance(o,list):
            for v in o:
                r=dig(v)
                if r: return r
        return None
    u=dig(j)
    print(u if u else "")
except Exception:
    m=re.search(r"[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}", t)
    print(m.group(0) if m else "")
' 2>/dev/null)
    fi
    if [ -n "$uuid" ]; then
        uuid=$(printf '%s' "$uuid" | tr -d '-' | tr 'A-Z' 'a-z')
        if [ "${#uuid}" = "32" ]; then
            uuid="${uuid:0:8}-${uuid:8:4}-${uuid:12:4}-${uuid:16:4}-${uuid:20:12}"
        fi
        wl_cache_put "$name" "$uuid"
    fi
    printf '%s' "$uuid"
}

# 服务器是否在运行
mc_running() {
    for d in /proc/[0-9]*; do
        [ -r "$d/comm" ] || continue
        [ "$(cat "$d/comm" 2>/dev/null)" = "java" ] && return 0
    done
    return 1
}

# 序号选择解析: "1 3-5 all" -> 逐行序号
sel_expand() {
    local input="$1" total="$2" tok i a b
    for tok in $input; do
        case "$tok" in
        all|a|A) i=1; while [ "$i" -le "$total" ]; do echo "$i"; i=$((i+1)); done;;
        *-*)
            a=${tok%%-*}; b=${tok##*-}
            case "$a" in ''|*[!0-9]*) continue;; esac
            case "$b" in ''|*[!0-9]*) continue;; esac
            [ "$a" -lt 1 ] && a=1; [ "$b" -gt "$total" ] && b=$total
            i=$a; while [ "$i" -le "$b" ]; do echo "$i"; i=$((i+1)); done;;
        *)
            case "$tok" in ''|*[!0-9]*) continue;; esac
            [ "$tok" -ge 1 ] && [ "$tok" -le "$total" ] && echo "$tok";;
        esac
    done | sort -n -u
}

# 从运行日志提取玩家名
wl_from_log() {
    local out=""
    for f in "${LOGDIR}"/server-*.log; do
        [ -f "$f" ] || continue
        out="$out$(sed -n 's/.*: \([A-Za-z0-9_]\{2,16\}\) joined the game.*/\1/p; s/.*: \([A-Za-z0-9_]\{2,16\}\) lost connection.*/\1/p' "$f" 2>/dev/null)"
    done
    printf '%s\n' "$out" | grep -v '^$' | sort -u
}

wl_menu() {
    [ -n "$CUR" ] || { warn "先选服务器"; press; return; }
    local sdir="${ROOT}/servers/${CUR}"
    local wl="${sdir}/whitelist.json"
    [ -d "$sdir" ] || { warn "服务器目录不存在"; press; return; }
    while true; do
        title "白名单管理"
        local st="${Y}未设置${R}" n=0
        grep -q "^white-list=true" "$sdir/server.properties" 2>/dev/null && st="${G}已开启${R}"
        grep -q "^white-list=false" "$sdir/server.properties" 2>/dev/null && st="${Y}已关闭${R}"
        n=$(wl_list "$wl" 2>/dev/null | grep -c . 2>/dev/null)
        echo -e "  服务器: ${C}$CUR${R}"
        echo -e "  状态  : $st     人数: ${C}${n}${R}"
        echo
        echo "   1) 开启白名单"
        echo "   2) 关闭白名单"
        echo "   3) 查看白名单"
        echo "   4) 手动添加玩家 (自动查 UUID)"
        echo "   5) 从玩家缓存导入 (序号多选)"
        echo "   6) 从运行日志提取 (序号多选)"
        echo "   7) 删除玩家 (序号多选)"
        echo "   8) 清空白名单"
        echo "   0) 返回"
        echo
        ask "选择: "; rd c || return
        [ -z "$c" ] && continue
        case "$c" in
        1) touch "$sdir/server.properties"
           sed -i "s/^white-list=.*/white-list=true/" "$sdir/server.properties" 2>/dev/null
           grep -q "^white-list=" "$sdir/server.properties" 2>/dev/null || echo "white-list=true" >> "$sdir/server.properties"
           say "白名单已开启"
           mc_running && warn "服务器运行中, 需在游戏里执行: /whitelist reload"
           press;;
        2) touch "$sdir/server.properties"
           sed -i "s/^white-list=.*/white-list=false/" "$sdir/server.properties" 2>/dev/null
           say "白名单已关闭"; press;;
        3) if [ "$n" -eq 0 ]; then warn "白名单为空"; else
               echo; local i=1
               while IFS=$'\t' read -r nm uu; do
                   [ -z "$nm" ] && continue
                   echo -e "  ${C}$i)${R} $nm  ${Y}${uu:-<无UUID>}${R}"
                   i=$((i+1))
               done < <(wl_list "$wl")
           fi
           press;;
        4) ask "玩家名(多个用空格隔开): "; rd names
           if [ -z "$names" ]; then press; continue; fi
           local tmpf="${TMP_DIR}/wl.$$"; : > "$tmpf"
           wl_list "$wl" >> "$tmpf" 2>/dev/null
           local ok=0 fail=0
           for nm in $names; do
               if wl_list "$wl" | grep -qi "^${nm}	"; then warn "$nm 已在白名单"; continue; fi
               echo -ne "  查询 ${C}$nm${R} 的 UUID... "
               local uu; uu=$(wl_uuid "$nm")
               if [ -n "$uu" ]; then
                   printf '%s\t%s\n' "$nm" "$uu" >> "$tmpf"
                   echo -e "${G}$uu${R}"; ok=$((ok+1))
               else
                   echo -e "${RD}失败${R}"; fail=$((fail+1))
               fi
           done
           local cnt; cnt=$(wl_write "$wl" < "$tmpf"); rm -f "$tmpf"
           say "完成: 新增 $ok 人, 失败 $fail 人, 白名单共 ${cnt} 人"
           [ "$fail" -gt 0 ] && warn "查不到 UUID 通常是网络问题; 可让该玩家先进一次服生成 usercache.json, 再用 [5] 导入"
           mc_running && warn "服务器运行中, 需在游戏里执行: /whitelist reload"
           press;;
        5) local uc="${sdir}/usercache.json"
           if [ ! -f "$uc" ]; then warn "还没有 usercache.json (需要先有人进过服)"; press; continue; fi
           local cands=(); local nm uu i=1
           while IFS=$'\t' read -r nm uu; do
               [ -z "$nm" ] && continue
               cands+=("$nm	$uu")
           done < <(wl_py; python3 "$WL_PY" cache "$uc" 2>/dev/null)
           [ ${#cands[@]} -eq 0 ] && { warn "usercache.json 里没有玩家"; press; continue; }
           title "玩家缓存 (共 ${#cands[@]} 人)"
           for row in "${cands[@]}"; do
               nm=${row%%	*}; uu=${row##*	}
               if wl_list "$wl" | grep -qi "^${nm}	"; then
                   echo -e "  ${C}$i)${R} $nm  ${G}[已在白名单]${R}"
               else
                   echo -e "  ${C}$i)${R} $nm  ${Y}${uu:0:13}...${R}"
               fi
               i=$((i+1))
           done
           echo; echo -e "  ${Y}支持: 1 3  或  2-5  或  all${R}"
           ask "序号: "; rd sel
           [ -z "$sel" ] && continue
           local tmpf2="${TMP_DIR}/wl2.$$"; : > "$tmpf2"
           wl_list "$wl" >> "$tmpf2" 2>/dev/null
           local added=0 idx
           for idx in $(sel_expand "$sel" "${#cands[@]}"); do
               local row2="${cands[$((idx-1))]}"
               printf '%s\n' "$row2" >> "$tmpf2"; added=$((added+1))
           done
           local cnt2; cnt2=$(wl_write "$wl" < "$tmpf2"); rm -f "$tmpf2"
           say "选中 $added 人, 白名单共 ${cnt2} 人 (自动去重)"
           mc_running && warn "服务器运行中, 需在游戏里执行: /whitelist reload"
           press;;
        6) local cands2=() nm2 i2=1
           while read -r nm2; do
               [ -z "$nm2" ] && continue
               cands2+=("$nm2")
           done < <(wl_from_log)
           [ ${#cands2[@]} -eq 0 ] && { warn "运行日志里没找到玩家记录"; press; continue; }
           title "日志中的玩家 (共 ${#cands2[@]} 人)"
           for row in "${cands2[@]}"; do
               if wl_list "$wl" | grep -qi "^${row}	"; then
                   echo -e "  ${C}$i2)${R} $row  ${G}[已在白名单]${R}"
               else
                   echo -e "  ${C}$i2)${R} $row  ${Y}(需联网查 UUID)${R}"
               fi
               i2=$((i2+1))
           done
           echo; echo -e "  ${Y}支持: 1 3  或  2-5  或  all${R}"
           ask "序号: "; rd sel2
           [ -z "$sel2" ] && continue
           local tmpf3="${TMP_DIR}/wl3.$$"; : > "$tmpf3"
           wl_list "$wl" >> "$tmpf3" 2>/dev/null
           local ok2=0 fail2=0 idx2
           for idx2 in $(sel_expand "$sel2" "${#cands2[@]}"); do
               local nm3="${cands2[$((idx2-1))]}"
               echo -ne "  ${C}$nm3${R} ... "
               local uu3; uu3=$(wl_uuid "$nm3")
               if [ -n "$uu3" ]; then
                   printf '%s\t%s\n' "$nm3" "$uu3" >> "$tmpf3"
                   echo -e "${G}已添加${R}"; ok2=$((ok2+1))
               else
                   echo -e "${RD}UUID 查询失败${R}"; fail2=$((fail2+1))
               fi
           done
           local cnt3; cnt3=$(wl_write "$wl" < "$tmpf3"); rm -f "$tmpf3"
           say "成功 $ok2 人, 失败 $fail2 人, 白名单共 ${cnt3} 人"
           mc_running && warn "服务器运行中, 需在游戏里执行: /whitelist reload"
           press;;
        7) if [ "$n" -eq 0 ]; then warn "白名单为空"; press; continue; fi
           echo; local i3=1
           while IFS=$'\t' read -r nm4 uu4; do
               [ -z "$nm4" ] && continue
               echo -e "  ${C}$i3)${R} $nm4  ${Y}${uu4}${R}"
               i3=$((i3+1))
           done < <(wl_list "$wl")
           echo; echo -e "  ${Y}支持: 1 3  或  2-5  或  all${R}"
           ask "要删除的序号: "; rd sel3
           [ -z "$sel3" ] && continue
           local dellist; dellist=$(sel_expand "$sel3" "$n")
           [ -z "$dellist" ] && { warn "没有有效序号"; press; continue; }
           local tmpf4="${TMP_DIR}/wl4.$$"; : > "$tmpf4"
           local j4=1 keep=0
           while IFS=$'\t' read -r nm5 uu5; do
               [ -z "$nm5" ] && continue
               local hit=0
               for d in $dellist; do [ "$d" = "$j4" ] && hit=1; done
               if [ "$hit" = "0" ]; then printf '%s\t%s\n' "$nm5" "$uu5" >> "$tmpf4"; keep=$((keep+1)); fi
               j4=$((j4+1))
           done < <(wl_list "$wl")
           local cnt4; cnt4=$(wl_write "$wl" < "$tmpf4"); rm -f "$tmpf4"
           say "已删除, 白名单剩余 ${cnt4} 人"
           mc_running && warn "服务器运行中, 需在游戏里执行: /whitelist reload"
           press;;
        8) ask "确认清空白名单? (y/N): "; rd k8
           case "$k8" in y|Y) printf '[]' > "$wl"; say "已清空";; esac
           mc_running && warn "服务器运行中, 需在游戏里执行: /whitelist reload"
           press;;
        0|q|Q) return;;
        esac
    done
}

# ============================================================
#  主菜单
# ============================================================

# ============================================================
#  server.properties 配置编辑器
# ============================================================
# 条目:  key|默认值|中文说明|分类|类型
#  类型: bool / int / text / enum:a,b,c
PROP_ITEMS=(
 # ---- 1 连接 ----
 "server-port|25565|MC 端口|连接|int"
 "server-ip||监听 IP, 留空=所有网卡(组网必留空)|连接|text"
 "max-players|20|最大玩家数|连接|int:2=2人,5=5人,10=10人,20=标准,50=50人"
 "online-mode|true|正版验证, 公网服必须开|连接|bool"
 "prevent-proxy-connections|false|阻止 VPN/代理连入|连接|bool"
 "accepts-transfers|false|接受 transfer 跨服跳转(1.20.5+)|连接|bool"
 # ---- 2 网络 ----
 "network-compression-threshold|256|网络压缩阈值|网络|int:-1=禁用压缩,0=全部压缩,256=标准,512=省带宽,1024=更省带宽"
 "use-native-transport|true|Linux 原生传输(更快)|网络|bool"
 "player-idle-timeout|0|挂机几分钟踢出, 0=不踢|网络|int:0=不踢,10=10分钟,30=30分钟,60=1小时"
 "rate-limit|0|踢出风暴限流, 0=不限|网络|int:0=不限,10=10个,20=20个"
 "log-ips|true|日志里记录玩家 IP|网络|bool"
 "enable-status|true|允许被服务器列表查询|网络|bool"
 # ---- 3 性能 ----
 "view-distance|10|可视区块距离, 卡顿先降它|性能|int:2=很流畅,4=流畅,6=较流畅,8=均衡,10=标准,12=远,16=很远"
 "simulation-distance|10|模拟区块距离, 影响刷怪/作物|性能|int:2=很流畅,4=流畅,6=较流畅,8=均衡,10=默认,12=远"
 "sync-chunk-writes|true|同步写区块, 关掉更快但断电易损|性能|bool"
 "region-file-compression|deflate|区域文件压缩方式|性能|enum:标准压缩=deflate,不压缩=none,快速压缩=lz4"
 "entity-broadcast-range-percentage|100|实体广播范围百分比|性能|int:50=省一半,100=默认,150=看得更远,200=最远"
 "max-tick-time|60000|单 tick 超时毫秒(看门狗)|性能|int:60000=标准,120000=宽松,-1=禁用看门狗"
 # ---- 4 世界生成 ----
 "level-name|world|存档目录名|世界生成|text"
 "level-seed||世界种子, 留空=随机|世界生成|text"
 "level-type|minecraft:normal|世界类型|世界生成|enum:普通地形=minecraft:normal,超平坦=minecraft:flat,巨型生物群系=minecraft:large_biomes,放大化=minecraft:amplified"
 "generator-settings|{}|超平坦/单生态自定义|世界生成|text"
 "generate-structures|true|生成村庄/要塞等建筑|世界生成|bool"
 "allow-nether|true|允许进入下界|世界生成|bool"
 # ---- 5 世界规则 ----
 "hardcore|false|极限模式(死亡不可重生)|世界规则|bool"
 "max-world-size|29999984|世界边界半径(格)|世界规则|int:1000=小,5000=中,10000=大,29999984=不限"
 "difficulty|easy|难度|世界规则|enum:和平(不刷怪)=peaceful,简单=easy,普通=normal,困难=hard"
 "pvp|true|玩家之间能否互殴|世界规则|bool"
 "allow-flight|false|允许飞行(装了鞘翅模组要开)|世界规则|bool"
 "spawn-protection|16|出生点保护半径(格), 0=关闭|世界规则|int:0=不保护,8=小,16=标准,32=大,64=很大"
 # ---- 6 模式刷怪 ----
 "gamemode|survival|默认游戏模式|模式刷怪|enum:生存=survival,创造=creative,冒险=adventure,旁观=spectator"
 "force-gamemode|false|强制所有人用默认模式|模式刷怪|bool"
 "spawn-monsters|true|刷怪物|模式刷怪|bool"
 "spawn-animals|true|刷动物|模式刷怪|bool"
 "spawn-npcs|true|刷村民|模式刷怪|bool"
 "hide-online-players|false|隐藏在线玩家名单|模式刷怪|bool"
 # ---- 7 权限安全 ----
 "white-list|false|白名单|权限安全|bool"
 "enforce-whitelist|false|白名单变动立即踢出|权限安全|bool"
 "op-permission-level|4|OP 权限等级 1-4|权限安全|int:1=仅绕过出生点保护,2=可用基础命令,3=可用多数管理命令,4=全部权限"
 "function-permission-level|2|数据包函数权限 2-4|权限安全|int:2=默认,3=较高,4=全部"
 "enable-command-block|false|启用命令方块|权限安全|bool"
 "enforce-secure-profile|true|要求正版签名聊天|权限安全|bool"
 # ---- 8 聊天外观 ----
 "motd|A Minecraft Server|服务器列表简介|聊天外观|text"
 "text-filtering-version|0|聊天过滤版本|聊天外观|int:0=关闭"
 "text-filtering-config||聊天过滤配置|聊天外观|text"
 "broadcast-console-to-ops|true|控制台输出广播给 OP|聊天外观|bool"
 "bug-report-link||Bug 反馈链接|聊天外观|text"
 # ---- 9 数据包资源 ----
 "initial-enabled-packs||默认启用的数据包|数据包资源|text"
 "initial-disabled-packs||默认禁用的数据包|数据包资源|text"
 "resource-pack||资源包下载 URL|数据包资源|text"
 "resource-pack-sha1||资源包 SHA1 校验|数据包资源|text"
 "resource-pack-prompt||资源包提示文字|数据包资源|text"
 "require-resource-pack|false|强制接受资源包|数据包资源|bool"
 # ---- 10 远程管理 ----
 "enable-rcon|false|开启远程控制台|远程管理|bool"
 "rcon.password||RCON 密码(开了必须设)|远程管理|text"
 "rcon.port|25575|RCON 端口|远程管理|int"
 "broadcast-rcon-to-ops|true|RCON 输出广播给 OP|远程管理|bool"
 "enable-query|false|开启 UDP 查询|远程管理|bool"
 "query.port|25565|查询端口|远程管理|int"
 "enable-jmx-monitoring|false|JMX 监控|远程管理|bool"
)

prop_get() {   # key file -> 当前值(未配置则空)
    local v
    v=$(grep -m1 "^$1=" "$2" 2>/dev/null | cut -d= -f2-)
    printf '%s' "$v"
}
prop_def() {   # key -> 默认值
    local k="$1" it a b
    for it in "${PROP_ITEMS[@]}"; do
        IFS='|' read -r a b _ _ _ <<< "$it"
        [ "$a" = "$k" ] && { printf '%s' "$b"; return; }
    done
}
prop_set() {   # key value file
    local k="$1" v="$2" f="$3"
    [ -f "$f" ] || : > "$f"
    # 优先用 python3 写入: 值里的 \n / & / | 等字符不会被 sed 误解析
    if command -v python3 >/dev/null 2>&1; then
        MCS_K="$k" MCS_V="$v" MCS_F="$f" python3 - <<'PYEOF' 2>/dev/null && return 0
import os
k=os.environ["MCS_K"]; v=os.environ["MCS_V"]; f=os.environ["MCS_F"]
lines=[]
found=False
if os.path.exists(f):
    with open(f,encoding="utf-8",errors="replace") as fh:
        raw=fh.read().split("\n")
    for ln in raw:
        if ln.startswith(k+"="):
            lines.append(k+"="+v); found=True
        else:
            lines.append(ln)
while lines and lines[-1].strip()=="" : lines.pop()
if not found: lines.append(k+"="+v)
with open(f,"w",encoding="utf-8") as fh:
    fh.write("\n".join(lines)+"\n")
PYEOF
    fi
    # 回退: sed (对 \ 与 & 做转义)
    local ev; ev=$(printf '%s' "$v" | sed -e 's/[\\&|]/\\&/g')
    grep -q "^${k}=" "$f" 2>/dev/null \
      && sed -i "s|^${k}=.*|${k}=${ev}|" "$f" \
      || printf '%s=%s\n' "$k" "$v" >> "$f"
}
prop_del() { sed -i "/^$1=/d" "$2" 2>/dev/null; }

# 逐项编辑某个分类

# 把原始值转成中文显示 (bool/enum/带候选的数字)
opt_label() {   # typ value -> 中文
    local typ="$1" v="$2" list opt lab val _oo _oi
    case "$typ" in
    bool*)
        case "$v" in
            true)  printf '%s' "开启";;
            false) printf '%s' "关闭";;
            *)     printf '%s' "$v";;
        esac;;
    enum:*)
        list="${typ#enum:}"
        IFS=',' read -ra _oo <<< "$list"
        for opt in "${_oo[@]}"; do
            IFS='=' read -r lab val <<< "$opt"
            [ -z "$val" ] && val="$lab"
            [ "$val" = "$v" ] && { printf '%s' "$lab"; return; }
        done
        printf '%s' "$v";;
    int:*)
        list="${typ#int:}"
        [ -z "$list" ] && { printf '%s' "$v"; return; }
        IFS=',' read -ra _oi <<< "$list"
        for opt in "${_oi[@]}"; do
            IFS='=' read -r val lab <<< "$opt"
            [ -z "$lab" ] && lab="$val"
            [ "$val" = "$v" ] && { printf '%s' "$lab"; return; }
        done
        printf '%s' "$v";;
    *) printf '%s' "$v";;
    esac
}

prop_edit_cat() {
    local f="$1" cat="$2" items=() it k d desc typ pcat ptyp cur i=1 sel
    for it in "${PROP_ITEMS[@]}"; do
        IFS='|' read -r k d desc pcat ptyp <<< "$it"
        [ "$pcat" = "$cat" ] || continue
        items+=("$k|$d|$desc|$ptyp")
    done
    while true; do
        clear 2>/dev/null
        title "配置 - $cat"
        echo -e "  文件: ${C}$f${R}"
        echo
        i=1
        for it in "${items[@]}"; do
            IFS='|' read -r k d desc typ <<< "$it"
            cur=$(prop_get "$k" "$f")
            if [ -z "$cur" ]; then
                printf "  ${C}%d)${R} ${Y}%-34s${R} %s\n" "$i" "$k" "${Y}(默认 $(opt_label "$typ" "$d"))${R}"
            else
                printf "  ${C}%d)${R} ${G}%-34s${R} = ${G}%s${R}\n" "$i" "$k" "$(opt_label "$typ" "$cur")"
            fi
            i=$((i+1))
        done
        echo
        echo -e "  ${Y}选中某项后才显示它的说明${R}"
        echo
        echo "   0) 返回"
        echo
        ask "序号 (回车返回): "; rd sel
        [ -z "$sel" ] && return
        [ "$sel" = "0" ] && return
        [[ ! "$sel" =~ ^[0-9]+$ ]] && continue
        [ "$sel" -lt 1 ] || [ "$sel" -gt "${#items[@]}" ] && continue
        IFS='|' read -r k d desc typ <<< "${items[$((sel-1))]}"
        cur=$(prop_get "$k" "$f"); [ -z "$cur" ] && cur="$d"
        local cl; cl=$(opt_label "$typ" "$cur")
        local list opt lab val idx=1 nv= chose=0
        local _opts=()
        echo
        echo -e "  ${B}${C}── $desc ──${R}"
        echo -e "  ${Y}$k${R}"
        if [ "$cl" = "$cur" ]; then
            echo -e "  当前: ${G}${cl}${R}"
        else
            echo -e "  当前: ${G}${cl}${R}  ${Y}($cur)${R}"
        fi
        echo
        case "$typ" in
        bool*)
            [ "$cur" = "true" ]  && echo -e "  ${C}1)${R} 开启   ${G}← 当前${R}" || echo "  1) 开启"
            [ "$cur" = "false" ] && echo -e "  ${C}2)${R} 关闭   ${G}← 当前${R}" || echo "  2) 关闭"
            echo
            ask "选择 (1 开启 / 2 关闭): "; rd nv
            case "$nv" in
                1|开|开启|是|y|Y|true)  nv="true";;
                2|关|关闭|否|n|N|false) nv="false";;
                *) [ -z "$nv" ] && continue
                   warn "填 1 或 2 就行"; press; continue;;
            esac;;
        enum:*)
            list="${typ#enum:}"
            IFS=',' read -ra _opts <<< "$list"
            for opt in "${_opts[@]}"; do
                IFS='=' read -r lab val <<< "$opt"
                [ -z "$val" ] && val="$lab"
                if [ "$val" = "$cur" ]; then
                    echo -e "  ${C}${idx})${R} ${lab}   ${G}← 当前${R}"
                else
                    echo -e "  ${C}${idx})${R} ${lab}"
                fi
                idx=$((idx+1))
            done
            echo
            ask "选择 (1-${#_opts[@]}): "; rd nv
            if [[ "$nv" =~ ^[0-9]+$ ]] && [ "$nv" -ge 1 ] && [ "$nv" -le "${#_opts[@]}" ]; then
                opt="${_opts[$((nv-1))]}"
                IFS='=' read -r lab val <<< "$opt"
                [ -z "$val" ] && val="$lab"
                nv="$val"
            else
                [ -z "$nv" ] && continue
                warn "填 1 到 ${#_opts[@]} 之间的数字"; press; continue
            fi;;
        int:*)
            list="${typ#int:}"
            if [ -n "$list" ]; then
                IFS=',' read -ra _opts <<< "$list"
                for opt in "${_opts[@]}"; do
                    IFS='=' read -r val lab <<< "$opt"
                    [ -z "$lab" ] && lab="$val"
                    if [ "$val" = "$cur" ]; then
                        printf "  ${C}%d)${R} %-8s %s   ${G}← 当前${R}\n" "$idx" "$val" "$lab"
                    else
                        printf "  ${C}%d)${R} %-8s %s\n" "$idx" "$val" "$lab"
                    fi
                    idx=$((idx+1))
                done
                echo -e "  ${C}0)${R} 手动输入其它数字"
                echo
                ask "选择 (1-${#_opts[@]}, 0 手输): "; rd nv
                if [ "$nv" = "0" ]; then
                    ask "输入数字: "; rd nv
                    [[ ! "$nv" =~ ^-?[0-9]+$ ]] && { warn "要填数字"; press; continue; }
                elif [[ "$nv" =~ ^[0-9]+$ ]] && [ "$nv" -ge 1 ] && [ "$nv" -le "${#_opts[@]}" ]; then
                    opt="${_opts[$((nv-1))]}"
                    IFS='=' read -r val lab <<< "$opt"
                    nv="$val"
                else
                    [ -z "$nv" ] && continue
                    warn "填 1 到 ${#_opts[@]} 之间的数字"; press; continue
                fi
            else
                ask "输入数字: "; rd nv
                [ -z "$nv" ] && continue
                [[ ! "$nv" =~ ^-?[0-9]+$ ]] && { warn "要填数字"; press; continue; }
            fi;;
        *)
            if [ "$k" = "level-seed" ]; then
                prop_seed_menu "$f"
                continue
            fi
            if [ "$k" = "motd" ]; then motd_menu "$f"; continue; fi
            case "$k" in
            server-ip) echo -e "  ${Y}直接回车 = 留空 (组网联机必须留空)${R}";;
            esac
            ask "输入内容 (直接回车=清空/留空): "; rd nv
            if [ -z "$nv" ]; then
                ask "确定清空此项? (y/N): "; rd cf
                case "$cf" in y|Y) nv="";; *) continue;; esac
            fi;;
        esac
        if [ -n "$nv" ]; then
            prop_set "$k" "$nv" "$f"
            say "已写入: $k=$nv  ($(opt_label "$typ" "$nv"))"
        fi
        sleep 0.6
    done
}

# 种子专用菜单: 随机生成 / 文字转种子 / 手动输入 / 查看当前世界种子
prop_seed_menu() {
    local f="$1"
    local sdir="${ROOT}/servers/${CUR}"
    local cw; cw=$(cat "${HIST_DIR}/${CUR}.world" 2>/dev/null || echo world)
    local cur; cur=$(prop_get level-seed "$f")
    while true; do
        title "世界种子"
        echo -e "  当前设置: ${C}${cur:-(留空=随机)}${R}"
        if [ -f "$sdir/$cw/level.dat" ]; then
            local real; real=$(wt_seed "$sdir/$cw/level.dat")
            [ -n "$real" ] && echo -e "  当前世界实际种子: ${G}${real}${R}"
        fi
        echo
        echo "   1) 随机生成一个"
        echo "   2) 手动输入数字"
        echo "   3) 用文字当种子 (如: 生电)"
        echo "   4) 清空 (每次随机)"
        echo "   5) 用当前世界的种子"
        echo "   0) 返回"
        echo
        ask "选择: "; rd sc || return
        case "$sc" in
        1) local r1; r1=$(( (RANDOM << 17) ^ (RANDOM << 3) ^ RANDOM ))
           [ "$r1" = "0" ] && r1=1
           prop_set level-seed "$r1" "$f"
           say "已设为随机种子: $r1"
           warn "改种子只对【新建世界】生效; 已有世界需删除旧存档才会重生成"
           press; return;;
        2) ask "输入种子数字: "; rd sv
           [ -z "$sv" ] && continue
           prop_set level-seed "$sv" "$f"
           say "已设为: $sv"
           warn "改种子只对【新建世界】生效; 已有世界需删除旧存档才会重生成"
           press; return;;
        3) ask "输入文字: "; rd st
           [ -z "$st" ] && continue
           local hv; hv=$(wt_hash "$st")
           if [ -n "$hv" ]; then
               echo -e "  ${Y}「$st」→ 种子 ${C}$hv${R}"
               ask "用这个? (Y/n): "; rd ok
               case "$ok" in n|N) continue;; esac
               prop_set level-seed "$hv" "$f"
               say "已设为: $hv (等价输入文字「$st」)"
               warn "改种子只对【新建世界】生效; 已有世界需删除旧存档才会重生成"
           else
               err "转换失败"
           fi
           press; return;;
        4) prop_set level-seed "" "$f"
           say "已清空 (下次开服随机生成)"
           press; return;;
        5) if [ -f "$sdir/$cw/level.dat" ]; then
               local rs; rs=$(wt_seed "$sdir/$cw/level.dat")
               if [ -n "$rs" ]; then
                   prop_set level-seed "$rs" "$f"
                   say "已设为当前世界种子: $rs"
               else
                   err "读取失败"
               fi
           else
               err "当前世界还没生成过 (无 level.dat)"
           fi
           press; return;;
        0|q|Q) return;;
        esac
    done
}

# 预设方案
prop_preset() {
    local f="$1"
    while true; do
        clear 2>/dev/null
        title "快速预设"
        echo "   1) 流畅优先 (降视距降模拟, 老机器救星)"
        echo "   2) 画质优先 (视距拉满)"
        echo "   3) 安全加固 (白名单+正版+关远程)"
        echo "   4) 创造服 (创造模式+飞行+无保护)"
        echo "   5) 原版默认 (恢复官方初始值)"
        echo "   0) 返回"
        echo
        ask "选择: "; rd k
        case "$k" in
        1) prop_set view-distance 6 "$f"; prop_set simulation-distance 4 "$f"
           prop_set network-compression-threshold 512 "$f"
           prop_set sync-chunk-writes false "$f"
           prop_set entity-broadcast-range-percentage 100 "$f"
           say "已应用: 流畅优先"; press;;
        2) prop_set view-distance 12 "$f"; prop_set simulation-distance 10 "$f"
           prop_set sync-chunk-writes true "$f"
           say "已应用: 画质优先"; press;;
        3) prop_set white-list true "$f"; prop_set enforce-whitelist true "$f"
           prop_set online-mode true "$f"; prop_set enable-rcon false "$f"
           prop_set enable-query false "$f"; prop_set spawn-protection 16 "$f"
           prop_set prevent-proxy-connections false "$f"
           say "已应用: 安全加固"; press;;
        4) prop_set gamemode creative "$f"; prop_set spawn-protection 0 "$f"
           prop_set allow-flight true "$f"; prop_set difficulty peaceful "$f"
           say "已应用: 创造服"; press;;
        5) local it
           for it in "${PROP_ITEMS[@]}"; do
               IFS='|' read -r kk2 vv2 _ _ _ <<< "$it"
               [ -n "$vv2" ] && prop_set "$kk2" "$vv2" "$f"
           done
           say "已恢复官方默认"; press;;
        0|q|Q) return;;
        esac
    done
}

prop_menu() {
    [ -z "$CUR" ] && { warn "先选服务器"; press; return; }
    local sdir="${ROOT}/servers/${CUR}"
    [ ! -d "$sdir" ] && { err "目录不存在"; press; return; }
    local f="$sdir/server.properties"
    [ -f "$f" ] || { printf 'server-ip=\nonline-mode=true\n' > "$f"; }

    while true; do
        clear 2>/dev/null
        title "服务器配置 - $CUR"
        local n; n=$(grep -c "^[a-z-]*=" "$f" 2>/dev/null)
        echo -e "  文件: ${C}$f${R}"
        echo -e "  已配置项: ${C}${n}${R}"
        echo
        echo "   1) 按分类修改 (推荐)"
        echo "   2) 快速预设 (流畅/画质/安全/创造)"
        echo "   3) 按 key 名直接改"
        echo "   4) 添加自定义项"
        echo "   5) 删除某项"
        echo "   6) 查看完整文件"
        echo "   7) 用编辑器打开"
        echo "   8) 备份当前配置"
        echo "   9) 服务器图标 / 简介 (MOTD)"
        echo "   0) 返回"
        echo
        ask "选择: "; rd c
        case "$c" in
        1) while true; do
               clear 2>/dev/null
               title "选择分类"
               echo "  1) 连接  (6项)   端口 / IP / 人数 / 正版验证"
               echo "  2) 网络  (6项)   压缩 / 挂机 / 限流 / 状态查询"
               echo "  3) 性能  (6项)   视距 / 模拟距离 / 区块写入"
               echo "  4) 世界生成 (6项) 种子 / 地形 / 建筑 / 下界"
               echo "  5) 世界规则 (6项) 难度 / PVP / 飞行 / 出生点保护"
               echo "  6) 模式刷怪 (6项) 游戏模式 / 怪物动物村民"
               echo "  7) 权限安全 (6项) 白名单 / OP 等级 / 命令方块"
               echo "  8) 聊天外观 (5项) MOTD / 聊天过滤 / 广播"
               echo "  9) 数据包资源 (6项) 数据包 / 资源包"
               echo " 10) 远程管理 (7项) RCON / Query / JMX"
               echo "  0) 返回"
               echo
               ask "分类 (1-10): "; rd cc
               case "$cc" in
               1) prop_edit_cat "$f" 连接;;     2) prop_edit_cat "$f" 网络;;
               3) prop_edit_cat "$f" 性能;;     4) prop_edit_cat "$f" 世界生成;;
               5) prop_edit_cat "$f" 世界规则;; 6) prop_edit_cat "$f" 模式刷怪;;
               7) prop_edit_cat "$f" 权限安全;; 8) prop_edit_cat "$f" 聊天外观;;
               9) prop_edit_cat "$f" 数据包资源;; 10) prop_edit_cat "$f" 远程管理;;
               0|q|Q) break;;
               esac
           done;;
        2) prop_preset "$f";;
        3) echo; ask "key 名: "; rd kk
           [ -n "$kk" ] && {
               if [ "$kk" = "level-seed" ]; then prop_seed_menu "$f"; press; continue; fi
               echo -e "  当前: ${G}$(prop_get "$kk" "$f")${R}"
               ask "新值: "; rd vv
               [ -n "$vv" ] && { prop_set "$kk" "$vv" "$f"; say "已写入 $kk=$vv"; }
           }
           press;;
        4) echo; ask "key 名: "; rd kk; ask "值: "; rd vv
           [ -n "$kk" ] && { prop_set "$kk" "$vv" "$f"; say "已添加 $kk=$vv"; }
           press;;
        5) echo; ask "要删的 key 名: "; rd kk
           [ -n "$kk" ] && { prop_del "$kk" "$f"; say "已删除 $kk"; }
           press;;
        6) clear 2>/dev/null; echo; cat "$f" 2>/dev/null | sed 's/^/  /'; echo; press;;
        7) ${EDITOR:-nano} "$f" 2>/dev/null || vi "$f" 2>/dev/null || warn "没找到编辑器"; press;;
        8) local bk="$f.bak.$(date +%m%d-%H%M%S)"
           cp "$f" "$bk" && say "已备份: $bk"
           press;;
        9) icon_menu;;
        0|q|Q) return;;
        esac
    done
}

# ============================================================
#  后台启动: 启动后立刻回菜单
# ============================================================

# ---------- 后台启动: 从日志算进度 ----------
bg_pct_of() {   # 日志文件 -> "百分比|阶段名"
    local f="$1" line st name s2 e2 pct=4 stage="启动中" sub
    if [ ! -s "$f" ]; then echo "3|启动中"; return; fi
    if grep -q 'Done (' "$f" 2>/dev/null; then echo "100|已就绪"; return; fi
    while IFS= read -r line; do
        st=$(mc_stage_of "${line,,}")
        [ -n "$st" ] || continue
        IFS='|' read -r name s2 e2 <<< "$st"
        pct="$s2"; stage="$name"
        if [ "$name" = "生成出生点区块" ]; then
            sub=$(printf '%s' "$line" | grep -oE '[0-9]{1,3}%' | tail -1 | tr -d '%')
            if [ -n "$sub" ]; then
                pct=$(( 70 + sub * (97-70) / 100 ))
                [ "$pct" -gt 97 ] 2>/dev/null && pct=97
            fi
        fi
    done < <(tail -60 "$f" 2>/dev/null)
    echo "${pct}|${stage}"
}

start_bg() {
    local sdir="$1"
    [ ! -d "$sdir" ] && { err "服务器目录不存在"; press; return; }
    local pre; pre=$(java_pids 2>/dev/null | tr '\n' ' ')
    if [ -n "${pre// /}" ]; then
        warn "已有服务端在跑: $pre  先按 16 停止"
        press; return
    fi
    NOMENU=1
    cd "$sdir" || return
    [ -f server.jar ] || [ -f run.sh ] || { err "未找到 server.jar"; press; return; }
    if [ ! -f eula.txt ] || ! grep -q 'eula=true' eula.txt 2>/dev/null; then
        { warn "eula.txt 未同意, 服务端会立刻退出"; } 
        ask "现在自动写入 eula=true? (Y/n): "; rd _e
        case "$_e" in n|N) press; return;; esac
        echo "eula=true" > eula.txt
        say "已写入 eula.txt"
    fi
    local mem; mem=$(cat "${HIST_DIR}/${CUR}.mem" 2>/dev/null)
    [ -z "$mem" ] && mem=1536
    mkdir -p "$LOGDIR" 2>/dev/null
    local lf="${LOGDIR}/server-$(date +%m%d-%H%M%S).log"
    ln -sf "$lf" "${LOGDIR}/latest.log" 2>/dev/null
    : > "$lf"

    bk_autolock; sp_autobk_if_on
    title "后台启动 $CUR (内存 ${mem}MB)"

    # stdin 用 FIFO 保持打开: 直接 </dev/null 会让服务端读到 EOF 后自我关闭
    local fifo="${CONF_DIR}/stdin.fifo"
    rm -f "$fifo" 2>/dev/null; mkfifo "$fifo" 2>/dev/null
    if [ ! -p "$fifo" ]; then
        warn "无法创建 stdin 管道, 改用 /dev/null (服务端可能秒退)"
        fifo=/dev/null
    fi
    local holder=0
    if [ "$fifo" != "/dev/null" ]; then
        ( exec </dev/null >"$fifo" 2>/dev/null; sleep 2147483647 ) &
        holder=$!
        disown "$holder" 2>/dev/null || true
        printf '%s' "$holder" > "${CONF_DIR}/stdin.pid" 2>/dev/null
    fi

    if [ -f run.sh ]; then
        chmod +x run.sh
        nohup bash ./run.sh < "$fifo" >> "$lf" 2>&1 &
    else
        nohup java -Xms${mem}M -Xmx${mem}M -XX:+UseG1GC -XX:MaxMetaspaceSize=256m -jar server.jar nogui < "$fifo" >> "$lf" 2>&1 &
    fi
    local pid=$!
    disown "$pid" 2>/dev/null || true
    printf '%s' "$pid" > "${CONF_DIR}/server.pid" 2>/dev/null
    echo -e "  PID: ${C}$pid${R}   日志: ${C}$lf${R}"
    echo

    # launch 脚本可能再 fork 一层, 记下真正跑 java 的 PID
    ( sleep 2; local rp; rp=$(java_pids 2>/dev/null | head -1)
      [ -n "$rp" ] && printf '%s' "$rp" > "${CONF_DIR}/server.pid" 2>/dev/null ) &

    # ---------- 转圈 + 进度条等待 (高频刷新, 严格单行) ----------
    local cols; cols=$(term_cols)
    local bw=20
    [ "$cols" -lt 68 ] 2>/dev/null && bw=16
    [ "$cols" -lt 56 ] 2>/dev/null && bw=12
    [ "$cols" -lt 44 ] 2>/dev/null && bw=8
    [ "$cols" -lt 34 ] 2>/dev/null && bw=5
    # 固定占位: "  " + 转圈 + " " + [bar] + " " + "100%" + "  " + "(NNNs)"
    # 逐段核算: "  "2 + 转圈1 + " "1 + [bar]bw+2 + " "1 + "100%"4
    #            + "  "2 + 阶段名 + "  "2 + "(180s)"6
    local fixed=$(( 2 + 1 + 1 + bw + 2 + 1 + 4 + 2 + 2 + 6 ))
    local stagew=$(( cols - fixed ))
    [ "$stagew" -lt 4 ] 2>/dev/null && stagew=4

    local tick=0 pct=0 target=0 stage="启动中" dead=1 secs=0 lastparse=-1
    local tpct tstage tend est cap gap step
    local mt; mt=$(spin_tick)
    local maxtick; maxtick=$(max_ticks "$mt")   # 按帧间隔折算, 上限 180 秒
    local stg_last='' STG=''
    BAR_CACHE=()
    local ss; ss=$(date +%s)

    while [ "$tick" -lt "$maxtick" ]; do
        now_secs; secs=$(( NOW - ss ))
        # --- 每整秒: 解析日志拿目标百分比 (与刷新帧率解耦) ---
        if [ "$secs" -gt "$lastparse" ] 2>/dev/null; then
            IFS='|' read -r tpct tstage tend < <(bg_pct_of "$lf")
            [ -z "$tend" ] && tend=97
            [ -z "$tpct" ] && tpct=0
            [ -z "$tstage" ] && tstage="启动中"
            if [ "$tpct" -ge 100 ] 2>/dev/null; then
                target=100; stage="已就绪"
            else
                est=$(( secs * 97 / 90 ))
                cap=$tend
                [ "$est" -gt "$cap" ] 2>/dev/null && cap=$est
                [ "$cap" -gt 97 ] 2>/dev/null && cap=97
                target=$tpct
                [ "$target" -gt "$cap" ] 2>/dev/null && target=$cap
                # 保底: 不留原地, 至少缓慢爬
                [ "$target" -le "$pct" ] 2>/dev/null && target=$((pct + 1))
                [ "$target" -gt "$cap" ] 2>/dev/null && target=$cap
                stage="$tstage"
            fi
            lastparse=$secs
        fi
        # --- 每 tick: 平滑靠拢目标 (亚秒级爬升, 不再一秒一跳) ---
        if [ "$pct" -lt "$target" ] 2>/dev/null; then
            gap=$(( target - pct ))
            step=1
            [ "$gap" -gt 4 ] 2>/dev/null && step=$(( gap * 3 / 10 + 1 ))
            pct=$(( pct + step ))
            [ "$pct" -gt "$target" ] 2>/dev/null && pct=$target
        fi
        # --- 完成 ---
        if [ "$pct" -ge 100 ] 2>/dev/null; then
            printf "\r  ${G}✔${R} %s 100%%  ${G}%s${R}\033[K\n" \
                   "$(mc_bar 100 "$bw")" "$(wcut "已就绪" "$stagew")"
            break
        fi
        # --- 进程没了 ---
        if ! kill -0 "$pid" 2>/dev/null; then
            sleep 1
            kill -0 "$pid" 2>/dev/null || { dead=0; break; }
        fi
        # --- 渲染: 严格单行, 零 fork(除 sleep) ---
        now_secs; secs=$(( NOW - ss ))
        spin_frame "$tick"                                  # 写 $SP_CH
        bar_cached "$pct" "$bw"                             # 写 $BAR_STR
        [ "$stage" != "$stg_last" ] && { STG=$(wcut "$stage" "$stagew"); stg_last=$stage; }
        printf "\r  ${C}%b${R} %s ${Y}%3d%%${R}  %s  ${Y}(%ds)\033[K" \
               "$SP_CH" "$BAR_STR" "$pct" "$STG" "$secs"
        sleep "$mt"; tick=$((tick+1))
    done
    [ "$dead" -eq 0 ] && printf "\r\033[K"

    if grep -q 'Done (' "$lf" 2>/dev/null; then
        say "已就绪! 朋友可以连了"
        grep -oE '\[[0-9]{2}:[0-9]{2}:[0-9]{2}\].*Done \(.*\)' "$lf" 2>/dev/null \
            | tail -1 | cut -c1-88 | sed 's/^/  /'
        echo
        quick_addr
    elif [ "$dead" -eq 0 ]; then
        err "服务端进程已退出, 启动失败"
        echo
        mc_diagnose "$lf" 1 0
        echo
        echo -e "  ${Y}完整日志:${R} ${C}$lf${R}"
        echo -e "  ${Y}菜单 14 → 1 看末尾错误行${R}"
    else
        warn "已等待 ${max}s 仍未出现 Done"
        echo -e "  ${Y}服务端还在后台跑, 只是启动比较慢(模组多/首次生成地形)${R}"
        echo -e "  ${Y}菜单 14 → 2 实时跟踪进度${R}"
    fi
    echo
    if grep -q 'Done (' "$lf" 2>/dev/null; then
        echo -e "  ${Y}提示:${R}"
        echo -e "   ${C}已回到菜单${R}, 服务器继续在后台跑"
        echo -e "   ${C}14${R} 看日志 / 跟踪    ${C}16${R} 停止服务器    ${C}13${R} 联机地址"
    else
        echo -e "  ${Y}提示:${R} ${C}14 → 1${R} 看日志末尾, ${C}16${R} 可停止残留进程"
    fi
    # 服务端起来了就挂上守护 (看门狗 / 定时备份), 菜单 24 管理
    if [ -n "$(java_pids 2>/dev/null | tr -d '\n ')" ]; then
        guard_start_if_on "$sdir"
        guard_alive && echo -e "  ${G}守护已挂上${R} ${Y}(崩了自动拉起 / 定时备份 → 菜单 24)${R}"
    fi
    press
}

# 后台状态一行
bg_status_line() {
    local pid; pid=$(cat "${CONF_DIR}/server.pid" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo -e "  状态  : ${G}${B}运行中${R} ${Y}(后台 PID $pid)${R}"
    elif [ -n "$(java_pids 2>/dev/null | tr '\n' ' ' | tr -d ' ')" ]; then
        echo -e "  状态  : ${G}${B}运行中${R}"
    fi
}


# 开服前按需拉起 frpc
frp_boot_if_needed() {
    frp_load
    [ "$FRP_AUTOSTART" = 1 ] || return 0
    frp_sync 1 >/dev/null 2>&1
    [ -x "$FRP_BIN" ] || return 0
    local n; n=$(frp_cnt)
    [ "$n" -eq 0 ] && return 0
    local i cnt=0
    for ((i=1;i<=n;i++)); do
        frp_parse "$i" || continue
        [ "$N_ON" = 1 ] || continue
        if frp_npid "$i" >/dev/null; then
            echo -e "  ${G}${N_NAME} 已在跑${R}"
            continue
        fi
        local f; f=$(frp_gen "$i")
        GODEBUG=netdns=go nohup "$FRP_BIN" -c "$f" >> "$(frp_logf "$i")" 2>&1 &
        echo "$!" > "$(frp_pidf "$i")"
        sleep 2
        if frp_npid "$i" >/dev/null; then
            echo -e "  ${G}${N_NAME} 已启动${R} -> ${C}${N_ADDR}:${N_REMOTE}${R}"
        else
            echo -e "  ${Y}${N_NAME} 启动失败${R} (日志: $(frp_logf "$i"))"
        fi
        cnt=$((cnt+1))
    done
    [ "$cnt" -gt 0 ] && sleep 1
    return 0
}

# 启动方式: 前台(可输命令) / 后台(回菜单)
start_choose() {
    local sdir="$1"
    while true; do
        clear 2>/dev/null
        title "启动 $CUR"
        echo "   1) 前台启动  (可敲 /stop /op, Ctrl+C 停止)"
        echo "      ${Y}启动期间会占着这个窗口, 看不到菜单${R}"
        echo
        echo "   2) 后台启动  (启动后立刻回菜单) ${C}← 推荐${R}"
        echo "      ${Y}适合挂机开服; 菜单14看日志, 菜单16停止${R}"
        echo
        echo "   0) 返回"
        echo
        ask "选择: "; rd k
        case "$k" in
        1) frp_boot_if_needed; start_server "$sdir"; return;;
        2) frp_boot_if_needed; start_bg "$sdir"; return;;
        0|q|Q) return;;
        esac
    done
}

# ============================================================
# ============================================================
#  FRP 多节点穿透 (菜单 23)
#  多个地域节点 -> 同一台服务器, 国内外各连各的
# ============================================================
FRP_DIR="${CONF_DIR}/frp"
FRP_BIN="$FRP_DIR/frpc"
FRP_NODES="$FRP_DIR/nodes"
FRP_LOGD="$FRP_DIR/logs"
FRP_SET="$FRP_DIR/settings"
FRP_VER_DEFAULT="v0.62.1"
FRP_AUTOSTART=0
FRP_AUTOSYNC=1
FRP_LOCAL_DEFAULT="25565"

frp_load() {
    mkdir -p "$FRP_DIR" "$FRP_LOGD" 2>/dev/null
    [ -f "$FRP_SET" ] && source "$FRP_SET" 2>/dev/null
}
frp_set_auto() {
    mkdir -p "$FRP_DIR" 2>/dev/null
    { echo "FRP_AUTOSTART=$FRP_AUTOSTART"; echo "FRP_AUTOSYNC=$FRP_AUTOSYNC"; } > "$FRP_SET"
}

frp_cnt() { if [ -f "$FRP_NODES" ]; then grep -cve '^[[:space:]]*$' "$FRP_NODES"; else echo 0; fi; }

# 解析第 N 行到 N_* 变量 (字段用 | 分隔)
frp_parse() {
    local l; l=$(sed -n "${1}p" "$FRP_NODES" 2>/dev/null)
    [ -z "$l" ] && return 1
    IFS='|' read -r N_NAME N_ADDR N_PORT N_AUTH N_TOK N_USER N_REMOTE N_LOCAL N_ON <<< "$l"
    [ -z "$N_PORT" ] && N_PORT=7000
    [ -z "$N_AUTH" ] && N_AUTH=token
    [ -z "$N_LOCAL" ] && N_LOCAL="$FRP_LOCAL_DEFAULT"
    [ -z "$N_ON" ] && N_ON=1
    # frtt 里有同名配置 -> 以文件为准, 画面显示的就是真正生效的地址
    local uc
    if uc=$(frp_userconf "$N_NAME"); then
        frp_uc_parse "$uc"
        [ -n "$UC_ADDR" ]   && N_ADDR="$UC_ADDR"
        [ -n "$UC_PORT" ]   && N_PORT="$UC_PORT"
        [ -n "$UC_REMOTE" ] && N_REMOTE="$UC_REMOTE"
        [ -n "$UC_LOCAL" ]  && N_LOCAL="$UC_LOCAL"
    fi
    return 0
}

frp_write_line() {   # 序号 内容
    local n="$1" line="$2" tmp; tmp=$(mktemp 2>/dev/null || echo "$FRP_DIR/.tmp")
    awk -v n="$n" -v l="$line" 'NR==n{print l; next}{print}' "$FRP_NODES" > "$tmp" 2>/dev/null
    mv -f "$tmp" "$FRP_NODES" 2>/dev/null
}
frp_del_line() {
    local n="$1" tmp; tmp=$(mktemp 2>/dev/null || echo "$FRP_DIR/.tmp")
    awk -v n="$n" 'NR!=n' "$FRP_NODES" > "$tmp" 2>/dev/null
    mv -f "$tmp" "$FRP_NODES" 2>/dev/null
}

# frpc >= 0.50 用 toml
frp_need_toml() {
    [ -x "$FRP_BIN" ] || return 0
    local v; v=$("$FRP_BIN" -v 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
    [ -z "$v" ] && return 0
    local maj=${v%%.*} min=${v##*.}
    [ "$maj" -gt 0 ] && return 0
    [ "$min" -ge 50 ] && return 0
    return 1
}
frp_conf_of() { if frp_need_toml; then echo "$FRP_DIR/n${1}.toml"; else echo "$FRP_DIR/n${1}.ini"; fi; }
frp_pidf()    { echo "$FRP_DIR/n${1}.pid"; }
frp_logf()    { echo "$FRP_LOGD/n${1}.log"; }

frp_gen_force() {   # 按 nodes 参数生成配置
    local i="$1"; frp_parse "$i" || return 1
    local f; f=$(frp_conf_of "$i")
    if frp_need_toml; then
        { echo "serverAddr = \"$N_ADDR\""
          echo "serverPort = $N_PORT"
          if [ "$N_AUTH" = "user" ]; then
              echo "user = \"$N_USER\""; echo "meta_token = \"$N_TOK\""
          else
              [ -n "$N_TOK" ] && echo "auth.token = \"$N_TOK\""
          fi
          echo
          echo "[[proxies]]"
          echo "name = \"mc\""
          echo "type = \"tcp\""
          echo "localIP = \"127.0.0.1\""
          echo "localPort = $N_LOCAL"
          echo "remotePort = $N_REMOTE"
        } > "$f"
    else
        { echo "[common]"
          echo "server_addr = $N_ADDR"
          echo "server_port = $N_PORT"
          if [ "$N_AUTH" = "user" ]; then
              echo "user = $N_USER"; echo "meta_token = $N_TOK"
          else
              [ -n "$N_TOK" ] && echo "token = $N_TOK"
          fi
          echo
          echo "[mc]"
          echo "type = tcp"
          echo "local_ip = 127.0.0.1"
          echo "local_port = $N_LOCAL"
          echo "remote_port = $N_REMOTE"
        } > "$f"
    fi
    echo "$f"
}

# ---- frtt 目录: 用户自己放的节点配置, 文件名 = 节点名 ----
frp_userdir() {
    if [ -n "$ROOT" ] && [ -d "$ROOT" ]; then echo "$ROOT/frtt"; else echo "$FRP_DIR/userconf"; fi
}
frp_mkuser() { local d; d=$(frp_userdir); mkdir -p "$d" 2>/dev/null; echo "$d"; }

# 按节点名找 frtt 里的配置文件 (不含扩展名要完全一致)
frp_userconf() {
    local d nm="$1" f
    d=$(frp_userdir); [ -d "$d" ] || return 1
    [ -z "$nm" ] && return 1
    for f in "$d/$nm.toml" "$d/$nm.ini" "$d/$nm.frp" "$d/$nm.conf" "$d/$nm.cfg" "$d/$nm.txt" "$d/$nm"; do
        [ -f "$f" ] && { echo "$f"; return 0; }
    done
    return 1
}

# 从配置文件里读字段 (同时认 toml 和 ini 写法)
frp_uc_get() {
    local f="$1" k1="$2" k2="$3"
    sed -nE "s/^[[:space:]]*(${k1}|${k2})[[:space:]]*[=:][[:space:]]*\"?([^\"#]+?)\"?[[:space:]]*$/\2/p" "$f" 2>/dev/null \
        | head -1 | tr -d '"' | sed 's/[[:space:]]*$//'
}
frp_uc_parse() {   # 文件 -> UC_ADDR UC_PORT UC_REMOTE UC_LOCAL UC_AUTH UC_TOK UC_USER
    local f="$1"
    UC_ADDR=$(frp_uc_get "$f" serverAddr server_addr)
    UC_PORT=$(frp_uc_get "$f" serverPort server_port);   [ -z "$UC_PORT" ] && UC_PORT=7000
    UC_REMOTE=$(frp_uc_get "$f" remotePort remote_port); [ -z "$UC_REMOTE" ] && UC_REMOTE=25565
    UC_LOCAL=$(frp_uc_get "$f" localPort local_port);    [ -z "$UC_LOCAL" ] && UC_LOCAL="$FRP_LOCAL_DEFAULT"
    UC_TOK=$(frp_uc_get "$f" 'auth\.token' token)
    UC_USER=$(frp_uc_get "$f" '^user' 'user')
    if [ -n "$UC_USER" ] && [ "$UC_USER" != "$UC_ADDR" ]; then UC_AUTH=user; else UC_AUTH=token; fi
    return 0
}

# 导出当前节点的配置到 frtt, 方便你自己改
frp_export_one() {
    local i="$1"; frp_parse "$i" || return 1
    local d; d=$(frp_mkuser)
    local ext; if frp_need_toml; then ext=toml; else ext=ini; fi
    local dst="$d/$N_NAME.$ext"
    local src
    src=$(frp_userconf "$N_NAME") && { echo -e "  ${Y}frtt 里已有一份, 不覆盖:${R} $src"; return 0; }
    # 强制生成一份到 FRP_DIR, 再拷过去
    local gen; gen=$(frp_gen_force "$i") || return 1
    cp -f "$gen" "$dst" 2>/dev/null && {
        say "已导出: $dst"
        echo -e "  ${Y}改完这个文件, 下次启动就用它了 (文件名别改)${R}"
    } || err "导出失败"
    return 0
}
frp_export_menu() {
    local n; n=$(frp_cnt)
    [ "$n" -eq 0 ] && { warn "没有节点"; press; return; }
    frp_list
    echo
    ask "导出哪个 (序号, all=全部): "; rd c
    local i
    if [ "$c" = "all" ]; then
        for ((i=1;i<=n;i++)); do frp_export_one "$i"; done
    else
        case "$c" in ''|*[!0-9]*) ;; *) frp_export_one "$c";; esac
    fi
    press
}

# 扫描 frtt 里还没被用的配置文件
frp_scan_user() {
    local d; d=$(frp_userdir); [ -d "$d" ] || return 1
    find "$d" -maxdepth 1 -type f \( -name '*.toml' -o -name '*.ini' -o -name '*.frp' \
         -o -name '*.conf' -o -name '*.cfg' -o -name '*.txt' \) 2>/dev/null | sort
    return 0
}

frp_import_menu() {
    local d; d=$(frp_mkuser)
    echo -e "  ${C}frtt 目录:${R} $d"
    echo -e "  ${Y}文件名(不带扩展名) 要和节点名完全一样, 例如 北京.toml${R}"
    echo
    local list; list=$(frp_scan_user)
    if [ -z "$list" ]; then
        warn "frtt 里还没有配置文件"
        echo -e "  ${Y}支持的后缀: .toml .ini .frp .conf .cfg .txt${R}"
        echo -e "  ${Y}也可以先用菜单 13 导出一份当模板${R}"
        press; return
    fi
    local i=1 f nm nn j hit
    local -a FS
    while IFS= read -r f; do [ -n "$f" ] && FS+=("$f"); done <<< "$list"
    echo -e "  ${B}序号  文件名          解析出的地址              状态${R}"
    for f in "${FS[@]}"; do
        nm=$(basename "$f"); nm=${nm%.*}
        frp_uc_parse "$f"
        local u_addr="$UC_ADDR" u_port="$UC_PORT" u_rem="$UC_REMOTE"               u_loc="$UC_LOCAL" u_tok="$UC_TOK" u_user="$UC_USER" u_auth="$UC_AUTH"
        hit="新"
        nn=$(frp_cnt); for ((j=1;j<=nn;j++)); do
            frp_parse "$j"; [ "$N_NAME" = "$nm" ] && hit="${G}已在节点里${R}"
        done
        printf "   %-4s %-14s %-24s %s\n" "$i" "$nm" "${u_addr}:${u_rem}" "$(echo -e "$hit")"
        i=$((i+1))
    done
    echo
    ask "导入哪个 (序号, all=全部): "; rd c
    local toadd
    if [ "$c" = "all" ]; then toadd=$(seq 1 "${#FS[@]}"); else toadd="$c"; fi
    local k
    for k in $toadd; do
        case "$k" in ''|*[!0-9]*) continue;; esac
        [ "$k" -ge 1 ] && [ "$k" -le "${#FS[@]}" ] || continue
        f="${FS[$((k-1))]}"
        nm=$(basename "$f"); nm=${nm%.*}
        frp_uc_parse "$f"
        local u_addr="$UC_ADDR" u_port="$UC_PORT" u_rem="$UC_REMOTE"               u_loc="$UC_LOCAL" u_tok="$UC_TOK" u_user="$UC_USER" u_auth="$UC_AUTH"
        # 已存在就跳过 (frp_parse 会改 UC_*, 所以先存一份)
        local dup=0; nn=$(frp_cnt)
        for ((j=1;j<=nn;j++)); do frp_parse "$j"; [ "$N_NAME" = "$nm" ] && dup=1; done
        if [ "$dup" = 1 ]; then warn "$nm 已经在节点里了, 跳过"; continue; fi
        echo "${nm}|${u_addr}|${u_port}|${u_auth}|${u_tok}|${u_user}|${u_rem}|${u_loc}|1" >> "$FRP_NODES"
        say "已导入 ${nm}  (${u_addr}:${u_rem})"
    done
    press
}

frp_gen() {    # 序号 -> 实际使用的配置路径 (frtt 优先)
    local i="$1"; frp_parse "$i" || return 1
    local uc
    if uc=$(frp_userconf "$N_NAME"); then
        echo "$uc"; return 0
    fi
    frp_gen_force "$i"
}

frp_npid() {   # 序号 -> 活着的 PID
    local pf; pf=$(frp_pidf "$1")
    [ -f "$pf" ] || return 1
    local p; p=$(cat "$pf" 2>/dev/null)
    [ -z "$p" ] && return 1
    kill -0 "$p" 2>/dev/null || return 1
    echo "$p"
}

frp_start_one() {   # 序号
    local i="$1"; frp_parse "$i" || return 1
    if [ ! -x "$FRP_BIN" ]; then warn "还没装 frpc (菜单 23 -> 10)"; press; return 1; fi
    local p; if p=$(frp_npid "$i"); then warn "$N_NAME 已经在跑 (PID $p)"; return 0; fi
    local f; f=$(frp_gen "$i")
    local lf; lf=$(frp_logf "$i")
    GODEBUG=netdns=go nohup "$FRP_BIN" -c "$f" >> "$lf" 2>&1 &
    local np=$!
    echo "$np" > "$(frp_pidf "$i")"
    sleep 3
    if kill -0 "$np" 2>/dev/null; then
        say "$N_NAME 已启动 -> ${N_ADDR}:${N_REMOTE}"
        echo -e "    朋友填: ${G}${N_ADDR}:${N_REMOTE}${R}"
    else
        err "$N_NAME 启动失败:"
        tail -12 "$lf" 2>/dev/null | sed 's/^/      /'
        echo -e "    ${Y}常见问题: 地址/端口填错、token 不对、公网端口被占用${R}"
    fi
}

frp_stop_one() {
    local i="$1"; frp_parse "$i" || return 1
    local p; if ! p=$(frp_npid "$i"); then warn "$N_NAME 没在跑"; return 0; fi
    kill "$p" 2>/dev/null; sleep 2
    kill -0 "$p" 2>/dev/null && kill -9 "$p" 2>/dev/null
    rm -f "$(frp_pidf "$i")" 2>/dev/null
    say "$N_NAME 已停止"
}

frp_start_all() {
    local n; n=$(frp_cnt)
    [ "$n" -eq 0 ] && { warn "还没有节点, 先添加"; press; return; }
    local i on=0
    for ((i=1;i<=n;i++)); do
        frp_parse "$i" || continue
        [ "$N_ON" = 1 ] || continue
        frp_start_one "$i"
        on=$((on+1))
    done
    [ "$on" -eq 0 ] && { warn "没有已启用的节点"; press; return; }
    press
}

frp_stop_all() {
    local n; n=$(frp_cnt); local i hit=0
    for ((i=1;i<=n;i++)); do
        if frp_npid "$i" >/dev/null; then frp_parse "$i"; frp_stop_one "$i"; hit=1; fi
    done
    [ "$hit" = 0 ] && warn "没有在跑的节点"
    press
}

# 连通性测试
frp_test_one() {
    local i="$1"; frp_parse "$i" || return 1
    echo -e "  ${C}测试 ${N_NAME}  ${N_ADDR}:${N_REMOTE} ...${R}"
    python3 - "$N_ADDR" "$N_REMOTE" <<'PYEOF' 2>/dev/null
import socket,sys
h,p=sys.argv[1],int(sys.argv[2])
try:
    s=socket.create_connection((h,p),timeout=8); s.close()
    print("    [+] 通了! 这个节点能连上")
except Exception as e:
    print("    [x] 连不上:",e)
    print("       -> frpc 跑起来了吗")
    print("       -> MC 服务端开着吗 (菜单3)")
    print("       -> 公网端口对不对 / 防火墙放行了吗")
PYEOF
}
frp_test_menu() {
    local n; n=$(frp_cnt)
    [ "$n" -eq 0 ] && { warn "没有节点"; press; return; }
    frp_list
    echo
    ask "测哪个 (序号, all=全部): "; rd c
    if [ "$c" = "all" ]; then
        local i; for ((i=1;i<=n;i++)); do frp_test_one "$i"; done
    else
        case "$c" in ''|*[!0-9]*) ;; *) frp_test_one "$c";; esac
    fi
    echo
    echo -e "  ${Y}端口通 = 隧道成了; 还要 MC 在跑, 朋友才进得来${R}"
    press
}

# 列表
frp_list() {
    local n; n=$(frp_cnt)
    if [ "$n" -eq 0 ]; then
        echo -e "  ${Y}还没有节点${R}"
        echo -e "  ${Y}添加后, 不同地区的朋友可以各自连最近的节点${R}"
        return
    fi
    local i
    echo -e "  ${B}序号  节点        状态      朋友填的地址${R}"
    for ((i=1;i<=n;i++)); do
        frp_parse "$i" || continue
        local st
        if frp_npid "$i" >/dev/null; then st="${G}运行中${R}"
        elif [ "$N_ON" = 1 ]; then st="${Y}已启用${R}"
        else st="未启用"; fi
        if frp_userconf "$N_NAME" >/dev/null; then st="${st} ${C}[frtt]${R}"; fi
        printf "   %-4s %-11s %-26s %s\n" "$i" "$N_NAME" "$(echo -e "$st")" "${N_ADDR}:${N_REMOTE}"
    done
}

# 添加节点
frp_add() {
    echo -e "  ${Y}在服务商后台创建「TCP 隧道」, 页面上会给你下面这些${R}"
    echo
    echo -e "  ${B}快捷取名 (直接回车也行):${R}"
    echo "   1) 北京  2) 中国香港  3) 洛杉矶  4) 凉州  5) 自定义"
    ask "节点名 (1-5 或自己打): "; rd nm
    case "$nm" in
        1) nm="北京";; 2) nm="中国香港";; 3) nm="洛杉矶";; 4) nm="凉州";;
        5) nm="";;
        *) ;;
    esac
    [ -z "$nm" ] && { ask "节点名: "; rd nm; }
    [ -z "$nm" ] && nm="节点"

    local addr port auth tok user remote lport on
    ask "服务器地址 (域名或IP): "; rd addr
    [ -z "$addr" ] && { err "地址不能为空"; press; return; }
    ask "服务器端口 [7000]: "; rd port; [ -z "$port" ] && port=7000
    echo "   鉴权: 1) token/密钥   2) user+密钥 (樱花FRP 那种)"
    ask "选择 (1/2): "; rd auth
    if [ "$auth" = "2" ]; then
        auth=user
        ask "user (访问密钥): "; rd user
        ask "meta_token (隧道密钥): "; rd tok
    else
        auth=token; user=""
        ask "token (可留空): "; rd tok
    fi
    ask "公网端口 (朋友连的): "; rd remote
    [ -z "$remote" ] && remote=25565
    ask "本机 MC 端口 [${FRP_LOCAL_DEFAULT}]: "; rd lport
    [ -z "$lport" ] && lport="$FRP_LOCAL_DEFAULT"
    on=1

    mkdir -p "$FRP_DIR"
    echo "${nm}|${addr}|${port}|${auth}|${tok}|${user}|${remote}|${lport}|${on}" >> "$FRP_NODES"
    local i; i=$(frp_cnt)
    say "已添加 ${nm}  (第 $i 号)"
    echo -e "  朋友填: ${G}${addr}:${remote}${R}"
    echo
    ask "顺便导出一份到 frtt 方便以后改? (y/n): "; rd v
    [ "$v" = "y" ] && frp_export_one "$i"
    press
}

# 编辑节点
frp_edit() {
    local n; n=$(frp_cnt)
    [ "$n" -eq 0 ] && { warn "没有节点"; press; return; }
    frp_list
    ask "编辑哪个 (序号): "; rd i
    case "$i" in ''|*[!0-9]*) return;; esac
    [ "$i" -lt 1 ] || [ "$i" -gt "$n" ] && { warn "没这个序号"; press; return; }
    frp_parse "$i"
    local uc
    if uc=$(frp_userconf "$N_NAME"); then
        echo
        warn "${N_NAME} 用的是 frtt 里的配置文件, 在这里改没用"
        echo -e "  ${C}请直接改这个文件:${R}"
        echo -e "     ${G}$uc${R}"
        echo
        echo -e "  ${Y}改完不用重新导入, 下次启动自动生效${R}"
        echo -e "  ${Y}想让脚本重新接管, 把那个文件删掉${R}"
        press; return
    fi
    echo -e "  ${C}直接回车 = 保持原样${R}"
    local v
    ask "节点名 [${N_NAME}]: "; rd v; [ -n "$v" ] && N_NAME="$v"
    ask "地址 [${N_ADDR}]: "; rd v; [ -n "$v" ] && N_ADDR="$v"
    ask "端口 [${N_PORT}]: "; rd v; [ -n "$v" ] && N_PORT="$v"
    ask "公网端口 [${N_REMOTE}]: "; rd v; [ -n "$v" ] && N_REMOTE="$v"
    ask "本机端口 [${N_LOCAL}]: "; rd v; [ -n "$v" ] && N_LOCAL="$v"
    ask "token [${N_TOK}]: "; rd v; [ -n "$v" ] && N_TOK="$v"
    frp_write_line "$i" "${N_NAME}|${N_ADDR}|${N_PORT}|${N_AUTH}|${N_TOK}|${N_USER}|${N_REMOTE}|${N_LOCAL}|${N_ON}"
    say "已保存"
    if frp_npid "$i" >/dev/null; then
        ask "配置变了, 重启这个节点? (y/n): "; rd v
        [ "$v" = "y" ] && { frp_stop_one "$i"; frp_start_one "$i"; }
    fi
    press
}

# 启/停用切换
frp_toggle() {
    local n; n=$(frp_cnt)
    [ "$n" -eq 0 ] && { warn "没有节点"; press; return; }
    frp_list
    ask "切换哪个 (序号): "; rd i
    case "$i" in ''|*[!0-9]*) return;; esac
    frp_parse "$i" || return
    if [ "$N_ON" = 1 ]; then N_ON=0; else N_ON=1; fi
    frp_write_line "$i" "${N_NAME}|${N_ADDR}|${N_PORT}|${N_AUTH}|${N_TOK}|${N_USER}|${N_REMOTE}|${N_LOCAL}|${N_ON}"
    say "${N_NAME} 已设为 $([ "$N_ON" = 1 ] && echo 启用 || echo 停用)"
    press
}

# 把序号 src 的所有附属文件改名为 dst (序号会因删除而前移)
frp_movefiles() {
    local src="$1" dst="$2" e
    for e in toml ini; do
        [ -f "$FRP_DIR/n${src}.${e}" ] && mv -f "$FRP_DIR/n${src}.${e}" "$FRP_DIR/n${dst}.${e}" 2>/dev/null
    done
    [ -f "$FRP_DIR/n${src}.pid" ] && mv -f "$FRP_DIR/n${src}.pid" "$FRP_DIR/n${dst}.pid" 2>/dev/null
    [ -f "$FRP_LOGD/n${src}.log" ] && mv -f "$FRP_LOGD/n${src}.log" "$FRP_LOGD/n${dst}.log" 2>/dev/null
    return 0
}

frp_del() {
    local n; n=$(frp_cnt)
    [ "$n" -eq 0 ] && { warn "没有节点"; press; return; }
    frp_list
    ask "删除哪个 (序号): "; rd i
    case "$i" in ''|*[!0-9]*) return;; esac
    [ "$i" -ge 1 ] && [ "$i" -le "$n" ] || { warn "没这个序号"; press; return; }
    frp_parse "$i" || return
    frp_npid "$i" >/dev/null && frp_stop_one "$i"
    rm -f "$FRP_DIR/n${i}.pid" "$FRP_DIR/n${i}.toml" "$FRP_DIR/n${i}.ini" "$FRP_LOGD/n${i}.log" 2>/dev/null
    frp_del_line "$i"
    # 后面的节点序号前移, 文件跟着改名, 避免错位
    local j
    for ((j=i+1;j<=n;j++)); do frp_movefiles "$j" "$((j-1))"; done
    rm -f "$FRP_DIR/n${n}.pid" "$FRP_DIR/n${n}.toml" "$FRP_DIR/n${n}.ini" "$FRP_LOGD/n${n}.log" 2>/dev/null
    say "已删除 ${N_NAME}"
    press
}

# 本地打包包目录: 网速下不动时, 把现成的包丢这里就能直接用
#   $ROOT/bundle/          放 frp_xxx_linux_arm64.tar.gz 或直接放 frpc
#   ~/bundle/              同上
#   脚本同目录/bundle/     同上
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
: "${SCRIPT_DIR:=$HOME}"

# 在本地打包包里找 frpc: 优先现成二进制, 其次 tar.gz
# 找到就输出文件路径并 return 0
frp_from_bundle() {
    local d f arch; arch=$(uname -m)
    # 动态拼目录: ROOT 可能在运行中被改过, 别用启动时那份快照
    local dirs=("${ROOT}/bundle" "${HOME}/bundle" "${HOME}/.mcserv/bundle" "${SCRIPT_DIR}/bundle")
    for d in "${dirs[@]}"; do
        [ -d "$d" ] || continue
        # ① 现成二进制
        for f in "$d"/frpc "$d"/frpc_* "$d"/frp_*/frpc; do
            if [ -f "$f" ] && [ -x "$f" ] || { [ -f "$f" ] && chmod +x "$f" 2>/dev/null; [ -x "$f" ]; }; then
                printf '%s' "$f"; return 0
            fi
        done
        # ② 打包的 tar.gz (按架构优先)
        for f in "$d"/frp_*linux_*"$arch"*.tar.gz "$d"/frp_*linux_arm64*.tar.gz "$d"/frp_*linux_*.tar.gz; do
            [ -f "$f" ] || continue
            printf '%s' "$f"; return 0
        done
    done
    return 1
}

frp_unpack() {   # $1=包路径(二进制或tar.gz) -> 装到 $FRP_BIN
    local src="$1"
    mkdir -p "$FRP_DIR"
    case "$src" in
        *.tar.gz|*.tgz)
            tar -xzf "$src" -C "$FRP_DIR" 2>/dev/null || return 1
            local found; found=$(find "$FRP_DIR" -maxdepth 3 -name frpc -type f 2>/dev/null | head -1)
            [ -z "$found" ] && return 1
            cp -f "$found" "$FRP_BIN" || return 1
            ;;
        *)
            cp -f "$src" "$FRP_BIN" || return 1
            ;;
    esac
    chmod +x "$FRP_BIN"
    return 0
}

frp_verify() {   # 装完自检: 能跑就报版本, 不能跑给提示
    if "$FRP_BIN" -v >/dev/null 2>&1; then
        say "frpc 装好: $("$FRP_BIN" -v 2>&1 | head -1)"
        return 0
    fi
    err "装上了但跑不起来"
    echo -e "  ${Y}Termux 常见: 二进制与 Bionic 不兼容${R}"
    echo -e "  ${Y}可试 pkg install proot-distro 在容器里跑${R}"
    echo -e "  ${Y}或换别的版本丢进打包包目录:${R} ${ROOT}/bundle"
    return 1
}

# 手动从本地打包包装 frpc (断网 / 限速时用, 完全不走网络)
frp_install_local() {
    title "用本地打包包装 frpc"
    echo -e "  ${Y}把下面任意一样丢进这些目录:${R}"
    local d
    for d in "${ROOT}/bundle" "${HOME}/bundle" "${HOME}/.mcserv/bundle"; do
        echo -e "     ${C}$d${R}"
    done
    echo
    echo -e "     ${C}frp_*_linux_arm64.tar.gz${R}  ${Y}(官方 release 包, 手机一般 arm64)${R}"
    echo -e "     ${C}frpc${R}                     ${Y}(解压出来的二进制, 直接放)${R}"
    echo
    local bp
    if ! bp=$(frp_from_bundle); then
        err "没找到打包包"
        echo -e "  ${Y}也可用菜单 10 走网络下载${R}"
        return 1
    fi
    echo -e "  ${C}找到:${R} $bp"
    echo -ne "  ${Y}正在安装...${R}"
    if frp_unpack "$bp"; then
        printf "\r\033[K"
        say "已用本地打包包装好 (没走网络)"
        frp_verify
        return 0
    fi
    printf "\r\033[K"
    err "解不开或里面没有 frpc"
    return 1
}

frp_download() {
    local arch; arch=$(uname -m)
    case "$arch" in
        aarch64|arm64)  A=arm64;;
        armv7l|arm*)    A=arm;;
        x86_64|amd64)   A=amd64;;
        i686|i386)      A=386;;
        *) warn "认不出的架构 $arch, 按 arm64 试"; A=arm64;;
    esac
    local ver="$FRP_VER_DEFAULT" v="${FRP_VER_DEFAULT#v}"
    local name="frp_${v}_linux_${A}"
    local urls=(
        "https://github.com/fatedier/frp/releases/download/${ver}/${name}.tar.gz"
        "https://ghproxy.net/https://github.com/fatedier/frp/releases/download/${ver}/${name}.tar.gz"
        "https://gh-proxy.com/https://github.com/fatedier/frp/releases/download/${ver}/${name}.tar.gz"
        "https://mirror.ghproxy.com/https://github.com/fatedier/frp/releases/download/${ver}/${name}.tar.gz"
    )
    mkdir -p "$FRP_DIR"
    # 依赖自动补齐: 没 curl 就先装, 不然下面全是"下载失败"的假象
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "  ${Y}[!]${R} 检测到缺少 ${C}curl${R}"
        echo -e "      ${Y}正在自动安装...${R}"
        if _pkg_do curl; then
            echo -e "      ${G}✔${R} curl 就绪, 开始下载"
        else
            err "curl 装不上, 无法联网下载; 可用菜单里的本地打包包装"
            return 1
        fi
    fi
    # 缺解压工具也补一下, 否则下完了解不开
    command -v tar >/dev/null 2>&1 || _pkg_do tar >/dev/null 2>&1
    local tmp="$FRP_DIR/dl.tar.gz" ok="" why=""
    for u in "${urls[@]}"; do
        [ -z "$u" ] && continue
        echo -e "  ${C}尝试:${R} ${u##*/}"
        rm -f "$tmp" 2>/dev/null
        # speed-limit/16K + speed-time 15: 15 秒低于 16KB/s 判定卡死, 立刻换源
        # 不加这个, 一个死源能干等到 180 秒超时, 看着像"卡住了"
        if curl -fsSL --connect-timeout 10 --max-time 180 \
             --speed-limit 16384 --speed-time 15 \
             "$u" -o "$tmp" 2>/dev/null; then
            if [ -s "$tmp" ]; then ok="$u"; break; fi
            why="空文件"
        else
            case "$?" in
                28) why="超时/速度过低" ;;
                22) why="源返回 4xx/5xx" ;;
                *)  why="连接失败" ;;
            esac
        fi
        echo -e "      ${RD}✘${R} ${why}, 自动切换下一个源..."
    done

    # ---------- 网速下不动 -> 用本地打包好的文件 ----------
    if [ -z "$ok" ]; then
        rm -f "$tmp" 2>/dev/null
        warn "网络下载失败, 改从本地打包包找"
        echo
        local bp
        if bp=$(frp_from_bundle); then
            echo -e "  ${C}找到打包包:${R} $bp"
            echo -ne "  ${Y}正在安装...${R}"
            if frp_unpack "$bp"; then
                printf "\r\033[K"
                say "已用本地打包包装好 (没走网络)"
                frp_verify
                press; return 0
            fi
            printf "\r\033[K"
            err "这个包解不开/里面没有 frpc"
        else
            echo -e "  ${Y}打包包目录里也没有:${R}"
            for d in "${ROOT}/bundle" "${HOME}/bundle" "${HOME}/.mcserv/bundle"; do
                echo -e "     ${C}$d${R}"
            done
            echo
            echo -e "  ${Y}把这两样任意一样丢进去就行:${R}"
            echo -e "     ${C}frp_${v}_linux_${A}.tar.gz${R}  ${Y}(官方 release 包)${R}"
            echo -e "     ${C}frpc${R}                      ${Y}(解压出来的二进制)${R}"
            echo
            echo -e "  ${Y}或者手动下:${R} ${urls[0]}"
            echo -e "  ${Y}解压后把 frpc 放:${R} $FRP_BIN"
        fi
        press; return 1
    fi
    # ---------- 下载成功: 顺手存一份到打包包目录, 下次断网也能装 ----------
    tar -xzf "$tmp" -C "$FRP_DIR" 2>/dev/null
    local found; found=$(find "$FRP_DIR" -maxdepth 2 -name frpc -type f 2>/dev/null | head -1)
    if [ -z "$found" ]; then err "包里没 frpc"; rm -f "$tmp"; press; return 1; fi
    cp -f "$found" "$FRP_BIN"; chmod +x "$FRP_BIN"
    # 先留一份到打包包目录(下次断网/限速也能装), 再删临时文件
    mkdir -p "${ROOT}/bundle" 2>/dev/null
    cp -f "$tmp" "${ROOT}/bundle/${name}.tar.gz" 2>/dev/null \
        && echo -e "  ${Y}(已存一份到打包包目录, 下次可离线装)${R}"
    rm -f "$tmp" 2>/dev/null; rm -rf "$FRP_DIR/${name}" 2>/dev/null
    echo
    frp_verify
    press
}

frp_log_menu() {
    local n; n=$(frp_cnt)
    [ "$n" -eq 0 ] && { warn "没有节点"; press; return; }
    frp_list
    ask "看哪个 (序号): "; rd i
    case "$i" in ''|*[!0-9]*) return;; esac
    clear 2>/dev/null
    frp_parse "$i" || return
    echo -e "\n${B}=== ${N_NAME} 日志 ===${R}\n"
    tail -40 "$(frp_logf "$i")" 2>/dev/null | sed 's/^/  /' || warn "还没有日志"
    echo; press
}

# ---- 自动识别: frtt 里的配置文件自动变成节点, 不用手动导入 ----
# $1=1 静默; 输出新增数量
frp_sync() {
    local quiet="${1:-1}"
    [ "${FRP_AUTOSYNC:-1}" = 1 ] || { echo 0; return 0; }
    local d; d=$(frp_userdir)
    [ -d "$d" ] || { echo 0; return 0; }
    local list; list=$(frp_scan_user)
    [ -z "$list" ] && { echo 0; return 0; }
    mkdir -p "$FRP_DIR" 2>/dev/null
    local f nm nn j dup added=0
    local u_addr u_port u_rem u_loc u_tok u_user u_auth
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        nm=$(basename "$f"); nm=${nm%.*}
        [ -z "$nm" ] && continue
        frp_uc_parse "$f"
        u_addr="$UC_ADDR"; u_port="$UC_PORT"; u_rem="$UC_REMOTE"
        u_loc="$UC_LOCAL"; u_tok="$UC_TOK"; u_user="$UC_USER"; u_auth="$UC_AUTH"
        [ -z "$u_addr" ] && continue          # 解析不出地址 = 格式不对, 跳过
        dup=0; nn=$(frp_cnt)
        for ((j=1;j<=nn;j++)); do
            frp_parse "$j" 2>/dev/null
            [ "${N_NAME:-}" = "$nm" ] && dup=1
        done
        [ "$dup" = 1 ] && continue
        echo "${nm}|${u_addr}|${u_port}|${u_auth}|${u_tok}|${u_user}|${u_rem}|${u_loc}|1" >> "$FRP_NODES"
        added=$((added+1))
        [ "$quiet" != "1" ] && say "自动识别: ${nm}  ->  ${u_addr}:${u_rem}"
    done <<< "$list"
    echo "$added"
}
# 手动立即扫描一次 (菜单 13)
frp_sync_now() {
    if [ "${FRP_AUTOSYNC:-1}" != 1 ]; then
        warn "自动识别已关闭"
        ask "临时扫一次? (y/n): "; rd v
        [ "$v" != "y" ] && { press; return; }
    fi
    local n; n=$(frp_sync 0)
    if [ "${n:-0}" -gt 0 ] 2>/dev/null; then
        say "新识别 $n 个节点, 已自动启用"
        if [ "$FRP_AUTOSTART" = 1 ] && [ -x "$FRP_BIN" ]; then
            frp_boot_if_needed
        else
            echo -e "  ${Y}按 7 启动全部${R}"
        fi
    else
        say "frtt 里没有新的配置文件"
    fi
    press
}


# 主菜单底部: 一句话说清 FRP 状态
frp_status_line() {
    [ "${FRP_AUTOSYNC:-1}" = 1 ] || return 0
    local d; d=$(frp_userdir)
    [ -d "$d" ] || return 0
    local n nf=0 i
    n=$(frp_cnt)
    [ "$n" -eq 0 ] && return 0
    for ((i=1;i<=n;i++)); do frp_npid "$i" >/dev/null && nf=$((nf+1)); done
    if [ "$nf" -gt 0 ]; then
        echo -e "  ${G}● 穿透 ${nf}/${n} 个节点在跑${R}"
    elif [ "$FRP_AUTOSTART" = 1 ]; then
        echo -e "  ${Y}穿透 ${n} 个节点已识别, 启动服务器时自动拉起${R}"
    else
        echo -e "  ${Y}穿透 ${n} 个节点已识别 (菜单 23-7 启动)${R}"
    fi
}


frp_menu() {
    frp_load
    while true; do
        local synced; synced=$(frp_sync 1)
        clear 2>/dev/null
        title "FRP 多节点穿透"
        echo -e "  ${Y}多个地域节点 -> 同一台服务器, 朋友各连最近的${R}"
        echo -e "  ${C}自动识别:${R} $([ "${FRP_AUTOSYNC:-1}" = 1 ] && echo "${G}开${R}" || echo "关")   ${Y}frtt 里放配置文件就会自动变成节点${R}"
        if [ "${synced:-0}" -gt 0 ] 2>/dev/null; then
            echo
            echo -e "  ${G}[+] 刚自动识别到 ${synced} 个新节点, 已启用${R}"
            if [ "$FRP_AUTOSTART" = 1 ] && [ -x "$FRP_BIN" ]; then
                frp_boot_if_needed
                echo
                press
            else
                echo -e "  ${Y}按 7 启动全部${R}"
            fi
        fi
        local ud; ud=$(frp_mkuser)
        local un; un=$(frp_scan_user 2>/dev/null | grep -c . )
        echo -e "  ${C}frtt:${R} $ud   ${Y}里面有 ${un:-0} 个配置文件${R}"
        echo
        frp_list
        echo
        echo "   1) 添加节点        2) 编辑节点"
        echo "   3) 启/停用节点     4) 删除节点"
        echo "   5) 启动某节点      6) 停止某节点"
        echo "   7) 启动全部启用    8) 停止全部"
        echo "   9) 测试连通       10) 下载/更新 frpc"
        echo "  11) 查看节点日志   12) 开服自动启动  当前: $([ "$FRP_AUTOSTART" = 1 ] && echo 开 || echo 关)"
        echo "  13) 立即扫描 frtt    14) 导出配置到 frtt"
        echo "  15) frtt 自动识别  当前: $([ "${FRP_AUTOSYNC:-1}" = 1 ] && echo 开 || echo 关)"
        echo "  16) 用本地打包包装 frpc (不走网络)"
        echo "   0) 返回"
        echo
        ask "选择: "; rd c || return
        case "$c" in
            1) frp_add;;
            2) frp_edit;;
            3) frp_toggle;;
            4) frp_del;;
            5) frp_list; ask "启动哪个: "; rd i; case "$i" in ''|*[!0-9]*) ;; *) frp_start_one "$i";; esac; press;;
            6) frp_list; ask "停止哪个: "; rd i; case "$i" in ''|*[!0-9]*) ;; *) frp_stop_one "$i";; esac; press;;
            7) frp_start_all;;
            8) frp_stop_all;;
            9) frp_test_menu;;
           10) frp_download;;
           11) frp_log_menu;;
           13) frp_sync_now;;
           14) frp_export_menu;;
           15) if [ "${FRP_AUTOSYNC:-1}" = 1 ]; then FRP_AUTOSYNC=0; else FRP_AUTOSYNC=1; fi
               frp_set_auto
               say "frtt 自动识别已设为 $([ "$FRP_AUTOSYNC" = 1 ] && echo 开 || echo 关)"
               [ "$FRP_AUTOSYNC" = 1 ] && frp_sync_now
               press;;
           12) if [ "$FRP_AUTOSTART" = 1 ]; then FRP_AUTOSTART=0; else FRP_AUTOSTART=1; fi
               frp_set_auto
               say "已设为 $([ "$FRP_AUTOSTART" = 1 ] && echo 开 || echo 关)"; press;;
            16) frp_install_local; press;;
            0|q|Q) return;;
        esac
    done
}

# ============================================================
#  安卓权限 API (菜单 26) —— 已内置, 不依赖外部 perm.sh
#
#  每项权限三级降级:
#    ① 能静默拿就静默拿  (root / Shizuku 直接 pm grant / appops)
#    ② 拿不到就弹窗      (am start 跳设置页 + Termux:API 发通知)
#    ③ 用户不想管就跳过  (记进 perm_skip, 以后不再烦)
#
#  提权手段自动择优: root > Shizuku > 普通; proot 作兜底运行环境
# ============================================================
PERM_PKG="${PERM_PKG:-com.termux}"
PERM_SKIP_FILE="${CONF_DIR}/perm_skip"
PERM_LOG="${LOGDIR}/perm.log"
[ -d "$LOGDIR" ] || mkdir -p "$LOGDIR" 2>/dev/null

perm_log() { echo "[$(date '+%m-%d %H:%M:%S')] $*" >> "$PERM_LOG" 2>/dev/null; }

# ---------- 能力探测 ----------
perm_has_root() {
    [ -n "${PERM_ROOT:-}" ] && { [ "$PERM_ROOT" = 1 ] && return 0 || return 1; }
    PERM_ROOT=0
    command -v su >/dev/null 2>&1 || return 1
    local u; u=$(su -c 'id -u' 2>/dev/null | tr -d ' \r\n')
    [ "$u" = "0" ] && { PERM_ROOT=1; perm_log "root 可用"; return 0; }
    return 1
}
perm_has_shizuku() {
    [ -n "${PERM_SHIZUKU:-}" ] && { [ "$PERM_SHIZUKU" = 1 ] && return 0 || return 1; }
    PERM_SHIZUKU=0
    local rish=""
    for c in rish shizuku; do command -v "$c" >/dev/null 2>&1 && { rish="$c"; break; }; done
    [ -z "$rish" ] && for pp in /data/local/tmp/rish "$HOME/rish" "${PREFIX:-/data/data/com.termux/files/usr}/bin/rish"; do
        [ -x "$pp" ] && { rish="$pp"; break; }
    done
    [ -z "$rish" ] && return 1
    "$rish" -c 'id -u' >/dev/null 2>&1 && { PERM_SHIZUKU=1; PERM_RISH="$rish"; perm_log "Shizuku 可用: $rish"; return 0; }
    return 1
}
perm_has_proot() {
    command -v proot >/dev/null 2>&1 && return 0
    command -v proot-distro >/dev/null 2>&1 && return 0
    return 1
}
perm_has_tapi() {
    command -v termux-toast >/dev/null 2>&1 && return 0
    command -v termux-notification >/dev/null 2>&1 && return 0
    command -v termux-dialog >/dev/null 2>&1 && return 0
    return 1
}
perm_mode() {
    if   perm_has_root;    then echo "root"
    elif perm_has_shizuku; then echo "shizuku"
    else echo "普通"; fi
}
perm_probe() {
    title "权限能力探测"
    echo -e "  包名      : ${C}$PERM_PKG${R}"
    echo -ne "  Root      : "; perm_has_root    && echo -e "${G}可用${R}" || echo -e "${Y}无${R}"
    echo -ne "  Shizuku   : "; perm_has_shizuku && echo -e "${G}可用${R} (${PERM_RISH})" || echo -e "${Y}无${R}"
    echo -ne "  proot     : "; perm_has_proot   && echo -e "${G}可用${R}" || echo -e "${Y}无${R}"
    echo -ne "  TermuxAPI : "; perm_has_tapi    && echo -e "${G}可用${R}" || echo -e "${Y}无${R}"
    echo
    echo -e "  ${Y}当前提权方式: ${C}$(perm_mode)${R}"
}

# ---------- 执行层: 用能拿到的最高权限跑命令 ----------
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

# ---------- 跳过名单 ----------
perm_skip_load() { [ -f "$PERM_SKIP_FILE" ] || : > "$PERM_SKIP_FILE" 2>/dev/null; }
perm_is_skipped() { perm_skip_load; grep -qx "$1" "$PERM_SKIP_FILE" 2>/dev/null; }
perm_do_skip() {
    perm_skip_load
    grep -qx "$1" "$PERM_SKIP_FILE" 2>/dev/null || echo "$1" >> "$PERM_SKIP_FILE" 2>/dev/null
    perm_log "跳过: $1"
    warn "已记入跳过名单, 以后不再提示 ($1)"
}
perm_unskip_all() { : > "$PERM_SKIP_FILE" 2>/dev/null; say "跳过名单已清空"; }

# ---------- 弹窗 / 跳设置页 ----------
perm_open() {
    local intent="$1" desc="${2:-设置页}"
    echo -e "  ${Y}需要手动允许:${R} ${C}$desc${R}"
    if perm_exec "am start $intent" >/dev/null 2>&1; then
        echo -e "  ${C}已跳转设置页, 允许后回来按回车${R}"
    else
        echo -e "  ${Y}手动: 系统设置 → 应用 → Termux → 权限${R}"
    fi
    perm_log "跳转设置: $desc"
}
perm_hint() {
    local msg="$1"
    command -v termux-toast >/dev/null 2>&1 && { termux-toast -g middle "$msg" 2>/dev/null && return 0; }
    command -v termux-notification >/dev/null 2>&1 && { termux-notification -t "mcserv 权限" -c "$msg" 2>/dev/null && return 0; }
    return 1
}

# ---------- 各项权限 ----------
perm_storage() {
    local dir="${1:-${ROOT}}"
    if [ -w "$dir" ] 2>/dev/null && touch "$dir/.permprobe" 2>/dev/null; then
        rm -f "$dir/.permprobe" 2>/dev/null
        say "存储可写 ✅  $dir"; return 0
    fi
    warn "存储不可写: $dir"
    if perm_has_root || perm_has_shizuku; then
        echo -ne "  ${C}尝试用 $(perm_mode) 授予存储权限...${R}"
        perm_exec "pm grant $PERM_PKG android.permission.READ_EXTERNAL_STORAGE" >/dev/null 2>&1
        perm_exec "pm grant $PERM_PKG android.permission.WRITE_EXTERNAL_STORAGE" >/dev/null 2>&1
        perm_exec "appops set $PERM_PKG MANAGE_EXTERNAL_STORAGE allow" >/dev/null 2>&1
        perm_exec "appops set --uid $PERM_PKG MANAGE_EXTERNAL_STORAGE allow" >/dev/null 2>&1
        printf "\r\033[K"
        if touch "$dir/.permprobe" 2>/dev/null; then
            rm -f "$dir/.permprobe" 2>/dev/null
            say "已通过 $(perm_mode) 拿到存储权限 ✅"; return 0
        fi
        warn "$(perm_mode) 授予了但还是写不了 (ROM 限制)"
    fi
    if ! perm_has_tapi; then
        need_tapi || echo -e "  ${Y}建议手动:${R} ${C}pkg install termux-api${R} 然后 ${C}termux-setup-storage${R}"
    fi
    echo
    perm_open "-a android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION -d package:$PERM_PKG" "所有文件访问权限"
    perm_hint "请允许 Termux 的文件访问权限"
    return 1
}
perm_battery() {
    if perm_has_root || perm_has_shizuku; then
        local st; st=$(perm_exec "dumpsys deviceidle whitelist" 2>/dev/null | grep -c "$PERM_PKG")
        [ "${st:-0}" -gt 0 ] && { say "电池优化已豁免 ✅"; return 0; }
    else
        echo -e "  ${Y}没有 root/Shizuku, 查不到电池优化状态${R}"
    fi
    warn "建议把 Termux 加进电池优化白名单 (否则后台容易被杀)"
    if perm_has_root || perm_has_shizuku; then
        echo -ne "  ${C}尝试用 $(perm_mode) 加白名单...${R}"
        perm_exec "dumpsys deviceidle whitelist +$PERM_PKG" >/dev/null 2>&1
        printf "\r\033[K"
        local st2; st2=$(perm_exec "dumpsys deviceidle whitelist" 2>/dev/null | grep -c "$PERM_PKG")
        [ "${st2:-0}" -gt 0 ] && { say "已加进白名单 ✅"; return 0; }
        warn "$(perm_mode) 加了但没生效"
    fi
    echo
    perm_open "-a android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS -d package:$PERM_PKG" "电池优化 → 选「不优化」"
    return 1
}
perm_notify() {
    if perm_has_root || perm_has_shizuku; then
        local st; st=$(perm_exec "dumpsys package $PERM_PKG" 2>/dev/null | grep -c "POST_NOTIFICATIONS: granted=true")
        [ "${st:-0}" -gt 0 ] && { say "通知权限已有 ✅"; return 0; }
        echo -ne "  ${C}尝试用 $(perm_mode) 授予通知权限...${R}"
        perm_exec "pm grant $PERM_PKG android.permission.POST_NOTIFICATIONS" >/dev/null 2>&1
        printf "\r\033[K"
        st=$(perm_exec "dumpsys package $PERM_PKG" 2>/dev/null | grep -c "POST_NOTIFICATIONS: granted=true")
        [ "${st:-0}" -gt 0 ] && { say "通知权限已授予 ✅"; return 0; }
    fi
    warn "通知权限可能没开 (掉线/崩溃提醒收不到)"
    perm_open "-a android.settings.APP_NOTIFICATION_SETTINGS --extra android.provider.extra.APP_PACKAGE $PERM_PKG" "通知权限"
    return 1
}
perm_overlay() {
    if perm_has_root || perm_has_shizuku; then
        echo -ne "  ${C}尝试用 $(perm_mode) 开后台弹出/悬浮窗...${R}"
        perm_exec "appops set $PERM_PKG SYSTEM_ALERT_WINDOW allow" >/dev/null 2>&1
        perm_exec "appops set $PERM_PKG START_ACTIVITIES_FROM_BACKGROUND allow" >/dev/null 2>&1
        perm_exec "pm grant $PERM_PKG android.permission.SYSTEM_ALERT_WINDOW" >/dev/null 2>&1
        printf "\r\033[K"
        say "已尝试开启 (部分 ROM 只认设置页手动开)"; return 0
    fi
    warn "后台弹出界面: 国产 ROM 常拦, 建议手动开"
    echo -e "  ${Y}路径: 设置 → 应用 → Termux → 权限管理 → 后台弹出界面/悬浮窗 → 允许${R}"
    perm_open "-a android.settings.action.MANAGE_OVERLAY_PERMISSION -d package:$PERM_PKG" "悬浮窗/后台弹出"
    return 1
}
perm_wakelock() {
    if command -v termux-wake-lock >/dev/null 2>&1; then
        termux-wake-lock 2>/dev/null && { say "唤醒锁已获取 ✅"; return 0; }
        warn "termux-wake-lock 调不动 (Termux:API 没装?)"
    else
        warn "没有 termux-wake-lock"
    fi
    echo -e "  ${Y}装:${R} pkg install termux-api"
    echo -e "  ${Y}手机设置里把 Termux 设成「允许后台高耗电/锁定后台」${R}"
    return 1
}
perm_autostart() {
    warn "自启动/关联启动只能手动开 (各家 ROM 没有统一开关)"
    echo
    echo -e "  ${C}小米/红米${R} 设置 → 应用设置 → 应用管理 → Termux → 自启动 + 省电策略选「无限制」"
    echo -e "  ${C}华为/荣耀${R} 手机管家 → 应用启动管理 → Termux → 手动管理(三项全开)"
    echo -e "  ${C}OPPO/一加${R} 设置 → 电池 → 应用耗电管理 → Termux → 允许后台运行"
    echo -e "  ${C}vivo/iQOO${R} 设置 → 电池 → 后台管理 → Termux → 允许后台高耗电"
    echo -e "  ${C}三星${R}   设置 → 电池 → 后台使用限制 → 从不休眠应用 加上 Termux"
    echo
    echo -e "  ${Y}通用狠招: 多任务界面把 Termux 卡片往下拉锁住${R}"
    return 1
}
perm_install() {
    if perm_has_root || perm_has_shizuku; then
        echo -ne "  ${C}尝试用 $(perm_mode) 开「允许安装未知应用」...${R}"
        perm_exec "appops set $PERM_PKG REQUEST_INSTALL_PACKAGES allow" >/dev/null 2>&1
        perm_exec "pm grant $PERM_PKG android.permission.REQUEST_INSTALL_PACKAGES" >/dev/null 2>&1
        printf "\r\033[K"
        say "已尝试开启"; return 0
    fi
    warn "安装未知应用权限"
    perm_open "-a android.settings.MANAGE_UNKNOWN_APP_SOURCES -d package:$PERM_PKG" "允许安装未知应用"
    return 1
}
perm_vpn() {
    if perm_has_root || perm_has_shizuku; then
        echo -ne "  ${C}尝试用 $(perm_mode) 开 VPN 权限...${R}"
        perm_exec "appops set $PERM_PKG ACTIVATE_VPN allow" >/dev/null 2>&1
        printf "\r\033[K"
        say "已尝试开启"
    fi
    warn "VPN 类权限: 首次使用会弹系统框, 点允许即可"
    echo -e "  ${Y}注意: 安卓同一时刻只允许一个 VPN 存活${R}"
    return 1
}
perm_net() {
    if ! curl -fsS --max-time 8 https://www.baidu.com -o /dev/null 2>/dev/null; then
        warn "联网测试失败"
        echo -e "  ${Y}检查: 系统设置 → 流量管理 → Termux 是否允许 WLAN/移动数据${R}"
        perm_open "-a android.settings.APPLICATION_DETAILS_SETTINGS -d package:$PERM_PKG" "Termux 联网权限"
        return 1
    fi
    say "联网正常 ✅"; return 0
}
perm_proot_run() {
    local cmd="$1"
    perm_has_proot || { err "没有 proot, 装: pkg install proot"; return 1; }
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

# ---------- 状态速览 (只做轻量检测, 不申请, 列表里用) ----------
perm_stat() {
    local k="$1"
    perm_is_skipped "$k" && { echo "跳过"; return; }
    case "$k" in
        storage)
            [ -w "$ROOT" ] 2>/dev/null && echo "已就绪" || echo "待处理";;
        net)
            command -v curl >/dev/null 2>&1 && echo "点序号检测" || echo "缺 curl";;
        wakelock)
            command -v termux-wake-lock >/dev/null 2>&1 && echo "可获取" || echo "需装 TermuxAPI";;
        battery|notify|overlay|install|vpn)
            if perm_has_root || perm_has_shizuku; then echo "可静默授予"; else echo "需手动"; fi;;
        autostart) echo "仅指引";;
        *) echo "?";;
    esac
}
perm_name() {
    case "$1" in
        storage) echo "存储读写";;   battery) echo "电池优化白名单";;
        notify)  echo "通知权限";;   overlay) echo "后台弹出/悬浮窗";;
        wakelock)echo "唤醒锁";;     autostart) echo "自启动(指引)";;
        install) echo "安装未知应用";; vpn) echo "VPN 权限";;
        net)     echo "联网测试";;   *) echo "$1";;
    esac
}

# 显示宽度: 中文算 2 格, 英文算 1 格 (不依赖 locale, 逐字符按字节判)
perm_wid() {
    local s="$1" w=0 i c len=${#s}
    for ((i=0;i<len;i++)); do
        c="${s:i:1}"
        if [ "$(printf '%s' "$c" | wc -c)" -gt 1 ]; then w=$((w+2)); else w=$((w+1)); fi
    done
    echo "$w"
}
# 按显示宽度右补空格, 中文列才对得齐
perm_pad() {
    local s="$1" n="$2" w; w=$(perm_wid "$s")
    printf '%s' "$s"
    [ "$w" -lt "$n" ] && printf '%*s' $((n-w)) ''
    return 0
}

# ---------- 统一入口: perm_ensure <名> ----------
# 返回 0=已搞定 1=待用户处理 2=已跳过
perm_ensure() {
    local name="$1"
    if perm_is_skipped "$name"; then
        echo -e "  ${Y}$(perm_name "$name") 已跳过 (之前选过不再管)${R}"
        return 2
    fi
    echo
    echo -e "${B}--- $(perm_name "$name") ---${R}"
    local rc=0
    case "$name" in
        storage)   perm_storage "${ROOT}"; rc=$?;;
        battery)   perm_battery;  rc=$?;;
        notify)    perm_notify;   rc=$?;;
        overlay)   perm_overlay;  rc=$?;;
        wakelock)  perm_wakelock; rc=$?;;
        autostart) perm_autostart; rc=$?;;
        install)   perm_install;  rc=$?;;
        vpn)       perm_vpn;      rc=$?;;
        net)       perm_net;      rc=$?;;
        *)         err "不认识的权限: $name"; return 1;;
    esac
    if [ $rc -ne 0 ] && [ "${PERM_BATCH:-0}" != 1 ]; then
        echo
        ask "这项以后不再提示? (y=跳过 / 回车=下次再说): "
        rd _ps
        case "$_ps" in y|Y) perm_do_skip "$name"; return 2;; esac
    fi
    return $rc
}

# ---------- 权限中心: 进去直接按序号获取 ----------
PERM_KEYS=(storage net wakelock battery notify overlay autostart install vpn)

perm_hub() {
    while true; do
        clear 2>/dev/null
        title "安卓权限中心"
        echo -e "  提权方式: ${C}$(perm_mode)${R}    包名: ${C}${PERM_PKG}${R}    根目录: ${C}$ROOT${R}"
        echo -e "  ${Y}输入序号直接获取, 可多选(空格分隔); all=全部, s=跳过名单, d=能力探测${R}"
        echo
        local i k st col
        for i in "${!PERM_KEYS[@]}"; do
            k="${PERM_KEYS[$i]}"; st=$(perm_stat "$k")
            case "$st" in
                已就绪)                   col="${G}";;
                可静默授予|可获取)        col="${C}";;
                跳过|点序号检测|仅指引)   col="${Y}";;
                *)                        col="${RD}";;
            esac
            printf "  ${B}%2d)${R} %s ${col}[%s]${R}\n" \
                $((i+1)) "$(perm_pad "$(perm_name "$k")" 20)" "$st"
        done
        echo
        echo -e "  ${B} 0)${R} 返回"
        echo
        ask "序号: "; rd c || return
        [ -z "$c" ] && continue
        case "$c" in
            0|q|Q) return;;
            d|D) clear 2>/dev/null; perm_probe; press; continue;;
            s|S) clear 2>/dev/null; perm_skip_menu; continue;;
            all|ALL|a|A)
                PERM_BATCH=1
                local n ok=0 sk=0
                for n in "${PERM_KEYS[@]}"; do
                    perm_ensure "$n"
                    case $? in 0) ok=$((ok+1));; 2) sk=$((sk+1));; esac
                done
                PERM_BATCH=0
                echo
                echo -e "  ${G}已就绪 ${ok}${R}   ${Y}跳过 ${sk}${R}"
                perm_log "全部获取: ok=$ok skip=$sk"
                press; continue;;
        esac
        # 多选: 空格分隔的序号
        local got=0
        for tok in $c; do
            case "$tok" in ''|*[!0-9]*) continue;; esac
            [ "$tok" -ge 1 ] && [ "$tok" -le "${#PERM_KEYS[@]}" ] || continue
            PERM_BATCH=1
            perm_ensure "${PERM_KEYS[$((tok-1))]}"
            PERM_BATCH=0
            got=1
            echo
        done
        [ "$got" = 1 ] && press
    done
}

perm_skip_menu() {
    title "跳过名单"
    if [ ! -s "$PERM_SKIP_FILE" ]; then
        say "名单是空的"
    else
        echo -e "  ${Y}这些权限以后不再提示:${R}"
        local n
        while IFS= read -r n; do
            [ -n "$n" ] && echo -e "     ${C}$n${R}  ${Y}($(perm_name "$n"))${R}"
        done < "$PERM_SKIP_FILE"
        echo
        ask "清空名单? (y/n): "; rd y
        case "$y" in y|Y) perm_unskip_all;; esac
    fi
    press
}

# 开服前批量自检(静默版, 只统计不打断)
perm_ensure_all() {
    local n ok=0 sk=0
    PERM_BATCH=1
    for n in storage net wakelock battery notify; do
        perm_ensure "$n" >/dev/null 2>&1
        case $? in 0) ok=$((ok+1));; 2) sk=$((sk+1));; esac
    done
    PERM_BATCH=0
    echo -e "  ${G}权限已就绪 ${ok}${R}   ${Y}跳过 ${sk}${R}"
    perm_log "批量自检: ok=$ok skip=$sk"
}

# ============================================================
#  云端公告 (菜单 27) —— Cloudflare Workers 版
#
#  从 Cloudflare Workers (xxx.workers.dev) 或任意直链拉公告.
#  两种格式自动识别:
#
#  ① JSON (Workers 推荐) —— 响应体:
#     {"v":"20261005","title":"v1.1","level":"info",
#      "body":["第一行","第二行"]}
#     字段: v/version 版本号, title 标题, body 正文(字符串或数组),
#           level 级别(info/warn/urgent), ttl 覆盖缓存小时
#
#  ② 纯文本 —— 直链txt:
#     #v=20261005
#     #title=标题
#     正文...
#
#  版本协商: 带 ?v=<已读版本> 请求, Worker 可回 {"upToDate":true}
#  表示无更新, 省流量. 不吃这个参数的老源会原样重试一次.
#
#  多源兜底: ANN_URL 空格分隔写多个, 依次试.
#  缓存期内不联网, 启动零延迟.
# ============================================================
ANN_CACHE="${CONF_DIR}/announce.txt"
ANN_READ="${CONF_DIR}/announce_read"
ANN_TSF="${CONF_DIR}/announce.ts"
ANN_ALWAYS="${ANN_ALWAYS:-1}"
ANN_MAX_LINE="${ANN_MAX_LINE:-18}"
ANN_UA="${ANN_UA:-mcserv/${MCSERV_VER:-1.6} (+announce)}"

ann_now() { date +%s; }

# 去掉 ANSI 转义和 CR, 防止公告内容把终端搞乱
ann_clean() { sed -e 's/\x1b\[[0-9;]*[A-Za-z]//g' -e 's/\r$//' 2>/dev/null; }

# Cloudflare 错误页 / 拦截页识别 (Worker 挂了或域名不对会回 HTML)
# Cloudflare 拒绝/错误识别 (HTML 拦截页 或 JSON 拒绝体)
# 这两种都不是公告, 必须挡掉, 否则会把 "Request denied" 当标题显示出来
ann_is_denied() {
    local f="$1"
    # --- HTML 拦截页 / 错误页 ---
    grep -qiE '^[[:space:]]*(<!DOCTYPE html|<html)' "$f" 2>/dev/null && return 0
    grep -qiE '<html|attention required|cloudflare.*error|error 1[0-9]{3}' "$f" 2>/dev/null && return 0
    # --- JSON 拒绝体: {"title":"Request denied","status":403,...} ---
    # Cloudflare Zero Trust / Access 策略拒绝时返回这个
    grep -qiE '"Request denied"|"policy_default_denied"|"reason"[[:space:]]*:[[:space:]]*"policy' "$f" 2>/dev/null && return 0
    grep -qiE '"status"[[:space:]]*:[[:space:]]*(403|401|404|5[0-9]{2})' "$f" 2>/dev/null && return 0
    grep -qiE '"title"[[:space:]]*:[[:space:]]*"(Request denied|Access denied|Forbidden|Not Found|Unauthorized)"' "$f" 2>/dev/null && return 0
    return 1
}

# 把响应规范成统一缓存格式: #v= / #title= / #level= / 正文
# 参数: <原始文件> <输出文件>  返回 0=成功, 3=服务端说无更新, 1=失败
ann_parse() {
    local src="$1" dst="$2" rc=0
    [ -s "$src" ] || return 1

    # ---- JSON 分支 ----
    local first; first=$(head -c 1 "$src" 2>/dev/null | tr -d ' \n\r\t')
    if [ "$first" = "{" ] || [ "$first" = "[" ]; then
        if command -v python3 >/dev/null 2>&1; then
            python3 - "$src" "$dst" <<'PYJSONEOF' 2>/dev/null
import json, sys
src, dst = sys.argv[1], sys.argv[2]
try:
    raw = open(src, encoding='utf-8', errors='replace').read().strip()
except Exception:
    sys.exit(1)
try:
    d = json.loads(raw)
except Exception:
    sys.exit(1)
if isinstance(d, list):
    d = d[0] if d else {}
if not isinstance(d, dict):
    sys.exit(1)
if d.get('upToDate') or d.get('uptodate') or d.get('noChange'):
    sys.exit(3)
v  = d.get('v') or d.get('version') or d.get('ver') or ''
t  = d.get('title') or d.get('subject') or ''
lv = d.get('level') or d.get('type') or 'info'
b  = d.get('body') or d.get('content') or d.get('msg') or d.get('text') or ''
if isinstance(b, str):
    lines = b.splitlines()
elif isinstance(b, list):
    lines = [str(x) for x in b]
else:
    lines = []
ttl = d.get('ttl')
out = ['#v=%s' % str(v).strip(),
       '#title=%s' % str(t).strip(),
       '#level=%s' % str(lv).strip()]
if ttl:
    out.append('#ttl=%s' % str(ttl).strip())
out.extend([l.rstrip() for l in lines])
open(dst, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
sys.exit(0)
PYJSONEOF
            rc=$?
            [ $rc -eq 0 ] && return 0
            [ $rc -eq 3 ] && return 3
        fi
        # python 不在 / JSON 坏了 → 退回当纯文本处理
    fi

    # ---- 纯文本分支 ----
    if grep -qE '^#(v|title)=' "$src" 2>/dev/null; then
        ann_clean < "$src" > "$dst" 2>/dev/null
    else
        { echo "#v="; ann_clean < "$src"; } > "$dst" 2>/dev/null
    fi
    [ -s "$dst" ] || return 1
    return 0
}

# 拉公告 → 写缓存. 0=拿到新内容, 3=无更新, 1=失败
ann_fetch() {
    [ "${ANN_ON:-1}" = 1 ] || return 1
    [ -n "${ANN_URL:-}" ] || return 1
    local u tmp="${TMP_DIR}/ann.$$" parsed="${TMP_DIR}/annp.$$" ok=0 rc url
    mkdir -p "$TMP_DIR" 2>/dev/null
    # 已读版本, 用于 ?v= 协商 (支持协商的 Worker 可省流量)
    local rv=""
    [ -f "$ANN_READ" ] && rv=$(tr -d ' \n' < "$ANN_READ" 2>/dev/null)

    for u in $ANN_URL; do
        url="$u"
        # 每次尝试前清掉上一次的状态码, 否则会读到旧值误判
        rm -f "${tmp}.code" 2>/dev/null
        if [ -n "$rv" ]; then
            case "$u" in
                *\?*) url="${u}&v=${rv}";;
                *)    url="${u}?v=${rv}";;
            esac
        fi
        if curl -fsSL --max-time 6 --connect-timeout 3 \
                -H "User-Agent: $ANN_UA" \
                -H "Accept: application/json, text/plain, */*" \
                "$url" -o "$tmp" -w '%{http_code}' > "${tmp}.code" 2>/dev/null \
                && [ -s "$tmp" ]; then
            ok=1; break
        fi
        # 带 v 协商失败可能是老源不吃参数, 原样再试一次
        rm -f "${tmp}.code" 2>/dev/null
        if [ -n "$rv" ] && curl -fsSL --max-time 6 --connect-timeout 3 \
                -H "User-Agent: $ANN_UA" "$u" -o "$tmp" \
                -w '%{http_code}' > "${tmp}.code" 2>/dev/null \
                && [ -s "$tmp" ]; then
            ok=1; break
        fi
    done
    [ "$ok" = 1 ] || { rm -f "$tmp" "$parsed" 2>/dev/null; return 1; }

    # HTTP 状态码校验: 非 2xx 一律当失败
    local code; code=$(tr -d ' \n\r' < "${tmp}.code" 2>/dev/null)
    rm -f "${tmp}.code" 2>/dev/null
    if [ -n "$code" ]; then
        case "$code" in
            2??) ;;
            *) rm -f "$tmp" "$parsed" 2>/dev/null; return 1;;
        esac
    fi

    # 大小校验: 空的不收, 超过 64K 不收(防止误填了大文件)
    local sz; sz=$(wc -c < "$tmp" 2>/dev/null | tr -d ' ')
    if [ -z "$sz" ] || [ "$sz" -lt 1 ] || [ "$sz" -gt 65536 ]; then
        rm -f "$tmp" "$parsed" 2>/dev/null; return 1
    fi

    # Cloudflare 拦到 HTML 错误页 / JSON 拒绝体 = 这个源不对
    if ann_is_denied "$tmp"; then
        rm -f "$tmp" "$parsed" 2>/dev/null; return 1
    fi

    ann_parse "$tmp" "$parsed"; rc=$?

    # rc=3 = 服务端说"没新公告": 缓存不动, 但要打时间戳
    # 否则每次启动都算过期、都要联网, 违背"启动零延迟"的初衷
    if [ $rc -eq 3 ]; then
        rm -f "$tmp" "$parsed" 2>/dev/null
        mkdir -p "$CONF_DIR" 2>/dev/null
        ann_now > "$ANN_TSF" 2>/dev/null
        return 3
    fi

    if [ $rc -ne 0 ]; then rm -f "$tmp" "$parsed" 2>/dev/null; return "$rc"; fi

    mkdir -p "$CONF_DIR" 2>/dev/null
    mv -f "$parsed" "$ANN_CACHE" 2>/dev/null
    ann_now > "$ANN_TSF" 2>/dev/null
    # Worker 可以在 JSON 里给 ttl 覆盖本地缓存时长
    local tt; tt=$(grep -m1 '^#ttl=' "$ANN_CACHE" 2>/dev/null | sed 's/^#ttl=//' | tr -d '\r\n')
    case "$tt" in
        ''|*[!0-9]*) ;;
        *) [ "$tt" -ge 1 ] && [ "$tt" -le 168 ] && ANN_TTL="$tt";;
    esac
    rm -f "$tmp" 2>/dev/null
    return 0
}

# 缓存是否过期 (没时间戳也算过期)
ann_stale() {
    # -------------------------------------------------------------
    #  默认: 每次启动都拉。
    #
    #  原来的做法有多蠢:
    #    本地拿 ANN_TTL(默认 6h) 判断"缓存过没过期", 过期才去拉。
    #    而这个 ANN_TTL 是【上次拉公告时服务端带回来的】。
    #    于是: 你发第二个公告, 同时把服务端 ttl 从 6h 改成 1h ——
    #    客户端本地还记着 6h, 判定"没过期", 根本不去拉。
    #    想要的新公告得等满 6 小时才出现, 服务端改 ttl 完全失效。
    #
    #  现在: 每次启动都拉, 不再看本地缓存时间。
    #    流量靠 ?v= 版本协商兜住 —— 服务端支持协商时, 没新公告
    #    只回一个几十字节的 {"upToDate":true}, 比一张图都小。
    #
    #  真要省这几 KB, 把 ANN_ALWAYS 设成 0 就回到按小时判断。
    # -------------------------------------------------------------
    [ "${ANN_ALWAYS:-1}" = 1 ] && return 0
    local ts age
    [ -f "$ANN_TSF" ] || return 0          # 还没拉过 = 过期
    ts=$(tr -d ' \n' < "$ANN_TSF" 2>/dev/null)
    [ -n "$ts" ] || return 0
    age=$(( ($(ann_now) - ts) / 3600 ))
    [ "$age" -ge "${ANN_TTL:-6}" ]
}

ann_ver()   { grep -m1 '^#v='     "$ANN_CACHE" 2>/dev/null | sed 's/^#v=//'     | tr -d '\r\n'; }
ann_level() { grep -m1 '^#level=' "$ANN_CACHE" 2>/dev/null | sed 's/^#level=//' | tr -d '\r\n'; }
ann_title() { grep -m1 '^#title=' "$ANN_CACHE" 2>/dev/null | sed 's/^#title=//' | tr -d '\r\n'; }
ann_body()  { grep -v '^#' "$ANN_CACHE" 2>/dev/null; }
ann_total() { ann_body | wc -l | tr -d ' \n'; }

# 显示公告
ann_show() {
    if [ ! -s "$ANN_CACHE" ]; then
        warn "暂无公告 (可在菜单 27 手动刷新)"
        return 1
    fi
    local t lv bc hc
    t=$(ann_title); lv=$(ann_level)
    # 级别配色: info=黄 / warn=青 / urgent=红
    case "$lv" in
        urgent|critical) bc="${RD}"; hc="${RD}";;
        warn|warning)    bc="${C}";  hc="${C}";;
        *)               bc="${Y}";  hc="${G}";;
    esac
    [ -z "$lv" ] || [ "$lv" = "info" ] || lv=""
    echo
    echo -e "  ${bc}┌── 公告 ────────────────────────────┐${R}"
    if [ -n "$t" ]; then
        echo -e "  ${bc}│${R} ${hc}${B}$t${R}$([ -n "$lv" ] && echo -e " ${bc}[$lv]${R}")"
        echo -e "  ${bc}├───────────────────────────────────┤${R}"
    fi
    local total; total=$(ann_total)
    ann_body | head -n "$ANN_MAX_LINE" | while IFS= rd line; do
        if [ -z "$line" ]; then echo -e "  ${bc}│${R}"
        else echo -e "  ${bc}│${R} $line"; fi
    done
    if [ "${total:-0}" -gt "$ANN_MAX_LINE" ]; then
        echo -e "  ${bc}│${R} ${C}... 还有 $((total - ANN_MAX_LINE)) 行 (菜单 27 看全文)${R}"
    fi
    echo -e "  ${bc}└───────────────────────────────────┘${R}"
    return 0
}

# 启动时调用: 有新公告才弹, 已读静默
# ============================================================
#  极早期公告 —— 在任何依赖检查之前就要把公告弹出来
# ============================================================
#  为什么单独写一个:
#    正常流程是 先装依赖(need_curl/need_py) → 再拉公告,
#    但新用户第一次运行时 curl / python3 都还没装,
#    公告就得等到装完才能看到, 违背了"让人第一时间看到"的目的。
#  所以这里做一版"零依赖"的:
#    - 没 curl 就先悄悄装 curl, 装不上就静默跳过(绝不卡启动)
#    - JSON 解析用纯 sed 实现, 完全不碰 python3
#    - 拉到就立刻显示, 后面 ann_boot 会因为"已读"自动跳过, 不会弹两次
#    - 全程 5 秒超时, 失败一律静默

# 纯 shell 提取 JSON 字符串字段: ann_jstr <key> <单行文件>
ann_jstr() {
    sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$2" 2>/dev/null | head -1
}

# 纯 shell 提取 body 数组, 每条一行: ann_jbody <单行文件>
ann_jbody() {
    sed -n 's/.*"body"[[:space:]]*:[[:space:]]*\[\(.*\)\].*/\1/p' "$1" 2>/dev/null | head -1 \
      | sed -e 's/","/|/g' -e 's/\\n/|/g' -e 's/^"//' -e 's/"$//' \
      | tr '|' '\n'
}

ann_early() {
    [ "${ANN_ON:-1}" = 1 ] || return 0
    [ -n "${ANN_URL:-}" ] || return 0
    mkdir -p "$CONF_DIR" "$TMP_DIR" 2>/dev/null

    # 没 curl: 先装一次(此时连依赖检查都还没跑, 所以要自己显示进度)
    if ! command -v curl >/dev/null 2>&1; then
        if [ "${AUTO_DEPS:-1}" = 1 ]; then
            echo
            echo -e "  ${Y}[!]${R} 拉取公告需要 ${C}curl${R}, 但未安装"
            echo -e "      正在自动安装, 装完立刻显示公告"
            spin_start "安装 curl"
            _pkg_do curl
            spin_stop ""
            if command -v curl >/dev/null 2>&1; then
                echo -e "      ${G}✔${R} curl 就绪, 正在拉取公告..."
            else
                echo -e "      ${RD}✘${R} curl 安装失败, 跳过公告"
            fi
        fi
        command -v curl >/dev/null 2>&1 || return 0
    fi

    local u tmp="${TMP_DIR}/anne.$$" code="" rv="" got=""
    [ -f "$ANN_READ" ] && rv=$(tr -d ' \n' < "$ANN_READ" 2>/dev/null)

    for u in $ANN_URL; do
        local url="$u"
        [ -n "$rv" ] && url="${u}?v=${rv}"
        rm -f "${tmp}.code" 2>/dev/null
        if curl -fsSL --max-time 5 --connect-timeout 3 \
                -H "User-Agent: ${ANN_UA:-mcserv/${MCSERV_VER:-1.6}}" "$url" \
                -o "$tmp" -w '%{http_code}' > "${tmp}.code" 2>/dev/null \
            && [ -s "$tmp" ]; then
            code=$(tr -d ' \n\r' < "${tmp}.code" 2>/dev/null)
            rm -f "${tmp}.code" 2>/dev/null
            case "$code" in
                2??) got="$tmp"; break;;
                *)   rm -f "$tmp" 2>/dev/null; continue;;
            esac
        fi
        rm -f "$tmp" "${tmp}.code" 2>/dev/null
    done
    [ -n "$got" ] && [ -s "$got" ] || { rm -f "$tmp" 2>/dev/null; return 0; }

    # 大小校验: 空的不收, 超 64K 不收
    local sz; sz=$(wc -c < "$got" 2>/dev/null | tr -d ' ')
    case "$sz" in ''|*[!0-9]*) rm -f "$got"; return 0;; esac
    [ "$sz" -lt 1 ] || [ "$sz" -gt 65536 ] && { rm -f "$got" 2>/dev/null; return 0; }

    # Cloudflare 拦截页 / 拒绝 JSON = 这个源不对, 静默放弃
    if grep -qiE 'Request denied|policy_default_denied|Attention Required|error code 1[01][0-9][0-9]' "$got" 2>/dev/null; then
        rm -f "$got" 2>/dev/null; return 0
    fi

    # 压成单行再解析(JSON.stringify 出来的本来就是单行, 这里防 pretty print)
    local flat="${TMP_DIR}/annef.$$"
    tr -d '\n\r' < "$got" > "$flat" 2>/dev/null
    rm -f "$got" 2>/dev/null

    # 服务端说没新公告 → 打时间戳后静默退出
    if grep -qiE '"(upToDate|uptodate|noChange)"[[:space:]]*:[[:space:]]*true' "$flat" 2>/dev/null; then
        ann_now > "$ANN_TSF" 2>/dev/null
        rm -f "$flat" 2>/dev/null
        ANN_EARLY_OK=1        # 已经拉过了, ann_boot 别再拉一次
        return 0
    fi

    # 纯 shell 解析(JSON 优先, 老式 #v= 纯文本兜底)
    local v t lv cache="${TMP_DIR}/annc.$$"
    if grep -q '"v"[[:space:]]*:' "$flat" 2>/dev/null; then
        v=$(ann_jstr  v     "$flat")
        t=$(ann_jstr  title "$flat")
        lv=$(ann_jstr level "$flat")
        [ -z "$lv" ] && lv=info
        {
            echo "#v=$v"
            echo "#title=$t"
            echo "#level=$lv"
            ann_jbody "$flat"
        } > "$cache" 2>/dev/null
    else
        if grep -qE '^#(v|title)=' "$flat" 2>/dev/null; then
            sed -e 's/\x1b\[[0-9;]*[A-Za-z]//g' -e 's/\r$//' "$flat" > "$cache" 2>/dev/null
        else
            { echo "#v="; sed -e 's/\x1b\[[0-9;]*[A-Za-z]//g' -e 's/\r$//' "$flat"; } > "$cache" 2>/dev/null
        fi
    fi
    rm -f "$flat" 2>/dev/null
    [ -s "$cache" ] || { rm -f "$cache" 2>/dev/null; return 0; }

    mv -f "$cache" "$ANN_CACHE" 2>/dev/null
    ann_now > "$ANN_TSF" 2>/dev/null
    ANN_EARLY_OK=1            # 已经拉过了, ann_boot 别再拉一次

    # 版本号没变 → 已读, 不打扰
    local rv2=""
    v=$(ann_ver)
    [ -f "$ANN_READ" ] && rv2=$(tr -d ' \n' < "$ANN_READ" 2>/dev/null)
    if [ -n "$v" ] && [ "$v" = "$rv2" ]; then return 0; fi

    clear 2>/dev/null
    banner
    ann_show
    mkdir -p "$CONF_DIR" 2>/dev/null
    echo "$v" > "$ANN_READ" 2>/dev/null
    echo
    press
    return 0
}

ann_boot() {
    [ "${ANN_ON:-1}" = 1 ] || return 0
    [ -n "${ANN_URL:-}" ] || return 0
    # ann_early 已经成功拉过一次了, 这里别再拉(否则每次启动两条请求)
    if [ "${ANN_EARLY_OK:-0}" != 1 ] && ann_stale; then
        ann_fetch >/dev/null 2>&1
        case $? in
            3) ann_now > "$ANN_TSF" 2>/dev/null; return 0;;   # 无更新, 刷新时间戳
        esac
    fi
    [ -s "$ANN_CACHE" ] || return 0
    local v rv=""
    v=$(ann_ver)
    [ -f "$ANN_READ" ] && rv=$(tr -d ' \n' < "$ANN_READ" 2>/dev/null)
    # 公告没写版本号 → 每次启动都显示; 写了且没变 → 不打扰
    if [ -n "$v" ] && [ "$v" = "$rv" ]; then return 0; fi
    clear 2>/dev/null
    banner
    ann_show
    mkdir -p "$CONF_DIR" 2>/dev/null
    echo "$v" > "$ANN_READ" 2>/dev/null
    echo
    press
    return 0
}

# 设置公告源
ann_seturl() {
    title "公告源设置"
    echo -e "  ${Y}填 Cloudflare Workers 地址或公告直链, 多个用空格分隔(依次兜底)${R}"
    echo -e "  ${C}Workers:${R} https://xxx.workers.dev  (返回 JSON, 推荐)"
    echo -e "  ${C}直链  :${R} https://a.com/ann.txt      (返回纯文本)"
    echo
    echo -e "  当前: ${C}${ANN_URL:-<未设置>}${R}"
    echo
    echo -e "  ${Y}内置源:${R} ${C}${ANN_DEFAULT_URL}${R}"
    echo
    ask "新地址 (回车=不改, d=恢复内置源): "
    rd u
    case "$u" in
        "") ;;
        d|D) ANN_URL="$ANN_DEFAULT_URL"; say "已恢复内置源"; save_conf;;
        *)   ANN_URL="$u"; say "已更新"; save_conf;;
    esac
}

# 公告菜单
ann_menu() {
    while true; do
        clear 2>/dev/null
        title "云端公告"
        local v st="未设置"
        [ "${ANN_ON:-1}" = 1 ] && st="${G}开${R}" || st="${Y}关${R}"
        [ -n "${ANN_URL:-}" ] && [ "${ANN_ON:-1}" = 1 ] && st="${G}开${R}"
        echo -e "  开关: ${st}    源: ${C}${ANN_URL:-<未设置>}${R}"
    [ -z "${ANN_URL:-}" ] && echo -e "  ${Y}!${R} 源为空, 按 ${C}d${R} 一键恢复内置源 (${ANN_DEFAULT_URL})"
        local md
        if [ "${ANN_ALWAYS:-1}" = 1 ]; then
            md="${G}每次启动都拉${R} (推荐)"
        else
            md="${Y}按小时${R} ${C}${ANN_TTL:-6}h${R}  ${Y}← 容易错过新公告${R}"
        fi
        echo -e "  模式: ${md}    缓存: $([ -s "$ANN_CACHE" ] && echo "${G}有${R}" || echo "${Y}无${R}")"
        echo
        echo "   1) 查看公告              2) 立即刷新"
        echo "   3) 设置公告源            4) 开/关公告"
        echo "   5) 拉取模式(每次/按小时) 6) 清除已读 (下次启动重弹)"
        echo "   7) 清空缓存               d) 恢复内置源"
        echo "   0) 返回"
        echo
        ask "选择: "; rd c || return
        case "$c" in
            1) clear 2>/dev/null; title "公告全文"; ann_show || true
               if [ -s "$ANN_CACHE" ]; then echo; ann_body; fi
               press;;
            2) clear 2>/dev/null
               if [ -z "${ANN_URL:-}" ]; then warn "先设公告源 (选 3)"; press; continue; fi
               echo -ne "  ${C}拉取中...${R}"
               if ann_fetch; then printf "\r\033[K"; say "刷新完成"; ann_show
               else printf "\r\033[K"; err "拉取失败 (检查地址/网络)"; fi
               press;;
            3) clear 2>/dev/null; ann_seturl; press;;
            4) if [ "${ANN_ON:-1}" = 1 ]; then ANN_ON=0; say "公告已关闭"; else ANN_ON=1; say "公告已开启"
                 [ -z "${ANN_URL:-}" ] && { ANN_URL="$ANN_DEFAULT_URL"; say "已填回内置源"; }; fi
               save_conf; press;;
            5) clear 2>/dev/null; title "公告拉取模式"
               echo -e "  ${C}1)${R} 每次启动都拉  ${G}(推荐)${R}"
               echo -e "     新公告一发, 别人下次开脚本就能看到。"
               echo -e "     服务端有版本协商, 没新公告只回几个字节, 不费流量。"
               echo
               echo -e "  ${C}2)${R} 按小时缓存 ${Y}(可能错过新公告)${R}"
               echo -e "     到点才去问一次。你中途改了公告, 别人要等满这个时长才看得到。"
               echo
               ask "选择 (1/2, 直接回车=1): "; rd m
               case "$m" in
                   2) ANN_ALWAYS=0; save_conf
                      ask "缓存小时数 (1-168): "; rd h
                      case "$h" in ''|*[!0-9]*) ;;
                          *) [ "$h" -ge 1 ] && [ "$h" -le 168 ] && { ANN_TTL="$h"; save_conf; say "已设为 ${h} 小时"; };; esac
                      say "已切到按小时模式 (${ANN_TTL:-6}h)";;
                   *) ANN_ALWAYS=1; save_conf; say "已切到每次启动都拉";;
               esac
               press;;
            6) : > "$ANN_READ" 2>/dev/null; say "已清除已读标记, 下次启动会重新弹"; press;;
            7) rm -f "$ANN_CACHE" "$ANN_TSF" 2>/dev/null; say "缓存已清空"; press;;
            d|D) ANN_URL="$ANN_DEFAULT_URL"; ANN_ON=1; save_conf
                 say "已恢复内置源: ${ANN_DEFAULT_URL}"; press;;
            0|q|Q) return;;
        esac
    done
}

# 取当前服核心信息; meta 不全就现场问一次, 不再让它崩
MM_T=""; MM_L=""; MM_M=""
_meta_or_ask() {
    MM_T=$(mg type); MM_L=$(mg loader); MM_M=$(mg mc)
    [ -n "${MM_L:-}" ] && [ -n "${MM_M:-}" ] && return 0
    warn "这个服缺少核心信息 (meta 不全)"
    [ -z "${MM_L:-}" ] && {
        echo -e "  ${C}加载器:${R} neoforge / fabric / forge / paper / purpur / folia"
        ask "选一个: "; rd MM_L
    }
    [ -n "$MM_L" ] && [ -z "${MM_M:-}" ] && MM_M=$(pick_mc_version "$MM_L")
    [ -z "${MM_T:-}" ] && case "$MM_L" in
        paper|purpur|folia|velocity) MM_T=plugin;; *) MM_T=mod;;
    esac
    [ -n "$MM_L" ] && [ -n "$MM_M" ] && {
        mkdir -p "$HIST_DIR" 2>/dev/null
        cat > "${HIST_DIR}/${CUR}.meta" <<EOF
type=$MM_T
loader=$MM_L
mc=$MM_M
EOF
    }
    return 0
}

main_menu() {
    while true; do
        clear 2>/dev/null
        banner
        echo -e "  根目录: ${C}$ROOT${R}"
        echo -e "  当前服: ${C}${CUR:-<未选择>}${R}"
        if [ -n "$CUR" ] && [ -f "${HIST_DIR}/${CUR}.meta" ]; then
            echo -e "  类型  : ${C}$(mg type)${R} / ${C}$(mg loader)${R} / MC ${C}$(mg mc)${R}"
        fi
        echo
        echo "   1) 新建服务器"
        echo "   2) 选择/切换服务器"
        echo "   3) 启动服务器"
        echo "   4) 安装/重装核心"
        echo "   5) 云端添加模组 (支持镜像)"
        echo "   6) 云端添加插件 (支持镜像)"
        echo "   7) 导入整合包"
        echo "   8) 存档管理 (切换/备份)"
        echo "   9) 修复缺失文件 (按历史重下)"
        echo "  10) 设置"
        echo "  11) 镜像连通性自检"
        echo "  12) 许可证审计 (标出 ARR 受限资源)"
        echo "  13) 查看联机地址 (自动识别组网工具)"
        echo "  14) 运行日志 (查看 / 清理)"
        echo "  15) 白名单管理 (序号批量增删)"
        echo "  16) 停止服务器 / 查看后台状态"
        echo "  17) 服务器配置 (全部 server.properties 项)"
        echo "  18) 后台保活 (防息屏掉线)"
        echo "  19) 存档保护 (备份 / 回滚)"
        echo "  20) 人员权限 (OP / 封禁)"
        echo "  21) 模组/插件管理 (禁用/删除)"
        echo "  22) 服务器图标 / 简介"
        echo "  23) FRP 多节点穿透 (公网地址)"
        echo "  24) 守护 (崩溃自动拉起 / 定时备份)"
        echo "  25) 一键自检 (环境问题全查)"
        echo "  26) 安卓权限中心 (root/Shizuku/弹窗)"
        echo "  27) 云端公告 (启动时拉取)"
        echo "   0) 退出   ${C}(任何时候也能直接按 q 退出)${R}"
        bg_status_line
        guard_status_line
        frp_status_line
        echo
        ask "选择: "
        rd c || exit 0
        [ -z "$c" ] && continue

        local sdir="${ROOT}/servers/${CUR}"
        [ -z "$CUR" ] && sdir=""

        case "$c" in
        1) new_server;;
        2) srv_menu;;
        3) [ -n "$CUR" ] && start_choose "$sdir" || { warn "先选服务器"; press; };;
        4) [ -n "$CUR" ] && { _meta_or_ask; install_core "$sdir" "${MM_T}" "${MM_L}" "${MM_M}"; press; } || { warn "先选服务器"; press; };;
        5) [ -n "$CUR" ] && { _meta_or_ask; cloud_add "$sdir" mod "${MM_L}" "${MM_M}"; press; } || { warn "先选服务器"; press; };;
        6) [ -n "$CUR" ] && { _meta_or_ask; cloud_add "$sdir" plugin "${MM_L}" "${MM_M}"; press; } || { warn "先选服务器"; press; };;
        7) [ -n "$CUR" ] && import_pack "$sdir" || { warn "先选服务器"; press; };;
        8) [ -n "$CUR" ] && world_menu "$sdir" || { warn "先选服务器"; press; };;
        9) [ -n "$CUR" ] && repair "$sdir" || { warn "先选服务器"; press; };;
        10) settings;;
        11) test_mirror;;
        12) [ -n "$CUR" ] && license_audit "$sdir" || { warn "先选服务器"; press; };;
        13) net_info;;
        14) log_menu;;
        15) wl_menu;;
        16) stop_server;;
        17) prop_menu;;
        18) bk_menu;;
        19) [ -n "$CUR" ] && sp_menu || { warn "先选服务器"; press; };;
        20) [ -n "$CUR" ] && pm_menu || { warn "先选服务器"; press; };;
        21) mp_menu;;
        22) icon_menu;;
        23) frp_menu;;
        24) guard_menu;;
        25) do_diag; press;;
        26) perm_hub;;
        27) ann_menu;;
        0|q|Q) save_conf; echo "再见!"; exit 0;;
        *) ;;
        esac
    done
}

# ============================================================
#  入口
# ============================================================
MR_API="${MR_API:-https://api.modrinth.com/v2}"
JAVA_ARGS="${JAVA_ARGS:-}"
# 云端公告源(多源空格分隔). 给默认值, 开箱即用, 不用手动填
ANN_URL="${ANN_URL:-$ANN_DEFAULT_URL}"
# 自动选最优镜像: 下载卡死/不通时自动换源
AUTO_MIRROR="${AUTO_MIRROR:-1}"
ANN_ON="${ANN_ON:-1}"            # 公告开关
ANN_TTL="${ANN_TTL:-6}"          # 公告缓存小时数(仅 ANN_ALWAYS=0 时生效)
ANN_ALWAYS="${ANN_ALWAYS:-1}"    # 1=每次启动都拉公告(推荐, 有小流量协商)
ANN_EARLY_OK=0                   # 运行期标记: ann_early 是否已拉过

# ---- 探测亚秒 sleep: 决定转圈/进度条的刷新频率 ----
# 之所以提前到这里: 下面装依赖/装 curl 时要用转圈显示进度,
# 如果还放在后面初始化, 那会儿动画还没准备好, 只能干瞪眼等。
# 0.1 = 每 0.1 秒刷一帧(流畅); 1 = 系统不支持小数 sleep, 退化为每秒一帧
TICK=1; TICK_MS=1000
for _t in 0.02 0.03 0.05 0.1 0.2; do
    if sleep "$_t" 2>/dev/null; then TICK=$_t; break; fi
done
case "$TICK" in
    0.02) TICK_MS=20;;  0.03) TICK_MS=30;;  0.05) TICK_MS=50;;
    0.1)  TICK_MS=100;; 0.2)  TICK_MS=200;; *)    TICK_MS=1000;;
esac

# ---- 启动顺序说明 ----
#  1) 先读配置(拿到公告地址), 再把公告弹出来 —— 任何依赖检查之前
#     这样新用户第一次运行、curl/python3 都还没装时, 也能第一时间看到公告
#  2) 然后再自动补齐依赖(缺什么装什么, 不再直接退出)
#  3) 最后 ann_boot 兜底: ann_early 已经显示过的话会被"已读"逻辑挡住, 不会弹两次
load_conf
ann_early

# ---- 依赖准备 ----
# 扫一遍全套依赖(不只是 curl/python3), 缺什么摆出来, 再逐个装
# 分两级: need=缺了功能跑不动, opt=缺了只是不方便
dep_prepare() {
    local miss="" opt=""
    local b

    # —— 必需 ——
    command -v curl    >/dev/null 2>&1 || miss="$miss curl"
    command -v python3 >/dev/null 2>&1 || miss="$miss python3"
    for b in unzip tar; do
        command -v "$b" >/dev/null 2>&1 || miss="$miss $b"
    done

    # —— 可选但强烈建议 ——
    command -v wget >/dev/null 2>&1 || opt="$opt wget"
    # java: 没装不算致命, 装 MC 核心时 ensure_deps 会自动装对应版本
    if ! command -v java >/dev/null 2>&1; then
        opt="$opt java(装核心时自动装)"
    fi
    # termux-api: 唤醒锁/通知/文件选择器都靠它
    if ! command -v termux-wake-lock >/dev/null 2>&1; then
        opt="$opt termux-api(唤醒锁/通知)"
    fi

    [ -z "$miss" ] && [ -z "$opt" ] && return 0   # 全齐, 静默跳过

    echo
    echo -e "  ${B}──── 首次运行: 准备依赖 ────${R}"
    [ -n "$miss" ] && echo -e "  ${RD}必需${R}缺少: ${C}${miss}${R}"
    [ -n "$opt" ]  && echo -e "  ${Y}建议${R}缺少: ${C}${opt}${R}"
    if [ "${AUTO_DEPS:-1}" = 1 ]; then
        echo -e "  正在自动安装, 每个包装完都会提示结果"
    else
        echo -e "  ${Y}自动安装已关闭, 请按提示手动安装${R}"
    fi
    echo -e "  ${B}────────────────────────────${R}"
    return 0
}

# 补装"建议级"依赖: java / termux-api 这类
# 静默调用, 失败只警告不阻断
dep_prepare_opt() {
    [ "${AUTO_DEPS:-1}" = 1 ] || return 0

    # termux-api (唤醒锁/通知用; App 那部分只能指引, 命令行包可以自动)
    if ! command -v termux-wake-lock >/dev/null 2>&1; then
        echo
        echo -e "  ${Y}[!]${R} 未装 ${C}termux-api${R} (唤醒锁/通知/文件选择器依赖它)"
        spin_start "安装 termux-api"
        if _pkg_do termux-api; then
            spin_stop ""
            echo -e "      ${G}✔${R} termux-api 安装完成"
            echo -e "      ${Y}!${R} 还需装 ${C}Termux:API${R} 这个 App (F-Droid / 官网), 否则命令调不动"
        else
            spin_stop ""
            echo -e "      ${RD}✘${R} 安装失败, 唤醒锁/通知功能不可用 (不影响开服)"
        fi
    fi

    # java: 没选服务器就先按当前主流版本预热一个, 有服就按服的版本
    if ! command -v java >/dev/null 2>&1; then
        local jv=21
        [ -n "$CUR" ] && [ -f "${HIST_DIR}/${CUR}.meta" ] && {
            local _mc; _mc=$(mg mc)
            [ -n "${_mc:-}" ] && jv=$(need_java "$_mc" 2>/dev/null || echo 21)
        }
        echo
        echo -e "  ${Y}[!]${R} 未装 Java, 先装 ${C}openjdk-${jv}${R} (体积较大)"
        echo -e "      装 MC 核心时若版本不符, 会自动换成对应版本"
        spin_start "安装 openjdk-${jv}"
        if _pkg_do "openjdk-${jv}"; then
            spin_stop ""
            echo -e "      ${G}✔${R} openjdk-${jv} 安装完成"
        else
            spin_stop ""
            echo -e "      ${RD}✘${R} 安装失败; 装 MC 核心时会重试, 也可手动: ${C}pkg install openjdk-${jv}${R}"
        fi
    fi
    return 0
}

dep_prepare
# 依赖自动安装: 缺 curl / python3 就自己装, 装不上才退出
need_curl
need_py
# 小工具补齐(解压/下载用, 失败只警告)
need_bins
# 建议级依赖(termux-api / java), 失败只警告不阻断
dep_prepare_opt
# 自动选最优镜像(下载卡死时会自动换源)
mirror_auto

mkdir -p "$ROOT"

# 云端公告兜底: ann_early 若因网络/缺少 curl 没拉到, 这里依赖齐全后再试一次
ann_boot

# ---------- 根目录结构初始化 ----------
# dtmcbp/
#   ├── servers/    服务器专属目录(每个服一个子目录)
#   ├── cache/      下载缓存
#   ├── tmp/        临时解压目录
#   ├── backups/    存档备份
#   └── logs/       运行日志
init_root() {
    local r="$1"
    mkdir -p "$r" || { err "无法创建根目录: $r"; return 1; }
    mkdir -p "$r/servers" "$r/cache" "$r/tmp" "$r/backups" "$r/logs"
    return 0
}

# 服务器专属目录 = $ROOT/servers/<名字>
srv_dir() { echo "${ROOT}/servers/${CUR}"; }

# 首次运行: 引导设置根目录
if [ ! -f "$CONF_FILE" ]; then
    title "首次运行 —— 初始化"
    echo "  直接回车 = 使用默认目录:"
    echo -e "  ${C}${DEFAULT_ROOT}${R}"
    echo
    ask "服务器根目录: "
    rd p || exit 0
    if [ -n "$p" ]; then
        ROOT=$(eval echo "${p/#\~/$HOME}")
    else
        ROOT="$DEFAULT_ROOT"
    fi

    if init_root "$ROOT"; then
        say "根目录已就绪: $ROOT"
        echo "    servers/  服务器目录"
        echo "    cache/    下载缓存"
        echo "    tmp/      临时文件"
        echo "    backups/  存档备份"
        echo "    logs/     运行日志"
    else
        err "创建失败, 退回备用目录"
        ROOT="${HOME}/dtmcbp"
        init_root "$ROOT"
    fi

    echo
    ask "Modrinth API 地址 (直接回车=官方, 可填镜像): "
    rd p || exit 0
    [ -n "$p" ] && MR_API="$p"
    save_conf
    say "配置已保存到 $CONF_FILE, 下次自动读取."
    press
else
    # 非首次: 确保目录结构完整(升级兼容)
    init_root "$ROOT" 2>/dev/null
fi

boot_anim
frp_sync 1 >/dev/null 2>&1     # 启动时自动识别 frtt 里的节点
# ---- 非交互入口 (供定时任务调用) ----
NOMENU=""
case "${1:-}" in
  __start)
      [ -n "$CUR" ] || { echo "[x] 未选择服务器 (先运行脚本, 菜单2 选一次)"; exit 1; }
      echo "[*] 定时启动: $CUR"
      if [ -n "$(java_pids 2>/dev/null | tr -d '\n ')" ]; then
          echo "[*] 已在运行, 跳过"; exit 0
      fi
      start_bg "${ROOT}/servers/${CUR}"
      if [ -n "$(java_pids 2>/dev/null | tr -d '\n ')" ]; then
          guard_start_if_on "${ROOT}/servers/${CUR}"
          echo "[+] 守护已挂上"
      fi
      echo "[+] 定时启动完成"
      exit 0;;
  __guard)
      # 守护进程入口: bash mcserv.sh __guard <服务器目录> <CUR> <ROOT>
      [ -f "$CONF_FILE" ] || { echo "[x] 脚本还没初始化过, 先手动运行一次"; exit 1; }
      if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
          echo "[x] __guard 缺少参数"; exit 1
      fi
      CUR="$3"; ROOT="${4:-$ROOT}"
      guard_loop "$2" "$CUR" "$ROOT"
      exit 0;;
  __stop)
      echo "[*] 定时停止"
      guard_stop            # 先撤守护, 免得刚停就被拉起
      local_pids=$(java_pids 2>/dev/null | tr '\n' ' ')
      [ -z "${local_pids// /}" ] && { echo "[*] 没有运行中的服务端"; exit 0; }
      for pp in $local_pids; do kill -TERM "$pp" 2>/dev/null; done
      w=0
      while [ "$w" -lt 30 ]; do
          sleep 1; w=$((w+1))
          [ -z "$(java_pids 2>/dev/null | tr -d '\n ')" ] && break
      done
      if [ -n "$(java_pids 2>/dev/null | tr -d '\n ')" ]; then
          for pp in $local_pids; do kill -KILL "$pp" 2>/dev/null; done
          echo "[*] 已强制结束"
      else
          echo "[+] 已优雅停止"
      fi
      hp=$(cat "${CONF_DIR}/stdin.pid" 2>/dev/null)
      [ -n "$hp" ] && { kill -9 "$hp" 2>/dev/null; wait "$hp" 2>/dev/null; } 2>/dev/null
      rm -f "${CONF_DIR}/stdin.pid" "${CONF_DIR}/server.pid" "${CONF_DIR}/stdin.fifo" 2>/dev/null
      exit 0;;
esac

main_menu

# ============================================================
#  ---- GPL-3.0 声明 (文件结尾) ----
#
#  MC 开服器 (mcserv)
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
#  协议文件(同目录):
#    LICENSE    GNU General Public License v3.0 官方全文(具法律效力)
#    README.md  项目说明与内置公告源地址
#
#  内置云端公告源: https://siyt.de5.net
#    想改成自己的地址完全允许(菜单 27 -> 3), 但把改过的版本分发
#    给他人时, 必须一并提供完整源码并以同样 GPL-3.0 授权。
#
#  本项目与 Mojang Studios / Microsoft / 各加载器与模组项目
#  及其开发团队均无任何隶属、授权、赞助或合作关系, 非官方产品。
#  本脚本不分发任何受著作权保护的游戏文件。
#  SPDX-License-Identifier: GPL-3.0-or-later
#
#  ---- 全文结束 ----
# ============================================================
