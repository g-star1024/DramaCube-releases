import XCTest
@testable import HongguoCore

final class WebParserTests: XCTestCase {

    // MARK: - _ROUTER_DATA 提取

    /// 新站点赋值不带 `window.` 前缀，两种形态都要识别。
    func testExtractRouterDataWithoutWindowPrefix() throws {
        let html = #"<script async>_ROUTER_DATA = {"loaderData":{"page":{}}}</script>"#
        XCTAssertNotNil(WebParser.extractRouterData(html))
        let html2 = #"<script>window._ROUTER_DATA = {"a":1}</script>"#
        XCTAssertNotNil(WebParser.extractRouterData(html2))
    }

    /// 验证字符串内包含大括号时括号配对不误判。
    func testBraceMatchingWithStringBraces() throws {
        let html = #"window._ROUTER_DATA = {"name":"a{b}c","list":[{"id":1,"title":"x"}]};"#
        let data = try XCTUnwrap(WebParser.extractRouterData(html))
        let items = try WebParser.parseCatalog(data)
        XCTAssertEqual(items.first?.title, "x")
    }

    // MARK: - 详情页（seriesDetail + vid_list）

    /// 详情页：loaderData.detail_page.seriesDetail 含完整 vid_list；相关推荐排除自身。
    func testParseSeriesDetail() throws {
        let html = #"""
        _ROUTER_DATA = {"loaderData":{"detail_layout":null,"detail_page":{"req":{},"recommendations":{"videoList":[
            {"series_id":"7673810791547538494","series_name":"万妖图录传第十一季","series_cover":"https://img/1.jpg","episode_cnt":164,"vid_list":["7673813850805767230"]},
            {"series_id":"9999999999999999999","series_name":"别的剧","series_cover":"https://img/2.jpg"}
        ]},"seriesDetail":{"series_id":"7693753523955043353","series_name":"一梦青玄","series_cover":"https://img/0.jpg","series_intro":"简介","episode_cnt":3,"tags":["玄幻","穿越"],"episode_right_text":"全3集","vid_list":["7693757720175856664","7693757816653220888","7693757738190375960"]}}}}
        """#
        let data = try XCTUnwrap(WebParser.extractRouterData(html))
        let detail = try WebParser.parseSeriesDetail(data)
        XCTAssertEqual(detail.drama.id, "7693753523955043353")
        XCTAssertEqual(detail.drama.title, "一梦青玄")
        XCTAssertEqual(detail.episodes.count, 3)
        XCTAssertEqual(detail.episodes[0].id, "7693757720175856664")
        XCTAssertEqual(detail.episodes[2].index, 3)
        XCTAssertEqual(detail.drama.tags, ["玄幻", "穿越"])
        // 相关推荐：不含自身，含 recommendations 里的两部
        XCTAssertEqual(detail.related?.count, 2)
        XCTAssertFalse(detail.related?.contains { $0.id == detail.drama.id } ?? true)
    }

    // MARK: - 播放页 main_url

    func testParseMainURL() throws {
        let html = #"""
        _ROUTER_DATA = {"loaderData":{"player_(series_id)/(vid)/page":{"series_id":"1111111111111111111","vid":"2222222222222222222",
        "video_player_info":{"duration":60.44,"width":"1280","height":"720","main_url":"https://v11-hgweb.qznovelvod.com/abc/video/x.mp4?a=8662"}}}}
        """#
        let data = try XCTUnwrap(WebParser.extractRouterData(html))
        XCTAssertEqual(WebParser.parseMainURL(data), "https://v11-hgweb.qznovelvod.com/abc/video/x.mp4?a=8662")
    }

    // MARK: - 首页 / 类目列表

    /// 首页 homeSections[].video_list 用 series_title；类目 recommendList 用 series_name；标签小字典不误入。
    func testParseSeriesList() throws {
        let html = #"""
        _ROUTER_DATA = {"loaderData":{"page":{"bannerList":[],"homeSections":[
            {"tab_type":1,"tab_name":"热播","video_list":[
                {"series_id":"7691228619774905368","series_title":"聚宝仙盆","series_cover":"https://img/a.jpg","episode_cnt":"222","episode_right_text":"全222集"},
                {"series_id":"7686713195246930968","series_title":"首辅娇娘","series_cover":"https://img/b.jpg","episode_cnt":69}
            ]},
            {"tab_type":2,"tab_name":"推荐","video_list":[{"series_id":"7693753523955043353","series_name":"一梦青玄","series_cover":"https://img/c.jpg","episode_cnt":200}]}
        ]},"category_$":{"selectorList":[{"row_id":"r1","row_name":"筛选","items":[{"name":"现代","id":"cate_757"},{"name":"都市","id":"cate_1"}]}],"recommendList":[
            {"series_id":"7691975395733687320","series_name":"穿越七零","series_cover":"https://img/d.jpg","episode_cnt":109}
        ]}}}
        """#
        let data = try XCTUnwrap(WebParser.extractRouterData(html))
        let items = WebParser.parseSeriesList(data)
        // JSONSerialization 不保证字典键遍历序（数组内序保留），这里按集合断言
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(Set(items.map(\.title)), ["聚宝仙盆", "首辅娇娘", "一梦青玄", "穿越七零"])
        let jubao = try XCTUnwrap(items.first { $0.title == "聚宝仙盆" })
        XCTAssertEqual(jubao.episodeCount, 222)
        XCTAssertEqual(jubao.updateStatus, "全222集")
        // 标签筛选字典（cate_x + 现代等）不应混入剧集列表
        XCTAssertFalse(items.contains { $0.title == "现代" || $0.title == "都市" })
    }

    // MARK: - DOM 卡片（榜单 / 搜索）

    /// 榜单卡片：alt 带「封面」后缀需剥离；同剧去重。
    func testParseCardsHTML() throws {
        let html = #"""
        <li class="pc-list-item"><article aria-labelledby="rank-title-1">
        <a aria-label="查看聚宝仙盆" href="/detail?series_id=7691228619774905368">
        <img class="pc-cover" src="https://p3-novel.byteimg.com/novel-pic/a~tplv-shrink:640:0.image" alt="聚宝仙盆封面"/></a></article></li>
        <article><a href="/detail?series_id=7686713195246930968">
        <img src="https://p3-novel.byteimg.com/novel-pic/b.image" alt="首辅娇娘封面"/></a></article>
        <article><a href="/detail?series_id=7691228619774905368">重复卡片应去重</a></article>
        """#
        let items = WebParser.parseCardsHTML(html)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].id, "7691228619774905368")
        XCTAssertEqual(items[0].title, "聚宝仙盆")
        XCTAssertEqual(items[0].coverURL, "https://p3-novel.byteimg.com/novel-pic/a~tplv-shrink:640:0.image")
        XCTAssertEqual(items[1].title, "首辅娇娘")
    }

    // MARK: - 旧版解析兼容

    /// 旧版分享落地页（album_video_list + play_url）仍可解析。
    func testParseDetailLegacySharePage() throws {
        let html = """
        var a = 1;
        window._ROUTER_DATA = {
          "album_id": "abc123",
          "album_name": "测试短剧",
          "cover": "https://img.example.com/cover.jpg",
          "album_video_list": [
            {"video_id": "v1", "title": "第1集", "play_url": "https://cdn.example.com/1.mp4", "duration": 90},
            {"video_id": "v2", "title": "第2集", "play_url": "https://cdn.example.com/2.mp4"}
          ]
        };
        var b = 2;
        """
        let data = try XCTUnwrap(WebParser.extractRouterData(html))
        let detail = try WebParser.parseDetail(data)
        XCTAssertEqual(detail.drama.id, "abc123")
        XCTAssertEqual(detail.drama.title, "测试短剧")
        XCTAssertEqual(detail.episodes.count, 2)
        XCTAssertEqual(detail.episodes.first?.playURL, "https://cdn.example.com/1.mp4")
        XCTAssertEqual(detail.episodes.first?.duration, 90)
    }
}
