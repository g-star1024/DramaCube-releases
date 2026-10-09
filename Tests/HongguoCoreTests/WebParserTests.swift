import XCTest
@testable import HongguoCore

final class WebParserTests: XCTestCase {

    /// 验证从内联 JSON 提取 + 解析详情（含分集与 play_url）。
    func testParseDetailFromInlineJSON() throws {
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

    /// 验证字符串内包含大括号时括号配对不误判。
    func testBraceMatchingWithStringBraces() throws {
        let html = #"window._ROUTER_DATA = {"name":"a{b}c","list":[{"id":1,"title":"x"}]};"#
        let data = try XCTUnwrap(WebParser.extractRouterData(html))
        let items = try WebParser.parseCatalog(data)
        XCTAssertEqual(items.first?.title, "x")
    }
}
