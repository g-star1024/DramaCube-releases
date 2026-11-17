# DramaCube 数据源（导入链接）

> 自 **v2.8.0** 起，剧立方 DramaCube **不内置任何数据源**（视频源 / 短剧源均不随安装包捆绑）。
> 所有源由本目录以「导入链接」形式对外提供，用户在 app 内粘贴链接即可导入。

## 一、推荐视频源（TVBox 采集订阅）

- **导入链接**：<https://raw.githubusercontent.com/g-star1024/DramaCube-releases/main/sources/video/subscription.json>
- **说明**：精选 11 个公开、稳定、普通类（Ordinary）MacCMS V10 采集 API，覆盖电影 / 剧集 / 综艺 / 动漫 / 短剧主流需求。
- **导入方式**：视频源页 → 订阅导入 → 粘贴上方链接 → 导入。
- 导入后 app 自动测速并按延迟排序，失效源自动禁用。

## 二、短剧源（CatPawOpen Spider JS 采集源）

- **导入链接**：<https://raw.githubusercontent.com/g-star1024/DramaCube-releases/main/sources/shortdrama/subscription.json>
- **单源 JS**（可选，按需手动添加）：本目录下 `xifan.js` / `xingya.js` / `liangzi.js` / `feifan.js` / `baofeng.js` / `dytt.js` / `jisu.js`。
- **说明**：7 个 QuickJS 沙箱内全链路验证过的短剧 JS 源：
  - 西饭短剧 / 星芽短剧：真实直链播放源；
  - 量子资源（liangzi）：MacCMS V10 通用采集站，全库（含短剧）；
  - 非凡短剧 / 暴风短剧 / 电影天堂短剧 / 极速短剧：公开免费第三方短剧采集源（home 只出短剧类、搜索限定短剧类、m3u8 直链）。
- **导入方式**：短剧源页 → 订阅导入 → 粘贴上方链接 → 导入（一次导入全部 7 源）。

## 三、注意事项

- 这些源均为第三方聚合/采集站，可能随时失效或更换域名；源失效时用户可在 app 内删除。
- app 不内置数据，全新安装后视频源 / 短剧源为空，请先导入上述链接。
- 旧版本（≤ v2.7.92）升级到 v2.8.0 后，内置短剧源会被移除，需重新导入「二、短剧源」链接。
