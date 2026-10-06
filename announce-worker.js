// ============================================================
//  mcserv 云端公告服务 (Cloudflare Worker + KV)
//  配套 mcserv.sh 菜单 27, 提供网页后台改公告
//
//  Copyright (C) 2026  bwt1346 <ok819@qq.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
// ============================================================

/**
 * mcserv 云端公告服务 —— Cloudflare Worker + KV + 网页后台
 *
 * ── 提供的入口 ──────────────────────────────────────────
 *   GET  /                    → 给 mcserv 脚本拉的公告(JSON), 支持 ?v= 版本协商
 *   GET  /aaaaadddmie         → 网页后台(浏览器打开, Basic Auth 弹窗输密码)
 *   POST /aaaaadddmie/save    → 后台保存公告
 *   GET  /aaaaadddmie/logout  → 登出
 *   其它路径                  → 404 Not Found(静默, 不泄露接口)
 *
 * ── 部署 ────────────────────────────────────────────────
 *   1. Workers 和 Pages → KV → 创建命名空间(名字随意)
 *   2. Workers 和 Pages → 创建 Worker → 粘贴本文件 → 部署
 *   3. Worker → 设置 → 变量和机密:
 *        KV 命名空间绑定:  变量名 ANKV                 ← 必须叫这个
 *        环境变量/机密:     ANNOUNCE_ADMIN_PASS = 密码
 *   4. 可选: 设置 → 域和路由 → 添加自定义域
 *
 * ── 换后台路径 ──────────────────────────────────────────
 *   改下面 ADMIN_PATH 这一行, 重新部署即可.
 */

// ==================== 配置 ====================
const ADMIN_PATH = "/aaaaadddmie";        // ← 后台路径, 想改成别的就改这里
const KV_KEY     = "current";              // KV 里存公告的键名
const DEFAULT_PASS = "mcserv";             // 没设环境变量时的兜底密码
const MAX_FAIL   = 5;                      // 连续输错几次锁定
const LOCK_MIN   = 15;                     // 锁多少分钟
// ==============================================

// 默认公告: KV 为空时返回这个
const FALLBACK = {
  v: "20261005",
  title: "mcserv 公告服务已上线",
  level: "info",
  body: [
    "后台地址: " + ADMIN_PATH,
    "",
    "去后台改这条公告吧"
  ],
  ttl: 6
};

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const p = url.pathname.replace(/\/+$/, "") || "/";

    // 只允许 GET / POST
    if (!["GET", "HEAD", "POST"].includes(req.method)) {
      return new Response("Method Not Allowed", { status: 405 });
    }

    // ---- 公告接口 ----
    if (p === "/") return handleAnnounce(req, env, url);

    // ---- 后台 ----
    if (p === ADMIN_PATH) return handleAdmin(req, env, url);
    if (p === ADMIN_PATH + "/save") return handleSave(req, env);
    if (p === ADMIN_PATH + "/logout") return handleLogout();

    // ---- 其它一律静默 404 ----
    return new Response("404 Not Found", {
      status: 404,
      headers: { "content-type": "text/plain; charset=utf-8" }
    });
  }
};

// ══════════════ 公告接口 ══════════════
async function handleAnnounce(req, env, url) {
  const data = await loadAnnounce(env);
  const clientV = url.searchParams.get("v");

  // 版本协商: 客户端已读版本一致 → 告诉它不用更新
  if (clientV && String(data.v) === String(clientV)) {
    return json({ upToDate: true }, req.method === "HEAD");
  }
  return json(data, req.method === "HEAD");
}

async function loadAnnounce(env) {
  if (env.ANKV) {
    try {
      const kv = await env.ANKV.get(KV_KEY, { type: "json" });
      if (kv && typeof kv === "object") {
        // 补全缺省字段, 免得后台漏填导致客户端出问题
        return {
          v: String(kv.v || ""),
          title: kv.title || "",
          level: kv.level || "info",
          body: Array.isArray(kv.body) ? kv.body
                : typeof kv.body === "string" ? kv.body.split("\n") : [],
          ttl: Number(kv.ttl) > 0 ? Number(kv.ttl) : undefined
        };
      }
    } catch (e) { /* KV 读失败就用兜底 */ }
  }
  return FALLBACK;
}

// ══════════════ 网页后台 ══════════════
async function handleAdmin(req, env, url) {
  // 先查锁定状态
  // 紧急解锁: /aaaaadddmie?reset=1  (锁定后清计数用, 优先于一切)
  if (url.searchParams.get("reset")) {
    return html(resultPage("已重置",
      "登录失败计数已清零, 现在可以重新登录了。", true, ADMIN_PATH), clearCookies());
  }

  const lock = await checkLock(req);
  if (lock.locked) return lockResponse(lock.left);

  // Basic Auth 校验
  const auth = req.headers.get("authorization") || "";
  // 注意: 这里是"还没输密码"的首次访问, 绝对不能计数!
  // 否则每刷新一次页面就 +1, 刷 5 次就被锁, 根本没输错过
  if (!auth.startsWith("Basic ")) {
    return needAuth(req);
  }

  let user = "", pass = "";
  try {
    const dec = atob(auth.slice(6));
    const i = dec.indexOf(":");
    user = dec.slice(0, i);
    pass = dec.slice(i + 1);
  } catch (e) {
    return needAuth(req);
  }

  const want = env.ANNOUNCE_ADMIN_PASS || DEFAULT_PASS;
  if (pass !== want) {
    // 只有真的输错密码才计数
    const next = Number(parseCookies(req).af_cnt || 0) + 1;
    if (next >= MAX_FAIL) return lockResponse(LOCK_MIN);
    return needAuth(req, `密码错误, 还可尝试 ${MAX_FAIL - next} 次`, next);
  }

  // 密码对: 清失败计数, 渲染后台
  const cc = clearCookies();
  const data = await loadAnnounce(env);
  const usingDefault = !env.ANNOUNCE_ADMIN_PASS;
  const hasKV = !!env.ANKV;
  return html(page(data, usingDefault, hasKV, ADMIN_PATH), cc);
}

async function handleSave(req, env) {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  const lock = await checkLock(req);
  if (lock.locked) return lockResponse(lock.left);

  const auth = req.headers.get("authorization") || "";
  if (!auth.startsWith("Basic ")) return needAuth(req);
  let pass = "";
  try {
    const dec = atob(auth.slice(6));
    pass = dec.slice(dec.indexOf(":") + 1);
  } catch (e) { return needAuth(req); }

  const want = env.ANNOUNCE_ADMIN_PASS || DEFAULT_PASS;
  if (pass !== want) {
    const next = Number(parseCookies(req).af_cnt || 0) + 1;
    if (next >= MAX_FAIL) return lockResponse(LOCK_MIN);
    return needAuth(req, `密码错误, 还可尝试 ${MAX_FAIL - next} 次`, next);
  }
  const cc = clearCookies();

  // 没绑 KV → 明确报错, 不假装成功
  if (!env.ANKV) {
    return html(resultPage("保存失败", "未绑定 KV 命名空间。<br>请在 Worker 设置里绑定变量名 <code>ANKV</code>。", false, ADMIN_PATH), cc);
  }

  let form;
  try {
    form = await req.formData();
  } catch (e) {
    return html(resultPage("保存失败", "表单解析失败: " + String(e), false, ADMIN_PATH), cc);
  }

  const raw = String(form.get("body") || "");
  const payload = {
    v:     String(form.get("v") || "").trim(),
    title: String(form.get("title") || "").trim(),
    level: String(form.get("level") || "info").trim(),
    body:  raw.split("\n"),
    ttl:   Number(form.get("ttl")) || undefined
  };

  try {
    await env.ANKV.put(KV_KEY, JSON.stringify(payload));
  } catch (e) {
    return html(resultPage("保存失败", "写入 KV 出错: " + String(e), false, ADMIN_PATH), cc);
  }

  return html(resultPage("保存成功",
    `版本号 <b>${esc(payload.v || "(空)")}</b> 已写入。<br>客户端下次拉取就会显示新公告。`,
    true, ADMIN_PATH), cc);
}

function handleLogout() {
  // Basic Auth 没有真正的登出, 返回 401 让浏览器弹新框
  return new Response("已登出", {
    status: 401,
    headers: {
      "WWW-Authenticate": 'Basic realm="mcserv announce admin", charset="UTF-8"',
      "content-type": "text/plain; charset=utf-8"
    }
  });
}

// ══════════════ 登录失败计数(存 Cookie) ══════════════
// 无状态的轻量做法: 失败次数和锁定时间戳放客户端 Cookie,
// 换浏览器能绕过, 但对付随手扫的足够了. 要严格就上 KV 记 IP.
function parseCookies(req) {
  const out = {};
  const c = req.headers.get("cookie") || "";
  c.split(";").forEach(s => {
    const i = s.indexOf("=");
    if (i > 0) out[s.slice(0, i).trim()] = s.slice(i + 1).trim();
  });
  return out;
}

async function checkLock(req) {
  const ck = parseCookies(req);
  const until = Number(ck.af_lock || 0);
  const now = Date.now();
  if (until && now < until) {
    return { locked: true, left: Math.ceil((until - now) / 60000) };
  }
  return { locked: false, left: 0 };
}

// 失败计数统一由 needAuth(req, msg, count) 写入, 这里不再需要单独函数

// 登录成功后把失败计数清零, 返回要下发的 Set-Cookie 数组
// (一个 Set-Cookie 头只能设一个 cookie, 所以返回数组让调用方 append)
function clearCookies() {
  const exp = "Path=/; Max-Age=1";   // Max-Age=1 等于立刻过期 = 删除
  return [`af_cnt=0; ${exp}`, `af_lock=0; ${exp}`];
}

function lockResponse(left) {
  const body = `<h2 style="color:#f87171">已锁定</h2>
    <p>连续输错密码 ${MAX_FAIL} 次。</p>
    <p>解锁办法(任选一个):</p>
    <p>
      1. 点 <a href="${ADMIN_PATH}?reset=1">这里立即清零</a> ← 最快<br>
      2. 等 ${left} 分钟自动解除<br>
      3. 清除本网站的 Cookie 和已保存的密码
    </p>
    <p style="color:#8b93a7;font-size:13px">
      提示: 浏览器会记住 Basic Auth 密码, 如果之前存错过,
      即使刷新也会一直发错误密码。建议用无痕窗口重开。
    </p>`;
  return new Response(body, {
    status: 429,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "retry-after": String(left * 60)
    }
  });
}

// ══════════════ 响应构造 ══════════════
// count: 传数字才写计数 cookie(表示"真的输错了"); 不传 = 只是首次弹框, 不计数
function needAuth(req, msg, count) {
  const h = new Headers({
    "WWW-Authenticate": 'Basic realm="mcserv announce admin", charset="UTF-8"',
    "content-type": "text/html; charset=utf-8"
  });
  if (count != null) {
    h.append("set-cookie", `af_cnt=${count}; Path=/; Max-Age=3600`);
    if (count >= MAX_FAIL) {
      h.append("set-cookie",
        `af_lock=${Date.now() + LOCK_MIN * 60000}; Path=/; Max-Age=${LOCK_MIN * 60}`);
    }
  }
  const body = msg
    ? `<h3 style="color:#c00">${esc(msg)}</h3>`
    : "";
  return new Response(body || "需要认证", { status: 401, headers: h });
}

function json(data, headOnly) {
  return new Response(headOnly ? null : JSON.stringify(data), {
    status: 200,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "access-control-allow-origin": "*",
      "cache-control": "public, max-age=60"
    }
  });
}

// cookies: 可选的 Set-Cookie 字符串数组, 登录成功时用来清失败计数
function html(s, cookies) {
  const h = new Headers({
    "content-type": "text/html; charset=utf-8",
    "cache-control": "no-store",
    "x-robots-tag": "noindex, nofollow"
  });
  if (Array.isArray(cookies)) cookies.forEach(c => h.append("set-cookie", c));
  return new Response(s, { status: 200, headers: h });
}

// ══════════════ 页面 ══════════════
function esc(s) {
  return String(s).replace(/[&<>"']/g, c =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function css() {
  return `
  *{box-sizing:border-box}
  body{margin:0;padding:16px;background:#12141a;color:#e8eaed;
       font:15px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif}
  h2{margin:0 0 4px;font-size:20px}
  .sub{color:#8b93a7;font-size:13px;margin-bottom:18px;word-break:break-all}
  .warn{background:#3a2a12;border-left:3px solid #e8a33d;padding:10px 12px;
        margin-bottom:16px;border-radius:4px;font-size:13px}
  label{display:block;margin:14px 0 6px;font-size:13px;color:#a8b0c0}
  .hint{color:#6b7385;font-size:12px;margin-left:6px}
  input[type=text],input[type=number],textarea,select{
       width:100%;padding:11px 12px;background:#1c1f27;border:1px solid #2e3340;
       border-radius:8px;color:#e8eaed;font-size:15px;font-family:inherit}
  textarea{min-height:150px;resize:vertical;line-height:1.6}
  input:focus,textarea:focus,select:focus{outline:none;border-color:#4a7cf7}
  .row{display:flex;gap:12px}
  .row>div{flex:1}
  button{width:100%;margin-top:20px;padding:14px;background:#4a7cf7;color:#fff;
         border:0;border-radius:8px;font-size:16px;font-weight:600;cursor:pointer}
  button:active{background:#3a68d8}
  .meta{color:#6b7385;font-size:12px;margin-top:14px;text-align:center}
  a{color:#4a7cf7}
  code{background:#1c1f27;padding:2px 6px;border-radius:4px;font-size:13px}
  .ok{color:#4ade80}.bad{color:#f87171}
  `;
}

function page(d, usingDefault, hasKV, adminPath) {
  const bodyText = Array.isArray(d.body) ? d.body.join("\n") : String(d.body || "");
  const lv = d.level || "info";
  const warn = [
    usingDefault ? "⚠️ 正在使用默认密码 <code>mcserv</code>，请到 Worker 设置里配置 <code>ANNOUNCE_ADMIN_PASS</code>。" : "",
    !hasKV ? "⚠️ 未绑定 KV 命名空间 <code>ANKV</code>，保存会失败。" : ""
  ].filter(Boolean).join("<br>");

  return `<!DOCTYPE html><html lang="zh-CN"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>mcserv 公告后台</title><style>${css()}</style></head>
<body>
<h2>mcserv 公告后台</h2>
<div class="sub">${esc(adminPath)}</div>
${warn ? `<div class="warn">${warn}</div>` : ""}
<form method="post" action="${esc(adminPath)}/save">
  <label>版本号 <span class="hint">改了才会重新弹</span></label>
  <input type="text" name="v" value="${esc(d.v || "")}" placeholder="例: 20261005">

  <label>标题</label>
  <input type="text" name="title" value="${esc(d.title || "")}" placeholder="公告框顶部大字">

  <label>级别 <span class="hint">决定公告框颜色</span></label>
  <select name="level">
    <option value="info"${lv === "info" ? " selected" : ""}>info 黄（普通）</option>
    <option value="warn"${lv === "warn" ? " selected" : ""}>warn 青（提醒）</option>
    <option value="urgent"${lv === "urgent" ? " selected" : ""}>urgent 红（紧急）</option>
  </select>

  <label>正文 <span class="hint">一行一条，空行就是空行</span></label>
  <textarea name="body" placeholder="第一行&#10;第二行">${esc(bodyText)}</textarea>

  <label>缓存小时 <span class="hint">1-168，客户端多久重拉一次</span></label>
  <input type="number" name="ttl" min="1" max="168" value="${esc(d.ttl || 6)}">

  <button type="submit">保存</button>
</form>
<div class="meta"><a href="${esc(adminPath)}/logout">登出</a></div>
</body></html>`;
}

function resultPage(title, msg, ok, adminPath) {
  return `<!DOCTYPE html><html lang="zh-CN"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>${esc(title)}</title><style>${css()}</style></head>
<body>
<h2 class="${ok ? "ok" : "bad"}">${esc(title)}</h2>
<div class="sub">${msg}</div>
<a href="${esc(adminPath)}">← 返回后台</a>
</body></html>`;
}
