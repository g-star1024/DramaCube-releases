// ============================================================================
// 极速短剧 —— 苹果CMS(MacCMS V10) 短剧采集源（内置，自包含）。
//
// 通用 MacCMS 适配器 + 本站真实接口 + 短剧专用类过滤。
// 短剧分散在多个子类（45=古装仙侠 / 46=现代都市 / 47=穿越年代 / 50=反转爽剧 /
// 52=脑洞悬疑 / 54=AI漫剧）；主类 38 实测为空，48/49/53(擦边) 实测异常，已剔除。
//   - home() 只出上述短剧子类
//   - category(空分类) 默认拉最大子类 46（现代都市）
//   - search() 全库搜（无单一「短剧」父类可限定，搜索为次级能力）
//   - detail() 标准 MacCMS 分集，m3u8 直链
//
// 只依赖 fetch，不依赖任何 Node 模块。改 __CFG.api 即可换站。
// ============================================================================

var __CFG = {
  id: 'jisu',
  name: '极速短剧',
  api: 'https://jszyapi.com/api.php/provide/vod/',
  // 短剧专用：home 只展示这些子类（45/46/47/50/52/54）。空数组 = 全部类（通用源）。
  categories: ['45', '46', '47', '50', '52', '54'],
  // 空分类（app「最新」）默认拉的类；短剧源必须指向短剧类，否则「最新」会混入全库。
  primary: '46',
  // 搜索限定类（空 = 全库搜）。极速无单一「短剧」父类，故全库搜（次级能力）。
  searchType: '',
  ua: 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36'
};

var meta = {
  id: __CFG.id,
  name: __CFG.name,
  version: '1.0.0',
  description: __CFG.name + '（MacCMS V10 采集站，短剧专用）',
  author: '',
  type: 'video',
  features: ['search', 'categories']
};

var failure = function (message, code) { return Object.assign(new Error(message), { code: code }); };

function buildUrl(params) {
  var base = __CFG.api.replace(/[?&]+$/, '');
  if (base.indexOf('?') < 0) base += '?';
  var parts = [];
  for (var key in params) {
    if (!Object.prototype.hasOwnProperty.call(params, key)) continue;
    var value = params[key];
    if (value === undefined || value === null || value === '') continue;
    parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(String(value)));
  }
  if (parts.length === 0) return base;
  return base + (base.charAt(base.length - 1) === '?' ? '' : '&') + parts.join('&');
}

// 单次请求，不重试（v2.8.4 用户实测：采集站慢/502 时重试把 20s×2=40s
// 放大超过 app 30s 页面超时→「列表加载超时」。单次=20s 内返回结果或失败，
// 配合 app 侧超时上限不再翻倍干等。间歇慢站（如极速 3-25s）单次可救回。）
async function getJson(params) {
  var url = buildUrl(params);
  try {
    var res = await fetch(url, { headers: { 'User-Agent': __CFG.ua, 'Accept': 'application/json' }, timeoutMs: 15000 });
    var text = await res.text();
    if (!res.ok) throw failure('接口返回 HTTP ' + res.status, 'HTTP_' + res.status);
    var data;
    try { data = JSON.parse(text); } catch (e) { throw failure('接口返回的不是 JSON（前 120 字）：' + text.slice(0, 120), 'INVALID_RESPONSE'); }
    if (data && data.code !== undefined && Number(data.code) !== 1) {
      throw failure('接口返回 code=' + data.code + ' msg=' + (data.msg || ''), 'REJECTED');
    }
    return data || {};
  } catch (err) {
    throw err || failure('接口请求失败', 'REQUEST_FAILED');
  }
}

// MacCMS 的 total/limit/pagecount 不一定都有，按能拿到的推算还有没有下一页。
function packPage(data, page, list) {
  var pageCount = Number(data.pagecount) || Number(data.pageCount) || 0;
  if (!pageCount && Number(data.total) > 0 && Number(data.limit) > 0) {
    pageCount = Math.ceil(Number(data.total) / Number(data.limit));
  }
  var hasMore = pageCount ? page < pageCount : list.length > 0;
  return { page: page, pagecount: pageCount || page, hasMore: hasMore, list: list };
}

function toList(vod) {
  return {
    vod_id: String(vod.vod_id || ''),
    vod_name: String(vod.vod_name || ''),
    vod_pic: String(vod.vod_pic || ''),
    vod_remarks: String(vod.vod_remarks || '')
  };
}

function init(cfg) {}

async function home(filter) {
  var data = await getJson({ ac: 'list' });
  var classes = data.class || [];
  var out = [];
  for (var i = 0; i < classes.length; i++) {
    var c = classes[i];
    if (!c || c.type_id === undefined) continue;
    var tid = String(c.type_id);
    // 短剧专用：只保留配置的短剧类；通用源（categories 空）保留全部。
    if (__CFG.categories.length > 0 && __CFG.categories.indexOf(tid) < 0) continue;
    out.push({ type_id: tid, type_name: String(c.type_name || '') });
  }
  // 站方改了类ID导致匹配不到时，兜底用主类，避免整源「无分类」不可用。
  if (out.length === 0 && __CFG.primary) {
    out.push({ type_id: __CFG.primary, type_name: '短剧' });
  }
  return { class: out, filters: {} };
}

async function category(tid, page, filter, extend) {
  page = Number(page) || 1;
  // 空分类（app「最新」）默认拉主类；短剧源主类=短剧类，通用源主类=''→全库。
  var t = String(tid || __CFG.primary || '');
  var data = await getJson({ ac: 'detail', t: t, pg: page });
  var rows = data.list || [];
  var out = [];
  for (var i = 0; i < rows.length; i++) out.push(toList(rows[i]));
  return packPage(data, page, out);
}

async function detail(id) {
  var vodId = String(id || '');
  var data = await getJson({ ac: 'detail', ids: vodId });
  var rows = data.list || [];
  var vod = rows[0] || {};
  if (!vod.vod_id) throw failure('详情为空（接口没返回这部剧）', 'EMPTY');
  return {
    list: [{
      vod_id: String(vod.vod_id || vodId),
      vod_name: String(vod.vod_name || ''),
      vod_pic: String(vod.vod_pic || ''),
      vod_content: String(vod.vod_blurb || vod.vod_content || ''),
      vod_remarks: String(vod.vod_remarks || ''),
      vod_year: String(vod.vod_year || ''),
      vod_area: String(vod.vod_area || ''),
      vod_actor: String(vod.vod_actor || ''),
      vod_director: String(vod.vod_director || ''),
      vod_play_from: String(vod.vod_play_from || '默认线路'),
      vod_play_url: String(vod.vod_play_url || '')
    }]
  };
}

async function search(keyword, quick, page) {
  var word = String(keyword || '').trim();
  if (!word) return { page: 1, pagecount: 1, hasMore: false, list: [] };
  page = Number(page) || 1;
  var params = { ac: 'detail', wd: word, pg: page };
  // 短剧专用：wd + t 组合限定短剧类（实测只回短剧）；通用源全库搜。
  if (__CFG.searchType) params.t = __CFG.searchType;
  var data = await getJson(params);
  var rows = data.list || [];
  var out = [];
  for (var i = 0; i < rows.length; i++) out.push(toList(rows[i]));
  return packPage(data, page, out);
}

async function play(flag, id, flags) {
  var url = String(id || '');
  if (/^https?:\/\//.test(url)) {
    return { parse: 0, url: url, header: { 'User-Agent': __CFG.ua } };
  }
  return { parse: 0, url: '', error: 'MISSING_STREAM' };
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
