/**
 * 星芽短剧 CatPawOpen Spider (xingya.js)
 * 接口：登录换 token -> 首页/分类列表 -> 详情拿直链 mp4 -> 搜索。
 * 写法对齐官方 hongguo.js / 七猫西饭源：
 *   - category/search 返回 { page, pagecount: hasMore ? page+1 : page, hasMore, list }
 *   - 后续页失败自动降级成「没有下一页」
 *   - 统一错误对象带 code
 *   - detail 返回 { list: [ ... ] }
 */
const meta = {
  id: "xingya",
  name: "星芽短剧",
  version: "1.0.0",
  description: "星芽短剧官方接口，支持分类、搜索、详情与直链播放",
  author: "THL adapter",
  type: "video",
  icon: "",
  features: ["search", "categories"],
  updateUrl: "https://raw.githubusercontent.com/kid941005/hongguo-web/main/sources/builtin/xingya.js"
};

const HOST = "https://app.whjzjx.cn";
const LOGIN_HOST = "https://u.shytkjgs.com";
const DEVICE = "24250683a3bdb3f118dff25ba4b1cba1a";
const UA = "okhttp/3.12.11";
const PAGE_SIZE = 24;
const MAX_PAGE = 50;
const TTL = 30 * 60 * 1000;
const TOKEN_TTL = 30 * 60 * 1000;
const states = new Map();

let token = "";
let tokenAt = 0;

const text = (v) => (v === null || v === undefined ? "" : String(v));
const number = (v) => {
  const n = parseInt(v, 10);
  return isNaN(n) ? 0 : n;
};
const cleanText = (v) => text(v).replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim();
const failure = (message, code) => Object.assign(new Error(message), { code: code });

function pageState(key) {
  let state = states.get(key);
  if (state && Date.now() - state.updated < TTL) return state;
  state = { pages: new Map(), updated: Date.now() };
  states.delete(key);
  states.set(key, state);
  while (states.size > 32) states.delete(states.keys().next().value);
  return state;
}

function packPage(state, page, list, hasMore, pageCount) {
  const more = Boolean(hasMore) && list.length > 0 && page < MAX_PAGE;
  // pagecount 只回真实总页数（0 = 源端不提供），不再用 page+1 伪造。
  const result = { page: page, pagecount: Number(pageCount) || 0, hasMore: more, list: list };
  state.pages.set(page, result);
  state.updated = Date.now();
  return result;
}

async function login() {
  const res = await fetch(LOGIN_HOST + "/user/v1/account/login", {
    method: "POST",
    headers: {
      "User-Agent": "okhttp/4.10.0",
      "platform": "1",
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ device: DEVICE }),
    timeoutMs: 15000
  });
  const raw = await res.text();
  if (!res.ok) throw failure("星芽登录返回 HTTP " + res.status, "HTTP_" + res.status);
  let data = null;
  try { data = JSON.parse(raw); } catch (e) { throw failure("星芽登录返回非 JSON", "INVALID_RESPONSE"); }
  const value = data && data.data && data.data.token;
  if (!value) throw failure("星芽登录失败", "LOGIN_FAILED");
  token = text(value);
  tokenAt = Date.now();
  return token;
}

async function ensureToken(force) {
  if (!force && token && Date.now() - tokenAt < TOKEN_TTL) return token;
  return await login();
}

async function requestJson(url, options, retried) {
  const current = await ensureToken(false);
  const opts = options || {};
  const headers = Object.assign({}, opts.headers || {}, {
    "User-Agent": UA,
    "content-type": "application/json; charset=utf-8",
    "authorization": current
  });
  let res;
  try {
    res = await fetch(url, { method: opts.method || "GET", headers: headers, body: opts.body, timeoutMs: 15000 });
  } catch (err) {
    throw failure("星芽请求失败", "REQUEST_FAILED");
  }
  const raw = await res.text();
  if (!res.ok) throw failure("星芽接口返回 HTTP " + res.status, "HTTP_" + res.status);
  let data = null;
  try { data = JSON.parse(raw); } catch (e) { throw failure("星芽接口返回非 JSON", "INVALID_RESPONSE"); }
  if (data && data.code && data.code !== "ok" && data.code !== 0) {
    // token 过期时自动重登一次
    if (!retried && /Unauthorized|签名失败/i.test(text(data.code) + text(data.msg))) {
      await ensureToken(true);
      return await requestJson(url, options, true);
    }
    throw failure(text(data.msg) || "星芽接口拒绝请求", "REJECTED");
  }
  return (data && data.data) || {};
}

function toItem(vod) {
  const id = text(vod.id).trim();
  const remarks = [];
  const total = number(vod.total);
  if (total > 0) remarks.push(total + "集");
  if (vod.play_amount_str) remarks.push(text(vod.play_amount_str) + "次播放");
  return {
    vod_id: id,
    vod_name: cleanText(vod.title) || ("短剧 " + id),
    vod_pic: text(vod.cover_url),
    vod_remarks: remarks.join(" · ")
  };
}

function mapTheaters(rows) {
  const list = [];
  for (let i = 0; i < (rows || []).length; i++) {
    const theater = (rows[i] && rows[i].theater) || rows[i];
    if (!theater || theater.id === undefined) continue;
    const item = toItem(theater);
    if (item.vod_id) list.push(item);
  }
  return list;
}

function init(extend) {
  states.clear();
  token = "";
  tokenAt = 0;
}

async function home(filter) {
  return {
    class: [
      { type_id: "1", type_name: "推荐" },
      { type_id: "2", type_name: "男频" },
      { type_id: "3", type_name: "女频" }
    ],
    filters: {}
  };
}

async function category(tid, page, filter, extend) {
  const area = text(tid) || "1";
  const current = Math.max(1, number(page) || 1);
  const state = pageState("xingya:" + area);
  if (state.pages.has(current)) return state.pages.get(current);
  try {
    const url = HOST + "/cloud/v2/theater/home_page?theater_class_id=" + encodeURIComponent(area) +
      "&type=1&class2_ids=0&page_num=" + current + "&page_size=" + PAGE_SIZE;
    const data = await requestJson(url);
    const rows = (data && data.list) || [];
    const list = mapTheaters(rows);
    const hasMore = rows.length >= PAGE_SIZE && current < MAX_PAGE;
    return packPage(state, current, list, hasMore, 0);
  } catch (err) {
    if (current > 1) return { page: current, pagecount: current, hasMore: false, list: [] };
    throw err;
  }
}

async function detail(id) {
  const parentId = text(id).replace(/^xingya:/, "").trim();
  if (!/^\d+$/.test(parentId)) throw failure("无效的短剧 ID", "INVALID_ID");
  const url = HOST + "/v2/theater_parent/detail?theater_parent_id=" + encodeURIComponent(parentId);
  const data = await requestJson(url);
  const episodes = [];
  const rows = data.theaters || [];
  for (let i = 0; i < rows.length; i++) {
    const ep = rows[i];
    const playUrl = text(ep.son_video_url);
    if (!/^https?:\/\//i.test(playUrl)) continue;
    const num = number(ep.num) || (i + 1);
    episodes.push("第" + num + "集$" + playUrl);
  }
  const remarks = [];
  const total = number(data.total);
  if (total > 0) remarks.push(total + "集");
  const tags = (data.class_two || []).map(function (x) { return x.class_name; }).filter(Boolean);
  if (tags.length > 0) remarks.push(tags.slice(0, 3).join(" "));
  return {
    list: [{
      vod_id: parentId,
      vod_name: cleanText(data.title) || ("短剧 " + parentId),
      vod_pic: text(data.cover_url),
      vod_content: cleanText(data.introduction),
      vod_remarks: remarks.join(" · "),
      vod_play_from: "星芽短剧",
      vod_play_url: episodes.join("#")
    }]
  };
}

async function search(keyword, quick, page) {
  const word = cleanText(keyword).slice(0, 60);
  const current = Math.max(1, number(page) || 1);
  if (!word) return { page: 1, pagecount: 1, hasMore: false, list: [] };
  const state = pageState("xingya:search:" + word);
  if (state.pages.has(current)) return state.pages.get(current);
  try {
    const data = await requestJson(HOST + "/v3/search", {
      method: "POST",
      headers: { "content-type": "application/json; charset=utf-8" },
      body: JSON.stringify({ text: word })
    });
    const rows = (data && data.theater && data.theater.search_data) || [];
    const list = [];
    for (let i = 0; i < rows.length; i++) {
      const item = toItem(rows[i]);
      if (item.vod_id) list.push(item);
    }
    // 搜索结果接口不分页：只返回第一页，标记结束避免无限请求
    return packPage(state, current, current === 1 ? list : [], false, 0);
  } catch (err) {
    if (current > 1) return { page: current, pagecount: current, hasMore: false, list: [] };
    throw err;
  }
}

async function play(flag, id, flags) {
  const target = text(id).replace(/^xingya:/, "").trim();
  if (/^https?:\/\/[^\s]+$/i.test(target)) {
    return { parse: 0, url: target, header: { "User-Agent": UA } };
  }
  return { parse: 0, url: "", header: {}, error: "MISSING_EPISODE" };
}

var spider = {
  meta: meta,
  init: init,
  home: home,
  category: category,
  detail: detail,
  search: search,
  play: play
};

globalThis.spider = spider;
