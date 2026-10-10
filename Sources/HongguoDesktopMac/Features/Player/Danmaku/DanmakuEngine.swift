import Foundation
import HongguoGatewayCore

// MARK: - 弹幕引擎（M4 超越点）
// 职责：弹幕来源加载（弹弹play API + 本地 xml/ass）→ 统一成 DanmakuEntry →
//       按播放时间轴调度「当前应显示」的弹幕集合。
// 中文内容匹配优化：标题归一化（去空格/全半角/标点）后做包含匹配，提升中文番剧命中率。
// 全平台约束：本文件只依赖 Foundation，可平移。

/// 弹幕引擎。load 装载 → tick 按播放进度吐出应显示的弹幕。
@MainActor
public final class DanmakuEngine: ObservableObject {
    /// 全部弹幕（按 time 升序）。
    @Published public private(set) var entries: [DanmakuEntry] = []
    /// 当前正在显示的弹幕 id 集合（供 overlay 增删动画）。
    @Published public private(set) var active: [DanmakuEntry] = []
    /// 当前播放时钟（秒），overlay 据此计算滚动相位（随 tick 更新，暂停时定格）。
    @Published public private(set) var currentPlayTime: TimeInterval = 0

    public init() {}

    private var cursor = 0          // entries 中下一个待发射下标
    private var lastTime: TimeInterval = -1
    /// 单条弹幕驻留时长（滚动弹幕横穿屏幕的时长）。
    public var scrollDuration: TimeInterval = 8
    public var topBottomDuration: TimeInterval = 4

    // MARK: - 装载

    /// 从统一服务器契约加载（适配器实现 danmaku(item:) 时可用）。
    public func load(entries: [DanmakuEntry]) {
        self.entries = entries.sorted { $0.time < $1.time }
        reset()
    }

    public func clear() {
        entries = []; active = []; reset()
    }

    private func reset() {
        cursor = 0; lastTime = -1
    }

    // MARK: - 时间轴调度

    /// 播放进度回调：发射到达时间的弹幕、清理过期弹幕。
    /// - Parameter time: 当前播放秒数。
    public func tick(time: TimeInterval) {
        currentPlayTime = time
        guard !entries.isEmpty else { return }
        // seek 回退：游标与活跃集重置到该时间点
        if time < lastTime - 1 {
            active.removeAll()
            cursor = entries.firstIndex { $0.time >= time } ?? entries.count
        }
        lastTime = time

        // 发射：time 在 [entry.time, entry.time+window) 的弹幕进入活跃集
        while cursor < entries.count, entries[cursor].time <= time {
            let e = entries[cursor]
            active.append(e)
            cursor += 1
        }
        // 清理：超过驻留时长的移除
        let keep = active.filter { e in
            let life = (e.mode == 0) ? scrollDuration : topBottomDuration
            return time < e.time + life
        }
        if keep.count != active.count { active = keep }
    }

    public func pause() {}
    public func resume() {}
}

// MARK: - 中文内容匹配（纯函数，非隔离，供弹幕源/任意上下文调用）

public enum DanmakuTitleMatcher {
    /// 标题归一化：去空白/常见标点/全角转半角/小写，提升中文标题匹配率。
    public static func normalizeTitle(_ s: String) -> String {
        var t = s.lowercased()
        // 全角字母数字转半角
        t = t.unicodeScalars.map { ch -> Character in
            if (0xFF10...0xFF19).contains(ch.value) || (0xFF21...0xFF3A).contains(ch.value) || (0xFF41...0xFF5A).contains(ch.value) {
                let half = UnicodeScalar(ch.value - 0xFEE0)!
                return Character(half)
            }
            return Character(ch)
        }.map(String.init).joined()
        // 移除空白与常见分隔标点
        let drop = CharacterSet(charactersIn: " \t\r\n·・.。:：-—_[]【】()（）'’\"“”")
        t = String(t.unicodeScalars.filter { !drop.contains($0) })
        return t
    }

    /// 两个标题是否指向同一内容（归一化后相等或互相包含）。
    public static func titleMatch(_ a: String, _ b: String) -> Bool {
        let x = normalizeTitle(a), y = normalizeTitle(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        return x == y || x.contains(y) || y.contains(x)
    }
}

// MARK: - 弹幕文本解析（弹弹play XML / B站 XML / 简版 ASS）

public enum DanmakuParser {

    /// 解析 dandanplay/B站 XML 弹幕：
    /// `<d p="time,mode,color,timestamp,...">text</d>`（B站）或
    /// `<d p="time,mode,size,color,...">text</d>`（弹弹play v2）。
    public static func parseXML(_ data: Data) -> [DanmakuEntry] {
        let parser = XMLDanmakuDelegate()
        let xp = XMLParser(data: data)
        xp.delegate = parser
        xp.parse()
        return parser.entries.sorted { $0.time < $1.time }
    }

    /// 解析简版 ASS 弹幕（Dialogue 行）：抽取开始时间与纯文本。
    /// 支持 `Dialogue: 0,0:00:05.00,0:00:09.00,...,,,,,text`。
    public static func parseASS(_ text: String) -> [DanmakuEntry] {
        var out: [DanmakuEntry] = []
        for line in text.components(separatedBy: .newlines) {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard l.hasPrefix("Dialogue:") else { continue }
            // 逗号分隔，正文在最后（可能含逗号）——取前 9 段后剩余拼接
            let body = String(l.dropFirst("Dialogue:".count))
            var parts = body.components(separatedBy: ",")
            guard parts.count >= 10 else { continue }
            let textPart = parts.suffix(from: 9).joined(separator: ",")
            let start = parts[1]
            // ASS 特效标签 {\...} 与换行 \N 清理
            let cleaned = textPart
                .replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\N", with: " ")
                .trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty, let t = parseASSTime(start) else { continue }
            // mode 默认滚动；颜色省略
            out.append(DanmakuEntry(id: UUID().uuidString, time: t, text: cleaned))
        }
        return out.sorted { $0.time < $1.time }
    }

    /// ASS 时间 `h:mm:ss.cc`（厘秒）。
    private static func parseASSTime(_ s: String) -> TimeInterval? {
        let seg = s.trimmingCharacters(in: .whitespaces).components(separatedBy: ":")
        guard seg.count == 3,
              let h = Double(seg[0]), let m = Double(seg[1]),
              let sec = Double(seg[2]) else { return nil }
        return h * 3600 + m * 60 + sec
    }

    /// 按扩展名/内容自适应解析。
    public static func parse(_ data: Data, filename: String) -> [DanmakuEntry] {
        let ext = (filename as NSString).pathExtension.lowercased()
        if ext == "ass" || ext == "ssa" {
            if let s = String(data: data, encoding: .utf8) { return parseASS(s) }
            return []
        }
        // 默认按 XML
        let xml = parseXML(data)
        if !xml.isEmpty { return xml }
        if let s = String(data: data, encoding: .utf8), s.contains("Dialogue:") {
            return parseASS(s)
        }
        return []
    }
}

/// XML 弹幕 SAX 解析（B站/dandanplay `<d p="...">`）。
private final class XMLDanmakuDelegate: NSObject, XMLParserDelegate {
    var entries: [DanmakuEntry] = []
    private var currentAttrs: [String: String] = [:]
    private var currentText = ""
    private var inD = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "d" {
            inD = true
            currentAttrs = attributeDict
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inD { currentText += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "d", inD else { return }
        inD = false
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let p = currentAttrs["p"] else { return }
        let f = p.components(separatedBy: ",")
        // p 字段：B站 [time,mode,color,...]；弹弹play [time,mode,size,color,...]
        // 取首个为时间；mode 在第 2 位；颜色：B站在第 3 位(十进制)，弹弹play在第 4 位(十进制)。
        guard let time = TimeInterval(f[0]) else { return }
        var mode = 0
        if f.count > 1, let m = Int(f[1]) {
            // B站 mode: 1滚动 4底部 5顶部 → 归一 0滚动 1顶部 2底部
            switch m { case 5: mode = 1; case 4: mode = 2; default: mode = 0 }
        }
        var colorHex: String?
        // 尝试第3位(十进制颜色)或第4位
        for idx in [2, 3] where f.count > idx {
            if let dec = Int(f[idx]), dec > 0, dec <= 0xFFFFFF {
                colorHex = String(format: "#%06X", dec)
                break
            }
        }
        entries.append(DanmakuEntry(id: UUID().uuidString, time: time, text: text, color: colorHex, mode: mode))
    }
}
