/**
 * 西饭短剧 CatPawOpen Spider (xifan.js)
 * 写法对齐官方 hongguo.js：
 *   - category/search 返回 { page, pagecount: hasMore ? page+1 : page, hasMore, list }
 *   - 后续页失败自动降级成「没有下一页」
 *   - 统一错误对象带 code
 *   - 详情返回 { list: [ ... ] }（catalog 只认 list，{vod:...} 不识别）
 */
const meta = {
  id: "xifan",
  name: "西饭短剧",
  version: "1.1.0",
  description: "西饭短剧官方接口，支持分类、搜索、详情与直链播放",
  author: "THL adapter",
  type: "video",
  icon: "",
  features: ["search", "categories"],
  updateUrl: "https://raw.githubusercontent.com/kid941005/hongguo-web/main/sources/builtin/xifan.js"
};

const HOST = "https://xifan-api-cn.youlishipin.com";
const SESSION = "eyJpbmZvIjp7InVpZCI6IiIsInJ0IjoiMTc0MDY1ODI5NCIsInVuIjoiT1BHXzFlZGQ5OTZhNjQ3ZTQ1MjU4Nzc1MTE2YzFkNzViN2QwIiwiZnQiOiIxNzQwNjU4Mjk0In19";
const UA = "okhttp/3.12.11";
const PAGE_SIZE = 30;
const MAX_PAGE = 20;
const TTL = 30 * 60 * 1000;
const states = new Map();

const text = (v) => (v === null || v === undefined ? "" : String(v));
const number = (v) => {
  const n = parseInt(v, 10);
  return isNaN(n) ? 0 : n;
};
const cleanText = (v) => text(v).replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim();
const failure = (message, code) => Object.assign(new Error(message), { code: code });

// requestId = 时间戳 + 固定后缀；不同接口的后缀不同（搜索接口多一段），由 suffix 传入
function apiQuery(suffix) {
  return "version=2001001&androidVersionCode=28&appId=drama&teenMode=false&userBaseMode=false&session=" + SESSION +
    "&requestId=" + Date.now() + "aa498144140ef297" + (suffix || "");
}

async function requestJson(url) {
  let lastError = null;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const res = await fetch(url, { headers: { "User-Agent": UA }, timeoutMs: 15000 });
      const body = await res.text();
      if (!res.ok) throw failure("西饭接口返回 HTTP " + res.status, "HTTP_" + res.status);
      let data = null;
      try { data = JSON.parse(body); } catch (e) { throw failure("西饭接口返回非 JSON", "INVALID_RESPONSE"); }
      if (data && data.ret !== undefined && number(data.ret) !== 0) {
        throw failure("西饭接口返回 ret=" + data.ret, "REJECTED");
      }
      return data || {};
    } catch (err) {
      lastError = err;
      if (err && err.code === "INVALID_RESPONSE") break;
    }
  }
  throw lastError || failure("西饭接口请求失败", "REQUEST_FAILED");
}

function toItem(vod) {
  const id = text(vod.duanjuId).trim();
  const remarks = [];
  const total = number(vod.total);
  if (total > 0) remarks.push(total + "集");
  if (vod.updateStatus === "over") remarks.push("已完结");
  return {
    vod_id: id + "#" + text(vod.source),
    vod_name: cleanText(vod.title) || ("短剧 " + id),
    vod_pic: text(vod.coverImageUrl),
    vod_remarks: remarks.join(" · ")
  };
}

function mapElements(elements) {
  const list = [];
  for (let i = 0; i < (elements || []).length; i++) {
    const contents = (elements[i] && elements[i].contents) || [];
    for (let k = 0; k < contents.length; k++) {
      const vod = contents[k].duanjuVo;
      if (!vod || !vod.duanjuId) continue;
      list.push(toItem(vod));
    }
  }
  return list;
}

function pageState(key) {
  let state = states.get(key);
  if (state && Date.now() - state.updated < TTL) return state;
  state = { pages: new Map(), updated: Date.now() };
  states.delete(key);
  states.set(key, state);
  while (states.size > 32) states.delete(states.keys().next().value);
  return state;
}

function packPage(state, page, list, hasMoreOverride, pageCount) {
  const hasMore = typeof hasMoreOverride === "boolean"
    ? hasMoreOverride
    : (list.length > 0 && page < MAX_PAGE);
  // pagecount 只回真实总页数（0 = 源端不提供），不再用 page+1 伪造。
  const result = { page: page, pagecount: Number(pageCount) || 0, hasMore: hasMore, list: list };
  state.pages.set(page, result);
  state.updated = Date.now();
  return result;
}

function init(extend) {
  states.clear();
}

async function home(filter) {
  const response = await requestJson(HOST + "/xifan/drama/portalPage?reqType=duanjuCategory&" + apiQuery());
  const elements = (response.result && response.result.elements) || [];
  const classes = [];
  const seen = {};
  for (let i = 0; i < elements.length; i++) {
    const contents = (elements[i] && elements[i].contents) || [];
    for (let k = 0; k < contents.length; k++) {
      const cell = contents[k];
      const vo = cell.categoryItemVo;
      if (!vo || vo.categoryId === undefined) continue;
      const types = cell.type || [];
      let isCategory = false;
      for (let t = 0; t < types.length; t++) {
        if (text(types[t]).indexOf("duanjuCategory") >= 0) isCategory = true;
      }
      if (!isCategory) continue;
      const name = cleanText(vo.oppoCategory);
      const id = text(vo.categoryId) + "@" + name;
      if (seen[id]) continue;
      seen[id] = true;
      classes.push({ type_id: id, type_name: name });
    }
  }
  // 分类接口偶尔抽风：兜一个已知可用的分类，至少让首页有内容
  if (classes.length === 0) classes.push({ type_id: "68@都市", type_name: "都市" });
  return { class: classes, filters: {} };
}

async function category(tid, page, filter, extend) {
  const parts = text(tid).split("@");
  const categoryId = parts[0] || "68";
  const categoryName = parts.slice(1).join("@"); // 分类名里可能带 @，全部保留
  const current = Math.max(1, number(page) || 1);

  const state = pageState("xifan:" + text(tid));
  if (state.pages.has(current)) return state.pages.get(current);

  try {
    const offset = (current - 1) * PAGE_SIZE;
    const url = HOST + "/xifan/drama/portalPage?reqType=aggregationPage&offset=" + offset +
      "&categoryId=" + encodeURIComponent(categoryId) +
      "&quickEngineVersion=-1&scene=&categoryNames=" + encodeURIComponent(categoryName) +
      "&categoryVersion=1&density=1.5&pageID=page_theater&" + apiQuery();
    const response = await requestJson(url);
    const list = mapElements((response.result && response.result.elements) || []);
    // 一页不满即到底；满页时多拉一页空页作为结束信号
    const hasMore = list.length >= PAGE_SIZE && current < MAX_PAGE;
    return packPage(state, current, list, hasMore, 0);
  } catch (err) {
    if (current > 1) {
      return { page: current, pagecount: current, hasMore: false, list: [] };
    }
    throw err;
  }
}

async function detail(id) {
  const raw = text(id).replace(/^xifan:/, "").trim();
  const parts = raw.split("#");
  const duanjuId = parts[0];
  const source = parts[1] || "";
  if (!duanjuId) throw failure("无效的短剧 ID", "INVALID_ID");

  const url = HOST + "/xifan/drama/getDuanjuInfo?duanjuId=" + encodeURIComponent(duanjuId) +
    "&source=" + encodeURIComponent(source) +
    "&openFrom=homescreen&type=&pageID=page_inner_flow&density=1.5&" + apiQuery();
  const response = await requestJson(url);
  const data = response.result || {};
  const episodes = data.episodeList || [];

  const playUrls = [];
  for (let i = 0; i < episodes.length; i++) {
    const ep = episodes[i];
    const playUrl = text(ep.playUrl);
    if (!/^https?:\/\//i.test(playUrl)) continue;
    const index = number(ep.index);
    playUrls.push("第" + (index > 0 ? index : i + 1) + "集$" + playUrl);
  }

  const remarks = [];
  const total = number(data.total);
  if (total > 0) remarks.push(total + "集");
  if (playUrls.length > 0 && total === 0) remarks.push("全" + playUrls.length + "集");
  if (data.updateStatus === "over") remarks.push("已完结");

  return {
    list: [{
      vod_id: raw,
      vod_name: cleanText(data.title) || ("短剧 " + duanjuId),
      vod_pic: text(data.coverImageUrl),
      vod_content: cleanText(data.desc),
      vod_remarks: remarks.join(" · "),
      vod_play_from: "西饭短剧",
      vod_play_url: playUrls.join("#")
    }]
  };
}

async function search(keyword, quick, page) {
  const word = cleanText(keyword).slice(0, 60);
  const current = Math.max(1, number(page) || 1);
  if (!word) return { page: 1, pagecount: 1, hasMore: false, list: [] };

  const state = pageState("xifan:search:" + word);
  if (state.pages.has(current)) return state.pages.get(current);

  try {
    const url = HOST + "/xifan/search/getSearchList?keyword=" + encodeURIComponent(word) +
      "&pageIndex=" + current + "&" + apiQuery("ea3a14bc0317d76f");
    const response = await requestJson(url);
    const list = mapElements((response.result && response.result.elements) || []);
    // 搜索接口不返回总数/游标：本页有数据就继续，拉到空页为止
    return packPage(state, current, list, undefined, 0);
  } catch (err) {
    if (current > 1) {
      return { page: current, pagecount: current, hasMore: false, list: [] };
    }
    throw err;
  }
}

async function play(flag, id, flags) {
  const target = text(id).replace(/^xifan:/, "").trim();
  if (/^https?:\/\//i.test(target)) {
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
